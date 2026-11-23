#!/system/bin/sh
# AccuWeather 模拟服务器 (busybox inetd, 端口 8080)
# 路由:
#   /cgi-bin/getData     -> handler.sh (HTC 中国XML, 兼容旧 P 规则)
#   /cc/.../KEY          -> currentconditions JSON
#   /d10/.../KEY         -> daily 10day JSON
#   /h12/.../KEY         -> hourly 12hour JSON
#   /loc/.../KEY         -> location info JSON
#   /geo/...             -> geoposition search (q=lat,lon)
#   /tz/...              -> timezone
DBG=/data/local/tmp/htcweather/accu_debug.log
echo "=== START pid=$$ date=$(date)" >> $DBG
BB=/data/local/tmp/htcweather/b2/busybox
BASE=/data/local/tmp/htcweather
PDIR=/data/adb/weatherfix_data
mkdir -p "$PDIR" 2>/dev/null
CR=$(printf '\r')
export TZ=CST-8

# ---- 读 HTTP 请求头 ----
read -r REQ
REQ=${REQ%$CR}
while read -r H; do
  H=${H%$CR}
  [ -z "$H" ] && break
done

echo "REQ=[${REQ%%$CR}]" >> $DBG
REST=${REQ#* }
P=${REST%%\?*}
QS=""
case "$REST" in *\?*) QS=${REST#*\?};; esac
QS=${QS%% *}

echo "STEP1 routes P=[$P]" >> $DBG
# ---- 路由: getData ----
if [ "$P" = "/cgi-bin/getData" ]; then
  printf 'HTTP/1.0 200 OK\r\n'
  QUERY_STRING="$QS" sh $BASE/handler.sh
  exit 0
fi

if [ "$P" = "/cgi-bin/search" ]; then
  printf 'HTTP/1.0 200 OK\r\n'
  QUERY_STRING="$QS" sh $BASE/wwwcgi/cgi-bin/search
  exit 0
fi
if [ "$P" = "/cgi-bin/jump" ]; then
  QUERY_STRING="$QS" sh $BASE/wwwcgi/cgi-bin/jump
  exit 0
fi

# ---- 取 KEY ----
KEY=""
case "$P" in
  /cc/*|/d10/*|/h12/*|/loc/*) KEY=${P##*/};;
esac

# ---- KEY -> 城市 (accu_alias.txt: accucode;htccode;cityid;wpname;cname;lon;lat) ----
echo "STEP2 key=[$KEY] row=[$ROW]" >> $DBG
ROW=""
HTCCODE=""
if [ -n "$KEY" ]; then
  K2=${KEY#\*}
  ROW=$($BB grep -m1 -F "$K2;" $BASE/accu_alias.txt | $BB sed 's/\r$//')
  [ -z "$ROW" ] && ROW=$($BB grep -m1 -F ";$K2;" $BASE/accu_alias.txt | $BB sed 's/\r$//')
fi

# ---- geoposition: q=lat,lon 最近邻 ----
if [ -z "$ROW" ] && [ "${P#/geo/}" != "$P" ]; then
  QLAT=$(echo "$QS" | $BB sed -n 's/.*q=\(-\{0,1\}[0-9.]*\),.*/\1/p')
  QLON=$(echo "$QS" | $BB sed -n 's/.*q=-\{0,1\}[0-9.]*,\(-\{0,1\}[0-9.]*\).*/\1/p')
  ROW=$($BB awk -F';' -v la="$QLAT" -v lo="$QLON" 'function dd(a,b,c,e, x,y){x=(a-c)*111;y=(b-e)*95;if(x<0)x=-x;if(y<0)y=-y;return x*x+y*y} NR>1 {v=dd($7,$6,la,lo); if(m==""||v<m){m=v;best=$0}} END{print best}' $BASE/accu_alias.txt)
fi

echo "STEP3 row=[$ROW]" >> $DBG
CID="101010100"; CNAME="北京"; CLON="116.41"; CLAT="39.90"; HTCCODE="01010101"; ACCUCODE="ASI|CN|CH002|BEIJING"
if [ -n "$ROW" ]; then
  CID=$(echo "$ROW" | $BB cut -d';' -f3)
  CNAME=$(echo "$ROW" | $BB cut -d';' -f5)
  CLON=$(echo "$ROW" | $BB cut -d';' -f6)
  CLAT=$(echo "$ROW" | $BB cut -d';' -f7)
  HTCCODE=$(echo "$ROW" | $BB cut -d';' -f2)
  ACCUCODE=$(echo "$ROW" | $BB cut -d';' -f1)
  # geo 需要 legacy code (ASI|CN|...) 供定位服务查 CityCodeTransferTable; 若首列是数字码则从同一城市的 legacy 行取
  case "$ACCUCODE" in *'|'*) ;; *) ACCUCODE=$($BB grep -m1 -F ";$HTCCODE;$CID;" $BASE/accu_alias.txt | $BB cut -d';' -f1);; esac
  case "$ACCUCODE" in *'|'*) ;; *) ACCUCODE="ASI|CN|CH006|GUANGZHOU";; esac
