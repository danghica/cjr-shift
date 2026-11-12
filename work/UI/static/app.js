import {responseFailure, pad, localTimestamp, localOrdinal, minuteDate, timeLabel, dateKey, duration, groupShifts} from './time.mjs';

const $ = id => document.getElementById(id);
let state = null;
let busy = false;
let available = false;
let refreshing = false;
let page = 'home';
let savedMessage = 'All changes saved';
let actionError = null;
let errorRecovery = 'refresh';
let metadata = {settings:null, revision:0, pendingKind:null, classifications:{}};
let previousPending = undefined;
let lastReport = null;
let assessmentDates = {start:'', end:''};
const timeZone = () => Intl.DateTimeFormat().resolvedOptions().timeZone;


function showError(message, recovery = 'refresh') {
  errorRecovery = recovery;
  $('retry').textContent = recovery === 'reload' ? 'reload page' : recovery === 'dismiss' ? 'dismiss' : 'retry';
  $('error-message').textContent = message;
  $('error').hidden = !message;
}
function setBusy(value) {
  busy = value;
  document.querySelectorAll('.request-control').forEach(button => { button.disabled = value || !available; });
  $('cancel-reset').disabled = value;
  $('track-button').setAttribute('aria-busy', String(value));
  $('save-status').lastChild.textContent = value ? 'Saving your change…' : savedMessage;
}
function closeMenu() {
  $('menu').hidden = true;
  $('menu-button').setAttribute('aria-expanded', 'false');
}
function navigate(target) {
  page = target;
  closeMenu();
  $('home').hidden = page !== 'home';
  $('shifts-page').hidden = page !== 'shifts';
  $('missed-page').hidden = page !== 'missed';
  $('compliance-page').hidden = page !== 'compliance';
  $('settings-page').hidden = page !== 'settings';
  $('report-page').hidden = page !== 'report';
  if (page === 'settings') fillSettings();
  $('menu-button').hidden = page !== 'home';
  for (const [target, id] of Object.entries({shifts:'back-button', missed:'missed-back', compliance:'compliance-back', settings:'settings-back', report:'report-back'})) {
    $(id).hidden = page !== target;
  }
  if (page === 'shifts') renderShifts();
  const title = $({home: 'home-title', shifts: 'shifts-title', missed: 'missed-title', compliance:'compliance-title', settings:'settings-title', report:'report-title'}[page]);
  title.tabIndex = -1;
  title.focus({preventScroll: true});
}
async function request(path, data) {
  let response;
  try {
    response = await fetch(`/api/${path}`, data === undefined ? {cache: 'no-store'} : {
      method: 'POST', headers: {'Content-Type': 'application/json', 'X-Tracker-UI': '1'}, body: JSON.stringify(data)
    });
  } catch {
    throw new Error('Could not reach the tracker server. Make sure it is running. Check your saved shifts before submitting again.');
  }
  let result;
  try { result = await response.json(); } catch { result = {}; }
  if (!result || typeof result !== 'object' || Array.isArray(result)) result = {};
  if (result.settings) metadata = {settings:result.settings, revision:result.metadataRevision,
    pendingKind:result.pendingKind, classifications:result.classifications, pendingOvertime:result.pendingOvertime, overtime:result.overtime};
  if (result.state) {
    $('demo-notice').hidden = !result.demo;
    state = result.state;
    available = true;
    render();
  }
  if (!response.ok || result.code || !result.state) {
    const failure = responseFailure(response.status, path, result);
    const error = new Error(failure.message);
    error.recovery = failure.recovery;
    throw error;
  }
  return result;
}
async function refresh() {
  if (busy || refreshing) return;
  refreshing = true;
  try {
    await request('state');
    if (!actionError) {
      showError('');
      savedMessage = 'All changes saved';
    } else {
      showError(actionError.message, actionError.recovery);
    }
  } catch (error) {
    available = false;
    showError('Could not load your shifts. ' + error.message, error.recovery || 'refresh');
    savedMessage = 'Waiting to reconnect';
  } finally {
    refreshing = false;
    setBusy(false);
  }
}
async function change(action, payload) {
  if (busy || refreshing || !available) return;
  closeMenu();
  actionError = null;
  showError('');
  setBusy(true);
  try {
    const data = payload ?? (action === 'reset' ? {confirmed: true} : {timestamp: localTimestamp(), attendance:$('attendance-time').checked, overtime:$('overtime').checked, timeZone:timeZone()});
    await request(action, data);
    savedMessage = action === 'reset' ? 'A fresh start. All changes saved.' : 'All changes saved';
    if (action === 'missed-shift') {
      $('missed-form').reset();
      navigate('shifts');
    }
    if (action === 'reset') {
      $('reset-dialog').close();
      navigate('home');
    }
  } catch (error) {
    // Reconcile after a lost response: the save might already have succeeded.
    const message = error.message;
    if (action === 'reset') $('reset-dialog').close();
    try { await request('state'); } catch { available = false; }
    actionError = {message, recovery: error.recovery || 'dismiss'};
    showError(message, actionError.recovery);
    savedMessage = available ? 'Showing your saved state' : 'Waiting to reconnect';
  } finally {
    setBusy(false);
  }
}
function tick() {
  const now = new Date();
  $('device-time').textContent = `${now.getHours()}:${pad(now.getMinutes())}`;
  $('today-date').textContent = now.toLocaleDateString(undefined, {weekday: 'long', month: 'long', day: 'numeric'});
  if (!state) return;
  const running = state.pending !== null;
  const minute = localOrdinal(now);
  const midnight = Math.floor(minute / 1440) * 1440;
  let todayTotal = state.shifts.reduce((sum, [start, end]) => sum + Math.max(0, Math.min(end, midnight + 1440) - Math.max(start, midnight)), 0);
  if (running) {
    todayTotal += Math.max(0, minute - Math.max(state.pending, midnight));
    const seconds = Math.max(0, Math.floor((minute - state.pending) * 60));
    $('timer').textContent = `${pad(Math.floor(seconds / 3600))}:${pad(Math.floor(seconds / 60) % 60)}:${pad(seconds % 60)}`;
  }
  const [hours, minutes] = duration(todayTotal).split(' ');
  $('today-total').replaceChildren(document.createTextNode(hours + ' '));
  const small = document.createElement('span'); small.textContent = minutes;
  $('today-total').append(small);
}
function render() {
  if (!state) return;
  const running = state.pending !== null;
  if (running) $('attendance-time').checked = metadata.pendingKind === 'attendance';
  else if (previousPending !== undefined && previousPending !== null) $('attendance-time').checked = false;
  if (running) $('overtime').checked = metadata.pendingOvertime === true;
  else if (previousPending !== undefined && previousPending !== null) $('overtime').checked = false;
  previousPending = state.pending;
  $('attendance-note').textContent = running && metadata.pendingKind === null ? 'Unclassified so far. Choose a type before stopping.' : 'Unchecked records actual working time. Overtime means regular overtime.';
  if (page === 'report' && lastReport && lastReport.revision !== metadata.revision && !$('report-stale')) {
    const note = element('p', 'report-stale', 'Your records or settings changed. Run the check again for an up-to-date report.');
    note.id = 'report-stale'; $('report-body').prepend(note);
  }
  $('home').classList.toggle('running', running);
  $('home-title').replaceChildren(document.createTextNode(running ? 'One thing' : 'Ready when'), document.createElement('br'), document.createTextNode(running ? 'at a time.' : 'you are.'));
  $('status-note').textContent = running ? 'You’re making space for what matters.' : 'A fresh moment to focus.';
  $('track-label').textContent = running ? 'stop' : 'start';
  $('track-button').setAttribute('aria-label', running ? 'stop' : 'start');
  $('play-icon').hidden = running;
  $('stop-icon').hidden = !running;
  $('timer').hidden = !running;
  $('tracking-label').textContent = running ? 'ON THE CLOCK' : 'OFF THE CLOCK';
  $('track-hint').textContent = running ? `Started at ${timeLabel(state.pending)} · take your time.` : 'One tap. A little more intention.';
  tick();
  if (page === 'shifts') renderShifts();
}
function element(tag, className, text) {
  const node = document.createElement(tag); node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}
