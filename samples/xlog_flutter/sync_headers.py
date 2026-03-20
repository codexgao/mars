#!/usr/bin/env python3
"""
sync_headers.py — Sync public xlog headers from mars/xlog into xlog_flutter.

Usage (run from any directory):
    python samples/xlog_flutter/sync_headers.py [--check]

Options:
    --check     Dry-run: report differences without copying. Exits with code 1
                if any file is out of date.

Source layout (relative to mars/ root):
    mars/xlog/appender.h                        → include/appender.h
    mars/xlog/export_include/xlogger/*.h        → include/xlogger/*.h
    mars/comm/windows/sys/time.h                → windows/src/sys/time.h
    mars/comm/windows/sys/time.c                → windows/src/sys/time.c
"""

import argparse
import filecmp
import os
import shutil
import sys

# ---------------------------------------------------------------------------
# Paths — all relative to the mars/ repository root
# ---------------------------------------------------------------------------
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.normpath(os.path.join(SCRIPT_DIR, "..", ".."))  # …/mars/

SOURCES = [
    # (src_path_relative_to_REPO_ROOT, dst_path_relative_to_SCRIPT_DIR)
    (
        os.path.join("mars", "xlog", "appender.h"),
        os.path.join("include", "appender.h"),
    ),
    # Windows POSIX-compat shim — only used by windows/CMakeLists.txt
    (
        os.path.join("mars", "comm", "windows", "sys", "time.h"),
        os.path.join("windows", "src", "sys", "time.h"),
    ),
    (
        os.path.join("mars", "comm", "windows", "sys", "time.c"),
        os.path.join("windows", "src", "sys", "time.c"),
    ),
]

# All .h files under mars/xlog/export_include/xlogger/ → include/xlogger/
EXPORT_INCLUDE_SRC = os.path.join(REPO_ROOT, "mars", "xlog", "export_include", "xlogger")
EXPORT_INCLUDE_DST = os.path.join(SCRIPT_DIR, "include", "xlogger")


def collect_pairs():
    """Return list of (abs_src, abs_dst) pairs to synchronise."""
    pairs = []

    # Fixed single-file entries
    for rel_src, rel_dst in SOURCES:
        pairs.append(
            (
                os.path.join(REPO_ROOT, rel_src),
                os.path.join(SCRIPT_DIR, rel_dst),
            )
        )

    # All headers under export_include/xlogger/
    if not os.path.isdir(EXPORT_INCLUDE_SRC):
        print(f"ERROR: source directory not found: {EXPORT_INCLUDE_SRC}", file=sys.stderr)
        sys.exit(1)

    for fname in sorted(os.listdir(EXPORT_INCLUDE_SRC)):
        if fname.endswith(".h"):
            pairs.append(
                (
                    os.path.join(EXPORT_INCLUDE_SRC, fname),
                    os.path.join(EXPORT_INCLUDE_DST, fname),
                )
            )

    return pairs


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="Dry-run: report diffs, exit 1 if stale")
    args = parser.parse_args()

    pairs = collect_pairs()
    stale = []

    for src, dst in pairs:
        if not os.path.isfile(src):
            print(f"ERROR: source file not found: {src}", file=sys.stderr)
            sys.exit(1)

        dst_exists = os.path.isfile(dst)
        up_to_date = dst_exists and filecmp.cmp(src, dst, shallow=False)

        rel_dst = os.path.relpath(dst, SCRIPT_DIR)

        if up_to_date:
            print(f"  OK       {rel_dst}")
        else:
            status = "MISSING" if not dst_exists else "STALE  "
            print(f"  {status}  {rel_dst}")
            stale.append((src, dst))

    if not stale:
        print("\nAll headers are up to date.")
        return

    if args.check:
        print(f"\n{len(stale)} file(s) out of date. Run without --check to sync.", file=sys.stderr)
        sys.exit(1)

    # Copy
    for src, dst in stale:
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(src, dst)
        print(f"  COPIED   {os.path.relpath(dst, SCRIPT_DIR)}")

    print(f"\nSynced {len(stale)} file(s).")


if __name__ == "__main__":
    main()
