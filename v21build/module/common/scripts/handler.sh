#!/system/bin/sh
# HTC 天气本地代理 v4.2 (2026-11-23 十种天气样式全映射)
# 数据源: wttr.in (IP 直连, 绕过 busybox DNS bug) -> 生成 HTC ChinaWeatherParser XML
# 坐标查询: /<lat>,<lon>?format=j1  城市经纬度来自 cities.txt
BB=/data/local/tmp/htcweather/busybox
BASE=/data/local/tmp/htcweather
MAP=$BASE/cities.txt
WTTR_IP=5.9.243.187
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
  CITYNAME=$(echo "$ROW" | $BB cut -d'|' -f2 | $BB tr -d '\r')
  CITYID=$(echo "$ROW" | $BB cut -d'|' -f3 | $BB tr -d '\r')
  CLON=$(echo "$ROW" | $BB cut -d'|' -f4 | $BB tr -d '\r')
  CLAT=$(echo "$ROW" | $BB cut -d'|' -f5 | $BB tr -d '\r')
else
  CITYNAME="北京"; CITYID="101010100"; CLON="116.407526"; CLAT="39.904030"
fi

# ---- 3. 请求 wttr.in (IP直连 + 坐标, 15分钟缓存 + 过期兜底) ----
CACHE=$BASE/c_$CITYID.json
RAW=""
if [ -f "$CACHE" ] && [ -n "$($BB find $CACHE -mmin -15 2>/dev/null)" ]; then
  RAW=$(cat $CACHE)
else
  RAW=$($BB timeout 8 $BB wget -q -O - -T 8 "http://$WTTR_IP/$CLAT,$CLON?format=j1" 2>/dev/null)
  if [ -n "$RAW" ]; then
    printf '%s' "$RAW" > $CACHE
  elif [ -f "$CACHE" ]; then
    RAW=$(cat $CACHE)
  fi
fi

echo "$($BB date "+%H:%M:%S.%N" | cut -c1-12) code=$CODE city=$CITYNAME raw_len=$(echo -n "$RAW" | wc -c)" >> $BASE/req.log

