# Running the wallpaper server

This describes the one deployment that exists: a personal home server reached over Tailscale. It records what the scripts in `scripts/cloud/` do today and, separately, what is not set up yet. Nothing here is needed to use All Set without a server.

Last checked against the scripts on 2026-10-06.

## What runs where

| Piece | Where | How it is reached | How it starts |
|---|---|---|---|
| Postgres, database `allset`, table `wallpapers` (`schema.sql`) | Server, bound to localhost | SSH tunnel from the Mac (`tunnel.sh`, port 5432) | launchd on the server |
| Wallpaper files, `~/AllSetStorage/wallpapers` | Server | Caddy over plain HTTP on the Tailscale address. The app fetches `<server URL>/<relative path>`, for example `live/<id>.mp4` | launchd on the server |
| Delete service, `delete_service.py`, port 8081 | Server, bound to localhost | The same SSH tunnel | By hand |
| Catalog service for a tester, `catalog_service.py`, port 8082 | Server, Tailscale address only | Directly over Tailscale, bearer token | By hand |

The server's layout mirrors the Mac's library folder, so a relative path means the same file on both sides.

On the Mac:

- `tunnel.sh` holds the SSH tunnel open. It forwards 5432 and 8081 to the server alias `allset-server` from `~/.ssh/config`.
- `push_wallpapers.sh` copies the library's files to the server with rsync. It never deletes on the server.
- `sync_catalog.py` uploads catalog metadata to Postgres through the tunnel. It reads `DATABASE_URL` from `scripts/cloud/.env`.
- The app is built with `ALLSET_LIBRARY_SERVER_HOST` (or `scripts/local.env`), which allows plain HTTP to that one host.

The headers of `sync_catalog.py` and `schema.sql` still mention Neon and Cloudflare R2. The deployment in use is the home server above. Those headers need correcting by someone who knows whether the cloud plan is still intended.

## Checking that each piece is up

| Piece | Check | Healthy answer |
|---|---|---|
| Tunnel | `scripts/cloud/tunnel.sh --check` | "tunnel is up". Both ports must be held by ssh and the delete service must answer. A local Postgres on 5432 is reported as not the tunnel |
| Postgres | With the tunnel open: `psql "$DATABASE_URL" -c "select count(*) from wallpapers"` | A row count |
| File server | `curl -I "<server URL>/thumbnails/<an id>.jpg"` from the Mac | `200` with a `Content-Length` |
| Delete service | Covered by `tunnel.sh --check` | Any HTTP answer through the tunnel |
| Catalog service | `curl -H "Authorization: Bearer <token>" http://<tailscale address>:8082/catalog` | A JSON list |

The app's own "checked on your server" count is stronger evidence than any of these for a given file: it means that file's server copy matched this Mac's by size and SHA-256 when the local copy was freed.

## Tokens

| Token | File on the server | Rotation |
|---|---|---|
| Delete service | `~/.allset_delete_token` (chmod 600) | Created and printed once on first run. Delete the file and restart the service to make a new one, then save the new token in the app (it is kept in the Mac's Keychain) |
| Catalog service | `~/.allset_catalog_token` (chmod 600) | Delete the file and restart the service |
| Postgres password | `~/.allset_pg_credentials` on the server, `scripts/cloud/.env` on the Mac | Change it in Postgres, then in both files |

A delete needs three things in order: this Mac's SSH key (for the tunnel), the delete token, and Touch ID or the Mac password in the app.

## Deleting, and writing storage keys

A delete from the app removes the wallpaper's row and retires its files. Retired files move to `~/AllSetStorage/wallpapers/.retired/<id>/<time>/` and stay there for 7 days (`--retention-days`), so **a delete frees the server's disk space a week later, not at once**.

That window is what protects a file another wallpaper comes to use:

- Anything that deletes a row, or sets or changes `playback_key`, `still_key` or `thumbnail_key`, must do it in a transaction that first runs `select pg_advisory_xact_lock(<ASSET_LOCK>)`. The number is in `scripts/cloud/catalog_lock.py`. The delete service and `sync_catalog.py` both take it. A writer must also only point a key at a file that exists in storage.
- A writer that skips the lock, such as a manual `UPDATE` in psql, is still covered while the file is retired. The delete service puts back any retired file that a row references. It checks after every delete, at startup and every 10 minutes.
- After the retention, an unreferenced retired file is removed for good. A reference written later than that points at nothing.

`.trash/<id>/` is different: it holds files only while one delete is in progress, and is settled at the next start if the service stopped midway.

## Tests

`/usr/bin/python3 -m unittest scripts/cloud/test_sync_catalog.py scripts/cloud/test_delete_service.py scripts/cloud/test_catalog_service.py` runs the server scripts against a throwaway Postgres 17 (`pgtest.py`). CI runs the same tests and fails if any are skipped.

## Not set up yet

These are gaps, listed so nobody assumes they exist.

- **Supervision.** The delete and catalog services are started by hand and are not restarted if they stop or the server reboots. Postgres and Caddy are under launchd; these two could be made launchd services the same way.
- **Backups.** Nothing in this repository backs up the database or the files. `push_wallpapers.sh` makes the server a second copy of the Mac's files, but a wallpaper freed from the Mac then exists only on the server.
- **Restore drill.** No restore has been rehearsed. Until one has, treat the server as a convenience copy and not as a backup.
- **Migrations.** `schema.sql` is `create table if not exists`. There is no versioned migration, so a column change has to be applied by hand.
- **The upload step.** Something outside this repository fills in the storage keys after files are pushed. Whatever does that must follow the lock rule above; nothing here can check that it does.
- **Scale.** The catalog service runs `psql` once per request and returns the whole list, with no pagination and no limit on concurrent requests. This is fine for one tester.

A reasonable first step for backups, not yet done or tested: on the server, a nightly `pg_dump allset` and an rsync of `~/AllSetStorage/wallpapers` to a second disk, followed by one rehearsed restore into a scratch database and folder.
