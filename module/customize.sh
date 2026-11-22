#!/system/bin/sh
# Runs at install time. $MODPATH is the staging module dir.
# APK patch layer is optional: drop a switch file to skip APK overlay.
#   Switch: /data/local/tmp/weatherfix-noapk  (any content) -> skip APK patches
# This lets non-M8ST / incompatible ROM users keep only the systemless hosts +
# local proxy framework, avoiding patched-APK boot loops.
if [ -f /data/local/tmp/weatherfix-noapk ]; then
  ui_print "[weatherfix] switch found: APK patch layer DISABLED"
  ui_print "[weatherfix] only hosts + local proxy will be installed"
  rm -rf "$MODPATH/system/priv-app"
else
  ui_print "[weatherfix] APK patch layer ENABLED (M8St / Sense 7 / Android 6.0)"
  ui_print "[weatherfix] incompatible ROM? reboot recovery, create"
  ui_print "[weatherfix]   /data/local/tmp/weatherfix-noapk  and re-flash"
fi
# Ensure scripts are executable in the installed module
set_perm_recursive "$MODPATH" 0 0 0755 0644 2>/dev/null
set_perm "$MODPATH/service.sh" 0 0 0755 2>/dev/null
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755 2>/dev/null
