#!/usr/bin/env python3
"""Build the Magisk module zip from the module/ source tree.

CRITICAL: a Magisk flashable module zip MUST contain
  META-INF/com/google/android/update-binary
  META-INF/com/google/android/updater-script (#MAGISK)
at the zip root. Without them Magisk 21.4 reports
"This zip is not a Magisk module!"

Also use STORED compression + normal timestamps + DOS attrs, matching the
format Magisk's legacy installer expects. Do NOT use `zip -r` defaults or
Python zipfile defaults (DEFLATE + 1980 timestamps + Unix mode bits).

Usage (run from repo root):
    python tools/repack.py
"""
import os
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "module")
OUT = os.path.join(ROOT, "releases", "weatherfix_v2_systemless.zip")
TS = (2026, 11, 23, 0, 35, 0)

# Byte-for-byte copy of the update-binary from the known-good v1 package.
UPDATE_BINARY = b"""#!/sbin/sh

#################
# Initialization
#################

umask 022

# echo before loading util_functions
ui_print() { echo "$1"; }

require_new_magisk() {
  ui_print "*******************************"
  ui_print " Please install Magisk v20.4+! "
  ui_print "*******************************"
  exit 1
}

#########################
# Load util_functions.sh
#########################

OUTFD=$2
ZIPFILE=$3

mount /data 2>/dev/null

[ -f /data/adb/magisk/util_functions.sh ] || require_new_magisk
. /data/adb/magisk/util_functions.sh
[ $MAGISK_VER_CODE -lt 20400 ] && require_new_magisk

install_module
exit 0
"""
UPDATER_SCRIPT = b"#MAGISK\n"


def unix_mode(arcname: str) -> int:
    base = arcname.rsplit("/", 1)[-1]
    if base == "update-binary" or arcname.endswith(".sh") or base in ("search", "jump", "busybox"):
        return 0o100755
    return 0o100644


def main():
    entries = [
        ("META-INF/com/google/android/update-binary", UPDATE_BINARY),
        ("META-INF/com/google/android/updater-script", UPDATER_SCRIPT),
    ]
    for root, _dirs, files in os.walk(SRC):
        for name in files:
            full = os.path.join(root, name)
            rel = os.path.relpath(full, SRC).replace("\\", "/")
            with open(full, "rb") as f:
                entries.append((rel, f.read()))
    entries = entries[:2] + sorted(entries[2:], key=lambda e: (e[0] != "module.prop", e[0]))

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_STORED) as z:
        for arcname, data in entries:
            zi = zipfile.ZipInfo(arcname, date_time=TS)
            zi.compress_type = zipfile.ZIP_STORED
            zi.create_system = 0
            zi.external_attr = (unix_mode(arcname) << 16) | 0x10
            z.writestr(zi, data)
    print("wrote", OUT, os.path.getsize(OUT), "bytes,", len(entries), "entries")


if __name__ == "__main__":
    main()
