#!/usr/bin/env python3
"""File adapter for the verified tracker executable; no domain rules live here."""
from contextlib import contextmanager
from pathlib import Path
import fcntl
import json
import os
import stat
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
NATIVE = Path(__file__).resolve().parent / 'bin' / 'tracker-core'
MUTATIONS = {
    'addPair': 'prepareAddPair', 'startShift': 'prepareStartShift',
    'endShift': 'prepareEndShift', 'deleteShift': 'prepareDeleteShift',
    'prepareAddPair': 'prepareAddPair', 'prepareStartShift': 'prepareStartShift',
    'prepareEndShift': 'prepareEndShift', 'prepareDeleteShift': 'prepareDeleteShift',
}
READS = {'queryContained': 'readContained', 'queryIntersecting': 'readIntersecting',
         'readContained': 'readContained', 'readIntersecting': 'readIntersecting'}
COUNTS = {name: (2 if name in ('addPair', 'prepareAddPair') else 1) for name in MUTATIONS}
COUNTS.update({name: 2 for name in READS})
COUNTS.update({'validState': 0, 'completeStore': 1})


def core(*args):
    result = subprocess.run([str(NATIVE), *args], text=True, capture_output=True)
    if result.returncode not in (0, 1):
        raise ValueError(result.stderr.strip() or 'native CLI failed')
    return json.loads(result.stdout)


def emit(result):
    print(json.dumps(result, separators=(',', ':')))
    return 0 if result.get('code', 0) == 0 and result.get('valid', True) else 1


@contextmanager
def locked(path):
    # Keep the lock inode: unlinking it could give concurrent writers different locks.
    lock = path.with_name(path.name + '.lock')
    with lock.open('a+b') as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        yield


def save(path, encoding):
    """Atomic visibility: every failure before replace leaves the old file intact.

    No fallible work follows replace. Directory-entry crash durability is not
    promised; this adapter handles definitive local write failures.
    """
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o600
    descriptor, temporary = tempfile.mkstemp(prefix='.' + path.name + '.', dir=path.parent)
    try:
        with os.fdopen(descriptor, 'w', encoding='utf-8') as handle:
            os.fchmod(handle.fileno(), mode)
            handle.write(encoding + '\n')
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
        temporary = None
    finally:
        # After successful replacement temporary no longer exists.
        if temporary is not None:
            try:
                os.unlink(temporary)
            except OSError:
                pass


def file_command(command, filename, arguments):
    path = Path(filename).expanduser().resolve()
    if command == 'initializeStore':
        if arguments:
            raise ValueError('initializeStore requires FILE')
    elif command not in COUNTS or len(arguments) != COUNTS[command]:
        raise ValueError('wrong command arguments; run help')
    if command == 'completeStore' and arguments[0] not in ('true', 'false'):
        raise ValueError('completeStore requires FILE true|false')
    with locked(path):
        if not path.exists():
            if command != 'initializeStore':
                raise ValueError('store does not exist; run initializeStore FILE first')
            save(path, '-|')
        loaded = path.read_text(encoding='utf-8').strip()
        session = core('initializeStore', loaded)
        session['storeFile'] = str(path)
        if session['code'] or command == 'initializeStore':
            return emit(session)
        if command == 'validState':
            return emit(core('validState', loaded))
        if command in READS:
            return emit(core(READS[command], session['sessionEncoding'], *arguments))
        if command == 'completeStore':
            # File-backed mutations already complete their own save protocol.
            result = core(command, session['sessionEncoding'], *arguments)
            result['storeFile'] = str(path)
            return emit(result)
        proposal = core(MUTATIONS[command], session['sessionEncoding'], *arguments)
        if proposal['code']:
            proposal['storeFile'] = str(path)
            return emit(proposal)
        try:
            save(path, proposal['storageRequest']['after'])
        except OSError as error:
            result = core('completeStore', proposal['sessionEncoding'], 'false')
            result['storeFile'] = str(path)
            result['storageError'] = str(error)
            return emit(result)
        result = core('completeStore', proposal['sessionEncoding'], 'true')
        result['storeFile'] = str(path)
        return emit(result)


def main(args=None):
    args = sys.argv[1:] if args is None else args
    try:
        if args and args[0] == 'validateWorkingTime':
            if len(args) != 5:
                raise ValueError('validateWorkingTime requires FILE|STATE START END METADATA.json')
            # The adapter reads input files and converts representations; the core calculates every finding.
            from working_time_metadata import encode_metadata
            encoded = encode_metadata(args[4])
            value = args[1]
            is_file = '|' not in value and '#' not in value
            if not is_file:
                try:
                    is_file = Path(value).expanduser().exists()
                except OSError:
                    pass
            if is_file:
                path = Path(value).expanduser().resolve()
                with locked(path):
                    loaded = path.read_text(encoding='utf-8').strip()
                    return subprocess.run([str(NATIVE), args[0], loaded, args[2], args[3], encoded]).returncode
            return subprocess.run([str(NATIVE), args[0], value, args[2], args[3], encoded]).returncode
        if args and args[0] == 'initializeStore':
            if len(args) != 2:
                raise ValueError('initializeStore requires FILE')
            return file_command(args[0], args[1], [])
        if len(args) >= 2 and args[0] in COUNTS:
            value = args[1]
            # Preserve the existing explicit-state/session commands for simulation.
            # Existing paths take precedence, even when their names contain | or #.
            is_file = '|' not in value and '#' not in value
            if not is_file:
                try:
                    is_file = Path(value).expanduser().exists()
                except OSError:
                    pass
            if is_file:
                return file_command(args[0], value, args[2:])
        return subprocess.run([str(NATIVE), *args]).returncode
    except (OSError, ValueError) as error:
        print('error: ' + str(error), file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
