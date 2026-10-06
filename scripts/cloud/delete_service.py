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

What it deletes is decided here, never by the request: a wallpaper's own files
are `<folder>/<id>.<ext>` in the storage folders, plus the storage keys in its
database row that no other row also uses. A `paths` list in the request (sent
by older app versions) is ignored.

A delete is staged so the files and the database can't end up disagreeing:
the files move into STORAGE/.trash/<id>/ first, then the row is deleted, then
the quarantine is emptied. If the database step fails, the files move back and
nothing has changed (503: retry). A quarantine left behind by a crash is
settled at startup: files go back if the row is still there, or are removed if
it's gone.

Replies: 200 deleted, 404 nothing known by that id (already gone), 400/413 a
malformed request, 503 the database wasn't reachable (nothing changed).

Usage (on the server):
    /usr/bin/python3 scripts/cloud/delete_service.py [--port 8081]
Tests:
    /usr/bin/python3 -m unittest scripts/cloud/test_delete_service.py
"""
import argparse
import json
import os
import re
import secrets
import shutil
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

STORAGE = os.path.expanduser("~/AllSetStorage/wallpapers")
TOKEN_PATH = os.path.expanduser("~/.allset_delete_token")
PSQL = "/opt/homebrew/bin/psql" if os.path.exists("/opt/homebrew/bin/psql") else "psql"
DATABASE_URL = "postgres://allset@localhost/allset"  # local, no tunnel needed here

# Where a wallpaper's rendered files live, each named after its id.
ASSET_DIRS = ("live", "stills", "thumbnails", "transcoded", "extracted", "originals")
ID_PATTERN = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
MAX_BODY = 16 * 1024
DATABASE_TIMEOUT = 20  # seconds for one psql call
KEY_COLUMNS = ("playback_key", "still_key", "thumbnail_key")


class DatabaseError(Exception):
    pass


def load_or_create_token():
    if os.path.exists(TOKEN_PATH):
        with open(TOKEN_PATH) as handle:
            return handle.read().strip()
    token = secrets.token_hex(32)
    fd = os.open(TOKEN_PATH, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as handle:
        handle.write(token)
    print(f"New delete-service token (put this in the client's Keychain, shown once):\n{token}")
    return token


def safe_path(relative):
    """None unless `relative` resolves strictly inside STORAGE — refuses
    '..', absolute paths, and symlink escapes."""
    if not isinstance(relative, str) or not relative or relative.startswith("/") or ".." in relative.split("/"):
        return None
    resolved = os.path.realpath(os.path.join(STORAGE, relative))
    root = os.path.realpath(STORAGE)
    if resolved != root and not resolved.startswith(root + os.sep):
        return None
    return resolved


def trash_dir(item_id):
    return os.path.join(STORAGE, ".trash", item_id)


def quote(value):
    # Ids are checked against ID_PATTERN before reaching SQL; quoted regardless.
    return "'" + value.replace("'", "''") + "'"


def sql(statement):
    try:
        result = subprocess.run([PSQL, DATABASE_URL, "-At", "-v", "ON_ERROR_STOP=1", "-c", statement],
                                capture_output=True, text=True, timeout=DATABASE_TIMEOUT)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise DatabaseError(str(error))
    if result.returncode != 0:
        raise DatabaseError(result.stderr.strip() or f"psql exited {result.returncode}")
    return result.stdout.strip()


def row_keys(item_id):
    """The row's storage keys, or None if there's no row."""
    out = sql("select coalesce(json_agg(json_build_array(%s)), '[]') from wallpapers where id = %s"
              % (", ".join(KEY_COLUMNS), quote(item_id)))
    rows = json.loads(out or "[]")
    return None if not rows else [key for key in rows[0] if key]


def key_used_elsewhere(key, item_id):
    count = sql("select count(*) from wallpapers where id <> %s and %s in (%s)"
                % (quote(item_id), quote(key), ", ".join(KEY_COLUMNS)))
    return int(count or 0) > 0


def owned_files(item_id, keys):
    """Relative paths of the files that belong to this wallpaper and nothing else:
    named after it or listed in its row, and in neither case referenced by any
    other row (a file named after one wallpaper can still be another's key)."""
    candidates = set()
    for folder in ASSET_DIRS:
        directory = os.path.join(STORAGE, folder)
        if not os.path.isdir(directory):
            continue
        for name in os.listdir(directory):
            stem, _ = os.path.splitext(name)
            if stem == item_id and os.path.isfile(os.path.join(directory, name)):
                candidates.add(f"{folder}/{name}")
    for key in keys or []:
        resolved = safe_path(key)
        if resolved and os.path.isfile(resolved):
            candidates.add(os.path.relpath(resolved, os.path.realpath(STORAGE)))
    return sorted(c for c in candidates if not key_used_elsewhere(c, item_id))


def move(source, destination):
    os.makedirs(os.path.dirname(destination), exist_ok=True)
    os.rename(source, destination)


def restore_quarantine(item_id, only=None):
    """Moves quarantined files back where they were (all, or the relative paths in
    `only`). A file whose place has been taken meanwhile is never overwritten and
    never discarded: it stays held and is returned as a conflict. The quarantine
    folder goes only once nothing is left in it."""
    root = trash_dir(item_id)
    conflicts = []
    for base, _, names in os.walk(root):
        for name in names:
            held = os.path.join(base, name)
            relative = os.path.relpath(held, root)
            if only is not None and relative not in only:
                continue
            destination = safe_path(relative)
            if destination is None or os.path.exists(destination):
                conflicts.append(relative)
                continue
            try:
                move(held, destination)
            except OSError:
                conflicts.append(relative)
    remove_if_empty(root)
    return sorted(conflicts)


def remove_if_empty(root):
    """Removes empty folders under (and including) root; never a file."""
    for base, _, _ in sorted(os.walk(root), key=lambda entry: -len(entry[0])):
        try:
            os.rmdir(base)
        except OSError:
            pass


def settle_quarantine(item_id):
    """A quarantine left by an interrupted delete: back if the row is still there,
    gone if the row is. Raises DatabaseError if that can't be told."""
    if not os.path.isdir(trash_dir(item_id)):
        return []
    if row_keys(item_id) is None:
        # Finished, except files another row started using meanwhile: those go back.
        held = held_files(item_id)
        reused = [relative for relative in held if key_used_elsewhere(relative, item_id)]
        conflicts = restore_quarantine(item_id, only=set(reused)) if reused else []
        if not conflicts:
            shutil.rmtree(trash_dir(item_id), ignore_errors=True)
        return conflicts
    return restore_quarantine(item_id)


def held_files(item_id):
    root = trash_dir(item_id)
    return sorted(os.path.relpath(os.path.join(base, name), root)
                  for base, _, names in os.walk(root) for name in names)


def settle_all_quarantines():
    root = os.path.join(STORAGE, ".trash")
    if not os.path.isdir(root):
        return
    for item_id in os.listdir(root):
        if ID_PATTERN.match(item_id):
            try:
                conflicts = settle_quarantine(item_id)
            except DatabaseError as error:
                print(f"Couldn't settle the quarantine for {item_id}: {error}", file=sys.stderr)
                continue
            if conflicts:
                print(f"Kept in {trash_dir(item_id)} (their places are taken): {', '.join(conflicts)}", file=sys.stderr)


def delete_wallpaper(item_id):
    """(status, body) for deleting one wallpaper everywhere on this server."""
    try:
        conflicts = settle_quarantine(item_id)
        if conflicts:
            return 409, {"error": "an earlier delete left files whose places are taken; resolve them by hand",
                         "conflicts": conflicts, "quarantine": trash_dir(item_id)}
        keys = row_keys(item_id)
        files = owned_files(item_id, keys)
    except DatabaseError as error:
        return 503, {"error": "database unavailable; nothing was deleted", "detail": error.args[0]}
    if keys is None and not files:
        return 404, {"error": "unknown id", "id": item_id}

    moved = []
    try:
        for relative in files:
            move(os.path.join(STORAGE, relative), os.path.join(trash_dir(item_id), relative))
            moved.append(relative)
    except OSError as error:
        conflicts = restore_quarantine(item_id)
        return 500, {"error": "couldn't move the files aside; nothing was deleted", "detail": str(error),
                     **({"conflicts": conflicts} if conflicts else {})}

    if keys is not None:
        try:
            sql("delete from wallpapers where id = %s" % quote(item_id))
        except DatabaseError as error:
            conflicts = restore_quarantine(item_id)
            body = {"error": "database delete failed; files restored, nothing was deleted", "detail": error.args[0]}
            if conflicts:
                body.update(error="database delete failed; some files' places were taken meanwhile, so those "
                                  "originals are kept in quarantine (nothing was lost)",
                            conflicts=conflicts, quarantine=trash_dir(item_id))
            return 503, body

    # Checked again now the row is gone: a file another row started using meanwhile goes back.
    try:
        reused = [relative for relative in moved if key_used_elsewhere(relative, item_id)]
    except DatabaseError:
        reused = list(moved)  # can't tell: keep everything, settled at the next start
    conflicts = restore_quarantine(item_id, only=set(reused)) if reused else []
    # Everything still held is what this delete removes, except a conflict, which stays.
    for relative in held_files(item_id):
        if relative not in conflicts:
            os.remove(os.path.join(trash_dir(item_id), relative))
    remove_if_empty(trash_dir(item_id))
    removed = [relative for relative in moved if relative not in reused]
    return 200, {"removedFiles": removed, "database": "deleted" if keys is not None else "no row",
                 **({"keptBecauseShared": sorted(reused)} if reused else {}),
                 **({"conflicts": conflicts} if conflicts else {})}


class Handler(BaseHTTPRequestHandler):
    token = None  # set in main()
    timeout = 15  # seconds a client may take to send its request

    def _reply(self, status, body):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _authorized(self):
        given = self.headers.get("Authorization", "")
        return secrets.compare_digest(given, f"Bearer {self.token}")

    def do_DELETE(self):
        if self.path != "/wallpaper":
            self._reply(404, {"error": "not found"})
            return
        if not self._authorized():
            self._reply(401, {"error": "bad token"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self._reply(400, {"error": "bad Content-Length"})
            return
        if length <= 0 or length > MAX_BODY:
            self._reply(413 if length > MAX_BODY else 400, {"error": f"body must be 1–{MAX_BODY} bytes"})
            return
        try:
            payload = json.loads(self.rfile.read(length))
        except (ValueError, UnicodeDecodeError, OSError):
            self._reply(400, {"error": "expected a JSON object {id}"})
            return
        item_id = payload.get("id") if isinstance(payload, dict) else None
        if not isinstance(item_id, str) or not ID_PATTERN.match(item_id):
            self._reply(400, {"error": "expected a JSON object {id} with a valid id"})
            return
        status, body = delete_wallpaper(item_id)
        if status >= 500:
            print(f"delete {item_id}: {status} {body.get('error')}", file=sys.stderr)
        self._reply(status, body)

    def log_message(self, format, *args):
        pass  # never log secrets or noisy per-request lines; failures go to stderr above


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8081)
    args = parser.parse_args()
    Handler.token = load_or_create_token()
    settle_all_quarantines()
    server = HTTPServer(("127.0.0.1", args.port), Handler)
    print(f"delete service on 127.0.0.1:{args.port} (localhost only; reach it through the SSH tunnel)")
    server.serve_forever()


if __name__ == "__main__":
    main()
