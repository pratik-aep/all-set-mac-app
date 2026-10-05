"""Read-only wallpaper API for a tester: the catalog list and file downloads.

  GET /catalog     -> JSON list of {id, title, kind, category, tags, duration,
                      width, height, size_bytes}. No paths, no provenance.
  GET /file/<id>   -> that wallpaper's playback file.

Every request needs `Authorization: Bearer <token>`. First run creates the
token at ~/.allset_catalog_token (chmod 600) and prints it once; delete that
file and restart to rotate it. Nothing here writes or deletes.

Binds all interfaces on purpose: reach it over Tailscale (share this machine
with the tester), never forward the port to the internet.

Usage (on the server):
    /usr/bin/python3 scripts/cloud/catalog_service.py [--port 8082]
"""
import argparse
import hmac
import json
import os
import secrets
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

STORAGE = os.path.expanduser("~/AllSetStorage/wallpapers")
TOKEN_PATH = os.path.expanduser("~/.allset_catalog_token")
PSQL = "/opt/homebrew/bin/psql" if os.path.exists("/opt/homebrew/bin/psql") else "psql"
DATABASE_URL = "postgres://allset@localhost/allset"
COLUMNS = "id, title, kind, category, tags, duration, width, height, size_bytes"


def load_or_create_token():
    if os.path.exists(TOKEN_PATH):
        return open(TOKEN_PATH).read().strip()
    token = secrets.token_urlsafe(32)
    fd = os.open(TOKEN_PATH, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as handle:
        handle.write(token)
    print(f"New catalog API key (shown once):\n{token}")
    return token


def query(sql):
    result = subprocess.run([PSQL, DATABASE_URL, "-At", "-v", "ON_ERROR_STOP=1", "-c", sql],
                            capture_output=True, text=True, check=True)
    return result.stdout.strip()


class Handler(BaseHTTPRequestHandler):
    token = ""

    def _json(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        given = self.headers.get("Authorization", "")
        if not hmac.compare_digest(given, f"Bearer {self.token}"):
            return self._json(401, {"error": "bad key"})
        if self.path == "/catalog":
            rows = query(f"select coalesce(json_agg(t), '[]') from (select {COLUMNS}, playback_key from wallpapers "
                         "where status <> 'unsupported' order by category, title) t")
            # only list wallpapers whose file is actually on this server
            return self._json(200, [{k: v for k, v in r.items() if k != "playback_key"}
                                    for r in json.loads(rows)
                                    if os.path.isfile(os.path.join(STORAGE, r["playback_key"] or "-"))])
        if self.path.startswith("/file/"):
            item_id = self.path[len("/file/"):]
            if not item_id.isalnum():
                return self._json(400, {"error": "bad id"})
            key = query(f"select playback_key from wallpapers where id = '{item_id}'")
            path = os.path.realpath(os.path.join(STORAGE, key)) if key else ""
            if not key or not path.startswith(os.path.realpath(STORAGE) + os.sep) or not os.path.isfile(path):
                return self._json(404, {"error": "not found"})
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(os.path.getsize(path)))
            self.send_header("Content-Disposition", f'attachment; filename="{item_id}{os.path.splitext(path)[1]}"')
            self.end_headers()
            with open(path, "rb") as handle:
                while chunk := handle.read(1 << 20):
                    self.wfile.write(chunk)
            return
        self._json(404, {"error": "not found"})

    def log_message(self, format, *args):
        pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8082)
    args = parser.parse_args()
    Handler.token = load_or_create_token()
    print(f"catalog API on 0.0.0.0:{args.port} (share over Tailscale only)")
    ThreadingHTTPServer(("0.0.0.0", args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
