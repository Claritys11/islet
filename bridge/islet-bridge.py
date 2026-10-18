#!/usr/bin/env python3
"""Local receiver for the Islet Bridge Spicetify extension.

Islet starts this and reads its stdout: every request from the extension is
printed as one JSON line ({"kind": "lyrics" | "position", ...}). It listens on
127.0.0.1 only and accepts requests only from Spotify's own page.
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 47821
ALLOWED_ORIGINS = {"https://xpui.app.spotify.com"}
MAX_BODY = 4 * 1024 * 1024


class Handler(BaseHTTPRequestHandler):
    def _allowed(self):
        return self.headers.get("Origin", "") in ALLOWED_ORIGINS

    def _cors(self):
        origin = self.headers.get("Origin", "")
        if origin in ALLOWED_ORIGINS:
            self.send_header("Access-Control-Allow-Origin", origin)
            self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
            self.send_header("Access-Control-Allow-Headers", "Content-Type")
            # Chromium's Private Network Access: let Spotify's page reach localhost.
            self.send_header("Access-Control-Allow-Private-Network", "true")
        return origin in ALLOWED_ORIGINS

    def do_OPTIONS(self):
        self.send_response(204 if self._allowed() else 403)
        self._cors()
        self.end_headers()

    def do_POST(self):
        kind = self.path.strip("/")
        length = int(self.headers.get("Content-Length") or 0)
        if not self._allowed() or kind not in ("lyrics", "position") or length > MAX_BODY:
            self.send_response(403)
            self.end_headers()
            return
        try:
            body = json.loads(self.rfile.read(length))
        except ValueError:
            self.send_response(400)
            self.end_headers()
            return
        body["kind"] = kind
        sys.stdout.write(json.dumps(body, separators=(",", ":")) + "\n")
        sys.stdout.flush()
        self.send_response(204)
        self._cors()
        self.end_headers()

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    try:
        ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
    except OSError as e:
        sys.stderr.write(f"islet-bridge: can't listen on 127.0.0.1:{PORT}: {e}\n")
        sys.exit(1)
