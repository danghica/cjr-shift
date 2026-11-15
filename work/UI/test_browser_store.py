"""Browser snapshots run through the real core, without shared persistence."""
import json
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch, MagicMock
from urllib.request import Request, urlopen
from urllib.error import HTTPError
import threading
import unittest
from server import make_server, main


class BrowserStoreTests(unittest.TestCase):
    def setUp(self):
        self.tmp=TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.old_store=Path(self.tmp.name)/'old-shared.store'
        self.old_store.write_text('old shared records must not be loaded')
        self.server=make_server(self.old_store,0,browser_storage=True)
        threading.Thread(target=self.server.serve_forever,daemon=True).start()
        self.addCleanup(self.server.server_close);self.addCleanup(self.server.shutdown)
        self.base=f'http://127.0.0.1:{self.server.server_port}'

    def call(self,action='state',data=None,snapshot=None,path='/api/browser'):
        payload={'action':action,'data':data or {},'snapshot':snapshot}
        request=Request(self.base+path,data=json.dumps(payload).encode(),headers={'Content-Type':'application/json','X-Tracker-UI':'1'})
        try: response=urlopen(request)
        except HTTPError as error: response=error
        with response:return response.status,json.load(response)

    def test_two_browsers_are_independent_and_old_shared_api_is_disabled(self):
        status,a=self.call('start',{'timestamp':'2026-11-12T09:00','attendance':False,'overtime':True})
        self.assertEqual(status,200);self.assertTrue(a['browserStorage']);self.assertFalse(a['demo'])
        self.assertIsNotNone(a['state']['pending'])
        _,b=self.call();self.assertEqual(b['state'],{'pending':None,'shifts':[]})
        _,again=self.call(snapshot=a['snapshot']);self.assertEqual(again['state'],a['state'])
        self.assertTrue(again['pendingOvertime'])
        self.assertEqual(self.call(path='/api/reset')[0],409)
        try:urlopen(self.base+'/api/state')
        except HTTPError as error:
            with error:self.assertEqual(error.code,409)
        else:self.fail('Shared data route must be disabled')
        self.assertEqual(self.old_store.read_text(),'old shared records must not be loaded')

    def test_full_snapshot_round_trip_settings_midnight_reset_and_compliance(self):
        settings={'restScheme':1,'fortnightStart':'','nightWorker':False,'hazardousNightWork':False}
        _,a=self.call('settings',settings)
        _,a=self.call('missed-shift',{'start':'2026-11-10T23:00','end':'2026-11-11T01:00','attendance':False,'overtime':True},a['snapshot'])
        self.assertEqual(len(a['overtime']),2);self.assertTrue(all(a['overtime'].values()))
        snapshot=a['snapshot']
        _,a=self.call('compliance',snapshot=snapshot)
        self.assertEqual(a['report']['validatorCode'],0,a)
        _,reset=self.call('reset',{'confirmed':True},snapshot)
        self.assertEqual(reset['state'],{'pending':None,'shifts':[]})
        self.assertEqual(reset['settings'],settings)
        self.assertEqual(reset['snapshot']['metadata']['spans'],[])
        self.assertEqual(reset['snapshot']['metadata']['optOuts'],[])
        # Resetting one browser never changes a separately saved snapshot.
        self.assertEqual(len(self.call(snapshot=snapshot)[1]['state']['shifts']),2)

    def test_invalid_and_failed_requests_do_not_return_a_saveable_snapshot(self):
        _,a=self.call('start',{'timestamp':'2026-11-12T09:00','attendance':False})
        status,b=self.call('stop',{'timestamp':'2026-11-12T09:00'},a['snapshot'])
        self.assertEqual(status,409);self.assertNotIn('snapshot',b)
        status,b=self.call(snapshot={'version':1,'encoding':'broken','metadata':a['snapshot']['metadata']})
        self.assertEqual(status,400);self.assertNotIn('snapshot',b)
        self.assertEqual(self.call(snapshot={'version':2})[0],400)
        self.assertEqual(self.call('not-an-action')[0],400)
        self.assertEqual(self.call('state',snapshot={'version':1,'encoding':'-|','metadata':{}})[0],400)

    def test_temporary_files_are_removed_after_each_request(self):
        paths=[]
        def temporary(**kwargs):
            item=TemporaryDirectory(**kwargs);paths.append(Path(item.name));return item
        with patch('server.TemporaryDirectory',side_effect=temporary):
            self.call('start',{'timestamp':'2026-11-12T09:00','attendance':False})
        self.assertTrue(paths);self.assertTrue(all(not p.exists() for p in paths))

    def test_main_defaults_to_browser_storage_without_volume(self):
        fake=MagicMock();fake.server_port=8080;fake.serve_forever.side_effect=KeyboardInterrupt
        with patch.dict('os.environ',{'PORT':'8080','RAILWAY_ENVIRONMENT_ID':'test'},clear=True),patch('sys.argv',['server.py']),patch('server.make_server',return_value=fake) as build:
            main()
        self.assertTrue(build.call_args.args[-1]);fake.server_close.assert_called_once()

if __name__=='__main__':unittest.main(verbosity=2)
