#!/system/bin/sh
# Bind-mount hosts (magic mount unreliable on this device) so weather
# endpoint hijack (htc-mobile.mywtv.cn -> 127.0.0.1) always takes effect.
MODDIR=${0%/*}
[ -f "$MODDIR/system/etc/hosts" ] && mount -o bind "$MODDIR/system/etc/hosts" /system/etc/hosts 2>/dev/null

# Clear weather app dexopt caches so PM re-dexopts from the patched APKs.
rm -f /data/dalvik-cache/*/system@priv-app@Weather@Weather.apk@classes.dex* 2>/dev/null
rm -f /data/dalvik-cache/*/system@priv-app@HtcServicePack@HtcServicePack.apk@classes.dex* 2>/dev/null
rm -f /data/dalvik-cache/*/system@product@priv-app@Weather@Weather.apk@classes.dex* 2>/dev/null
rm -f /data/dalvik-cache/*/system@product@priv-app@HtcServicePack@HtcServicePack.apk@classes.dex* 2>/dev/null

# Earliest safety net: start watchdog here too (service.sh may fail on some ROMs).
# The ps guard prevents a duplicate loop when both stages run.
BASE=/data/local/tmp/htcweather
mkdir -p "$BASE"
cp -f "$MODDIR/common/busybox/busybox" "$BASE/busybox" 2>/dev/null
chmod 755 "$BASE/busybox" 2>/dev/null
if [ -x "$BASE/busybox" ] && ! "$BASE/busybox" ps 2>/dev/null | "$BASE/busybox" grep -q "[w]atchdog.sh"; then
  setsid /system/bin/sh "$MODDIR/common/scripts/watchdog.sh" </dev/null >/dev/null 2>&1 &
fi
exit 0
