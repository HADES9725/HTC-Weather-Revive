#!/system/bin/sh
# HTC Weather Revive - Magisk service.sh (runs on every boot, after data is mounted)
# Starts the resident watchdog which deploys runtime files and keeps :80/:8080 alive.
# hosts override is handled by post-fs-data.sh + watchdog (bind mount, magic mount unreliable).
MODDIR=${0%/*}
BASE=/data/local/tmp/htcweather
SRC=$MODDIR/common
LOG=$BASE/boot.log

# Wait briefly for /data and network stack to settle (keep short: watchdog self-heals)
sleep 6
mkdir -p "$BASE"
{
echo "=== htcweather boot $(date) module=$MODDIR ==="

# Bootstrap busybox so watchdog can run even if runtime dir was wiped
cp -f "$SRC/busybox/busybox" "$BASE/busybox" 2>/dev/null
chmod 755 "$BASE/busybox" 2>/dev/null

# Kill any stale listeners on :80 / :8080 before watchdog takes over
BB=$BASE/busybox
for INO in $($BB grep -h -iE ":0050 |:1F90 " /proc/net/tcp6 /proc/net/tcp 2>/dev/null | $BB awk '{print $10}'); do
  for P in /proc/[0-9]*; do
    ls -l $P/fd 2>/dev/null | $BB grep -q "socket:\[$INO\]" && kill -9 ${P##*/} 2>/dev/null
  done
done

# Start (or restart) the resident watchdog, detached from adb session.
# Guard with a ps check to avoid duplicate loops if service.sh runs twice.
if ! $BB ps 2>/dev/null | $BB grep -q "[w]atchdog.sh"; then
  setsid /system/bin/sh "$SRC/scripts/watchdog.sh" </dev/null >/dev/null 2>&1 &
  echo "started watchdog"
else
  echo "watchdog already running"
fi

sleep 4
$BB netstat -tln 2>/dev/null | $BB grep -E ":(80|8080) " || echo "WARN: no listener yet (watchdog will fix)"
echo "=== boot done $(date) ==="
} >> "$LOG" 2>&1