function renderShifts() {
  if (!state) return;
  const today = Math.floor(localOrdinal() / 1440) * 1440;
  $('history-total').textContent = duration(state.shifts.reduce((sum, [start, end]) => sum + end - start, 0));
  $('history-count').textContent = `${state.shifts.length} ${state.shifts.length === 1 ? 'shift' : 'shifts'}`;
  $('shift-list').replaceChildren();
  $('empty-state').hidden = state.shifts.length !== 0;
  $('shift-list').hidden = state.shifts.length === 0;
  for (const [key, rows] of groupShifts(state.shifts)) {
    const section = element('section', 'shift-group');
    const header = element('div', 'shift-group-heading');
    const label = key === dateKey(today) ? 'Today' : key === dateKey(today - 1440) ? 'Yesterday' : minuteDate(rows[0][0]).toLocaleDateString(undefined, {weekday: 'short', month: 'short', day: 'numeric', year: 'numeric', timeZone: 'UTC'});
    header.append(element('h2', '', label), element('span', '', duration(rows.reduce((sum, [s, e]) => sum + e - s, 0))));
    section.append(header);
    for (const [start, end] of rows) {
      const row = element('article', 'shift-row');
      const detail = element('div', 'shift-detail');
      const times = element('div', 'shift-row-time');
      times.append(document.createTextNode(timeLabel(start)), element('span', '', '→'), document.createTextNode(timeLabel(end)));
      const kind = metadata.classifications?.[String(start)];
      detail.append(times, element('div', 'shift-row-date', (dateKey(start) !== dateKey(end) ? 'Completed at midnight' : 'Completed shift') + ' · ' + (kind === 'work' ? 'actual work' : kind === 'attendance' ? 'attendance' : 'unclassified') + (metadata.overtime?.[String(start)] ? ' · overtime' : '')));
      row.append(element('span', 'shift-row-icon', '↗'), detail, element('span', 'shift-duration', duration(end - start)));
      section.append(row);
    }
    $('shift-list').append(section);
  }
}

