// Representation bridge: core timestamps are Gregorian civil minutes, not instants.
const epoch = Date.parse('0001-01-01T00:00:00.000Z');
export const pad = n => String(n).padStart(2, '0');
export function localTimestamp(date = new Date()) {
  return `${String(date.getFullYear()).padStart(4, '0')}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}
export function localOrdinal(date = new Date()) {
  // setUTCFullYear avoids Date.UTC's special treatment of years 0..99.
  const civil = new Date(0);
  civil.setUTCFullYear(date.getFullYear(), date.getMonth(), date.getDate());
  civil.setUTCHours(date.getHours(), date.getMinutes(), date.getSeconds(), date.getMilliseconds());
  return (civil.getTime() - epoch) / 60000;
}
export const minuteDate = minute => new Date(epoch + minute * 60000);
export const timeLabel = minute => minuteDate(minute).toLocaleTimeString(undefined, {hour: '2-digit', minute: '2-digit', hourCycle: 'h23', timeZone: 'UTC'});
export const dateKey = minute => minuteDate(minute).toISOString().slice(0, 10);
export function duration(minutes) {
  const total = Math.max(0, Math.floor(minutes));
  return `${Math.floor(total / 60)}h ${pad(total % 60)}m`;
}
export function groupShifts(shifts) {
  const groups = new Map();
  for (const row of [...shifts].sort((a, b) => b[0] - a[0])) {
    const key = dateKey(row[0]);
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(row);
  }
  return groups;
}

// Translate transport errors into useful UI guidance; domain messages come from the core adapter.
export function responseFailure(status, path, result) {
  if (status === 404) {
    const feature = path === 'missed-shift' ? 'adding missed shifts' : path === 'state' ? 'loading your shifts' : ['compliance','opt-out'].includes(path) ? 'compliance checking' : ['settings','attendance'].includes(path) ? 'working-time metadata' : 'this action';
    return {
      message: `The running server does not support ${feature}. Restart the UI server, then reload this page.${path === 'missed-shift' ? ' Your entered dates have been kept.' : ''}`,
      recovery: 'reload'
    };
  }
  if (typeof result?.message === 'string' && result.message.trim() && result.message.trim().toLowerCase() !== 'not found.') {
    return {message: result.message, recovery: 'dismiss'};
  }
  if (status === 403) return {message: 'This action must be sent from the local tracker. Open the localhost address printed by the UI server and try again.', recovery: 'dismiss'};
  return {message: 'The server could not complete this request. Check your saved shifts before trying again. If this continues, restart the UI server.', recovery: 'dismiss'};
}

// Group only overlapping violations of the same rule. Keep every original
// finding so declarations and detailed evidence remain period-specific.
export function groupViolations(findings) {
  const groups = [];
  for (const finding of [...findings].sort((a,b) => a.start-b.start || a.end-b.end)) {
    const group = finding.code >= 100 && groups.findLast(g => g.code === finding.code && g.rule === finding.rule && finding.start < g.end);
    if (group) {
      group.end = Math.max(group.end, finding.end);
      group.windows.push(finding);
    } else groups.push({code:finding.code, rule:finding.rule, start:finding.start, end:finding.end, windows:[finding]});
  }
  return groups.sort((a,b) => Number(b.code >= 100)-Number(a.code >= 100) || a.start-b.start);
}
export function hours(minutes) {
  const value = Number((minutes/60).toFixed(2));
  return `${value} ${value === 1 ? 'hour' : 'hours'}`;
}
export function findingExplanation(finding) {
  if (finding.code === 106) return `${hours(finding.measured)} of actual work within a 24-hour window; maximum permitted: ${hours(finding.limit)}.`;
  if (finding.code === 102) return `Longest continuous rest: ${hours(finding.measured)}; required: ${hours(finding.limit)}.`;
  return finding.explanation;
}
export function worstWindow(windows) {
  return windows.reduce((worst, next) => {
    const score = f => (f.code === 102 || f.code === 103) ? -f.measured/(f.limit || 1) : f.limit > 0 ? f.measured/f.limit : f.measured;
    return score(next) > score(worst) ? next : worst;
  });
}
