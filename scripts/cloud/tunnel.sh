#!/bin/bash
# Opens the SSH tunnel to the home server's Postgres, which is bound to
# localhost there and reachable only over Tailscale. While this runs,
# postgres://allset@localhost:5432/allset on this Mac IS the server's database.
#
#   scripts/cloud/tunnel.sh          # hold the tunnel open (ctrl-C to stop)
#   scripts/cloud/tunnel.sh --check  # is it already up?
#
# Nothing here runs at login; start it when you need it.
set -euo pipefail

SERVER="allset-server"   # ~/.ssh/config alias
PORT=5432

if [[ "${1:-}" == "--check" ]]; then
    if nc -z localhost "$PORT" 2>/dev/null; then
        echo "tunnel is up: localhost:$PORT"
        exit 0
    fi
    echo "tunnel is down"
    exit 1
fi

if nc -z localhost "$PORT" 2>/dev/null; then
    echo "Something already listens on localhost:$PORT — not starting a second tunnel."
    echo "If that's a local Postgres rather than the tunnel, stop it first:"
    echo "    brew services stop postgresql@18"
    exit 1
fi

echo "Opening tunnel to $SERVER (ctrl-C to close)..."
exec ssh -N -L "$PORT:localhost:$PORT" "$SERVER"