function restFields() {
  const fortnight = $('rest-scheme').value !== '1';
  $('fortnight-field').hidden = !fortnight;
  $('fortnight-start').required = fortnight;
}
function fillSettings() {
  if (!metadata.settings) return;
  const settings = metadata.settings;
  $('rest-scheme').value = String(settings.restScheme);
  $('fortnight-start').value = settings.fortnightStart;
  $('night-worker').value = settings.nightWorker === null ? '' : String(settings.nightWorker);
  $('hazardous-night').value = settings.hazardousNightWork === null ? '' : String(settings.hazardousNightWork);
  $('settings-status').textContent = '';
  restFields();
}
async function action(path, payload, success, failure = () => {}) {
  if (busy || refreshing || !available) { failure(); return; }
  actionError = null; showError(''); setBusy(true);
  if (path === 'compliance' || path === 'opt-out') $('check-compliance').textContent = 'checking…';
  try {
    const result = await request(path, payload);
    savedMessage = path === 'compliance' ? 'Assessment complete' : 'All changes saved';
    success(result);
  } catch (error) {
    actionError = {message:error.message, recovery:error.recovery || 'dismiss'};
    showError(error.message, actionError.recovery);
    failure();
  } finally {
    $('check-compliance').replaceChildren(document.createTextNode('check '), element('span', '', '↗'));
    setBusy(false);
  }
}
function reportTime(n) {
  return minuteDate(n).toLocaleString(undefined, {dateStyle:'medium', timeStyle:'short', timeZone:lastReport.timeZone});
}
function optOutPanel(parent, start, end, answer) {
  const panel = element('div', 'optout-panel');
  panel.append(element('p', '', 'Did a voluntary written opt-out cover this period?'));
  if (answer !== undefined) panel.append(element('p', 'report-note', `Saved answer: ${answer ? 'Yes' : 'No'}. You can correct it below.`));
  const link = element('a', '', 'Opt-out agreements — regulation 5');
  link.href = 'https://www.legislation.gov.uk/uksi/1998/1833/regulation/5'; link.target='_blank'; link.rel='noopener noreferrer';
  panel.append(link, element('p', 'report-note', 'This declaration covers only this reference period. It does not waive rest or night-work limits.'));
  const actions = element('div', 'optout-actions');
  for (const [label, value] of [['yes', true], ['no', false]]) {
    const button = element('button', 'request-control', label);
    button.type = 'button'; button.disabled = busy || !available;
    button.addEventListener('click', () => action('opt-out', {...assessmentDates, timeZone:timeZone(),
      optOut:{start,end,answer:value,revision:lastReport.revision}}, result => {lastReport=result.report;renderReport();}));
    actions.append(button);
  }
  panel.append(actions); parent.append(panel);
}
function renderReport() {
  const report = lastReport;
  $('report-title').textContent = report.title;
  $('report-body').replaceChildren();
  const summary = element('div', 'report-summary '+report.status);
  summary.append(element('strong', '', report.validatorCode === null ? 'Not assessed by the validator' : `Result code: ${report.validatorCode}`), element('p', '', report.summary));
  if (report.range) summary.append(element('p', '', `${reportTime(report.range.start)} → ${reportTime(report.range.end)} (${report.timeZone})`));
  if (report.successCount) summary.append(element('p', '', `${report.successCount} assessed periods found no violation.`));
  if (report.notApplicableCount) summary.append(element('p', '', `${report.notApplicableCount} period checks were not applicable under your saved settings or opt-out.`));
  const law = element('a', '', report.legislation.title);
  law.href=report.legislation.url;law.target='_blank';law.rel='noopener noreferrer';summary.append(law);
  $('report-body').append(summary);
  const settings = element('button', 'report-settings', 'review settings');
  settings.type='button';settings.addEventListener('click',()=>navigate('settings'));
  $('report-body').append(element('p','report-note',report.findings.some(f=>f.code===21) || report.status==='incomplete' ? 'Unknown results do not mean compliant.' : 'In-work break entitlement is outside this check.'), settings);
  const notes=element('ul','report-note-list');
  for (const text of report.notes) notes.append(element('li','',text));

  const seen = new Set();
  for (const finding of [...report.findings].sort((a,b) => Number(b.code >= 100) - Number(a.code >= 100))) {
    const box = element('details','report-finding');
    box.open = finding.code >= 100;
    box.append(element('summary','', `${finding.title} · ${finding.code >= 100 ? 'violation' : 'incomplete'}`),
      element('p','finding-code',`Code ${finding.code} · ${reportTime(finding.start)} → ${reportTime(finding.end)}`),
      element('p','',finding.explanation));
    if (finding.calendarPeriod) box.append(element('p','report-note',`Calendar period: ${reportTime(finding.calendarPeriod.start)} → ${reportTime(finding.calendarPeriod.end)}. Adjacent daily-rest context is included above.`));
    const link=element('a','',finding.legislation.title);
    link.href=finding.legislation.url;link.target='_blank';link.rel='noopener noreferrer';box.append(link);
    if (finding.code === 101) {
      const answer=report.optOuts.find(row=>row.start===finding.start && row.end===finding.end)?.answer;
      optOutPanel(box,finding.start,finding.end,answer);seen.add(`${finding.start}:${finding.end}`);
    }
    $('report-body').append(box);
  }
  for (const row of report.optOuts) {
    if (seen.has(`${row.start}:${row.end}`)) continue;
    const box=element('section','report-finding');
    box.append(element('strong','','Saved weekly-cap declaration'),element('p','',`${reportTime(row.start)} → ${reportTime(row.end)}`));
    optOutPanel(box,row.start,row.end,row.answer);$('report-body').append(box);
  }
  $('report-body').append(notes);
}

