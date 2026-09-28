"""Uploads the wallpaper catalog's metadata to the cloud Postgres (Neon).

Metadata only — this does not touch the actual video/still/thumbnail files
(those go to object storage separately, once R2 is wired up). Safe to run
again: loads into a staging table, then upserts by id, so a rerun updates
rows instead of duplicating them.

Needs `psql` (already on this Mac via Homebrew) and a `.env` file next to
this script with:
    DATABASE_URL=postgres://user:pass@host/dbname

Usage:
    /usr/bin/python3 scripts/cloud/sync_catalog.py
"""
import csv
import io
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PSQL = "/opt/homebrew/bin/psql" if os.path.exists("/opt/homebrew/bin/psql") else "psql"

COLUMNS = ["id", "title", "kind", "category", "tags", "origin_root", "origin_file",
           "playback_key", "still_key", "thumbnail_key", "duration", "width", "height",
           "fps", "size_bytes", "status", "status_reason", "provenance", "content_rating", "added_at"]


def load_env(path):
    env = dict(os.environ)
    if os.path.exists(path):
        for line in open(path):
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            env[key.strip()] = value.strip().strip('"').strip("'")
    return env


def pg_array(values):
    # Postgres text[] literal for COPY: {a,b,"has space"}
    if not values:
        return "{}"
    parts = []
    for v in values:
        v = str(v).replace("\\", "\\\\").replace('"', '\\"')
        parts.append(f'"{v}"' if ("," in v or " " in v or '"' in v) else v)
    return "{" + ",".join(parts) + "}"


def row_for(item):
    provenance = item.get("provenance")
    return [
        item["id"], item.get("title", "Untitled"), item.get("kind", "video"),
        item.get("category", "abstract"), pg_array(item.get("tags", [])),
        item.get("root"), item.get("file"),
        None, None, None,  # storage keys: filled in once files are uploaded to R2
        item.get("duration"), item.get("width"), item.get("height"), item.get("fps"),
        item.get("size"), item.get("status", "quarantined"), item.get("statusReason"),
        json.dumps(provenance) if provenance else None,
        item.get("contentRating"), item.get("addedAt"),
    ]


def main():
    env = load_env(os.path.join(HERE, ".env"))
    url = env.get("DATABASE_URL")
    if not url:
        sys.exit("No DATABASE_URL. Put it in scripts/cloud/.env (gitignored) — see this file's docstring.")

    library = env.get("ALLSET_LIBRARY") or os.path.expanduser(
        "~/Library/Application Support/AllSet/Wallpaper/Library")
    all_items = json.load(open(os.path.join(library, "catalog.json")))["items"]
    items = [i for i in all_items if i.get("status") != "unsupported"]
    print(f"{len(items)} wallpapers to sync (of {len(all_items)} total)")

    buf = io.StringIO()
    writer = csv.writer(buf)
    writer.writerow(COLUMNS)
    for item in items:
        writer.writerow(row_for(item))

    cols = ",".join(COLUMNS)
    updates = ",\n    ".join(f"{c} = excluded.{c}" for c in COLUMNS if c != "id")
    script = f"""
create schema if not exists staging;
drop table if exists staging.wallpapers;
create table staging.wallpapers (like wallpapers including all);
\\copy staging.wallpapers ({cols}) from stdin with (format csv, header true)
{buf.getvalue()}\\.
insert into wallpapers ({cols}, synced_at)
select {cols}, now() from staging.wallpapers
on conflict (id) do update set
    {updates},
    synced_at = now();
drop table staging.wallpapers;
select count(*) as total_in_cloud from wallpapers;
"""

    proc = subprocess.run([PSQL, url, "-v", "ON_ERROR_STOP=1", "-f", "-"],
                          input=script, capture_output=True, text=True)
    print(proc.stdout)
    if proc.returncode != 0:
        print(proc.stderr, file=sys.stderr)
        sys.exit(1)
    print("Synced.")


if __name__ == "__main__":
    main()
