#!/system/bin/sh
# HTC 天气本地代理 (httpd CGI 模式, 兼容 nc stdin 模式)
# 数据源: 腾讯 sojson (纯HTTP) -> 生成 HTC ChinaWeatherParser XML

BB=/data/local/tmp/htcweather/busybox
BASE=/data/local/tmp/htcweather
MAP=$BASE/cities.txt
export TZ=CST-8

# ---- 1. 获取请求参数 ----
QS="$QUERY_STRING"
if [ -z "$QS" ]; then
  CR=$(printf '\r')
  read -r REQ
  i=0
  while [ $i -lt 60 ]; do
    read -r line || break
    line=${line%$CR}
    [ -z "$line" ] && break
    i=$((i+1))
  done
  QS="$REQ"
fi
echo "REQ: $REQ | QS: $QS" >> $BASE/req_raw.log

CODE=$(echo "$QS" | $BB sed -n 's/.*sname=\([0-9]*\).*/\1/p')
[ -z "$CODE" ] && CODE="01010101"

# ---- 2. 查映射表: HTC码|城市名|腾讯cityid|lon|lat ----
ROW=$($BB grep -m1 "^$CODE|" "$MAP")
if [ -n "$ROW" ]; then
  CITYNAME=$(echo "$ROW" | $BB cut -d'|' -f2)
  CITYID=$(echo "$ROW" | $BB cut -d'|' -f3)
  CLON=$(echo "$ROW" | $BB cut -d'|' -f4)
  CLAT=$(echo "$ROW" | $BB cut -d'|' -f5)
else
  CITYNAME="北京"; CITYID="101010100"; CLON="116.41"; CLAT="39.90"
fi

# ---- 3. 请求腾讯 sojson (4秒超时+15分钟缓存+过期兜底) ----
CACHE=$BASE/c_$CITYID.json
RAW=""
if [ -f "$CACHE" ] && [ -n "$($BB find $CACHE -mmin -15 2>/dev/null)" ]; then
  RAW=$(cat $CACHE)
else
  RAW=$($BB timeout 4 $BB wget -q -O - -T 4 "http://t.weather.sojson.com/api/weather/city/$CITYID" 2>/dev/null)
  if [ -n "$RAW" ]; then
    printf '%s' "$RAW" > $CACHE
  elif [ -f "$CACHE" ]; then
    RAW=$(cat $CACHE)
  fi
fi