$('track-button').addEventListener('click', () => change(state?.pending !== null ? 'stop' : 'start'));
$('shifts-button').addEventListener('click', () => navigate('shifts'));
$('back-button').addEventListener('click', () => navigate('home'));
$('empty-back').addEventListener('click', () => navigate('home'));
document.querySelector('.brand').addEventListener('click', event => { event.preventDefault(); navigate('home'); });
$('menu-button').addEventListener('click', () => {
  const opening = $('menu').hidden;
  $('menu').hidden = !opening;
  $('menu-button').setAttribute('aria-expanded', String(opening));
  if (opening) $('missed-menu').focus();
});
document.addEventListener('click', event => { if (!event.target.closest('.menu-container')) closeMenu(); });
document.addEventListener('keydown', event => { if (event.key === 'Escape') { closeMenu(); } });
$('missed-menu').addEventListener('click', () => { navigate('missed'); });
$('missed-back').addEventListener('click', () => navigate('home'));
$('missed-form').addEventListener('submit', event => {
  event.preventDefault();
  if ($('missed-form').reportValidity()) change('missed-shift', {start: $('missed-start').value, end: $('missed-end').value, attendance:$('missed-attendance').checked, overtime:$('missed-overtime').checked, timeZone:timeZone()});
});
$('compliance-menu').addEventListener('click', () => navigate('compliance'));
$('settings-menu').addEventListener('click', () => navigate('settings'));
$('compliance-back').addEventListener('click', () => navigate('home'));
$('settings-back').addEventListener('click', () => navigate('home'));
$('report-back').addEventListener('click', () => navigate('compliance'));
$('rest-scheme').addEventListener('change', restFields);
$('settings-form').addEventListener('submit', event => {
  event.preventDefault();
  if (!$('settings-form').reportValidity()) return;
  const choice = id => $(id).value === '' ? null : $(id).value === 'true';
  action('settings', {restScheme:Number($('rest-scheme').value), fortnightStart:$('fortnight-start').value,
    nightWorker:choice('night-worker'), hazardousNightWork:choice('hazardous-night')}, () => {
      $('settings-status').textContent = 'Settings saved. They apply to all stored shifts.';
    });
});
function saveRunningClassification() {
  if (state?.pending === null || !state) return;
  action('attendance', {start:state.pending, attendance:$('attendance-time').checked, overtime:$('overtime').checked, timeZone:timeZone()}, () => {}, () => {
    $('attendance-time').checked = metadata.pendingKind === 'attendance';
    $('overtime').checked = metadata.pendingOvertime === true;
  });
}
$('attendance-time').addEventListener('change', saveRunningClassification);
$('overtime').addEventListener('change', saveRunningClassification);
$('compliance-form').addEventListener('submit', event => {
  event.preventDefault();
  if (!$('compliance-form').reportValidity()) return;
  assessmentDates = {start:$('compliance-start').value, end:$('compliance-end').value};
  action('compliance', {...assessmentDates, timeZone:timeZone()}, result => { lastReport=result.report; renderReport(); navigate('report'); });
});
$('reset-menu').addEventListener('click', () => { closeMenu(); $('reset-dialog').showModal(); $('cancel-reset').focus(); });
$('cancel-reset').addEventListener('click', () => $('reset-dialog').close());
$('confirm-reset').addEventListener('click', () => change('reset'));
$('reset-dialog').addEventListener('cancel', event => { if (busy) event.preventDefault(); });
$('reset-dialog').addEventListener('close', () => $('menu-button').focus());
$('retry').addEventListener('click', () => {
  if (errorRecovery === 'reload') { window.location.reload(); return; }
  if (errorRecovery === 'dismiss') { actionError = null; showError(''); return; }
  refresh();
});
window.addEventListener('focus', refresh);
document.addEventListener('visibilitychange', () => { if (!document.hidden) refresh(); });
setInterval(tick, 1000);
setInterval(() => { if (!document.hidden && !$('reset-dialog').open) refresh(); }, 30000);
tick();
refresh();
