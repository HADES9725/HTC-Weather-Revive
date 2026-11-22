#!/system/bin/sh
# Clean up the runtime dir and stop listeners when module is removed.
BASE=/data/local/tmp/htcweather
for P in $(ps 2>/dev/null | grep -E "[n]c -l -p 8080|[h]ttpd -p 80" | awk '{print $2}'); do
  kill -9 "$P" 2>/dev/null
done
rm -rf "$BASE" 2>/dev/null
rm -f /data/local/tmp/weatherfix-noapk 2>/dev/null
exit 0
