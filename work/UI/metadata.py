"""Local metadata and recoverable two-file transactions, outside the CJR core."""
import copy
import json
from pathlib import Path
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


def defaults():
    return {'version': 1, 'revision': 0,
            'settings': {'restScheme': 1, 'fortnightStart': '', 'nightWorker': None, 'hazardousNightWork': None},
            'spans': [], 'pending': None, 'optOuts': []}


def settings_value(value):
    from datetime import date
    if not isinstance(value, dict) or set(value) != set(defaults()['settings']):
        raise ValueError('Supply the weekly-rest arrangement and both night-work settings.')
    if type(value['restScheme']) is not int or value['restScheme'] not in (1, 2, 3):
        raise ValueError('Choose a weekly-rest arrangement.')
    for name in ('nightWorker', 'hazardousNightWork'):
        if value[name] is not None and type(value[name]) is not bool:
            raise ValueError('Night-work settings must be yes, no or not set.')
    anchor = value['fortnightStart']
    if not isinstance(anchor, str):
        raise ValueError('Choose a fortnight-start date.')
    if anchor:
        day = date.fromisoformat(anchor)
        if len(anchor) != 10 or day.weekday() != 0:
            raise ValueError('The fortnight must start on a Monday.')
    if value['restScheme'] != 1 and not anchor:
        raise ValueError('Choose the Monday that starts a fortnight.')
    return copy.deepcopy(value)


def time_zone(value):
    if not isinstance(value, str) or len(value) > 80:
        raise ValueError('A valid time zone is required.')
    try:
        ZoneInfo(value)
    except (ZoneInfoNotFoundError, ValueError):
        raise ValueError('The time zone is not recognised.') from None
    return value


def validate(data):
    if not isinstance(data, dict) or set(data) != set(defaults()) or type(data['version']) is not int or data['version'] != 1:
        raise ValueError('The metadata file has an unsupported format. It has not been overwritten.')
    if type(data['revision']) is not int or data['revision'] < 0:
        raise ValueError('Invalid metadata revision.')
    # A missing fortnight anchor is allowed only in the unconfigured default weekly profile.
    settings_value(data['settings'])
    if not isinstance(data['spans'], list) or not isinstance(data['optOuts'], list):
        raise ValueError('Invalid metadata lists.')
    def moment(n):
        return type(n) is int and 0 <= n <= 6000000000
    for row in data['spans'] + ([data['pending']] if data['pending'] is not None else []):
        expected = {'start','kind','timeZone'} if row is data['pending'] else {'start','end','kind','timeZone','pieces'}
        if not isinstance(row, dict) or set(row) not in (expected, expected | {'overtime'}) or not moment(row.get('start')) or row.get('kind') not in ('work', 'attendance', None):
            raise ValueError('Invalid shift classification metadata.')
        if 'overtime' in row and type(row['overtime']) is not bool:
            raise ValueError('Overtime must be true or false.')
        if row.get('timeZone') is not None:
            time_zone(row['timeZone'])
        if row is not data['pending']:
            if not moment(row.get('end')) or row['end'] <= row['start'] or not isinstance(row.get('pieces'), list):
                raise ValueError('Invalid completed-shift metadata.')
            cursor = row['start']
            for pair in row['pieces']:
                if not isinstance(pair, list) or len(pair) != 2 or not all(moment(n) for n in pair) or pair[0] != cursor or pair[1] <= cursor:
                    raise ValueError('Invalid midnight-piece association.')
                cursor = pair[1]
            if cursor != row['end']:
                raise ValueError('Incomplete midnight-piece association.')
    for row in data['optOuts']:
        expected = {'start','end','answer'}
        if not isinstance(row, dict) or set(row) != expected or not moment(row.get('start')) or not moment(row.get('end')) or row['start'] >= row['end'] or type(row.get('answer')) is not bool:
            raise ValueError('Invalid opt-out declaration.')
    return data


def reconcile(data, state):
    result = copy.deepcopy(data)
    pieces = {tuple(row) for row in state['shifts']}
    used = set()
    retained = []
    for row in result['spans']:
        keys = {tuple(pair) for pair in row['pieces']}
        if keys <= pieces and not keys & used:
            retained.append(row)
            used |= keys
    result['spans'] = retained
    if result['pending'] and result['pending']['start'] != state['pending']:
        result['pending'] = None
    return result


class MetadataRepository:
    def __init__(self, store, save):
        self.path = Path(str(store) + '.metadata.json')
        self.journal = Path(str(store) + '.transaction.json')
        self.store = Path(store)
        self.atomic_save = save

    def load(self):
        if not self.path.exists():
            return defaults()
        return validate(json.loads(self.path.read_text(encoding='utf-8')))

    def save(self, value):
        self.atomic_save(self.path, json.dumps(validate(value), sort_keys=True))

    def recover(self, core):
        if not self.journal.exists():
            return
        tx = json.loads(self.journal.read_text(encoding='utf-8'))
        if not isinstance(tx, dict) or set(tx) != {'before', 'after', 'metadataBefore', 'metadataAfter'}:
            raise ValueError('The recovery journal is invalid; files have been preserved.')
        for key in ('before', 'after'):
            if not isinstance(tx[key], str) or not core.call('validState', tx[key]).get('valid'):
                raise ValueError('The recovery journal contains invalid state; files have been preserved.')
        before, after = validate(tx['metadataBefore']), validate(tx['metadataAfter'])
        present = self.load()
        if present not in (before, after):
            raise ValueError('Metadata changed during an interrupted save. Recovery needs attention; files have been preserved.')
        current = self.store.read_text(encoding='utf-8').strip()
        if current == tx['after']:
            self.save(after)
        elif current == tx['before']:
            self.save(before)
        else:
            raise ValueError('The store changed during an interrupted save. Recovery needs attention; files have been preserved.')
        self.journal.unlink()

    def commit(self, repository, before, after, old, new):
        tx = {'before': before, 'after': after, 'metadataBefore': old, 'metadataAfter': new}
        self.atomic_save(self.journal, json.dumps(tx, sort_keys=True))
        try:
            repository.save(after)
            self.save(new)
        except OSError:
            # Each replacement is atomic. Restore both before acknowledging failure.
            # If restoration itself fails, keep the journal and block until recovery.
            try:
                if repository.read() != before:
                    repository.save(before)
                self.save(old)
                self.journal.unlink()
            except OSError:
                raise OSError('The save was interrupted and recovery is still required. Restart the server and check your shifts.') from None
            raise
        try:
            self.journal.unlink()
        except OSError:
            # Both durable snapshots are already consistent. Recovery will only repeat metadataAfter.
            pass
