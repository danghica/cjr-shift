"""UI-side ports/adapters. The existing CJR core is called, never reimplemented."""
from pathlib import Path
import importlib.util
import threading
import copy
import hashlib
from metadata import MetadataRepository, reconcile, settings_value, time_zone

CLI = Path(__file__).resolve().parents[1] / 'CLI'
spec = importlib.util.spec_from_file_location('tracker_file_adapter', CLI / 'file_store.py')
file_adapter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(file_adapter)

MESSAGES = {
    1: 'That time could not be recorded. Please try again.',
    2: 'A shift must last at least one recorded minute. Wait until the next minute, then press stop.',
    3: 'That shift overlaps one already saved.',
    4: 'The saved shift has changed or conflicts with this start time. Check its status and try again.',
    5: 'There is no running shift to stop.',
    6: 'That shift could not be found.',
    7: 'The store contains invalid tracker data. It has not been overwritten.',
    8: 'A save is still in progress. Please wait.',
    9: 'Could not save your change. Your previous shifts and running status have been kept.',
    10: 'There is no outstanding save.',
}


class AdapterError(Exception):
    def __init__(self, code, message=None):
        self.code = code
        super().__init__(message or MESSAGES.get(code, 'The tracker could not complete that action.'))


class CorePort:
    """Bridge to the unchanged extracted implementation through its native CLI."""
    def call(self, name, *args):
        return file_adapter.core(name, *args)


class FileRepository:
    """Reuses the CLI adapter's lock discipline and atomic file replacement."""
    def __init__(self, path):
        self.path = Path(path).expanduser().resolve()

    def locked(self):
        return file_adapter.locked(self.path)

    def read(self):
        return self.path.read_text(encoding='utf-8').strip()

    def save(self, encoding):
        file_adapter.save(self.path, encoding)


