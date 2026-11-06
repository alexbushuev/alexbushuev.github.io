#!/usr/bin/env python3
# Local copy of the real site for testing: serves dist/ and passes /gaz-api/ to the accounts server, like Caddy does.
#   python3 tools/dev_server.py 8123 http://127.0.0.1:8788
import sys, urllib.request, os
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8123
API = sys.argv[2] if len(sys.argv) > 2 else "http://127.0.0.1:8788"
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "dist")


class H(SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory=ROOT, **k)

    def log_message(self, *a):
        pass

    def _proxy(self, method):
        n = int(self.headers.get("Content-Length") or 0)
        data = self.rfile.read(n) if n else None
        req = urllib.request.Request(API + self.path, data=data, method=method,
                                     headers={k: v for k, v in self.headers.items() if k.lower() in ("content-type", "authorization")})
        try:
            r = urllib.request.urlopen(req, timeout=15)
            code, body = r.status, r.read()
        except urllib.error.HTTPError as e:
            code, body = e.code, e.read()
        except Exception:
            code, body = 502, b'{"error":"bad gateway"}'
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.startswith("/gaz-api/"):
            return self._proxy("GET")
        return super().do_GET()

    def do_POST(self):
        return self._proxy("POST")

    def do_PUT(self):
        return self._proxy("PUT")


ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
