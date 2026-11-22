#!/system/bin/sh
# Clear weather app dexopt caches so PM re-dexopts from the patched APKs.
# Uses glob patterns so it works on both arm and arm64 dalvik-cache layouts.
rm -f /data/dalvik-cache/*/system@priv-app@Weather@Weather.apk@classes.dex* 2>/dev/null
rm -f /data/dalvik-cache/*/system@priv-app@HtcServicePack@HtcServicePack.apk@classes.dex* 2>/dev/null
rm -f /data/dalvik-cache/*/system@product@priv-app@Weather@Weather.apk@classes.dex* 2>/dev/null
rm -f /data/dalvik-cache/*/system@product@priv-app@HtcServicePack@HtcServicePack.apk@classes.dex* 2>/dev/null
exit 0
