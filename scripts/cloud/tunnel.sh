#!/bin/bash
# Opens the SSH tunnel to the home server's Postgres and delete service,
# both bound to localhost there and reachable only over Tailscale via this
# tunnel. While this runs, postgres://allset@localhost:5432/allset and
# http://localhost:8081 on this Mac ARE the server's.
#
#   scripts/cloud/tunnel.sh          # hold the tunnel open (ctrl-C to stop)
#   scripts/cloud/tunnel.sh --check  # is it already up?
#
# Nothing here runs at login; start it when you need it.
set -euo pipefail

SERVER="allset-server"   # ~/.ssh/config alias
PG_PORT=5432
DELETE_PORT=8081

if [[ "${1:-}" == "--check" ]]; then
    if nc -z localhost "$PG_PORT" 2>/dev/null; then
        echo "tunnel is up: localhost:$PG_PORT, localhost:$DELETE_PORT"
        exit 0
    fi
    echo "tunnel is down"
    exit 1
fi

if nc -z localhost "$PG_PORT" 2>/dev/null; then
    echo "Something already listens on localhost:$PG_PORT — not starting a second tunnel."
    echo "If that's a local Postgres rather than the tunnel, stop it first:"
    echo "    brew services stop postgresql@18"
    exit 1
fi

echo "Opening tunnel to $SERVER (ctrl-C to close)..."
exec ssh -N -L "$PG_PORT:localhost:$PG_PORT" -L "$DELETE_PORT:localhost:$DELETE_PORT" "$SERVER"