fi

# ---- 取数据: NMC 中央气象台 (sojson已失效403), 转成 sojson 兼容结构供下方解析 ----
NMC_IP=106.120.82.180
NCODE=$($BB grep -m1 "^$CID|" $BASE/nmc_stations.txt 2>/dev/null | $BB cut -d'|' -f2 | $BB tr -d '\r')
nmc_to_sojson(){
  [ -z "$NCODE" ] && return 1
  local req="GET /rest/weather?stationid=$NCODE HTTP/1.1\r\nHost: www.nmc.cn\r\nUser-Agent: Mozilla/5.0\r\nConnection: close\r\n\r\n"
  local out
  out=$(printf "$req" | $BB timeout 10 $BB nc "$NMC_IP" 80 2>/dev/null)
  echo "$out" | $BB grep -q '"msg":"success"' || return 1
  local BODY TD TI TT TEMP HUM DIR
  BODY=$(echo "$out" | $BB grep -m1 '^{')
  TEMP=$(echo "$BODY" | $BB grep -o '"temperature":[0-9][0-9.]*' | $BB head -1 | $BB cut -d: -f2)
  HUM=$(echo "$BODY" | $BB grep -o '"humidity":[0-9][0-9.]*' | $BB head -1 | $BB cut -d: -f2)
  DIR=$(echo "$BODY" | $BB grep -o '"direct":"[^"]*"' | $BB head -1 | $BB cut -d'"' -f4)
  [ -z "$TEMP" ] && return 1
  TD=$BASE/.nmc_d_$$; TI=$BASE/.nmc_i_$$; TT=$BASE/.nmc_t_$$
  echo "$BODY" | $BB grep -o '"date":"20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]"' | $BB cut -d'"' -f4 > $TD
  echo "$BODY" | $BB grep -o '"info":"[^"]*"' | $BB cut -d'"' -f4 | $BB tail -n +2 > $TI
  echo "$BODY" | $BB grep -o '"temperature":"[^"]*"' | $BB cut -d'"' -f4 > $TT
  $BB awk -v temp="$TEMP" -v hum="$HUM" -v dir="$DIR" '
    function okv(v){return v!=""&&v!="9999"&&v!="-"}
    function nv(v,x){x=v;gsub(/[^0-9.-]/,"",x);return x+0}
    FILENAME~/\.nmc_d_/{D[FNR]=$0;nd=FNR;next}
    FILENAME~/\.nmc_i_/{I[FNR]=$0;next}
    {T[FNR]=$0}
    END{
      printf "{\"status\":200,\"data\":{\"wendu\":%s,\"shidu\":%s,\"forecast\":[", nv(temp),nv(hum)
      for(k=1;k<=nd;k++){
        di=I[2*k-1]; ni=I[2*k]; dt=T[2*k-1]; nt=T[2*k]
        hi=(okv(dt)?nv(dt):(okv(nt)?nv(nt):nv(temp)))
        lo=(okv(nt)?nv(nt):(okv(dt)?nv(dt):nv(temp)))
        ty=(okv(di)?di:(okv(ni)?ni:"晴"))
        if(k==1){hi=nv(temp);lo=nv(temp)}
        if(k>1)printf ","
        printf "{\"date\":\"%s\",\"high\":\"高温 %s℃\",\"low\":\"低温 %s℃\",\"ymd\":\"%s\",\"fx\":\"%s\",\"fl\":\"1级\",\"type\":\"%s\"}", substr(D[k],9,2),hi,lo,D[k],dir,ty
      }
      printf "]}}"
    }' $TD $TI $TT
  $BB rm -f $TD $TI $TT 2>/dev/null
  return 0
}