echo "$($BB date "+%H:%M:%S.%N" | cut -c1-12) code=$CODE raw_len=$(echo -n "$RAW" | wc -c)" >> $BASE/req.log
# ---- 4. 生成 XML ----
if [ -n "$RAW" ]; then
  NOW=$($BB date "+%Y-%m-%d %H:%M")
  XML=$(echo "$RAW" | $BB sed 's/},{/}\n{/g; s/,"/,\n"/g' | $BB awk -F':' -v city="$CITYNAME" -v cid="$CITYID" -v clon="$CLON" -v clat="$CLAT" -v now="$NOW" '
  function trim(s){ gsub(/,$/,"",s); gsub(/^[ \t"]+|[ \t"]+$/,"",s); return s }
  function num(s,  t){ t=trim(s); gsub(/[^0-9.-]/,"",t); if(t==""||t=="-")t="0"; return t+0 }
  function mainpart(t,  a){ split(t,a,"转"); return a[1] }
  function wcode(t){
    t=mainpart(t)
    if(t~/雷/)return 4
    if(t~/冰雹/)return 5
    if(t~/雨夹雪/)return 6
    if(t~/冻雨/)return 18
    if(t~/暴雨/)return 10
    if(t~/大雨/)return 9
    if(t~/中雨/)return 8
    if(t~/阵雨/)return 3
    if(t~/雨/)return 7
    if(t~/暴雪|大雪/)return 16
    if(t~/中雪/)return 15
    if(t~/阵雪/)return 13
    if(t~/雪/)return 14
    if(t~/雾/)return 17
    if(t~/霾|沙|尘/)return 19
    if(t~/多云/)return 1
    if(t~/阴/)return 2
    if(t~/晴/)return 0
    return 0 }
  function wdir(d){
    d=mainpart(d)
    if(d~/西北/)return 7; if(d~/东北/)return 1
    if(d~/西南/)return 5; if(d~/东南/)return 3
    if(d~/北/)return 8; if(d~/南/)return 4
    if(d~/东/)return 2; if(d~/西/)return 6
    return 8 }
  function wfl(s,  a){ split(s,a,"[^0-9]"); return a[1]+0 }
  function wk(s){
    if(s~/一/)return 1; if(s~/二/)return 2; if(s~/三/)return 3
    if(s~/四/)return 4; if(s~/五/)return 5; if(s~/六/)return 6
    return 7 }
  # 2026-11-22 -> 11/22/2026 (HTC UI getWeekDayFormat/getDateFormat 按 / 分割)
  function dmy(s,  a){ split(s,a,"-"); if(a[3]=="")return s; return a[2]"/"a[3]"/"a[1] }
  BEGIN{ fn=0 }
  {
    line=$0
    if(line ~ /"wendu"/){ curtemp=num(substr(line,index(line,":")+1)); next }
    if(line ~ /"shidu"/){ curhum=num(substr(line,index(line,":")+1)); next }
    if(line ~ /"ymd"/){ fn++; fdate[fn]=trim(substr(line,index(line,":")+1)); next }
    if(line ~ /"week"/){ fweek[fn]=trim(substr(line,index(line,":")+1)); next }
    if(line ~ /"high"/){ fhigh[fn]=num(substr(line,index(line,":")+1)); next }
    if(line ~ /"low"/){ flow[fn]=num(substr(line,index(line,":")+1)); next }
    if(line ~ /"sunrise"/){ frise[fn]=trim(substr(line,index(line,":")+1)); next }
    if(line ~ /"sunset"/){ fset[fn]=trim(substr(line,index(line,":")+1)); next }
    if(line ~ /"fx"/){ ffx[fn]=trim(substr(line,index(line,":")+1)); next }
    if(line ~ /"fl"/){ ffl[fn]=trim(substr(line,index(line,":")+1)); next }
    if(line ~ /"type"/){ ftype[fn]=trim(substr(line,index(line,":")+1)); next }
  }
  END{
    if(fn==0){ fn=1 }
    cfx=ffx[1]; cfl=ffl[1]
    print "<?xml version=\"1.0\" encoding=\"utf-8\"?>"
    print "<Root>"
    printf "<CityMeteor CityName=\"%s\">\n", city
    printf "<StationInfo StationID=\"%s\" Longitude=\"%s\" Latitude=\"%s\"/>\n", cid, clon, clat
    printf "<SK ReportTime=\"%s:00\">\n", now
    printf "<Info Condition=\"%d\" Temperature=\"%.1f\" WindDir=\"%d\" WindPower=\"%d\" WindSpeed=\"%.1f\" Humidity=\"%d\" FeelTemperature=\"%.1f\" Sunrise=\"%s\" Sunset=\"%s\" Pressure=\"1010\" Visibility=\"10\"/>\n", \
      wcode(ftype[1]), curtemp, wdir(cfx), wfl(cfl), wfl(cfl)*0.9, curhum, curtemp, frise[1], fset[1]
    print "</SK>"
    print "<CF ReportTime=\"" now ":00\">"
    for(i=1; i<=fn && i<=5; i++)
      printf "<Period ForecastTime=\"%s\" Week=\"%d\" Weather=\"%d\" Tmax=\"%.1f\" Tmin=\"%.1f\" WindDir=\"%d\" WindPower=\"%d\"/>\n", \
        dmy(fdate[i]), wk(fweek[i]), wcode(ftype[i]), fhigh[i], flow[i], wdir(ffx[i]), wfl(ffl[i])
    print "</CF>"
    # ---- 每小时预报: CF3h 元素, 每个 Period 代表 3 小时, 8 个 = 24h ----
    # 温度按今天高低温正弦合成, 天气现象沿用今天
    nsh=split("0 .03 .06 .09 .12 .16 .22 .30 .38 .46 .55 .63 .72 .80 .88 .95 1 .96 .9 .82 .72 .62 .52 .42 .32", SH, " ")
    printf "<CF3h ReportTime=\"%s\">\n", now
    for(hh=0; hh<24; hh+=3){
      ttemp=flow[1]+(fhigh[1]-flow[1])*SH[hh+1]
      printf "<Period Timestart=\"%s %02d:00\" Weather=\"%d\" Temperature=\"%d\"/>\n", \
        dmy(fdate[1]), hh, wcode(ftype[1]), (ttemp<0?int(ttemp-0.5):int(ttemp+0.5))
    }
    print "</CF3h>"
    print "</CityMeteor>"
    print "</Root>"
  }')
else
  NOWB=$($BB date "+%Y-%m-%d %H:%M")
  FBD=$($BB date "+%m/%d/%Y")
  XML="<?xml version=\"1.0\" encoding=\"utf-8\"?><Root><CityMeteor CityName=\"$CITYNAME\"><StationInfo StationID=\"$CITYID\" Longitude=\"$CLON\" Latitude=\"$CLAT\"/><SK ReportTime=\"$NOWB:00\"><Info Condition=\"0\" Temperature=\"15\" WindDir=\"8\" WindPower=\"1\" WindSpeed=\"0.9\" Humidity=\"50\" FeelTemperature=\"15\" Sunrise=\"7:00\" Sunset=\"17:30\" Pressure=\"1010\" Visibility=\"10\"/></SK><CF ReportTime=\"\"><Period ForecastTime=\"$FBD\" Week=\"1\" Weather=\"0\" Tmax=\"15\" Tmin=\"5\" WindDir=\"8\" WindPower=\"1\"/></CF><CF3h ReportTime=\"$NOWB\"></CF3h></CityMeteor></Root>"
fi

# ---- 5. 输出 ----
if [ -n "$QUERY_STRING" ]; then
  printf 'Content-Type: text/xml; charset=utf-8\r\n\r\n'
  printf '%s' "$XML"
else
  LEN=$(echo -n "$XML" | wc -c | tr -d ' \r\n')
  printf 'HTTP/1.0 200 OK\r\nContent-Type: text/xml; charset=utf-8\r\nContent-Length: %s\r\nConnection: close\r\n\r\n' "$LEN"
  printf '%s' "$XML"
fi
