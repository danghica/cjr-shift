"""Railway networking and persistent-store configuration; no proof tools."""
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch, MagicMock
from urllib.request import Request, urlopen
from urllib.error import HTTPError
import json
import threading
import unittest

from server import make_server, main


class HostedHTTPTests(unittest.TestCase):
    def setUp(self):
        self.tmp=TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.server=make_server(Path(self.tmp.name)/'shifts.store',0,public_origin='https://shift.example',demo=True)
        threading.Thread(target=self.server.serve_forever,daemon=True).start()
        self.addCleanup(self.server.server_close);self.addCleanup(self.server.shutdown)
        self.base=f'http://127.0.0.1:{self.server.server_port}'

    def call(self,path,data=None,**headers):
        values={'Host':'shift.example','Content-Type':'application/json','X-Tracker-UI':'1',**headers}
        req=Request(self.base+path,data=json.dumps(data).encode() if data is not None else None,headers=values)
        try: response=urlopen(req)
        except HTTPError as error: response=error
        with response:return response.status,json.loads(response.read())

    def test_public_origin_demo_and_same_origin_write(self):
        status,state=self.call('/api/state')
        self.assertEqual(status,200);self.assertTrue(state['demo'])
        status,state=self.call('/api/start',{'timestamp':'2026-11-12T09:00','attendance':False},Origin='https://shift.example')
        self.assertEqual(status,200);self.assertIsNotNone(state['state']['pending'])
        self.assertEqual(self.call('/api/stop',{'timestamp':'2026-11-12T10:00'},Origin='https://foreign.example')[0],403)
        self.assertEqual(self.call('/api/state',Host='foreign.example')[0],403)
        self.assertEqual(self.call('/api/start',{'timestamp':'2026-11-12T10:00'},Origin='https://shift.example',**{'X-Tracker-UI':'0'})[0],403)

    def test_healthcheck_has_no_data_and_accepts_railway_health_host(self):
        status,health=self.call('/health',Host='healthcheck.railway.app')
        self.assertEqual((status,health),(200,{'status':'ok'}))
        self.assertEqual(self.call('/api/state',Host='healthcheck.railway.app')[0],403)

    def test_public_origin_must_be_an_origin(self):
        for address in ('https://shift.example/path','https://user:password@shift.example','https://shift.example?x=1','file:///tmp'):
            with self.assertRaises(ValueError):make_server(Path(self.tmp.name)/'invalid',0,public_origin=address)


class HostingConfigurationTests(unittest.TestCase):
    def test_railway_uses_platform_port_volume_and_domain(self):
        with TemporaryDirectory() as folder:
            volume=Path(folder)/'volume'
            fake=MagicMock();fake.server_port=8080;fake.serve_forever.side_effect=KeyboardInterrupt
            env={'PORT':'8080','RAILWAY_ENVIRONMENT_ID':'test','RAILWAY_VOLUME_MOUNT_PATH':str(volume),
                 'RAILWAY_PUBLIC_DOMAIN':'shift.up.railway.app','TRACKER_DEMO':'true'}
            with patch.dict('os.environ',env,clear=True),patch('sys.argv',['server.py']),patch('server.make_server',return_value=fake) as build:
                main()
            build.assert_called_once_with(volume/'shifts.store',8080,'0.0.0.0','https://shift.up.railway.app',True)
            self.assertTrue(volume.exists());fake.server_close.assert_called_once()

    def test_railway_refuses_ephemeral_or_wrong_mount_store(self):
        with TemporaryDirectory() as folder:
            for env in [dict(PORT='8080',RAILWAY_ENVIRONMENT_ID='test'),
                        dict(PORT='8080',RAILWAY_ENVIRONMENT_ID='test',RAILWAY_VOLUME_MOUNT_PATH=folder,TRACKER_STORE_FILE='/app/shifts.store')]:
                with patch.dict('os.environ',env,clear=True),patch('sys.argv',['server.py']),patch('server.make_server') as build:
                    with self.assertRaises(SystemExit) as caught:main()
                    self.assertEqual(caught.exception.code,1);build.assert_not_called()

    def test_local_defaults_stay_on_loopback_without_demo(self):
        with TemporaryDirectory() as folder:
            path=Path(folder)/'store'
            fake=MagicMock();fake.server_port=8765;fake.serve_forever.side_effect=KeyboardInterrupt
            with patch.dict('os.environ',{},clear=True),patch('sys.argv',['server.py','--store',str(path)]),patch('server.make_server',return_value=fake) as build:
                main()
            build.assert_called_once_with(path,8765,'127.0.0.1',None,False)

if __name__=='__main__':unittest.main(verbosity=2)
