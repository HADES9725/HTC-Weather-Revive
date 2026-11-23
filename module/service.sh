#!/system/bin/sh
# HTC Weather Revive - Magisk service.sh (runs on every boot, after data is mounted)
# Starts the resident watchdog which deploys runtime files and keeps :80/:8080 alive.
# hosts override is handled by post-fs-data.sh + watchdog (bind mount, magic mount unreliable).
MODDIR=${0%/*}
BASE=/data/local/tmp/htcweather
SRC=$MODDIR/common
PDIR=/data/adb/weatherfix_data
WBB=$SRC/busybox/busybox          # persistent busybox from module dir (survives boot)

sleep 6
mkdir -p "$BASE" "$PDIR" 2>/dev/null
{
echo "=== htcweather boot $(date) module=$MODDIR wbb=$WBB ==="

# Kill any stale listeners on :80 / :8080 before watchdog takes over
# (use persistent busybox - the volatile one may be missing after a wipe)
for INO in $($WBB grep -h -iE ":0050 |:1F90 " /proc/net/tcp6 /proc/net/tcp 2>/dev/null | $WBB awk '{print $10}'); do
  for P in /proc/[0-9]*; do
    ls -l $P/fd 2>/dev/null | $WBB grep -q "socket:\[$INO\]" && kill -9 ${P##*/} 2>/dev/null
  done
done

# Start (or restart) the resident watchdog, detached from adb session.
# Guard with a ps check to avoid duplicate loops if service.sh runs twice.
if ! $WBB ps 2>/dev/null | $WBB grep -q "[w]atchdog.sh"; then
  setsid /system/bin/sh "$SRC/scripts/watchdog.sh" </dev/null >/dev/null 2>&1 &
  echo "started watchdog"
else
  echo "watchdog already running"
fi

sleep 4
$WBB netstat -tln 2>/dev/null | $WBB grep -E ":(80|8080) " || echo "WARN: no listener yet (watchdog will fix)"
echo "=== boot done $(date) ==="
} >> "$BASE/boot.log" 2>&1