class TrackerAdapter:
    """Drives the existing prepare/save/complete protocol outside the core.

    Keep an internal session initialized at startup. Reconcile under the shared
    file lock before each request so writes from a separate CLI are respected.
    """
    def __init__(self, path, core=None):
        self.core = core or CorePort()
        self.repository = FileRepository(path)
        self.metadata_repository = MetadataRepository(self.repository.path, file_adapter.save)
        self.mutex = threading.RLock()
        self.session = None
        with self.repository.locked():
            if not self.repository.path.exists():
                if self.metadata_repository.journal.exists():
                    raise ValueError('The store is missing during recovery. Restore it before continuing; the journal has been preserved.')
                self.repository.save(self.core.call('emptyState')['stateEncoding'])
            self._load()

    def _load(self):
        self.metadata_repository.recover(self.core)
        encoding = self.repository.read()
        if self.session is None or encoding != self.session['stateEncoding']:
            session = self.core.call('initializeStore', encoding)
            if session['code']:
                raise AdapterError(session['code'])
            self.session = session
        self.raw_metadata = self.metadata_repository.load()
        self.metadata = reconcile(self.raw_metadata, self._snapshot())

    def _revision(self):
        return str(self.metadata['revision']) + ':' + hashlib.sha256(self.session['stateEncoding'].encode()).hexdigest()

    def _response(self, **extra):
        state = self._snapshot()
        classifications = {str(pair[0]): row['kind'] for row in self.metadata['spans'] for pair in row['pieces']}
        pending = self.metadata['pending']
        return {'code': 0, 'state': state, 'settings': self.metadata['settings'],
                'metadataRevision': self._revision(),
                'classifications': classifications, 'pendingKind': pending['kind'] if pending else None,
                'overtime': {str(pair[0]): row.get('overtime', False) for row in self.metadata['spans'] for pair in row['pieces']},
                'pendingOvertime': pending.get('overtime', False) if pending else False, **extra}

    def save_settings(self, settings):
        value = settings_value(settings)
        with self.mutex, self.repository.locked():
            self._load()
            updated = copy.deepcopy(self.metadata)
            updated['settings'] = value
            updated['revision'] += 1
            self.metadata_repository.save(updated)
            self.metadata = updated
            return self._response()

    def attendance(self, start, attendance, zone, overtime=None):
        if type(attendance) is not bool or type(start) is not int:
            raise ValueError('Supply the running start and attendance choice.')
        if overtime is not None and type(overtime) is not bool:
            raise ValueError('Overtime must be true or false.')
        zone = time_zone(zone)
        with self.mutex, self.repository.locked():
            self._load()
            if self._snapshot()['pending'] != start:
                raise ValueError('The running shift changed. Reload before changing its attendance setting.')
            updated = copy.deepcopy(self.metadata)
            previous_zone = (updated['pending'] or {}).get('timeZone', zone)
            updated['pending'] = {'start': start, 'kind': 'attendance' if attendance else 'work', 'timeZone': previous_zone,
                                  'overtime': (updated['pending'] or {}).get('overtime', False) if overtime is None else overtime}
            updated['revision'] += 1
            self.metadata_repository.save(updated)
            self.metadata = updated
            return self._response()

    def compliance(self, start='', end='', opt_out=None, zone='Europe/London'):
        from compliance import assess
        zone = time_zone(zone)
        with self.mutex, self.repository.locked():
            self._load()
            report = assess(self.core, self.session['stateEncoding'], self._snapshot(), self.metadata, start, end, zone)
            report['revision'] = self._revision()
            if opt_out is not None:
                if not isinstance(opt_out, dict) or set(opt_out) != {'start','end','answer','revision'} or type(opt_out['answer']) is not bool:
                    raise ValueError('Supply the reference period and opt-out answer.')
                if opt_out['revision'] != self._revision():
                    raise ValueError('The settings or shifts changed. Run the check again before answering.')
                period = (opt_out['start'], opt_out['end'])
                offered = {(f['start'], f['end']) for f in report['findings'] if f['code'] == 101}
                offered |= {(r['start'], r['end']) for r in report['optOuts']}
                if period not in offered:
                    raise ValueError('That reference period is no longer in this report. Run the check again.')
                updated = copy.deepcopy(self.metadata)
                updated['optOuts'] = [r for r in updated['optOuts'] if (r['start'], r['end']) != period]
                updated['optOuts'].append({k: opt_out[k] for k in ('start','end','answer')})
                updated['revision'] += 1
                self.metadata_repository.save(updated)
                self.metadata = updated
                report = assess(self.core, self.session['stateEncoding'], self._snapshot(), self.metadata, start, end, zone)
                report['revision'] = self._revision()
            return self._response(report=report)

    def _snapshot(self):
        result = self.core.call('readContained', self.session['sessionEncoding'], '@0', '@9223372036854774367')
        if result['code']:
            raise AdapterError(result['code'])
        return result['state']

    def state(self):
        with self.mutex, self.repository.locked():
            self._load()
            return self._response()

    def change(self, action, timestamp=None, end=None, attendance=None, zone='Europe/London', overtime=None):
        if overtime is not None and type(overtime) is not bool:
            raise ValueError('Overtime must be true or false.')
        if attendance is not None and type(attendance) is not bool:
            raise ValueError('Attendance time must be true or false.')
        zone = time_zone(zone)
        with self.mutex, self.repository.locked():
            self._load()
            old = copy.deepcopy(self.metadata)
            updated = copy.deepcopy(old)
            updated['revision'] += 1
            before = self.session['stateEncoding']
            previous = self._snapshot()
            if action == 'reset':
                after = self.core.call('emptyState')['stateEncoding']
                updated.update(spans=[], pending=None, optOuts=[])
                proposal = None
            else:
                operation = {'start': 'prepareStartShift', 'stop': 'prepareEndShift', 'missed-shift': 'prepareAddPair'}[action]
                arguments = [timestamp, end] if action == 'missed-shift' else [timestamp]
                proposal = self.core.call(operation, self.session['sessionEncoding'], *arguments)
                if proposal['code']:
                    message = MESSAGES[proposal['code']]
                    if action == 'missed-shift' and proposal['code'] == 2:
                        message = 'End must be later than start, by at least one recorded minute.'
                    if action == 'missed-shift' and proposal['code'] == 4:
                        message = 'A missed shift must finish at or before your running shift starts.'
                    return self._response(code=proposal['code'], message=message)
                after = proposal['storageRequest']['after']
                kind = None if attendance is None else 'attendance' if attendance else 'work'
                candidate = self.core.call('queryContained', after, '@0', '@9223372036854774367')['state']
                if action == 'start':
                    updated['pending'] = {'start': candidate['pending'], 'kind': kind, 'timeZone': zone, 'overtime': overtime if overtime is not None else False}
                else:
                    old_pieces = {tuple(p) for p in previous['shifts']}
                    pieces = [p for p in candidate['shifts'] if tuple(p) not in old_pieces]
                    if action == 'stop':
                        pending = updated['pending']
                        if overtime is None and pending:
                            overtime = pending.get('overtime', False)
                        if attendance is None and pending:
                            kind = pending['kind']
                        if pending and pending['timeZone'] != zone:
                            zone = None
                        updated['pending'] = None
                    updated['spans'].append({'start': pieces[0][0], 'end': pieces[-1][1],
                                             'kind': kind, 'timeZone': zone, 'pieces': pieces, 'overtime': overtime if overtime is not None else False})
            try:
                self.metadata_repository.commit(self.repository, before, after, self.raw_metadata, updated)
            except OSError as error:
                if proposal:
                    self.session = self.core.call('completeStore', proposal['sessionEncoding'], 'false')
                if self.metadata_repository.journal.exists():
                    raise OSError(str(error))
                return self._response(code=9, message=MESSAGES[9])
            self.session = self.core.call('completeStore', proposal['sessionEncoding'], 'true') if proposal else self.core.call('initializeStore', after)
            self.metadata = updated
            return self._response()