# ---- 4. 生成 XML ----
if [ -n "$RAW" ] && echo "$RAW" | $BB grep -q "current_condition"; then
  NOW=$($BB date "+%Y-%m-%d %H:%M")
  XML=$(echo "$RAW" | $BB tr -d '\n' | $BB tr ',' '\n' | $BB awk -F':' -v city="$CITYNAME" -v cid="$CITYID" -v clon="$CLON" -v clat="$CLAT" -v now="$NOW" '
  function trim(s){ gsub(/^[ \t]+|[ \t]+$/,"",s); gsub(/^"|"$/,"",s); return s }
  function num(s,  t){ t=trim(s); gsub(/[^0-9.-]/,"",t); if(t==""||t=="-")t="0"; return t+0 }
  # ===== wttr.in(AccuWeather系) weatherCode -> HTC 中国天气码 v4.2 =====
  # 三级链路(已反编译验证): XML Condition(中国码) -> g.java x[]/y[] -> Accu图标ID
  #                          -> f.smali b[] -> 动画(晴/雷阵雨/多云/雾/炎热/间歇多云/局部晴/雨/雪/风)
  # 中国码->动画(白天): 0晴 1/2多云 3/6/7/8/9/19/21/22雨 4/10/11/12/23/24/25雷阵雨
  #                      13~17/26~28/34雪 18/20/29~31/35雾 32风
  # 注意: 6->Accu图标29->雨动画(非雪); 中国码无"炎热/间歇多云/局部晴"专用码,归入晴/多云
  function hcode(c,  n){ n=num(c)
    if(n==113)return 0                                  # Sunny -> 晴
    if(n==116||n==119||n==122)return 1                  # 局部晴/多云/阴 -> 多云(1)
    if(n==143||n==146||n==148||n==149||n==152||n==153||n==154||n==155||n==156||n==248||n==260)return 18 # 雾/霾/烟 -> 雾(18) 不是雪!
    if(n==200||n==386||n==389||n==392)return 4           # 雷阵雨 -> 雷阵雨(4)
    if(n==176||n==263||n==266||n==293||n==296||n==350||n==353||n==356||n==359||n==365)return 7 # 各类雨 -> 小雨(7)
    if(n==299||n==302||n==305||n==308)return 9           # 大雨/暴雨 -> 大雨(9)
    if(n==179||n==182||n==185||n==281||n==284||n==311||n==314||n==317||n==362||n==374||n==377)return 6 # 雨夹雪/冻雨 -> 雨(6)
    if(n==227||n==320||n==323||n==368)return 15          # 小雪 -> 小雪(15)
    if(n==230||n==329||n==332||n==335||n==338||n==371||n==395)return 17 # 大雪/暴雪 -> 大雪(17)
    if(n==326)return 16                                  # 中雪 -> 中雪(16)
    return 0 }
  # 当前天气综合判断: 晴+大风 -> 有风(32); 否则用 hcode
  function hcodeCur(c, wind, t,  h){ h=hcode(c)
    if(h==0 && wind>=25)return 32                        # 晴/多云且风速>=25km/h -> 有风
    return h }
  # wind dir 16-point -> HTC 0-7 (N=8 in original, keep mapping)
  function wdir(s){
    if(s~/^N$/)return 8; if(s~/^NNE$/)return 1; if(s~/^NE$/)return 1
    if(s~/^ENE$/)return 2; if(s~/^E$/)return 2; if(s~/^ESE$/)return 3
    if(s~/^SE$/)return 3; if(s~/^SSE$/)return 4; if(s~/^S$/)return 4
    if(s~/^SSW$/)return 5; if(s~/^SW$/)return 5; if(s~/^WSW$/)return 6
    if(s~/^W$/)return 6; if(s~/^WNW$/)return 7; if(s~/^NW$/)return 7
    if(s~/^NNW$/)return 8
    return 8 }
  function dmy(s,  a){ split(s,a,"-"); if(a[3]=="")return s; return a[2]"/"a[3]"/"a[1] }
  BEGIN{ fn=0; mode=""; hhidx=0 }
  {
    line=$0
    # 日期触发新的一天 (在 weather 数组内)
    if(line ~ /"date"/ && mode!="" && fn<8){ fn++; fdate[fn]=trim(substr(line,index(line,":")+1)); hhidx=0; next }
    # 每日高低温: 不受 mode 限制, 直接按 fn 收集
    if(line ~ /"maxtempC"/){ if(fn>0) fhigh[fn]=num(substr(line,index(line,":")+1)); next }
    if(line ~ /"mintempC"/){ if(fn>0) flow[fn]=num(substr(line,index(line,":")+1)); next }
    # current_condition block (first occurrence)
    if(line ~ /"current_condition"/){ mode="cur"; next }
    if(line ~ /"weather"/ && line !~ /weatherCode|weatherDesc|weatherIconUrl/){ mode="day"; next }
    if(line ~ /"hourly"/){ mode="hour"; next }
    if(line ~ /"nearest_area"/){ mode=""; next }
    if(mode=="cur"){
      if(line ~ /"temp_C"/ && curtemp==""){ curtemp=num(substr(line,index(line,":")+1)); next }
      if(line ~ /"humidity"/ && curhum==""){ curhum=num(substr(line,index(line,":")+1)); next }
      if(line ~ /"weatherCode"/ && curcode==""){ curcode=num(substr(line,index(line,":")+1)); next }
      if(line ~ /"winddir16Point"/ && curdir==""){ curdir=trim(substr(line,index(line,":")+1)); next }
      if(line ~ /"windspeedKmph"/ && curwind==""){ curwind=num(substr(line,index(line,":")+1)); next }
      next }
    if(mode=="day"){ next }
    if(mode=="hour"){
      if(line ~ /"time"/){ hhidx++; htime[hhidx]=num(substr(line,index(line,":")+1)); next }
      if(line ~ /"tempC"/){ htemp[hhidx]=num(substr(line,index(line,":")+1)); next }
      if(line ~ /"weatherCode"/){ hcode_[hhidx]=num(substr(line,index(line,":")+1)); next }
      next }
  }
  END{
    if(fn==0){ fn=1; fdate[1]=now; fhigh[1]=curtemp; flow[1]=curtemp }
    if(curtemp=="")curtemp=fhigh[1]
    print "<?xml version=\"1.0\" encoding=\"utf-8\"?>"
    print "<Root>"
    printf "<CityMeteor CityName=\"%s\">\n", city
    printf "<StationInfo StationID=\"%s\" Longitude=\"%s\" Latitude=\"%s\"/>\n", cid, clon, clat
    printf "<SK ReportTime=\"%s:00\">\n", now
    printf "<Info Condition=\"%d\" Temperature=\"%.1f\" WindDir=\"%d\" WindPower=\"%d\" WindSpeed=\"%.1f\" Humidity=\"%d\" FeelTemperature=\"%.1f\" Sunrise=\"7:00\" Sunset=\"17:30\" Pressure=\"1010\" Visibility=\"10\"/>\n", \
      hcodeCur(curcode,curwind,curtemp), curtemp, wdir(curdir), (curwind>30?3:(curwind>15?2:1)), curwind/3.6, curhum, curtemp
    print "</SK>"
    printf "<CF ReportTime=\"%s:00\">\n", now
    for(i=1; i<=fn && i<=5; i++)
      printf "<Period ForecastTime=\"%s\" Week=\"%d\" Weather=\"%d\" Tmax=\"%.1f\" Tmin=\"%.1f\" WindDir=\"8\" WindPower=\"1\"/>\n", \
        dmy(fdate[i]), (i%7==0?7:i%7), (i==1?hcodeCur(curcode,curwind,curtemp):1), fhigh[i], flow[i]
    print "</CF>"
    # ---- 每小时预报 CF3h: 用 wttr.in 真实 hourly, 每3小时取一个 ----
    printf "<CF3h ReportTime=\"%s\">\n", now
    if(hhidx>=8){
      for(hh=0; hh<24; hh+=3){
        k=int(hh/3)+1
        if(k>hhidx)k=hhidx
        printf "<Period Timestart=\"%s %02d:00\" Weather=\"%d\" Temperature=\"%d\"/>\n", \
          dmy(fdate[1]), hh, hcode(hcode_[k]), htemp[k]
      }
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
