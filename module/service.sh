#!/system/bin/sh
# HTC Weather Revive - Magisk service.sh (runs on every boot, after data is mounted)
# Deploys local weather proxy from module dir to a writable runtime dir, then
# starts :8080 (AccuWeather emulator) and :80 (legacy HTC endpoint httpd).
# hosts override is handled systemlessly by Magisk (system/etc/hosts in module).
MODDIR=${0%/*}
BASE=/data/local/tmp/htcweather
SRC=$MODDIR/common
LOG=$BASE/boot.log

# Wait for /data and network stack to settle
sleep 12

mkdir -p "$BASE/b2" "$BASE/wwwcgi/cgi-bin" "$BASE/wwwA"
# Use the deployed busybox in $BASE (module-dir busybox may hit SELinux denials)
cp -f "$SRC/busybox/busybox" "$BASE/busybox" 2>/dev/null
chmod 755 "$BASE/busybox"
BB=$BASE/busybox
{
echo "=== htcweather boot $(date) module=$MODDIR ==="

# ---- 1. Deploy runtime files (idempotent, always overwrite from module) ----
cp -f "$SRC/scripts/accu_server.sh"   "$BASE/accu_server.sh"
cp -f "$SRC/scripts/handler.sh"       "$BASE/handler.sh"
cp -f "$SRC/scripts/nc_server.sh"     "$BASE/nc_server.sh"
cp -f "$SRC/scripts/search"           "$BASE/wwwcgi/cgi-bin/search"
cp -f "$SRC/scripts/jump"             "$BASE/wwwcgi/cgi-bin/jump"
cp -f "$SRC/data/accu_alias.txt"      "$BASE/accu_alias.txt"
cp -f "$SRC/data/cities.txt"          "$BASE/cities.txt"
cp -f "$SRC/data/cma_stations.txt"    "$BASE/cma_stations.txt"
cp -f "$SRC/wwwA/httpd.conf"          "$BASE/wwwA/httpd.conf"
cp -f "$SRC/busybox/busybox"          "$BASE/busybox"
cp -f "$SRC/busybox/busybox"          "$BASE/b2/busybox"
chmod 755 "$BASE/accu_server.sh" "$BASE/handler.sh" "$BASE/nc_server.sh" \
          "$BASE/wwwcgi/cgi-bin/search" "$BASE/wwwcgi/cgi-bin/jump" \
          "$BASE/busybox" "$BASE/b2/busybox"

# ---- 2. Kill any stale listeners on :80 / :8080 ----
for INO in $($BB grep -h -iE ":0050 |:1F90 " /proc/net/tcp6 /proc/net/tcp 2>/dev/null | $BB awk '{print $10}'); do
  for P in /proc/[0-9]*; do
    ls -l $P/fd 2>/dev/null | $BB grep -q "socket:\[$INO\]" && kill -9 ${P##*/} 2>/dev/null
  done
done
sleep 1

# ---- 3. Start :8080 AccuWeather emulator (detached, auto-restart loop) ----
if ! $BB ps | $BB grep -q "[n]c -l -p 8080"; then
  setsid /system/bin/sh "$BASE/nc_server.sh" < /dev/null > /dev/null 2>&1 &
  echo "started nc_server :8080"
fi

# ---- 4. Start :80 legacy HTC endpoint proxy ----
if ! $BB ps | $BB grep -q "[h]ttpd -p 80"; then
  setsid $BB httpd -p 80 -h "$BASE/wwwA" -c "$BASE/wwwA/httpd.conf" < /dev/null > /dev/null 2>&1 &
  echo "started httpd :80"
fi

sleep 2
$BB netstat -tln 2>/dev/null | $BB grep -E ":(80|8080)" || echo "WARN: no listener found"

# ---- 5. Trigger one weather autosync ----
sleep 45
am broadcast -a com.htc.sync.provider.weather.START_AUTOSYNC_SERVICE >/dev/null 2>&1
echo "=== boot done $(date) ==="
} >> "$LOG" 2>&1