CACHE=$PDIR/sj_$CID.json
RAW=""
if [ -f "$CACHE" ] && [ -n "$($BB find $CACHE -mmin -15 2>/dev/null)" ]; then
  RAW=$(cat $CACHE)
else
  echo "STEP4 fetching NMC ncode=$NCODE" >> $DBG
  RAW=$(nmc_to_sojson)
  [ -n "$RAW" ] && printf '%s' "$RAW" > $CACHE
  # fallback: sojson 旧IP(多已失效) + 旧缓存
  if [ -z "$RAW" ]; then
    RAW=$($BB timeout 6 $BB wget -q -O - -T 6 "http://115.231.101.162/api/weather/city/$CID" 2>/dev/null)
    [ -n "$RAW" ] && printf '%s' "$RAW" > $CACHE
  fi
  [ -z "$RAW" ] && [ -f "$CACHE" ] && RAW=$(cat $CACHE)
fi

echo "STEP5 fetched raw_len=$($BB echo -n "$RAW" | wc -c)" >> $DBG
echo "$($BB date "+%H:%M:%S") ep=${P%%\?*} key=$KEY cid=$CID raw=$($BB echo -n "$RAW" | wc -c)" >> $BASE/accu.log

# ---- 无数据 -> 404 ----
if [ -z "$RAW" ]; then
  printf 'HTTP/1.0 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n'
  exit 0
fi

NOWH=$($BB date +%H)
NOWHM=$($BB date +%H:%M)

