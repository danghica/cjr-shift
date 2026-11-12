"""Prepare declared legal context and present the existing validator's findings.

No hours/rest pass/fail calculation is implemented here. All measurements,
threshold comparisons and summary codes come from validateWorkingTime.
"""
from datetime import datetime, timedelta, timezone
from tempfile import NamedTemporaryFile
from zoneinfo import ZoneInfo
import json

EPOCH = datetime(1, 1, 1, tzinfo=timezone.utc)
DAY = 1440
REFERENCE = 17 * 7 * DAY
MAX = 6000000000
LEGISLATION = {
    101: ('Maximum weekly working time — regulation 4', 'https://www.legislation.gov.uk/uksi/1998/1833/regulation/4'),
    102: ('Daily rest — regulation 10', 'https://www.legislation.gov.uk/uksi/1998/1833/regulation/10'),
    103: ('Weekly rest — regulation 11', 'https://www.legislation.gov.uk/uksi/1998/1833/regulation/11'),
    105: ('Length of night work — regulation 6', 'https://www.legislation.gov.uk/uksi/1998/1833/regulation/6'),
    106: ('Hazardous night work — regulation 6(7)', 'https://www.legislation.gov.uk/uksi/1998/1833/regulation/6'),
}
TITLES = {101: '48-hour weekly average', 102: 'Daily rest', 103: 'Weekly rest',
          105: 'Average night work', 106: 'Hazardous night work'}


def ordinal(text):
    if not isinstance(text, str) or len(text) != 16:
        raise ValueError('Choose a date and time in YYYY-MM-DDTHH:MM format.')
    date = datetime.fromisoformat(text)
    if date.strftime('%Y').zfill(4) != text[:4] or date.tzinfo or date.second or text[10] != 'T':
        raise ValueError('Choose a valid local date and time.')
    return (date - EPOCH.replace(tzinfo=None)).days * DAY + date.hour * 60 + date.minute


