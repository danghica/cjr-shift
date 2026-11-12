#!/usr/bin/env python3
"""HTTP adapter for the JavaScript UI, with local defaults and optional Railway hosting."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit
import argparse
import json
import os
import sys

from adapters import AdapterError, TrackerAdapter

HERE = Path(__file__).resolve().parent
STATIC = {'/': ('index.html', 'text/html; charset=utf-8'),
          '/time.mjs': ('time.mjs', 'text/javascript; charset=utf-8'),
          '/app.js': ('app.js', 'text/javascript; charset=utf-8'),
          '/style.css': ('style.css', 'text/css; charset=utf-8')}


def make_server(store, port=8765, host='127.0.0.1', public_origin=None, demo=False):
    if public_origin:
        origin = urlsplit(public_origin)
        if origin.scheme not in ('http', 'https') or not origin.hostname or origin.username or origin.password or origin.path not in ('', '/') or origin.query or origin.fragment:
            raise ValueError('The public address must be an HTTP(S) origin without a path or credentials.')
        public_origin = origin.scheme.lower() + '://' + origin.netloc.lower()
    tracker = TrackerAdapter(store)

    class Handler(BaseHTTPRequestHandler):
        def reply(self, status, payload, content_type='application/json; charset=utf-8'):
            if isinstance(payload, dict) and 'state' in payload:
                payload = dict(payload, demo=demo)
            body = json.dumps(payload).encode() if isinstance(payload, dict) else payload
            self.send_response(status)
            self.send_header('Content-Type', content_type)
            self.send_header('Content-Length', str(len(body)))
            self.send_header('Cache-Control', 'no-store')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.send_header('Content-Security-Policy', "default-src 'self'; style-src 'self'; script-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'")
            self.end_headers()
            self.wfile.write(body)

        def valid_host(self):
            allowed = {f'localhost:{self.server.server_port}', f'127.0.0.1:{self.server.server_port}'}
            if public_origin:
                allowed.add(urlsplit(public_origin).netloc)
            return self.headers.get('Host', '').lower() in allowed

        def do_GET(self):
            path = urlsplit(self.path).path
            if path == '/health':
                return self.reply(200, {'status': 'ok'})
            if not self.valid_host():
                return self.reply(403, {'message': 'Open the app using its configured address.' if public_origin else 'Open the app using its localhost address.'})
            path = urlsplit(self.path).path
            if path in STATIC:
                name, content_type = STATIC[path]
                return self.reply(200, (HERE/'static'/name).read_bytes(), content_type)
            if path not in ('/api/state', '/api/settings'):
                return self.reply(404, {'message': 'This page or action is not available on this server. Restart the UI server and reload the tracker page.'})
            try:
                return self.reply(200, tracker.state())
            except (AdapterError, OSError, ValueError) as error:
                return self.reply(503, {'message': str(error)})

        def do_POST(self):
            origin = self.headers.get('Origin')
            allowed = {f'http://localhost:{self.server.server_port}', f'http://127.0.0.1:{self.server.server_port}'}
            if public_origin:
                allowed.add(public_origin)
            if not self.valid_host() or (origin is not None and origin not in allowed) or self.headers.get('X-Tracker-UI') != '1':
                return self.reply(403, {'message': 'This action must come from this tracker page.'})
            path = urlsplit(self.path).path
            if path not in ('/api/start', '/api/stop', '/api/reset', '/api/missed-shift', '/api/settings', '/api/attendance', '/api/compliance', '/api/opt-out'):
                return self.reply(404, {'message': 'This page or action is not available on this server. Restart the UI server and reload the tracker page.'})
            try:
                size = int(self.headers.get('Content-Length', '0'))
                if not 0 < size <= 4096 or self.headers.get_content_type() != 'application/json':
                    return self.reply(400, {'message': 'Expected a small JSON request.'})
                data = json.loads(self.rfile.read(size))
                if not isinstance(data, dict):
                    raise ValueError('Expected an object.')
                action = path.rsplit('/', 1)[1]
                if action == 'settings':
                    return self.reply(200, tracker.save_settings(data))
                if action == 'attendance':
                    return self.reply(200, tracker.attendance(data.get('start'), data.get('attendance'), data.get('timeZone', 'Europe/London'), data.get('overtime')))
                if action in ('compliance', 'opt-out'):
                    for key in ('start', 'end'):
                        if not isinstance(data.get(key, ''), str):
                            raise ValueError('Assessment dates must be strings or blank.')
                    return self.reply(200, tracker.compliance(data.get('start', ''), data.get('end', ''),
                        data.get('optOut') if action == 'opt-out' else None, data.get('timeZone', 'Europe/London')))
                timestamp = data.get('start') if action == 'missed-shift' else data.get('timestamp')
                end = data.get('end')
                if action == 'missed-shift' and (not isinstance(end, str) or len(end) != 16):
                    raise ValueError('An end timestamp in YYYY-MM-DDTHH:MM format is required.')
                if action != 'reset' and (not isinstance(timestamp, str) or len(timestamp) != 16):
                    raise ValueError('A local timestamp in YYYY-MM-DDTHH:MM format is required.')
                if action == 'reset' and data.get('confirmed') is not True:
                    raise ValueError('Reset requires confirmation.')
                result = tracker.change(action, timestamp, end, data.get('attendance'), data.get('timeZone', 'Europe/London'), data.get('overtime'))
                return self.reply(200 if result['code'] == 0 else 503 if result['code'] == 9 else 409, result)
            except (ValueError, json.JSONDecodeError) as error:
                return self.reply(400, {'message': str(error)})
            except (AdapterError, OSError) as error:
                return self.reply(503, {'message': str(error)})

    server = ThreadingHTTPServer((host, port), Handler)
    server.tracker = tracker
    return server


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    volume = os.environ.get('RAILWAY_VOLUME_MOUNT_PATH')
    default_store = Path(volume)/'shifts.store' if volume else HERE/'data'/'shifts.store'
    parser.add_argument('--store', type=Path, default=os.environ.get('TRACKER_STORE_FILE', default_store))
    parser.add_argument('--port', type=int, default=os.environ.get('PORT', 8765))
    parser.add_argument('--host', default=os.environ.get('TRACKER_HOST', '0.0.0.0' if 'PORT' in os.environ else '127.0.0.1'))
    domain = os.environ.get('RAILWAY_PUBLIC_DOMAIN')
    parser.add_argument('--public-origin', default=os.environ.get('TRACKER_PUBLIC_ORIGIN') or ('https://'+domain if domain else None))
    parser.add_argument('--demo', action='store_true', default=os.environ.get('TRACKER_DEMO', '').lower() == 'true')
    args = parser.parse_args()
    if os.environ.get('RAILWAY_ENVIRONMENT_ID'):
        if not volume or not args.store.resolve().is_relative_to(Path(volume).resolve()):
            parser.exit(1, 'Attach a persistent Railway volume and put the store inside its mount path.\n')
    if args.store == HERE/'data'/'shifts.store' or volume:
        args.store.parent.mkdir(parents=True, exist_ok=True)
    try:
        server = make_server(args.store, args.port, args.host, args.public_origin, args.demo)
    except (OSError, ValueError, AdapterError) as error:
        parser.exit(1, f'Could not start tracker: {error}\nBuild the CLI first with python3 work/CLI/build.py if needed.\n')
    print(f'Work tracker: {args.public_origin or ("http://"+args.host+":"+str(server.server_port))}', flush=True)
    print(f'Store: {server.tracker.repository.path}', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
