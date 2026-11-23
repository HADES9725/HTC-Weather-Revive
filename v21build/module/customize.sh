#!/system/bin/sh
# Runs at install time. $MODPATH is the staging module dir.
# APK patch layer is optional: drop a switch file to skip APK overlay.
#   Switch: /data/local/tmp/weatherfix-noapk  (any content) -> skip APK patches
# This lets non-M8ST / incompatible ROM users keep only the systemless hosts +
# local proxy framework, avoiding patched-APK boot loops.
# ===== 玄霜的刷入开场 =====
ui_print " _   _   ____   __  __"
ui_print '| | | | |  _ \  \ \/ /'
ui_print "| |_| | | | | |  >  < "
ui_print '|  _  | | |_| | / \ \'
ui_print '|_| |_| |____/  /_/  \_'
ui_print ""
ui_print "   玄霜正在为你闹   "
ui_print "   闹了闹了闹了闹了闹了 "
ui_print "   闹了闹了闹了闹了闹了 "
ui_print "   闹了闹了闹了闹了闹了 "
ui_print "   闹了闹了闹了呜呜呜呜呜呜QAQ "
ui_print ""
ui_print "*********************************************"

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

# ===== 模块信息（兼容无 moduleInfo 的 Magisk） =====
if ! type moduleInfo >/dev/null 2>&1; then
  moduleInfo() {
    ui_print " "
    ui_print "*********************************************"
    for _k in name version versionCode author description; do
      _v=$(grep -m1 "^${_k}=" "$MODPATH/module.prop" | cut -d= -f2-)
      [ -n "$_v" ] && ui_print "  $_k: $_v"
    done
    ui_print "*********************************************"
  }
fi
moduleInfo
sleep 5

ui_print "*********************************************"
ui_print " "
ui_print "恭喜！玄霜旋爽了，天气修复安装已圆满完成，请重启您的设备以生效！ "
ui_print " "
