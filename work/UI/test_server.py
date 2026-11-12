#!/usr/bin/env python3
"""Adapter and HTTP integration tests using temporary stores and the real core."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.request import Request, urlopen
import hashlib
import json
import threading
import unittest

from adapters import AdapterError, TrackerAdapter, file_adapter
from server import make_server

HERE = Path(__file__).resolve().parent


class AdapterTests(unittest.TestCase):
    def setUp(self):
        self.directory = TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name)/'shifts.store'
        self.app = TrackerAdapter(self.path)

    def test_start_stop_and_restart(self):
        self.assertEqual(self.path.read_text(), '-|\n')
        started = self.app.change('start', '2026-11-11T09:00')
        self.assertIsNotNone(started['state']['pending'])
        self.assertEqual(TrackerAdapter(self.path).state()['state'], started['state'])
        stopped = self.app.change('stop', '2026-11-11T17:00')
        self.assertIsNone(stopped['state']['pending'])
        self.assertEqual(stopped['state']['shifts'][0][1]-stopped['state']['shifts'][0][0], 480)
        self.assertEqual(TrackerAdapter(self.path).state()['state'], stopped['state'])

    def test_same_minute_and_duplicate_start(self):
        started = self.app.change('start', '2026-11-11T09:00')
        self.assertEqual(self.app.change('start', '2026-11-11T09:00')['code'], 4)
        failed = self.app.change('stop', '2026-11-11T09:00')
        self.assertEqual(failed['code'], 2)
        self.assertEqual(failed['state'], started['state'])

    def test_midnight(self):
        self.app.change('start', '2026-11-11T23:30')
        rows = self.app.change('stop', '2026-11-12T01:00')['state']['shifts']
        self.assertEqual([b-a for a,b in rows], [30,60])
        self.assertEqual(rows[0][1], rows[1][0])

    def test_reset_clears_saved_and_running_shifts(self):
        self.app.change('start', '2026-11-11T09:00')
        self.app.change('stop', '2026-11-11T10:00')
        self.app.change('start', '2026-11-11T11:00')
        reset = self.app.change('reset')
        self.assertEqual(reset['state'], {'pending':None,'shifts':[]})
        self.assertEqual(self.path.read_text(), '-|\n')

    def test_failed_stop_and_failed_reset_preserve_file_and_pending(self):
        before = self.app.change('start', '2026-11-11T09:00')['state']
        contents = self.path.read_bytes()
        with patch.object(file_adapter.os, 'replace', side_effect=OSError('simulated disk failure')):
            for action, timestamp in [('stop','2026-11-11T10:00'),('reset',None)]:
                failed = self.app.change(action, timestamp)
                self.assertEqual(failed['code'], 9)
                self.assertEqual(failed['state'], before)
                self.assertEqual(self.path.read_bytes(), contents)
        self.assertEqual(self.app.change('stop','2026-11-11T10:00')['code'], 0)

    def test_external_changes_reconcile_and_corruption_is_preserved(self):
        external = TrackerAdapter(self.path)
        external.change('start', '2026-11-11T09:00')
        self.assertIsNotNone(self.app.state()['state']['pending'])
        self.path.write_text('-|@10,@10\n')
        with self.assertRaises(AdapterError): self.app.state()
        with self.assertRaises(AdapterError): TrackerAdapter(self.path)
        self.assertEqual(self.path.read_text(), '-|@10,@10\n')

    def test_only_one_concurrent_start_succeeds(self):
        with ThreadPoolExecutor(max_workers=4) as pool:
            results = list(pool.map(lambda _: self.app.change('start','2026-11-11T09:00'),range(4)))
        self.assertEqual(sorted(r['code'] for r in results), [0,4,4,4])


    def test_missed_shift_persists_and_splits_at_midnight(self):
        added = self.app.change('missed-shift', '2026-11-10T23:30', '2026-11-11T01:00')
        self.assertEqual(added['code'], 0)
        self.assertEqual([b-a for a,b in added['state']['shifts']], [30,60])
        self.assertIsNone(added['state']['pending'])
        self.assertEqual(TrackerAdapter(self.path).state()['state'], added['state'])
        before = self.path.read_bytes()
        self.assertEqual(self.app.change('missed-shift', '2026-11-10T23:30', '2026-11-11T01:00')['code'], 3)
        self.assertEqual(self.path.read_bytes(), before)

    def test_missed_shift_rejection_and_disk_failure_preserve_state(self):
        running = self.app.change('start', '2026-11-11T12:00')['state']
        for start,end,code in [('2026-11-11T10:00','2026-11-11T10:00',2),
                               ('2026-11-11T11:00','2026-11-11T10:00',2),
                               ('2026-11-11T11:00','2026-11-11T13:00',4)]:
            rejected = self.app.change('missed-shift', start, end)
            self.assertEqual(rejected['code'], code)
            self.assertEqual(rejected['state'], running)
        contents = self.path.read_bytes()
        with patch.object(file_adapter.os, 'replace', side_effect=OSError('simulated disk failure')):
            failed = self.app.change('missed-shift', '2026-11-11T09:00', '2026-11-11T10:00')
        self.assertEqual(failed['code'], 9)
        self.assertEqual(failed['state'], running)
        self.assertEqual(self.path.read_bytes(), contents)
        added = self.app.change('missed-shift', '2026-11-11T09:00', '2026-11-11T10:00')
        self.assertEqual(added['code'], 0)
        self.assertEqual(added['state']['pending'], running['pending'])


class HTTPTests(unittest.TestCase):
    def setUp(self):
        self.directory = TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name)/'store'
        self.server = make_server(self.path, 0)
        thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(self.stop_server)
        self.base = f'http://127.0.0.1:{self.server.server_port}'

    def stop_server(self):
        self.server.shutdown()
        self.server.server_close()

    def request(self, route, data=None, headers=None):
        defaults={'Content-Type':'application/json','X-Tracker-UI':'1'}
        defaults.update(headers or {})
        req=Request(self.base+route, data=None if data is None else json.dumps(data).encode(),headers=defaults)
        try:
            response=urlopen(req)
        except HTTPError as error:
            response=error
        with response:
            body=response.read()
            return response.status,json.loads(body) if response.headers.get_content_type()=='application/json' else body.decode()

    def test_assets_and_start_stop(self):
        for asset in ['/','/app.js','/style.css','/time.mjs']:
            self.assertEqual(self.request(asset)[0],200)
        self.assertEqual(self.request('/api/state')[1]['state'],{'pending':None,'shifts':[]})
        self.assertEqual(self.request('/api/start',{'timestamp':'2026-11-11T09:00'})[0],200)
        self.assertEqual(self.request('/api/stop',{'timestamp':'2026-11-11T09:00'})[0],409)
        self.assertEqual(self.request('/api/stop',{'timestamp':'2026-11-11T09:01'})[0],200)

    def test_reset_confirmation_and_request_validation(self):
        self.request('/api/start',{'timestamp':'2026-11-11T09:00'})
        self.assertEqual(self.request('/api/reset',{})[0],400)
        self.assertIsNotNone(self.request('/api/state')[1]['state']['pending'])
        self.assertEqual(self.request('/api/reset',{'confirmed':True})[1]['state'],{'pending':None,'shifts':[]})
        self.assertEqual(self.request('/api/start',{'timestamp':'invalid'})[0],400)
        self.assertEqual(self.request('/api/start',{'timestamp':'2026-02-30T09:00'})[0],400)
        self.assertEqual(self.request('/api/reset',{'confirmed':True},headers={'Origin':'https://foreign.example'})[0],403)
        self.assertEqual(self.request('/api/reset',{'confirmed':True},headers={'X-Tracker-UI':'0'})[0],403)
        status, missing = self.request('/../server.py')
        self.assertEqual(status,404)
        self.assertIn('Restart the UI server', missing['message'])

    def test_missed_shift_api(self):
        status, added = self.request('/api/missed-shift', {'start':'2026-11-11T09:00','end':'2026-11-11T10:00'})
        self.assertEqual(status, 200)
        self.assertEqual(added['state']['shifts'][0][1]-added['state']['shifts'][0][0], 60)
        self.assertEqual(self.request('/api/missed-shift', {'start':'2026-11-11T09:00','end':'2026-11-11T10:00'})[0], 409)
        for data in [{'start':'2026-11-11T09:00'}, {'end':'2026-11-11T10:00'},
                     {'start':'2026-02-30T09:00','end':'2026-11-11T10:00'},
                     {'start':'2026-11-11T09:00','end':42}]:
            self.assertEqual(self.request('/api/missed-shift', data)[0], 400)

    def test_metadata_settings_and_compliance_routes(self):
        status, initial = self.request('/api/settings')
        self.assertEqual(status,200)
        self.assertIsNone(initial['settings']['nightWorker'])
        settings = dict(initial['settings'],nightWorker=True,hazardousNightWork=True)
        self.assertEqual(self.request('/api/settings',settings)[0],200)
        self.assertEqual(self.request('/api/settings',dict(settings,restScheme=2))[0],400)
        started=self.request('/api/start',{'timestamp':'2026-01-05T23:00','attendance':False})[1]
        pending=started['state']['pending']
        changed=self.request('/api/attendance',{'start':pending,'attendance':True})[1]
        self.assertEqual(changed['pendingKind'],'attendance')
        self.assertEqual(changed['state']['pending'],pending)
        self.assertEqual(self.request('/api/attendance',{'start':pending+1,'attendance':False})[0],400)
        self.request('/api/stop',{'timestamp':'2026-01-06T09:00','attendance':False})
        before=self.path.read_bytes()
        status,result=self.request('/api/compliance',{'start':'','end':''})
        self.assertEqual(status,200)
        self.assertEqual(result['report']['validatorCode'],106)
        self.assertTrue(result['report']['findings'])
        self.assertEqual(self.path.read_bytes(),before)
        self.assertEqual(self.request('/api/compliance',{'start':42})[0],400)
        self.assertEqual(self.request('/api/opt-out',{'optOut':{'answer':True}})[0],400)
        self.assertEqual(self.request('/api/settings',settings,headers={'Origin':'https://foreign.example'})[0],403)

    def test_save_failure_returns_old_state(self):
        started = self.request('/api/start',{'timestamp':'2026-11-11T09:00'})[1]['state']
        with patch.object(self.server.tracker.repository,'save',side_effect=OSError('disk failure')):
            status,result = self.request('/api/stop',{'timestamp':'2026-11-11T10:00'})
        self.assertEqual(status,503)
        self.assertEqual(result['code'],9)
        self.assertEqual(result['state'],started)


if __name__ == '__main__':
    unittest.main(verbosity=2)
