#!/system/bin/sh
# HDX: weather proxy watchdog (resident daemon) - v2.2 hardened
# Every 20s: rebuild runtime files if missing (/data/local/tmp is wiped on
# boot), keep :80 httpd and :8080 nc_server alive, re-apply hosts bind.
# KEY FIX: watchdog itself runs on the busybox inside the Magisk module dir
# (/data/adb/modules/weatherfix), which survives reboot. Never depend on the
# volatile /data/local/tmp busybox to rebuild that very directory.
MODDIR=/data/adb/modules/weatherfix
SRC=$MODDIR/common
BASE=/data/local/tmp/htcweather
PDIR=/data/adb/weatherfix_data
WBB=$SRC/busybox/busybox          # persistent busybox (module dir, survives boot)
BB=$BASE/busybox                  # volatile runtime busybox

log() { echo "$(date +%m-%d\ %H:%M:%S) $*" >> "$PDIR/watchdog.log" 2>/dev/null; }

deploy() {
  mkdir -p "$BASE/b2" "$BASE/wwwcgi/cgi-bin" "$BASE/wwwA" "$PDIR" 2>/dev/null || return 1
  # seed volatile busybox from persistent copy
  cp -f "$WBB" "$BASE/busybox" 2>/dev/null || return 1
  chmod 755 "$BASE/busybox" 2>/dev/null
  cp -f "$SRC/scripts/accu_server.sh" "$BASE/accu_server.sh"
  cp -f "$SRC/scripts/handler.sh" "$BASE/handler.sh"
  cp -f "$SRC/scripts/nc_server.sh" "$BASE/nc_server.sh"
  cp -f "$SRC/scripts/search" "$BASE/wwwcgi/cgi-bin/search"
  cp -f "$SRC/scripts/jump" "$BASE/wwwcgi/cgi-bin/jump"
  cp -f "$SRC/data/accu_alias.txt" "$BASE/accu_alias.txt"
  cp -f "$SRC/data/cities.txt" "$BASE/cities.txt"
  cp -f "$SRC/data/cma_stations.txt" "$BASE/cma_stations.txt"
  cp -f "$SRC/data/nmc_stations.txt" "$BASE/nmc_stations.txt"
  cp -f "$SRC/wwwA/httpd.conf" "$BASE/wwwA/httpd.conf"
  cp -f "$WBB" "$BASE/b2/busybox" 2>/dev/null
  chmod 755 "$BASE/accu_server.sh" "$BASE/handler.sh" "$BASE/nc_server.sh" \
            "$BASE/wwwcgi/cgi-bin/search" "$BASE/wwwcgi/cgi-bin/jump" \
            "$BASE/b2/busybox" 2>/dev/null
  # migrate any leftover caches from volatile dir to persistent dir
  for f in "$BASE"/c_*.json "$BASE"/sj_*.json; do
    [ -f "$f" ] && mv -f "$f" "$PDIR/" 2>/dev/null
  done
  apply_hosts
  log "deployed from $SRC"
}

apply_hosts() {
  [ -f "$MODDIR/system/etc/hosts" ] && \
    $WBB mount -o bind "$MODDIR/system/etc/hosts" /system/etc/hosts 2>/dev/null
}

listening() {
  $WBB netstat -tln 2>/dev/null | $WBB grep -q ":$1 "
}

start_8080() {
  listening 8080 && return 0
  setsid /system/bin/sh "$BASE/nc_server.sh" </dev/null >/dev/null 2>&1 &
  log "started nc_server :8080"
}

start_80() {
  listening 80 && return 0
  setsid "$BB" httpd -p 80 -h "$BASE/wwwA" -c "$BASE/wwwA/httpd.conf" </dev/null >/dev/null 2>&1 &
  log "started httpd :80"
}

log "=== watchdog start pid=$$ wbb=$WBB ==="
tick=0
while true; do
  if [ ! -x "$BB" ] || [ ! -f "$BASE/handler.sh" ] || [ ! -f "$BASE/cma_stations.txt" ] || [ ! -f "$BASE/nmc_stations.txt" ]; then
    deploy
  fi
  start_8080
  start_80
  # Re-apply hosts bind every ~10 min in case the system restores it
  tick=$((tick + 1))
  [ "$tick" -ge 30 ] && { tick=0; apply_hosts; }
  sleep 20
done
