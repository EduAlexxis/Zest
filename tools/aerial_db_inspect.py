#!/usr/bin/env python3
"""
Read-only decoder for macOS's Aerial screensaver metadata store.

On Sonoma/Sequoia the store is a SQLite database:
    /Library/Application Support/com.apple.idleassetsd/Aerial.sqlite
(older macOS releases used entries.json + a binary index.plist instead —
those paths are checked as a fallback but are no longer present on current
systems, WallpaperAerialAssets.framework has no remaining references to them).

This script never opens the database for writing. It connects with
`mode=ro` so it can safely run while idleassetsd is live.
"""
import argparse
import json
import plistlib
import sqlite3
import sys
from pathlib import Path

DEFAULT_DB = Path("/Library/Application Support/com.apple.idleassetsd/Aerial.sqlite")

LEGACY_CANDIDATES = [
    Path("/Library/Application Support/com.apple.idleassetsd/Customer/entries.json"),
    Path("/Library/Application Support/com.apple.idleassetsd/Customer/index.plist"),
    Path("/Library/Application Support/com.apple.idleassetsd/entries.json"),
]

BPLIST_MAGIC = b"bplist00"


def try_decode_blob(value):
    """Best-effort decode of a column value that might be an embedded plist/json blob."""
    if isinstance(value, (bytes, bytearray)):
        if value.startswith(BPLIST_MAGIC):
            try:
                return ("plist", plistlib.loads(bytes(value)))
            except Exception:
                return None
        stripped = value.strip()
        if stripped[:1] in (b"{", b"["):
            try:
                return ("json", json.loads(value))
            except Exception:
                return None
    elif isinstance(value, str):
        stripped = value.strip()
        if stripped[:1] in ("{", "["):
            try:
                return ("json", json.loads(value))
            except Exception:
                return None
    return None


def dump_sqlite(db_path: Path, table_filter: str | None, limit: int, json_out: Path | None):
    uri = f"file:{db_path}?mode=ro"
    try:
        conn = sqlite3.connect(uri, uri=True)
    except sqlite3.OperationalError as e:
        print(f"[!] Could not open {db_path} read-only: {e}", file=sys.stderr)
        print("    (the file may not exist yet — idleassetsd creates/populates it lazily,", file=sys.stderr)
        print("     see tools/watch_aerial_db.sh to snapshot it as soon as it appears)", file=sys.stderr)
        return None

    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    cur.execute("SELECT name, sql FROM sqlite_master WHERE type='table' ORDER BY name")
    tables = cur.fetchall()
    if not tables:
        print("[!] Database opened but contains no tables.", file=sys.stderr)
        return None

    dump = {}
    for row in tables:
        name, create_sql = row["name"], row["sql"]
        if table_filter and table_filter.lower() != name.lower():
            continue

        print(f"\n=== TABLE: {name} ===")
        print(create_sql)

        cur.execute(f"SELECT * FROM '{name}' LIMIT ?", (limit,))
        cols = [d[0] for d in cur.description]
        rows_out = []
        for r in cur.fetchall():
            record = {}
            for col in cols:
                val = r[col]
                decoded = try_decode_blob(val)
                if decoded:
                    kind, payload = decoded
                    record[col] = {"_decoded_as": kind, "value": payload}
                elif isinstance(val, (bytes, bytearray)):
                    record[col] = f"<{len(val)} raw bytes>"
                else:
                    record[col] = val
            rows_out.append(record)
        dump[name] = {"create_sql": create_sql, "rows": rows_out}
        print(json.dumps(rows_out, indent=2, default=str)[:4000])

    conn.close()

    if json_out:
        json_out.write_text(json.dumps(dump, indent=2, default=str))
        print(f"\n[+] Full dump written to {json_out}")

    return dump


def dump_legacy():
    found_any = False
    for path in LEGACY_CANDIDATES:
        if not path.exists():
            continue
        found_any = True
        print(f"\n=== LEGACY FILE: {path} ===")
        data = path.read_bytes()
        try:
            if path.suffix == ".json":
                print(json.dumps(json.loads(data), indent=2))
            else:
                print(json.dumps(plistlib.loads(data), indent=2, default=str))
        except Exception as e:
            print(f"[!] Failed to parse: {e}")
    if not found_any:
        print("[i] No legacy entries.json / index.plist found (expected on Sonoma/Sequoia).")


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--db", type=Path, default=DEFAULT_DB, help="Path to Aerial.sqlite")
    ap.add_argument("--table", help="Only dump this table")
    ap.add_argument("--limit", type=int, default=50, help="Row limit per table")
    ap.add_argument("--json-out", type=Path, help="Write the full decoded dump to this JSON file")
    ap.add_argument("--legacy-only", action="store_true", help="Only check the old entries.json/index.plist paths")
    args = ap.parse_args()

    if args.legacy_only:
        dump_legacy()
        return

    if args.db.exists():
        dump_sqlite(args.db, args.table, args.limit, args.json_out)
    else:
        print(f"[!] {args.db} does not exist yet.", file=sys.stderr)

    dump_legacy()


if __name__ == "__main__":
    main()
