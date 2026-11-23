#!/system/bin/sh
# HTC 天气本地代理 v5 (2026-11-23 中国气象局官方数据源)
# 主源: 中国气象局 weather.cma.cn (ssl_client + IP直连绕DNS, 中文天气现象)
# 备源: sojson 中国天气网 (IP直连, 363城市全覆盖, 同为气象局数据)
# 生成 HTC ChinaWeatherParser 兼容 XML
BB=/data/local/tmp/htcweather/busybox
BASE=/data/local/tmp/htcweather
MAP=$BASE/cities.txt
SMAP=$BASE/cma_stations.txt
CMA_IP=106.120.80.204
SJ_IP=115.231.101.162
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

# ---- 3. 取 CMA 站点号 ----
SID=$($BB grep -m1 "^$CITYID|" "$SMAP" 2>/dev/null | $BB cut -d'|' -f2 | $BB tr -d '\r')

# ---- 4. 取数据: CMA 优先, sojson 兜底 (15分钟缓存+过期兜底) ----
CACHE=$BASE/c_$CITYID.json
SRC_TAG=""
RAW=""

# helper: 发 HTTPS 请求到 CMA (ssl_client IP直连, 纯IP时 getaddrinfo 直接解析)
fetch_cma(){
  [ -z "$SID" ] && return 1
  local req="GET /api/weather/view?stationid=$SID HTTP/1.1\r\nHost: weather.cma.cn\r\nUser-Agent: Mozilla/5.0\r\nConnection: close\r\n\r\n"
  local out
  out=$(printf "$req" | $BB timeout 12 $BB ssl_client "$CMA_IP" 2>/dev/null)
  # 校验: 含 "msg":"success" 和 daily
  echo "$out" | $BB grep -q '"msg":"success"' && echo "$out" | $BB grep -q '"daily"' || return 1
  # 提取 JSON body: CMA 响应是 chunked, JSON 独占以 { 开头的一行
  # (不能用贪婪 sed, 因 Set-Cookie 的 base64 里可能含花括号)
  echo "$out" | $BB grep -m1 '^{'
  return 0
}

# helper: sojson IP直连 (nc 带 Host头)
fetch_sojson(){
  local req="GET /api/weather/city/$CITYID HTTP/1.1\r\nHost: t.weather.sojson.com\r\nUser-Agent: Mozilla/5.0\r\nConnection: close\r\n\r\n"
  local out
  out=$(printf "$req" | $BB timeout 10 $BB nc "$SJ_IP" 80 2>/dev/null)
  echo "$out" | $BB grep -q '"status":200' || return 1
  echo "$out" | $BB grep -m1 '^{'
  return 0
}

if [ -f "$CACHE" ] && [ -n "$($BB find "$CACHE" -mmin -15 2>/dev/null)" ]; then
  RAW=$(cat "$CACHE")
  SRC_TAG="cache"
else
  if [ -n "$SID" ]; then
    RAW=$(fetch_cma)
    [ -n "$RAW" ] && SRC_TAG="cma"
  fi
  if [ -z "$RAW" ]; then
    RAW=$(fetch_sojson)
    [ -n "$RAW" ] && SRC_TAG="sojson"
  fi
  if [ -n "$RAW" ]; then
    printf '%s' "$RAW" > "$CACHE"
  elif [ -f "$CACHE" ]; then
    RAW=$(cat "$CACHE")
    SRC_TAG="stale"
  fi
fi

echo "$($BB date "+%H:%M:%S.%N" | cut -c1-12) code=$CODE city=$CITYNAME sid=${SID:-none} src=$SRC_TAG raw_len=$(echo -n "$RAW" | wc -c)" >> $BASE/req.log

