# HTC Weather Revive

> 让 HTC 原生天气 App 在 AccuWeather 中国区停服后继续工作。
> Revive the stock HTC Weather app after AccuWeather China shut down — a systemless Magisk module with a local weather proxy.

[![Magisk](https://img.shields.io/badge/Magisk-systemless-brightgreen)](https://github.com/topjohnwu/Magisk)
[![Version](https://img.shields.io/badge/version-v2.0-blue)](../../releases)
[![License](https://img.shields.io/badge/license-Personal%20use-lightgrey)](LICENSE)

---

## 为什么需要它 / Why

HTC Sense 自带的天气 App 依赖 AccuWeather 接口，中国区服务停止后，天气卡片、桌面小部件和自动同步全部失效。本模块把这些请求劫持到手机本地的模拟服务器，用国内可访问的天气数据源重新喂给原生 App，不需要替换成第三方天气应用。

The stock HTC Weather app hard-codes AccuWeather endpoints. After the China service was retired, the app, widgets and auto-sync all broke. This module redirects those requests to a local emulator on the device and serves them from a domestic weather source — keeping the original HTC UI alive.

## 特性 / Features

- **Systemless**：通过 Magisk 覆盖 `/system/etc/hosts` 与系统应用 APK，不改动 `/system` 分区本身，可随时停用恢复。
- **本地代理**：开机自动在 `127.0.0.1:8080` 启动 AccuWeather 接口模拟（`/cc`、`/d10`、`/h12`、`/loc`、`/geo`、`/tz`、`/cgi-bin/*`），在 `:80` 兼容老 HTC 中国区天气接口。
- **数据源**：腾讯 sojson 天气 (`t.weather.sojson.com`)，15 分钟缓存 + 过期兜底，断网时回退最近一次缓存。
- **在线搜索可用**：修复了城市在线搜索、城市名重复（"深圳市深圳市"）等问题。
- **跨机型开关**：不兼容的机型可关闭 APK 补丁层，只保留通用框架（hosts + 本地代理），避免系统应用崩溃。

## 工作原理 / How it works

```
天气 App / HtcServicePack
        │  HTTPS 请求（补丁 APK 改写为本地 HTTP）
        ▼
systemless hosts:  api.accuweather.com → 127.0.0.1
                   htc-mobile.mywtv.cn / 3g.mywtv.cn → 127.0.0.1
        ▼
本地代理 :8080 (busybox nc + accu_server.sh)
        ▼
sojson 天气 API  ──15min 缓存──▶  /data/local/tmp/htcweather/c_<cityid>.json
        ▼
AccuWeather 风格的 JSON  ──▶  原生 App 正常解析显示
```

## 适用机型 / Compatibility

| 项目 | 状态 |
|---|---|
| HTC M8St / Sense 7 / Android 6.0 / armv7a | ✅ 已验证（Magisk 21.4） |
| 其他 HTC 机型 | ⚠️ 框架（hosts + 本地代理）通用；补丁 APK 与系统版本强绑定，跨机型有崩溃风险，见下方开关 |
| Android 版本 | 建议 6.0+，需 root + Magisk |
| 架构 | 模块附带 `armeabi-v7a` busybox |

## 安装 / Installation

1. 手机已 root 并装好 Magisk；先在 Magisk 里卸载旧版 `weatherfix` 并重启。
2. Magisk → 模块 → 从本地安装 → 选择 `weatherfix_v2_systemless.zip`。
3. 重启。开机约 1 分钟后天气 App 会自动同步一次。
4. 打开天气 App：添加城市、在线搜索都应恢复正常。

详细安装说明见 [docs/INSTALL.md](docs/INSTALL.md)。

## 跨机型 / 关闭 APK 补丁层

补丁 APK 只针对已验证的 M8St / Sense 7 / Android 6.0 系统。其他机型若刷入后系统应用崩溃，可在**刷入前**执行：

```sh
adb shell "su -c 'touch /data/local/tmp/weatherfix-noapk'"
```

然后正常刷入模块。`customize.sh` 检测到该文件会跳过 APK 覆盖，只安装 systemless hosts + 本地代理框架。

> 注意：关闭 APK 补丁后，如果目标机型的 App 仍走 HTTPS 到真实 AccuWeather（443 端口无服务），天气数据可能无法加载。此时需要为该机型单独制作补丁 APK，框架部分无需改动。

## 卸载 / Uninstall

Magisk → 模块 → 停用/删除 `weatherfix` → 重启。卸载脚本会停止本地服务并清理 `/data/local/tmp/htcweather`。

## 日志排查 / Troubleshooting

| 文件 | 内容 |
|---|---|
| `/data/local/tmp/htcweather/boot.log` | 开机部署与端口启动日志 |
| `/data/local/tmp/htcweather/accu.log` / `req.log` | 请求记录 |
| `/data/local/tmp/htcweather/accu_debug.log` | 代理详细调试日志 |
| `/data/local/tmp/htcweather/ncserver.log` | nc 监听循环日志 |

`netstat -tln | grep -E ':(80|8080)'` 可确认两个端口是否在监听。

## 从源码构建 / Build from source

仓库 `module/` 目录就是 Magisk 模块的完整源码树。在仓库根目录运行：

```sh
python tools/repack.py
```

> **重要**：不要直接用 `zip -r` 打包。Magisk 刷入包**必须**在 zip 根目录带有
> `META-INF/com/google/android/update-binary` 和 `updater-script`，否则 Magisk 会报
> "This zip is not a Magisk module!"。同时必须用 STORED 压缩 + 正常时间戳 + DOS 属性，
> 老版 Magisk（21.x）才能正确识别。`tools/repack.py` 已处理这些细节。

补丁 APK 的制作涉及反编译 / smali 重建，参见项目历史提交讨论。

## 已知限制 / Known limitations

- GPS「当前位置」卡片在某些机型上仍可能显示感叹号（定位服务与天气数据槽的关联属于 App 自身逻辑，本版本未处理）。
- 数据源依赖 `t.weather.sojson.com`；服务不可用时回退到 15 分钟内的缓存，超过缓存时长则无数据。
- 补丁 APK 版权归 HTC / AccuWeather 所有，本项目仅提供个人研究与修复用途，请勿用于商业分发。

## 致谢 / Credits

由 HADES (AWXUAN2072) 逆向与实现。数据源感谢 sojson 天气。
