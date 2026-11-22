# 安装说明 / Installation Guide

## HTC Weather Revive v2.0 (systemless)

作者: HDX

---

### 这是什么

让 HTC 原生天气 App 在 AccuWeather 中国区停服后继续工作的 Magisk 模块。采用 systemless 方式，不修改 `/system` 分区本身，可随时卸载恢复。

### 工作原理

1. **systemless hosts 覆盖** (`/system/etc/hosts`)：
   - `api.accuweather.com` / `htc-mobile.mywtv.cn` / `3g.mywtv.cn` → `127.0.0.1`
2. **开机 `service.sh`** 自动部署本地代理到 `/data/local/tmp/htcweather` 并启动：
   - `:8080` AccuWeather 接口模拟（`/cc` `/d10` `/h12` `/loc` `/geo` `/tz` `/cgi-bin/*`）
   - `:80` 老 HTC 中国天气接口代理
3. **数据来源**：腾讯 sojson 天气 (`t.weather.sojson.com`)，15 分钟缓存 + 过期兜底。
4. **两个补丁 APK** 覆盖原始 Weather / HtcServicePack，把 HTTPS 请求改到本地。

### 适用机型

- 已验证：HTC M8St / Sense 7 / Android 6.0 / armv7a（Magisk 21.4）
- 其他 HTC 机型：框架（hosts + 本地代理）通用；但补丁 APK 与系统版本强绑定，跨机型覆盖有系统应用崩溃风险。见下方「跨机型」。

### 安装步骤

1. 手机已 root + Magisk，先用 Magisk 卸载旧版 `weatherfix` 模块并重启。
2. Magisk → 模块 → 从本地安装 → 选择 `weatherfix_v2_systemless.zip`。
3. 重启。开机约 1 分钟后天气 App 会自动同步一次。
4. 打开天气 App 测试：添加城市、在线搜索都应正常。

### 跨机型 / 不兼容怎么办（关闭 APK 补丁层，只保留通用框架）

刷入前，在电脑上执行：

```sh
adb shell "su -c 'touch /data/local/tmp/weatherfix-noapk'"
```

然后正常刷入模块。`customize.sh` 检测到该文件会跳过 APK 覆盖，只安装 systemless hosts + 本地代理框架，避免补丁 APK 导致崩溃。

> 注意：关闭 APK 补丁后，若目标机型的 App 仍走 HTTPS 到真实 AccuWeather，hosts 劫持到 `127.0.0.1:443` 无服务，天气数据可能无法加载——此时需要为该机型单独制作补丁 APK，框架部分无需改动。

### 卸载

Magisk → 模块 → 停用/删除 `weatherfix` → 重启。卸载脚本会自动停止本地服务并清理 `/data/local/tmp/htcweather`。

### 日志排查

- 代理启动日志：`/data/local/tmp/htcweather/boot.log`
- 请求记录：`/data/local/tmp/htcweather/accu.log`、`req.log`
- 调试日志：`/data/local/tmp/htcweather/accu_debug.log`
- nc 监听：`/data/local/tmp/htcweather/ncserver.log`

### 已知限制

- GPS 自动定位卡片在某些机型上仍可能显示感叹号（定位服务与天气数据槽的关联问题，属于 App 自身逻辑，本版本未处理）。
- 数据源依赖 `t.weather.sojson.com`；若该服务不可用，代理会回退到 15 分钟内的缓存数据。
