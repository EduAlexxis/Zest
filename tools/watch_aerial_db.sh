#!/bin/bash
# Watches for /Library/Application Support/com.apple.idleassetsd/Aerial.sqlite
# to appear or change, snapshots it (plus -wal/-shm) read-only, and runs
# aerial_db_inspect.py against the snapshot so we never touch the live file.
#
# Usage:
#   ./watch_aerial_db.sh          # poll forever, snapshot on every change
#   ./watch_aerial_db.sh --once   # snapshot immediately if the db exists, then exit

set -euo pipefail

SRC_DIR="/Library/Application Support/com.apple.idleassetsd"
SRC_DB="$SRC_DIR/Aerial.sqlite"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SNAP_ROOT="$SCRIPT_DIR/snapshots"
mkdir -p "$SNAP_ROOT"

snapshot_and_decode() {
    local ts
    ts="$(date +%Y%m%d-%H%M%S)"
    local dest="$SNAP_ROOT/$ts"
    mkdir -p "$dest"

    cp -p "$SRC_DB" "$dest/Aerial.sqlite" 2>/dev/null || return 1
    cp -p "$SRC_DB-wal" "$dest/Aerial.sqlite-wal" 2>/dev/null || true
    cp -p "$SRC_DB-shm" "$dest/Aerial.sqlite-shm" 2>/dev/null || true

    echo "[+] Snapshot: $dest"
    python3 "$SCRIPT_DIR/aerial_db_inspect.py" --db "$dest/Aerial.sqlite" \
        --json-out "$dest/decoded.json" || true
}

if [[ "${1:-}" == "--once" ]]; then
    if [[ -f "$SRC_DB" ]]; then
        snapshot_and_decode
    else
        echo "[!] $SRC_DB does not exist yet." >&2
        exit 1
    fi
    exit 0
fi

echo "[i] Polling for changes to $SRC_DB (Ctrl+C to stop)..."
last_mtime=""
while true; do
    if [[ -f "$SRC_DB" ]]; then
        mtime="$(stat -f %m "$SRC_DB" 2>/dev/null || echo "")"
        if [[ -n "$mtime" && "$mtime" != "$last_mtime" ]]; then
            last_mtime="$mtime"
            snapshot_and_decode
        fi
    fi
    sleep 5
done
