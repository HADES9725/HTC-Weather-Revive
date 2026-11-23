#!/system/bin/sh
# HDX: weather proxy watchdog (resident daemon)
# Every 20s: rebuild runtime files if missing (/data/local/tmp is wiped on
# some ROMs), keep :80 httpd and :8080 nc_server alive, re-apply hosts bind.
# Launched via setsid by post-fs-data.sh / service.sh so it survives adb drop.
MODDIR=/data/adb/modules/weatherfix
SRC=$MODDIR/common
BASE=/data/local/tmp/htcweather
BB=$BASE/busybox

log() { echo "$(date +%m-%d\ %H:%M:%S) $*" >> "$BASE/watchdog.log" 2>/dev/null; }

deploy() {
  mkdir -p "$BASE/b2" "$BASE/wwwcgi/cgi-bin" "$BASE/wwwA" 2>/dev/null || return 1
  cp -f "$SRC/busybox/busybox" "$BASE/busybox" 2>/dev/null || return 1
  chmod 755 "$BASE/busybox" 2>/dev/null
  cp -f "$SRC/scripts/accu_server.sh" "$BASE/accu_server.sh"
  cp -f "$SRC/scripts/handler.sh" "$BASE/handler.sh"
  cp -f "$SRC/scripts/nc_server.sh" "$BASE/nc_server.sh"
  cp -f "$SRC/scripts/search" "$BASE/wwwcgi/cgi-bin/search"
  cp -f "$SRC/scripts/jump" "$BASE/wwwcgi/cgi-bin/jump"
  cp -f "$SRC/data/accu_alias.txt" "$BASE/accu_alias.txt"
  cp -f "$SRC/data/cities.txt" "$BASE/cities.txt"
  cp -f "$SRC/data/cma_stations.txt" "$BASE/cma_stations.txt"
  cp -f "$SRC/wwwA/httpd.conf" "$BASE/wwwA/httpd.conf"
  cp -f "$BASE/busybox" "$BASE/b2/busybox" 2>/dev/null
  chmod 755 "$BASE/accu_server.sh" "$BASE/handler.sh" "$BASE/nc_server.sh" \
            "$BASE/wwwcgi/cgi-bin/search" "$BASE/wwwcgi/cgi-bin/jump" \
            "$BASE/b2/busybox" 2>/dev/null
  apply_hosts
  log "deployed from $SRC"
}

apply_hosts() {
  [ -f "$MODDIR/system/etc/hosts" ] && \
    mount -o bind "$MODDIR/system/etc/hosts" /system/etc/hosts 2>/dev/null
}

listening() {
  $BB netstat -tln 2>/dev/null | $BB grep -q ":$1 "
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

log "=== watchdog start pid=$$ ==="
tick=0
while true; do
  if [ ! -x "$BB" ] || [ ! -f "$BASE/handler.sh" ] || [ ! -f "$BASE/cma_stations.txt" ]; then
    deploy || { sleep 20; continue; }
  fi
  start_8080
  start_80
  # Re-apply hosts bind every ~10 min in case the system restores it
  tick=$((tick + 1))
  [ "$tick" -ge 30 ] && { tick=0; apply_hosts; }
  sleep 20
done