# ---- 5. 生成 XML (统一 awk, 支持 CMA 中文现象 / sojson type / wttr code) ----
if [ -n "$RAW" ]; then
  NOW=$($BB date "+%Y-%m-%d %H:%M")
  # 判断是否 CMA 数据 (有 dayText) 或 sojson (有 "type":"晴") 或 wttr (current_condition)
  IS_CMA=$(echo "$RAW" | $BB grep -c 'dayText')
  IS_SJ=$(echo "$RAW" | $BB grep -c '"wendu"')
  XML=$(echo "$RAW" | $BB tr -d '\n' | $BB tr ',' '\n' | $BB awk -F':' \
    -v city="$CITYNAME" -v cid="$CITYID" -v clon="$CLON" -v clat="$CLAT" -v now="$NOW" \
    -v iscma="$IS_CMA" -v issj="$IS_SJ" '
  function trim(s,  t){ t=s; gsub(/^[ \t]+|[ \t]+$/,"",t); gsub(/^"|"$/,"",t); gsub(/\r/,"",t); return t }
  function num(s,  t){ t=trim(s); gsub(/[^0-9.-]/,"",t); if(t==""||t=="-")t="0"; return t+0 }

  # ===== 中文天气现象 -> HTC 中国天气码 (权威 g.java 码表) =====
  # 0晴 1多云 2阴 3阵雨 4雷阵雨 6雨夹雪 7小雨 8中雨 9大雨 10暴雨
  # 13小雪 15中雪 16大雪 17暴雪 18雾 32风
  function cncode(s,  t){ t=trim(s)
    if(t~/^晴/)return 0
    if(t~/雷/)return 4
    if(t~/雨夹雪|雨夹/)return 6
    if(t~/暴雪|大雪/)return 17
    if(t~/中雪/)return 16
    if(t~/小雪|阵雪/)return 15
    if(t~/雪/)return 15
    if(t~/暴雨|大暴雨/)return 10
    if(t~/大雨/)return 9
    if(t~/中雨/)return 8
    if(t~/小雨/)return 7
    if(t~/阵雨/)return 3
    if(t~/雨/)return 7
    if(t~/雾|霾|烟|沙尘/)return 18
    if(t~/风/)return 32
    if(t~/阴/)return 2
    if(t~/多云|少云/)return 1
    return 0 }

  function wdir(s){
    if(s~/北/)return 8; if(s~/东北/)return 1; if(s~/东/)return 2; if(s~/东南/)return 3
    if(s~/南/)return 4; if(s~/西南/)return 5; if(s~/西/)return 6; if(s~/西北/)return 7
    return 8 }
  function dmy(s,  a){ gsub(/\//,"-",s); split(s,a,"-"); if(a[3]=="")return s; return a[2]"/"a[3]"/"a[1] }
  BEGIN{ fn=0; mode=""; di=0; curcode=""; curtext=""; curtemp=""; curhum=""; curdir=""; curwind=""; n=0 }

  # ===== CMA 模式 =====
  {
    line=$0
    if(iscma==1){
      # daily 数组内每天: date/high/dayText/low 按出现顺序
      if(line ~ /"date"/){ fn++; fdate[fn]=trim(substr(line,index(line,":")+1)); next }
      if(line ~ /"dayText"/ && fn>0 && daytext[fn]==""){ daytext[fn]=trim(substr(line,index(line,":")+1)); next }
      if(line ~ /"nightText"/ && fn>0 && nighttext[fn]==""){ nighttext[fn]=trim(substr(line,index(line,":")+1)); next }
      if(line ~ /"high"/ && fn>0 && fhigh[fn]==""){ fhigh[fn]=num(substr(line,index(line,":")+1)); next }
      if(line ~ /"low"/ && fn>0 && flow[fn]==""){ flow[fn]=num(substr(line,index(line,":")+1)); next }
      # now 实况
      if(line ~ /"temperature"/ && curtemp==""){ curtemp=num(substr(line,index(line,":")+1)); next }
      if(line ~ /"humidity"/ && curhum==""){ curhum=num(substr(line,index(line,":")+1)); next }
      if(line ~ /"windDirection"/ && curdir==""){ curdir=trim(substr(line,index(line,":")+1)); next }
      if(line ~ /"windSpeed"/ && curwind==""){ curwind=num(substr(line,index(line,":")+1)); next }
      next
    }

    # ===== sojson 模式 =====
    if(issj==1){
      if(line ~ /"wendu"/ && curtemp==""){ curtemp=num(substr(line,index(line,":")+1)); next }
      if(line ~ /"shidu"/ && curhum==""){ curhum=num(substr(line,index(line,":")+1)); next }
      if(line ~ /"type"/){ n++; if(n==1){ curtext=trim(substr(line,index(line,":")+1)) } if(fn>0&&daytext[fn]=="")daytext[fn]=trim(substr(line,index(line,":")+1)); next }
      if(line ~ /"high"/){ fn++; gsub(/[^0-9.-]/,"",line); fhigh[fn]=num(line); next }
      if(line ~ /"low"/ && fn>0){ gsub(/[^0-9.-]/,"",line); flow[fn]=num(line); next }
      if(line ~ /"ymd"/ && fn>0 && fdate[fn]==""){ fdate[fn]=trim(substr(line,index(line,":")+1)); next }
      if(line ~ /"fx"/ && curdir==""){ curdir=trim(substr(line,index(line,":")+1)); next }
      next
    }

    # ===== wttr 兼容模式 (旧缓存) =====
    if(line ~ /"maxtempC"/){ if(fn>0) fhigh[fn]=num(substr(line,index(line,":")+1)); next }
    if(line ~ /"mintempC"/){ if(fn>0) flow[fn]=num(substr(line,index(line,":")+1)); next }
    if(line ~ /"current_condition"/){ mode="cur"; next }
    if(line ~ /"date"/ && mode!="" && fn<8){ fn++; fdate[fn]=trim(substr(line,index(line,":")+1)); next }
    if(line ~ /"weather"/ && line !~ /weatherCode|weatherDesc|weatherIconUrl/){ mode="day"; next }
    if(line ~ /"nearest_area"/){ mode=""; next }
    if(mode=="cur"){
      if(line ~ /"temp_C"/ && curtemp==""){ curtemp=num(substr(line,index(line,":")+1)); next }
      if(line ~ /"humidity"/ && curhum==""){ curhum=num(substr(line,index(line,":")+1)); next }
      if(line ~ /"weatherCode"/ && curcode==""){ curcode=num(substr(line,index(line,":")+1)); next }
      if(line ~ /"winddir16Point"/ && curdir==""){ curdir=trim(substr(line,index(line,":")+1)); next }
      if(line ~ /"windspeedKmph"/ && curwind==""){ curwind=num(substr(line,index(line,":")+1)); next }
      next }
  }
  END{
    if(fn==0){ fn=1; fdate[1]=now; fhigh[1]=curtemp; flow[1]=curtemp }
    if(curtemp==""||curtemp==0)curtemp=(fhigh[1]+flow[1])/2
    if(curtemp=="")curtemp=15
    # 当前天气码: CMA/sojson 用中文文字, wttr 用 code
    cc=0
    if(iscma==1||issj==1){ if(curtext!="")cc=cncode(curtext); else if(daytext[1]!="")cc=cncode(daytext[1]) }
    else { c=num(curcode); if(c==113)cc=0; else if(c>=176&&c<=182)cc=7; else if(c>=227&&c<=230)cc=17; else cc=1 }
    # 风速单位: CMA m/s, sojson "N级", wttr km/h -> 统一 km/h
    wspd=curwind
    if(iscma==1) wspd=curwind*3.6
    else if(issj==1) wspd=curwind*5
    if(cc==0 && wspd>=25)cc=32

    print "<?xml version=\"1.0\" encoding=\"utf-8\"?>"
    print "<Root>"
    printf "<CityMeteor CityName=\"%s\">\n", city
    printf "<StationInfo StationID=\"%s\" Longitude=\"%s\" Latitude=\"%s\"/>\n", cid, clon, clat
    printf "<SK ReportTime=\"%s:00\">\n", now
    printf "<Info Condition=\"%d\" Temperature=\"%.1f\" WindDir=\"%d\" WindPower=\"%d\" WindSpeed=\"%.1f\" Humidity=\"%d\" FeelTemperature=\"%.1f\" Sunrise=\"7:00\" Sunset=\"17:30\" Pressure=\"1010\" Visibility=\"10\"/>\n", \
      cc, curtemp, wdir(curdir), (wspd>30?3:(wspd>15?2:1)), wspd/3.6, curhum, curtemp
    print "</SK>"
    printf "<CF ReportTime=\"%s:00\">\n", now
    for(i=1; i<=fn && i<=5; i++){
      wc=(daytext[i]!=""?cncode(daytext[i]):(i==1?cc:1))
      printf "<Period ForecastTime=\"%s\" Week=\"%d\" Weather=\"%d\" Tmax=\"%.1f\" Tmin=\"%.1f\" WindDir=\"8\" WindPower=\"1\"/>\n", \
        dmy(fdate[i]), (i%7==0?7:i%7), wc, fhigh[i], flow[i]
    }
    print "</CF>"
    # CF3h: 用当日天气码填充 (CMA/sojson 无逐小时, 用当天白天/夜间)
    printf "<CF3h ReportTime=\"%s\">\n", now
    dayc=(daytext[1]!=""?cncode(daytext[1]):cc)
    nightc=(nighttext[1]!=""?cncode(nighttext[1]):dayc)
    for(hh=0; hh<24; hh+=3){
      wc=(hh>=6&&hh<18?dayc:nightc)
      printf "<Period Timestart=\"%s %02d:00\" Weather=\"%d\" Temperature=\"%d\"/>\n", dmy(fdate[1]), hh, wc, curtemp
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

# ---- 6. 输出 ----
if [ -n "$QUERY_STRING" ]; then
  printf 'Content-Type: text/xml; charset=utf-8\r\n\r\n'
fi
printf '%s' "$XML"
