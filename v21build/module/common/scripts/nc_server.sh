#!/system/bin/sh
# accu 万能路由服务器 (nc -l -e 循环, 替代不可用的 inetd)
BB=/data/local/tmp/htcweather/b2/busybox
BASE=/data/local/tmp/htcweather
LOG=$BASE/ncserver.log
echo "=== nc server start $(date) ===" >> $LOG
while true; do
  $BB nc -l -p 8080 -e /system/bin/sh $BASE/accu_server.sh >> $LOG 2>&1
  echo "--- conn done $(date +%T) ---" >> $LOG
  sleep 1
done