def instant(civil, zone):
    naive = (EPOCH + timedelta(minutes=civil)).replace(tzinfo=None)
    tz = ZoneInfo(zone)
    candidates = set()
    for fold in (0, 1):
        value = naive.replace(tzinfo=tz, fold=fold).astimezone(timezone.utc)
        if value.astimezone(tz).replace(tzinfo=None) == naive:
            candidates.add(int((value - EPOCH).total_seconds() // 60))
    if len(candidates) != 1:
        raise ValueError('A recorded time is ambiguous or does not exist because the clocks changed. Its elapsed duration cannot be established.')
    return candidates.pop()


def local_minute(value, zone):
    local = (EPOCH + timedelta(minutes=value)).astimezone(ZoneInfo(zone)).replace(tzinfo=None)
    return int((local - EPOCH.replace(tzinfo=None)).total_seconds() // 60)


def calendar_shift(value, days, zone):
    return instant(local_minute(value, zone) + days * DAY, zone)


def encode_state(rows, pending=None):
    # Timestamp representation only; midnight splitting is performed by addPair below.
    return ('-' if pending is None else '@' + str(pending)) + '|' + ';'.join(f'@{a},@{b}' for a, b in rows)


def period(rule, start, end, calendar=None, scheme=0, evidence='known'):
    return dict(rule=rule, start=start, end=end, calendarMinutes=end-start if calendar is None else calendar,
                extraStart=0, extraEnd=0, evidence=evidence, restScheme=scheme, dailyRestOverlap=False)


def clock_events(lower, upper, zone):
    """UTC offset discontinuities are additional rolling-window breakpoints."""
    tz = ZoneInfo(zone)
    def offset(n):
        return (EPOCH + timedelta(minutes=n)).astimezone(tz).utcoffset()
    a = lower
    while a < upper:
        b = min(a + DAY, upper)
        if offset(a) != offset(b):
            left, right = a, b
            while right - left > 1:
                middle = (left + right) // 2
                if offset(middle) == offset(left):
                    left = middle
                else:
                    right = middle
            yield right
        a = b


def assess(core, encoding, state, metadata, start='', end='', zone='Europe/London'):
    from working_time_metadata import encode_metadata
    settings = metadata['settings']
    report = {'validatorCode': None, 'status': 'not_assessed', 'title': 'Nothing to check yet',
              'summary': 'There are no completed shifts in this range.', 'findings': [], 'optOuts': [],
              'revision': metadata['revision'], 'timeZone': zone,
              'range': None, 'legislation': {'title':'Working Time Regulations 1998', 'url':'https://www.legislation.gov.uk/uksi/1998/1833/part/II'}, 'notes': [
                  'Ordinary adult Great Britain profile. Records are assumed complete and include all employment. Gaps are treated as no work.',
                  'No break tracking or assumed break deductions. In-work breaks are outside scope.',
                  'Only regular overtime is tracked. All classified actual work counts as normal hours, including regular overtime.',
                  'A result applies to the supplied records and declared profile; it is not a complete legal compliance certificate.']}
    if not state['shifts'] and state['pending'] is None:
        return report
    first = min([a for a, _ in state['shifts']] + ([state['pending']] if state['pending'] is not None else []))
    if not end and not state['shifts']:
        report['summary'] = 'Your running shift has no end time. Stop it or choose an end date; no end time has been invented.'
        return report
    low_civil = ordinal(start) if start else first
    high_civil = ordinal(end) if end else max(b for _, b in state['shifts'])
    if high_civil <= low_civil:
        raise ValueError('End must be later than start.')
    if len(state['shifts']) > 1500:
        report['title'] = 'This history needs a smaller dataset'
        report['summary'] = 'The local assessment adapter supports up to 1,500 daily pieces. Your records have not been changed.'
        return report
    try:
        lower, upper = instant(low_civil, zone), instant(high_civil, zone)
        if lower < 0 or upper > MAX or upper - lower > 3660 * DAY:
            raise ValueError('Choose a range of at most ten years within the supported timestamp bounds.')
        report['range'] = {'start': lower, 'end': upper}
        associated = {tuple(p) for row in metadata['spans'] for p in row['pieces']}
        spans = list(metadata['spans']) + [dict(start=a, end=b, kind=None, timeZone=zone) for a, b in state['shifts'] if (a, b) not in associated]
        intervals = []
        actual_encoding = '-|'
        for row in sorted(spans, key=lambda r: r['start']):
            tz = row['timeZone'] or zone
            a, b = instant(row['start'], tz), instant(row['end'], tz)
            if b <= a:
                raise ValueError('An elapsed shift duration could not be established.')
            kind = row['kind'] if row['timeZone'] else None
            intervals.append((a, b, kind))
            if kind == 'work':
                result = core.call('addPair', actual_encoding, '@'+str(a), '@'+str(b))
                if result['code']:
                    raise ValueError('The elapsed-time representation contains overlapping work. Check the recorded time zones.')
                actual_encoding = result['stateEncoding']
        pending = instant(state['pending'], (metadata['pending'] or {}).get('timeZone') or zone) if state['pending'] is not None else None
        actual = core.call('queryContained', actual_encoding, '@0', '@6000000000')['state']['shifts']
        actual_encoding = encode_state(actual, pending)
        reasons = {}
        ps = []
        calendar_periods = {}
        def append(p, missing=()):
            if not (p['start'] < upper and lower < p['end']):
                return
            missing = list(missing)
            if pending is not None and pending < p['end']:
                missing.append('The running shift has no completed end time for this period.')
            if any(a < p['end'] and p['start'] < b and kind != 'work' for a, b, kind in intervals):
                missing.append('This period includes attendance or unclassified records. Actual working hours and duty boundaries are not established.')
            if p['evidence'] == 'not_applicable':
                missing = []
            elif missing:
                p['evidence'] = 'unknown'
            key = (p['rule'], p['start'], p['end'])
            reasons[key] = list(dict.fromkeys(missing))
            ps.append(p)
        # The rolling total is piecewise linear. Endpoints and their calendar-shifted
        # counterparts, plus clock discontinuities, cover its extrema at minute resolution.
        ends = {upper, lower + 1}
        events = {n for a, b, _ in intervals for n in (a, b)}
        for event in clock_events(max(0, calendar_shift(lower, -119, zone)), upper, zone):
            events.update((event-1, event, event+1))
        for event in events:
            ends.add(event)
            try:
                ends.add(calendar_shift(event, 119, zone))
            except (ValueError, OverflowError):
                pass
        optouts = {(row['start'], row['end']): row['answer'] for row in metadata['optOuts']}
        for finish in sorted(e for e in ends if lower < e <= upper):
            boundary_missing = []
            try:
                begin = calendar_shift(finish, -119, zone)
            except ValueError:
                begin = finish - REFERENCE
                boundary_missing = ['A clock-change boundary makes this calendar reference period ambiguous. Its weekly average has not been assessed.']
            if begin < 0:
                continue
            waived = optouts.get((begin, finish)) is True
            append(period(101, begin, finish, REFERENCE, evidence='not_applicable' if waived else 'known'), boundary_missing)
        # Group actual duty context by an uninterrupted daily-rest opportunity.
        groups = []
        for a, b, kind in intervals:
            if not groups or a - groups[-1][1] >= 660:
                groups.append([a, b, kind != 'work'])
            else:
                groups[-1][1] = max(groups[-1][1], b)
                groups[-1][2] |= kind != 'work'
        for a, b, uncertain in groups:
            cursor = a
            while cursor < b:
                append(period(102, cursor, cursor+DAY), ['Duty-day boundaries cannot be established from attendance or unclassified records.'] if uncertain else [])
                cursor += DAY
        # Calendar-aligned weekly / declared fortnightly periods; daily rest is additional.
        local_low = (EPOCH + timedelta(minutes=local_minute(lower, zone))).replace(tzinfo=None)
        monday = local_low.replace(hour=0, minute=0) - timedelta(days=local_low.weekday())
        step = 7 if settings['restScheme'] == 1 else 14
        if step == 14:
            anchor = datetime.fromisoformat(settings['fortnightStart'])
            monday = anchor + timedelta(days=((monday-anchor).days // 14)*14)
        day = monday
        while instant(int((day-EPOCH.replace(tzinfo=None)).total_seconds()//60), zone) < upper:
            a = instant(int((day-EPOCH.replace(tzinfo=None)).total_seconds()//60), zone)
            b = instant(int(((day+timedelta(days=step))-EPOCH.replace(tzinfo=None)).total_seconds()//60), zone)
            # Include the adjacent daily-rest context. A qualifying 35/59-hour gap
            # can straddle the calendar boundary while still containing the required
            # 24/48 hours inside the week/fortnight. At most 11 hours lie outside.
            context_start, context_end = max(0, a-660), b+660
            if a < upper and lower < b:
                calendar_periods[(103, context_start, context_end)] = {'start':a, 'end':b}
                append(period(103, context_start, context_end, step*DAY, settings['restScheme']))
            day += timedelta(days=step)
        # This application records ordinary work and regular overtime only. Both
        # form normal hours. Supply genuine rest intervals for the core's night
        # denominator; no rest or normal hours are inferred inside uncertain spans.
        night_begin = max(0, calendar_shift(upper, -119, zone))
        weekly_rest = []
        rest_unknown = False
        cursor = night_begin
        remaining_days = 119
        while remaining_days > 0:
            days = min(remaining_days, 7 if settings['restScheme'] == 1 else 14)
            block_end = upper if days == remaining_days else calendar_shift(cursor, days, zone)
            required = days*DAY//7
            chunks = 1 if settings['restScheme'] in (1,3) else 2
            if days <= 7:
                chunks = 1
            size = required//chunks
            gaps = []
            gap_start = cursor
            for a,b,_ in intervals:
                if b <= cursor or a >= block_end:
                    continue
                if a > gap_start:
                    gaps.append((gap_start,min(a,block_end)))
                gap_start = max(gap_start,min(b,block_end))
            if gap_start < block_end:
                gaps.append((gap_start,block_end))
            selected = []
            for a,b in gaps:
                while len(selected) < chunks and b-a >= size:
                    selected.append([a,a+size]);a += size
            if len(selected) != chunks:
                rest_unknown = True
            weekly_rest.extend(selected)
            cursor = block_end
            remaining_days -= days
        night_missing = []
        if settings['nightWorker'] is None:
            night_missing.append('Night-worker status has not been set.')
        if rest_unknown:
            night_missing.append('The weekly-rest exclusion for the night-work average cannot be established from the recorded gaps. Review the weekly-rest findings.')
        append(period(105, night_begin, upper, REFERENCE,
                      evidence='not_applicable' if settings['nightWorker'] is False else 'unknown' if night_missing else 'known'), night_missing)
        # A strict window that intersects night work changes at work/night endpoints and
        # the corresponding endpoints minus 24 hours. Use the standard 23:00–06:00 night.
        night = []
        for a, b, _ in intervals:
            date = (EPOCH + timedelta(minutes=a)).astimezone(ZoneInfo(zone)).replace(tzinfo=None, hour=0, minute=0)
            while instant(int((date-EPOCH.replace(tzinfo=None)).total_seconds()//60), zone) < b:
                for h1, h2 in ((0, 6), (23, 24)):
                    s = instant(int(((date+timedelta(hours=h1))-EPOCH.replace(tzinfo=None)).total_seconds()//60), zone)
                    e = instant(int(((date+timedelta(hours=h2))-EPOCH.replace(tzinfo=None)).total_seconds()//60), zone)
                    if max(a, s) < min(b, e):
                        night.append([max(a, s), min(b, e)])
                date += timedelta(days=1)
        hazard_starts = {lower, max(lower, upper-DAY)}
        for a, b, _ in intervals:
            hazard_starts.update((a, b, a-DAY, b-DAY))
        for a, b in night:
            hazard_starts.update((a, b-1, a-DAY+1, b-DAY))
        if settings['nightWorker'] is False or settings['hazardousNightWork'] is False:
            append(period(106, lower, lower+DAY, evidence='not_applicable'))
        else:
            for a in sorted(n for n in hazard_starts if n >= 0 and n < upper and n+DAY > lower):
                append(period(106, a, a+DAY, evidence='unknown' if settings['nightWorker'] is None or settings['hazardousNightWork'] is None else 'known'),
                       ['Night-worker status has not been set.'] if settings['nightWorker'] is None else ['Hazardous-night-work status has not been set.'] if settings['hazardousNightWork'] is None else [])
        # Each rule is explicit even when no relevant duty starts in the selected range.
        for rule in TITLES:
            if not any(p['rule'] == rule for p in ps):
                append(period(rule, lower, lower+DAY, DAY if rule != 103 else 7*DAY, 1 if rule == 103 else 0, 'unknown'),
                       ['There is not enough duty or reference-period context to assess this rule.'])
        if len(ps) > 1200:
            raise ValueError('This range produces too many statutory periods. Choose a shorter assessment range.')
        # Night intervals must refer only to known actual work in the core representation.
        known_night = []
        for a, b in night:
            for s, e, kind in intervals:
                if kind == 'work' and max(a, s) < min(b, e):
                    known_night.append([max(a, s), min(b, e)])
        known_night = sorted({tuple(p) for p in known_night})
        # The caller declares the records complete, including gaps in the full
        # assessment context. Keep uncertain classifications and running shifts unknown.
        coverage_start = min([lower] + [p['start'] for p in ps] + [a for a, _, _ in intervals])
        coverage_end = max([upper] + [p['end'] for p in ps] + [b for _, b, _ in intervals])
        data = dict(jurisdiction='GB', adult=True, ordinaryRegime=True, coverageStart=coverage_start,
                    coverageEnd=coverage_end, periodCoverageComplete=True, elapsedWorkKnown=True,
                    otherWork=[], normalWork=actual, weeklyRest=weekly_rest, nightWork=known_night, periods=ps)
        # The existing JSON bridge is reused verbatim; no duplicate native encoding logic.
        with NamedTemporaryFile(mode='w+', suffix='.json') as handle:
            json.dump(data, handle);handle.flush()
            native = core.call('validateWorkingTime', actual_encoding, '@'+str(lower), '@'+str(upper), encode_metadata(handle.name))
        report['validatorCode'] = native['code']
        report['status'] = 'violation' if native['code'] >= 100 else {0:'clear',20:'invalid',21:'incomplete',22:'unsupported'}[native['code']]
        report['title'] = {'clear':'No violation detected', 'violation':'Time to review your shifts', 'incomplete':'More information is needed',
                           'invalid':'The assessment could not be completed', 'unsupported':'This profile is outside the supported rules'}[report['status']]
        report['summary'] = native['message']
        report['breaksAssessed'] = native['breaksAssessed']
        report['successCount'] = sum(f['code'] == 0 and p['evidence'] == 'known' for f, p in zip(native['findings'], ps))
        report['notApplicableCount'] = sum(p['evidence'] == 'not_applicable' for p in ps)
        for finding in native['findings']:
            if finding['code'] == 0:
                continue
            rule = finding['rule']
            missing = reasons.get((rule, finding['start'], finding['end']), [])
            if finding['code'] == 21 and not missing:
                missing = ['The required classification or reference-period coverage is incomplete.']
            title, url = LEGISLATION[rule]
            finding.update(title=TITLES[rule], reasons=missing, legislation={'title':title, 'url':url})
            if (rule, finding['start'], finding['end']) in calendar_periods:
                finding['calendarPeriod'] = calendar_periods[(rule, finding['start'], finding['end'])]
            if finding['code'] == 101:
                finding['explanation'] = f"Recorded weekly average: {finding['measured']/finding['limit']*48:.2f} hours; limit: 48 hours. All recorded actual work counts."
            elif finding['code'] == 102:
                finding['explanation'] = f"Longest continuous rest: {finding['measured']} minutes; required: {finding['limit']} minutes (11 hours)."
            elif finding['code'] == 103:
                finding['explanation'] = f"Qualifying rest periods: {finding['measured']}; required: {finding['limit']}. Daily rest is additional; no overlap exception is assumed."
            elif finding['code'] == 106:
                finding['explanation'] = f"Actual work: {finding['measured']} minutes; limit: {finding['limit']} minutes in this 24-hour period."
            elif finding['code'] == 105:
                finding['explanation'] = f"Recorded normal-hours average: {finding['measured']/finding['limit']*8:.2f} hours per 24 hours; limit: 8 hours. Regular overtime is included."
            else:
                finding['explanation'] = 'The average night-work check includes normal hours and regular overtime.'
            if finding['code'] in (20,21,22):
                finding['explanation'] = ' '.join(missing) or 'The validator could not assess this period from the supplied metadata.'
            report['findings'].append(finding)
        offered = {(p['start'], p['end']) for p in ps if p['rule'] == 101}
        report['optOuts'] = [r for r in metadata['optOuts'] if (r['start'], r['end']) in offered]
        report['notes'].append('Standard rolling 17-week periods are used. No excluded-day replacement or exceptional agreement has been declared; results are conditional on this standard profile.')
        return report
    except (ValueError, OverflowError) as error:
        # Bad user date ranges are rejected before this block; unresolved context is a report.
        report['status'] = 'incomplete'
        report['title'] = 'The recorded context needs attention'
        report['summary'] = str(error)
        return report
