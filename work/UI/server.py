#!/usr/bin/env python3
"""Local HTTP adapter for the JavaScript UI; run with --store FILE --port PORT."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit
import argparse
import json
import sys

from adapters import AdapterError, TrackerAdapter

HERE = Path(__file__).resolve().parent
STATIC = {'/': ('index.html', 'text/html; charset=utf-8'),
          '/time.mjs': ('time.mjs', 'text/javascript; charset=utf-8'),
          '/app.js': ('app.js', 'text/javascript; charset=utf-8'),
          '/style.css': ('style.css', 'text/css; charset=utf-8')}


def make_server(store, port=8765):
    tracker = TrackerAdapter(store)

    class Handler(BaseHTTPRequestHandler):
        def reply(self, status, payload, content_type='application/json; charset=utf-8'):
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
            return self.headers.get('Host') in {f'localhost:{self.server.server_port}', f'127.0.0.1:{self.server.server_port}'}

        def do_GET(self):
            if not self.valid_host():
                return self.reply(403, {'message': 'Open the app using its localhost address.'})
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
            if not self.valid_host() or (origin is not None and origin not in allowed) or self.headers.get('X-Tracker-UI') != '1':
                return self.reply(403, {'message': 'This action must come from the local tracker.'})
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
                    return self.reply(200, tracker.attendance(data.get('start'), data.get('attendance'), data.get('timeZone', 'Europe/London')))
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
                result = tracker.change(action, timestamp, end, data.get('attendance'), data.get('timeZone', 'Europe/London'))
                return self.reply(200 if result['code'] == 0 else 503 if result['code'] == 9 else 409, result)
            except (ValueError, json.JSONDecodeError) as error:
                return self.reply(400, {'message': str(error)})
            except (AdapterError, OSError) as error:
                return self.reply(503, {'message': str(error)})

    server = ThreadingHTTPServer(('127.0.0.1', port), Handler)
    server.tracker = tracker
    return server


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--store', type=Path, default=HERE/'data'/'shifts.store')
    parser.add_argument('--port', type=int, default=8765)
    args = parser.parse_args()
    if args.store == HERE/'data'/'shifts.store':
        args.store.parent.mkdir(parents=True, exist_ok=True)
    try:
        server = make_server(args.store, args.port)
    except (OSError, ValueError, AdapterError) as error:
        parser.exit(1, f'Could not start tracker: {error}\nBuild the CLI first with python3 work/CLI/build.py if needed.\n')
    print(f'Work tracker: http://127.0.0.1:{server.server_port}', flush=True)
    print(f'Store: {server.tracker.repository.path}', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
