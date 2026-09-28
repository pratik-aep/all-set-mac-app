#!/bin/bash
# Pushes this Mac's rendered wallpaper assets to the home server.
#
# Only the three folders that actually play are sent: live/, stills/ and
# thumbnails/ (~12 GB). originals/ (~49 GB), extracted/ and transcoded/ are
# pipeline working copies and are deliberately NOT sent — nothing plays from
# them, and they'd quadruple the transfer.
#
#   scripts/cloud/push_wallpapers.sh --dry-run   # list what would go, send nothing
#   scripts/cloud/push_wallpapers.sh             # send it
#
# Resumable and idempotent: rsync skips files already there with the same
# size and timestamp, so a re-run after an interrupted transfer picks up
# where it stopped. Nothing on the server is deleted (no --delete): a
# wallpaper removed here stays there until that's a deliberate decision.
set -euo pipefail

LIBRARY="$HOME/Library/Application Support/AllSet/Wallpaper/Library"
SERVER="allset-server"                      # ~/.ssh/config alias
REMOTE="AllSetStorage/wallpapers"           # relative to the server's home

DRY=""
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY="--dry-run"
    echo "DRY RUN — nothing will be transferred"
fi

for folder in live stills thumbnails; do
    source_dir="$LIBRARY/$folder"
    if [[ ! -d "$source_dir" ]]; then
        echo "skipping $folder (not on this Mac)"
        continue
    fi
    count=$(find "$source_dir" -type f ! -name '.DS_Store' | wc -l | tr -d ' ')
    size=$(du -sh "$source_dir" | cut -f1)
    echo "==> $folder: $count files, $size"
    rsync -avh --progress --partial $DRY \
        --exclude '.DS_Store' \
        "$source_dir/" "$SERVER:$REMOTE/$folder/"
done

echo
echo "Done. Catalog metadata is separate — see scripts/cloud/sync_catalog.py."
