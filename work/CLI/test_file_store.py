#!/usr/bin/env python3
"""Integration and write-failure tests for the CLI-only file adapter."""
from concurrent.futures import ThreadPoolExecutor
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch
import datetime
import hashlib
import importlib.util
import json
import os
import subprocess
import unittest

HERE = Path(__file__).resolve().parent
CLI = HERE/'bin/tracker'
spec = importlib.util.spec_from_file_location('file_store', HERE/'file_store.py')
adapter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adapter)


class FileStoreTests(unittest.TestCase):
    def setUp(self):
        self.directory = TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name)/'shifts with spaces.store'

    def command(self, command, *args, code=0, path=None):
        result = subprocess.run([str(CLI), command, str(path or self.path), *args], text=True, capture_output=True)
        self.assertEqual(result.returncode, code, result.stdout+result.stderr)
        return json.loads(result.stdout) if result.stdout else result.stderr

    def test_create_load_and_file_permissions(self):
        result = self.command('initializeStore')
        self.assertEqual(result['code'], 0)
        self.assertEqual(result['storeFile'], str(self.path.resolve()))
        self.assertEqual(self.path.read_text(), '-|\n')
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)
        self.path.write_text('@60|@0,@30\n')
        self.assertEqual(self.command('initializeStore')['stateEncoding'], '@60|@0,@30')
        self.assertEqual(self.path.read_text(), '@60|@0,@30\n')

    def test_add_query_delete_restart_and_midnight_split(self):
        self.command('initializeStore')
        added = self.command('addPair', '@1430', '@1450')
        self.assertFalse(added['waiting'])
        self.assertIsNone(added['storageRequest'])
        self.assertEqual(self.path.read_text(), '-|@1430,@1440;@1440,@1450\n')
        self.assertEqual(self.command('initializeStore')['stateEncoding'], added['stateEncoding'])
        before = self.path.stat().st_mtime_ns
        self.assertEqual(self.command('readContained', '@0', '@3000')['rows'], [[1430,1440],[1440,1450]])
        self.assertEqual(self.command('queryIntersecting', '@1440', '@1500')['rows'], [[1440,1450]])
        self.assertEqual(self.path.stat().st_mtime_ns, before)
        self.command('deleteShift', '@1440')
        self.assertEqual(self.path.read_text(), '-|@1430,@1440\n')

    def test_pending_start_and_prepare_commands_save_automatically(self):
        self.command('initializeStore')
        self.command('prepareStartShift', '@60')
        self.assertEqual(self.path.read_text(), '@60|\n')
        rejected = self.command('prepareEndShift', '@60', code=1)
        self.assertEqual(rejected['code'], 2)
        self.assertEqual(self.path.read_text(), '@60|\n')
        self.command('prepareEndShift', '@120')
        self.assertEqual(self.path.read_text(), '-|@60,@120\n')
        self.assertEqual(self.command('completeStore', 'true', code=1)['code'], 10)
        self.command('prepareDeleteShift', '@60')
        self.command('prepareAddPair', '@150', '@200')
        self.assertEqual(self.path.read_text(), '-|@150,@200\n')

    def test_invalid_input_does_not_overwrite_store(self):
        self.command('initializeStore')
        self.command('addPair', '@60', '@120')
        content = self.path.read_bytes()
        self.assertEqual(self.command('addPair', '@60', '@120', code=1)['code'], 3)
        self.command('addPair', 'invalid', '@180', code=2)
        self.assertEqual(self.path.read_bytes(), content)
        self.path.write_text('-|@10,@10\n')
        self.assertEqual(self.command('initializeStore', code=1)['code'], 7)
        self.assertEqual(self.path.read_text(), '-|@10,@10\n')
        self.path.write_text('corrupt\n')
        self.command('initializeStore', code=2)
        self.assertEqual(self.path.read_text(), 'corrupt\n')

    def test_failed_replace_rolls_back_and_cleans_temporary_file(self):
        self.command('initializeStore')
        self.command('startShift', '@60')
        before = self.path.read_bytes()
        output = StringIO()
        with patch.object(adapter.os, 'replace', side_effect=OSError('injected disk error')):
            with redirect_stdout(output):
                status = adapter.file_command('endShift', str(self.path), ['@3000'])
        self.assertEqual(status, 1)
        result = json.loads(output.getvalue())
        self.assertEqual(result['code'], 9)
        self.assertEqual(result['stateEncoding'], '@60|')
        self.assertFalse(result['waiting'])
        self.assertEqual(self.path.read_bytes(), before)
        self.assertEqual(sorted(p.name for p in self.path.parent.iterdir()), [self.path.name, self.path.name+'.lock'])

    def test_concurrent_processes_do_not_lose_updates(self):
        self.command('initializeStore')
        def add(i):
            return self.command('addPair', '@'+str(i*3), '@'+str(i*3+1))
        with ThreadPoolExecutor(max_workers=6) as pool:
            list(pool.map(add, range(12)))
        self.assertEqual(self.command('queryContained', '@0', '@100')['rows'], [[i*3,i*3+1] for i in range(12)])

    def test_existing_permissions_and_punctuation_filename(self):
        self.path = self.path.with_name('store#with|punctuation')
        self.command('initializeStore')
        os.chmod(self.path, 0o640)
        self.command('addPair', '@60', '@120')
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o640)
        self.assertEqual(self.path.read_text(), '-|@60,@120\n')

    def test_missing_file_and_bad_arity(self):
        self.command('addPair', '@60', '@120', code=2)
        self.assertFalse(self.path.exists())
        self.command('initializeStore', 'extra', code=2)
        self.assertFalse(self.path.exists())

    def test_explicit_state_commands_remain_available(self):
        result = subprocess.run([str(CLI), 'addPair', '-|', '@60', '@120'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(json.loads(result.stdout)['state']['shifts'], [[60,120]])


if __name__ == '__main__':
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(FileStoreTests))
    files = ['file_store.py','main.cj','bridge.cj','help.cj','generate_reference.py','build.py','test_file_store.py','bin/tracker','bin/tracker-core']
    (HERE/'file-store-tests.json').write_text(json.dumps({'finished_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'status':'passed' if result.wasSuccessful() else 'failed','tests':result.testsRun,'source_sha256':{f:hashlib.sha256((HERE/f).read_bytes()).hexdigest() for f in files}},indent=2)+'\n')
    raise SystemExit(0 if result.wasSuccessful() else 1)
