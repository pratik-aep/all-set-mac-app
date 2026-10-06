"""The one lock every writer of the wallpaper catalog takes.

Anything that deletes a row, or sets or changes a row's storage keys
(playback_key, still_key, thumbnail_key), does it in a transaction that
first runs

    select pg_advisory_xact_lock(ASSET_LOCK);

so "does another row use this file?" and "delete this row" can't interleave
with another writer's change. The lock is released when the transaction ends.

A writer must also only point a key at a file that exists in storage. The
delete service covers writers that skip either rule (a manual UPDATE, say):
deleted files are retired for a while rather than destroyed, and a retired
file that any row references is put back (delete_service.sweep_retired).
"""

# Arbitrary, fixed: the same number in every script and on every machine.
ASSET_LOCK = 4_711_061_026
