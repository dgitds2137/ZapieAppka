from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
import os

root = Path(r"C:\FFApi\zapieapp\build\web")
os.chdir(root)

class SpaHandler(SimpleHTTPRequestHandler):
    def do_GET(self):
        request_path = self.path.split('?', 1)[0].split('#', 1)[0]
        if request_path.startswith('/auth/callback'):
            self.path = '/index.html'
            return super().do_GET()
        target = Path(self.translate_path(request_path))
        if request_path in ('', '/'):
            self.path = '/index.html'
        elif not target.exists():
            self.path = '/index.html'
        return super().do_GET()

ThreadingHTTPServer(('127.0.0.1', 3001), SpaHandler).serve_forever()