printf 'HTTP/1.0 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n'
echo "$RAW" | $BB sed 's/},{/}\n{/g; s/,"/,\n"/g' | $BB awk -F':' -v ep="$P" -v key="$KEY" -v hcode="$HTCCODE" -v accucode="$ACCUCODE" -v cname="$CNAME" -v cid="$CID" -v clon="$CLON" -v clat="$CLAT" -v nh="$NOWH" -v nowhm="$NOWHM" '
  function trim(s){ gsub(/,$/,"",s); gsub(/^[ \t"]+|[ \t"]+$/,"",s); return s }
  function num(s,  t){ t=trim(s); gsub(/[^0-9.\-]/,"",t); if(t==""||t=="-")t="0"; return t+0 }
  function mainpart(t,  a){ split(t,a,"转"); return a[1] }
  function c2f(c){ return c*9/5+32 }
  function round(x){ return x<0?int(x-0.5):int(x+0.5) }
  function ampm(hh,mm,  h12){ h12=hh%12; if(h12==0)h12=12; return h12":"mm" "(hh<12?"AM":"PM") }
  function wfl2(s,  a){ split(s,a,"[^0-9]"); return a[1]+0 }
  function wcode(t){
    t=mainpart(t)
    if(t~/雷/)return 4; if(t~/冰雹/)return 5; if(t~/雨夹雪/)return 6
    if(t~/冻雨/)return 6; if(t~/暴雨/)return 10; if(t~/大雨/)return 9
    if(t~/中雨/)return 8; if(t~/阵雨/)return 3; if(t~/雨/)return 7
    if(t~/暴雪|大雪/)return 17; if(t~/中雪/)return 16; if(t~/阵雪/)return 15
    if(t~/雪/)return 13; if(t~/雾/)return 18; if(t~/霾|沙|尘/)return 18
    if(t~/多云/)return 1; if(t~/阴/)return 2; if(t~/晴/)return 0
    return 0 }
  function wdir(d2){
    d2=mainpart(d2)
    if(d2~/西北/)return "NW"; if(d2~/东北/)return "NE"
    if(d2~/西南/)return "SW"; if(d2~/东南/)return "SE"
    if(d2~/北/)return "N"; if(d2~/南/)return "S"
    if(d2~/东/)return "E"; if(d2~/西/)return "W"
    return "N" }
  function iconDay(i,  a){ split("1 6 8 12 15 51 29 14 13 18 17 16 15 21 21 20 19 22 11 26 52 13 18 17 16 15 20 19 22 53 52 52 32 54 19 11 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 5",a," "); return a[i+1] }
  function iconNight(i,  a){ split("33 38 8 12 15 51 29 39 40 18 41 42 15 43 43 43 19 22 11 26 52 40 18 41 42 15 43 19 22 53 52 52 32 54 19 11 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 37",a," "); return a[i+1] }
  function hourIcon(h,c){ return (h<=6||h>=18)?iconNight(c):iconDay(c) }
  BEGIN{ fn=0; split("0 .03 .06 .09 .12 .16 .22 .30 .38 .46 .55 .63 .72 .80 .88 .95 1 .96 .9 .82 .72 .62 .52 .42 .32",SH," ") }
  {
    line=$0
    if(line ~ /"wendu"/){ curtemp=num(substr(line,index(line,":")+1)) }
    if(line ~ /"shidu"/){ curhum=num(substr(line,index(line,":")+1)) }
    if(line ~ /"ymd"/){ fn++; fdate[fn]=trim(substr(line,index(line,":")+1)) }
    if(line ~ /"high"/){ fhigh[fn]=num(substr(line,index(line,":")+1)) }
    if(line ~ /"low"/){ flow[fn]=num(substr(line,index(line,":")+1)) }
    if(line ~ /"sunrise"/){ frise[fn]=trim(substr(line,index(line,":")+1)) }
    if(line ~ /"sunset"/){ fset[fn]=trim(substr(line,index(line,":")+1)) }
    if(line ~ /"fx"/){ ffx[fn]=trim(substr(line,index(line,":")+1)) }
    if(line ~ /"fl"/){ ffl[fn]=trim(substr(line,index(line,":")+1)) }
    if(line ~ /"type"/){ ftype[fn]=trim(substr(line,index(line,":")+1)) }
  }
  END{
    if(fn==0){ print "[]"; exit }
    MOBILE="http://www.weather.com.cn/weather/" cid ".shtml"
    if(ep ~ /^\/cc\//){
      cc=wcode(ftype[1])
      printf "[{\"LocalObservationDateTime\":\"%sT%s:00GMT+08:00\",", fdate[1], nowhm
      printf "\"MobileLink\":\"%s\",", MOBILE
      printf "\"WeatherIcon\":\"%s\",", iconDay(cc)
      printf "\"Temperature\":{\"Metric\":{\"Value\":%d,\"Unit\":\"C\"},\"Imperial\":{\"Value\":%d,\"Unit\":\"F\"}},", round(curtemp), round(c2f(curtemp))
      printf "\"RealFeelTemperature\":{\"Metric\":{\"Value\":%d,\"Unit\":\"C\"},\"Imperial\":{\"Value\":%d,\"Unit\":\"F\"}},", round(curtemp-2), round(c2f(curtemp-2))
      printf "\"RelativeHumidity\":%d,", curhum
      printf "\"Wind\":{\"Speed\":{\"Imperial\":{\"Value\":%.1f,\"Unit\":\"mi/h\"},\"Metric\":{\"Value\":%.1f,\"Unit\":\"km/h\"}},\"Direction\":{\"English\":\"%s\"}},", wfl2(ffl[1])*6, wfl2(ffl[1])*10, wdir(ffx[1])
      printf "\"Visibility\":{\"Imperial\":{\"Value\":10,\"Unit\":\"mi\"}},"
      printf "\"IsDayTime\":true,\"EpochTime\":0}]"
    }
    else if(ep ~ /^\/h12\//){
      printf "["
      cc=wcode(ftype[1]); hi=fhigh[1]; lo=flow[1]
      for(i=1;i<=12;i++){
        hh=(nh+i)%24
        wt=lo+(hi-lo)*SH[hh+1]
        printf "%s{\"DateTime\":\"%sT%02d:00:00+0800\",\"EpochDateTime\":0,\"WeatherIcon\":%d,\"Temperature\":{\"Value\":%d,\"Unit\":\"C\"},\"PrecipitationProbability\":0,\"MobileLink\":\"%s\"}", (i>1?",":""), fdate[1], hh, hourIcon(hh,cc), round(wt), MOBILE
      }
      printf "]"
    }
    else if(ep ~ /^\/d10\//){
      printf "{\"DailyForecasts\":["
      nd=(fn>10?10:fn)
      for(i=1;i<=10;i++){
        j=(i<=nd?i:nd)
        dc=wcode(ftype[j]); hi=fhigh[j]; lo=flow[j]
        split(frise[j],sr,":"); split(fset[j],ss,":")
        printf "%s{\"Date\":\"%sT07:00:00+0800\",\"Sun\":{\"Rise\":\"%s\",\"Set\":\"%s\"},", (i>1?",":""), fdate[j], ampm(sr[1]+0,sr[2]+0), ampm(ss[1]+0,ss[2]+0)
        printf "\"Day\":{\"Icon\":%d,\"PrecipitationProbability\":0},\"Night\":{\"Icon\":%d,\"PrecipitationProbability\":0},", iconDay(dc), iconNight(dc)
        printf "\"Temperature\":{\"Maximum\":{\"Value\":%d,\"Unit\":\"F\"},\"Minimum\":{\"Value\":%d,\"Unit\":\"F\"}},", round(c2f(hi)), round(c2f(lo))
        printf "\"RealFeelTemperature\":{\"Maximum\":{\"Value\":%d,\"Unit\":\"F\"},\"Minimum\":{\"Value\":%d,\"Unit\":\"F\"}},", round(c2f(hi-2)), round(c2f(lo-1))
        printf "\"MobileLink\":\"%s\"}", MOBILE
      }
      printf "]}"
    }
    else if(ep ~ /^\/loc\// || ep ~ /^\/geo\//){
      rkey=(ep ~ /^\/geo\// ? accucode : (key==""?hcode:key))
      printf "{\"Key\":\"%s\",\"LocalizedName\":\"%s\",\"EnglishName\":\"%s\",", rkey, cname, cname
      printf "\"AdministrativeArea\":{\"LocalizedName\":\"\",\"EnglishName\":\"\"},"
      printf "\"SupplementalAdminAreas\":[{\"LocalizedName\":\"\",\"EnglishName\":\"\"}],"
      printf "\"Country\":{\"LocalizedName\":\"中国\",\"EnglishName\":\"China\",\"ID\":\"CN\"},"
      printf "\"GeoPosition\":{\"Latitude\":%s,\"Longitude\":%s,\"Elevation\":0},", clat, clon
      printf "\"TimeZone\":{\"Name\":\"Asia/Shanghai\"},"
      printf "\"MobileLink\":\"%s\"}", MOBILE
    }
    else if(ep ~ /^\/tz\//){
      printf "{\"Name\":\"Asia/Shanghai\"}"
    }
    else { print "[]" }
  }
'
