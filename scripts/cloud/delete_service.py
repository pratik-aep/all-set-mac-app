"""A tiny, deliberately narrow HTTP service on the home server: the one
place a permanent delete from the app can reach the Postgres row and the
server's copy of a wallpaper's files. Nothing else.

Not exposed on the Tailscale interface directly, unlike Caddy — bound to
localhost only, reached the same way Postgres already is: through the SSH
tunnel (`scripts/cloud/tunnel.sh`, which forwards this port too). So a
delete needs, in order: an SSH key for this Mac, this bearer token, and
(client-side) Touch ID before the app ever sends the request — three
layers, not one.

First run creates a token, stores it at ~/.allset_delete_token (chmod 600,
same pattern as ~/.allset_pg_credentials) and prints it once — put that in
the client Mac's Keychain (see DeleteAPIKeychain.swift), it isn't shown
again.

Not a launchd service yet: start it by hand when you want deletes to work,
same as the tunnel. Can become one later the way Caddy and Postgres did.

Usage (on the server):
    /usr/bin/python3 scripts/cloud/delete_service.py [--port 8081]
"""
import argparse
import json
import os
import secrets
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer

STORAGE = os.path.expanduser("~/AllSetStorage/wallpapers")
TOKEN_PATH = os.path.expanduser("~/.allset_delete_token")
PSQL = "/opt/homebrew/bin/psql" if os.path.exists("/opt/homebrew/bin/psql") else "psql"
DATABASE_URL = "postgres://allset@localhost/allset"  # local, no tunnel needed here


def load_or_create_token():
    if os.path.exists(TOKEN_PATH):
        return open(TOKEN_PATH).read().strip()
    token = secrets.token_hex(32)
    fd = os.open(TOKEN_PATH, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as handle:
        handle.write(token)
    print(f"New delete-service token (put this in the client's Keychain, shown once):\n{token}")
    return token


def safe_path(relative):
    """None unless `relative` resolves strictly inside STORAGE — refuses
    '..', absolute paths, and symlink escapes."""
    if not relative or relative.startswith("/") or ".." in relative.split("/"):
        return None
    resolved = os.path.realpath(os.path.join(STORAGE, relative))
    root = os.path.realpath(STORAGE)
    if resolved != root and not resolved.startswith(root + os.sep):
        return None
    return resolved


class Handler(BaseHTTPRequestHandler):
    token = None  # set in main()

    def _reply(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _authorized(self):
        given = self.headers.get("Authorization", "")
        return given == f"Bearer {self.token}"

    def do_DELETE(self):
        if self.path != "/wallpaper":
            self._reply(404, {"error": "not found"})
            return
        if not self._authorized():
            self._reply(401, {"error": "bad token"})
            return
        length = int(self.headers.get("Content-Length", 0))
        try:
            payload = json.loads(self.rfile.read(length))
            item_id = payload["id"]
            paths = payload["paths"]
        except (KeyError, ValueError, json.JSONDecodeError):
            self._reply(400, {"error": "expected {id, paths}"})
            return
        if not isinstance(item_id, str) or not item_id or not isinstance(paths, list):
            self._reply(400, {"error": "expected {id, paths}"})
            return

        removed, refused = [], []
        for relative in paths:
            resolved = safe_path(relative)
            if resolved is None:
                refused.append(relative)
                continue
            try:
                os.remove(resolved)
                removed.append(relative)
            except FileNotFoundError:
                removed.append(relative)  # already gone: not a failure
            except OSError as error:
                refused.append(f"{relative}: {error}")

        result = subprocess.run([PSQL, DATABASE_URL, "-v", "ON_ERROR_STOP=1", "-c",
                                 "delete from wallpapers where id = %s" % Handler._quote(item_id)],
                                capture_output=True, text=True)
        db_ok = result.returncode == 0
        self._reply(200 if db_ok and not refused else 207, {
            "removedFiles": removed, "refusedFiles": refused,
            "database": "deleted" if db_ok else result.stderr.strip(),
        })

    @staticmethod
    def _quote(value):
        # id is a hex sha256 prefix from our own catalog (never user-typed
        # free text reaching this far), but quote defensively regardless.
        return "'" + value.replace("'", "''") + "'"

    def log_message(self, format, *args):
        pass  # never log secrets or noisy per-request lines; errors go via _reply


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8081)
    args = parser.parse_args()
    Handler.token = load_or_create_token()
    server = HTTPServer(("127.0.0.1", args.port), Handler)
    print(f"delete service on 127.0.0.1:{args.port} (localhost only; reach it through the SSH tunnel)")
    server.serve_forever()


if __name__ == "__main__":
    main()
