<div align="center">

# Phicomm N1 · ImmortalWrt

**斐讯 N1 有线旁路由固件** · 内置 honk / doona · 自编译 6.18 内核

[![Build](https://github.com/mackolzjj/N1_ImmortalWrt/actions/workflows/armsr_armv8.yml/badge.svg)](https://github.com/mackolzjj/N1_ImmortalWrt/actions/workflows/armsr_armv8.yml)
[![Release](https://img.shields.io/github/v/release/mackolzjj/N1_ImmortalWrt?label=Release)](https://github.com/mackolzjj/N1_ImmortalWrt/releases)
![Source](https://img.shields.io/badge/ImmortalWrt-v25.12.2-orange)
![Kernel](https://img.shields.io/badge/kernel-6.18.y-blue)
![Board](https://img.shields.io/badge/board-s905d%20%2F%20aarch64-green)
![Package](https://img.shields.io/badge/pkg-apk-lightgrey)

</div>

## 这是什么

一块斐讯 N1 当**旁路由**用：拨号和 WiFi 交给主路由，这台只做 eBPF 透明代理。

- **系统**：ImmortalWrt 25.12.2（`armsr/armv8`，apk 包管理）
- **内核**：自编译 [`ophub-kernel-ftrace`](https://github.com/mackolzjj/ophub-kernel-ftrace) `6.18.y`，开 `FUNCTION_TRACER` / `DYNAMIC_FTRACE`，nfqueue / nftables 内建
- **代理**：`honk` + 内嵌 doona 面板，配 `luci-app-honk`、`v2ray-geoip` / `v2ray-geosite`
- **其他**：`podman`（含 LuCI）、Argon 主题、`luci-app-amlogic`、`autocore`
- **不含**：PPPoE（`ppp` / `kmod-ppp`）、WiFi（`wpad` / `hostapd`）、Samba

## 快速开始

从 [Releases](https://github.com/mackolzjj/N1_ImmortalWrt/releases) 下载 `immortalwrt-armsr-armv8-generic_s905d_k6.18.*_<日期>.img.gz`，解压后写入 U 盘启动：

```bash
openwrt-install-amlogic      # 需要固化到 eMMC 时执行
```

浏览器打开 `http://192.168.2.2`，账号 `root` / 密码 `password`。

> 建议**全新刷写、不保留配置**。跨源码线（官方 OpenWrt ↔ ImmortalWrt）保留配置容易残留不兼容项。

刷完先核对这几项：

```bash
grep PRETTY_NAME /etc/os-release; uname -r    # 预期 ImmortalWrt 25.12.2 / 6.18.x-ophub
ls -l /sys/kernel/btf/vmlinux                 # honk 需要 BTF，文件必须在
apk list --installed | grep -E 'honk|daeuniverse|podman'
uci show amlogic.config | grep -E 'firmware|kernel'
```

## 默认配置

| 项 | 值 |
| --- | --- |
| LAN | `eth0` 静态 `192.168.2.2/24`，网关 `192.168.2.1`，只有 `lan` 没有 `wan` |
| 面板 | LuCI，honk 在「服务」下；honk 原生 API 启动要十几秒，太早访问会以为没起来 |
| 调度 | 每日 04:00 `fstrim -a`；CPU 锁 `performance` 1.512 GHz |
| 无线 | 板载 BCM43455 固件被禁用（见下） |

## 在线更新（晶晨宝盒）

固件源和内核源都已指向本项目，**点「在线更新」不会把你刷成别的系统或官方内核**：

```
固件  mackolzjj/N1_ImmortalWrt
内核  mackolzjj/ophub-kernel-ftrace（kernel_stable，6.18 线）
```

这些值由 `/etc/uci-defaults/zz-amlogic-repo` 在首次启动时写回（打包阶段会被 ophub 的模板覆盖，所以必须在设备上补一次）。

## 常见问题

| 现象 | 说明 |
| --- | --- |
| 不能拨号 / 没有 WiFi | 设计如此，拨号和无线交给主路由 |
| 日志每秒刷 `brcmf_dump_obss error (-52)` | 板载 BCM43455 的固件与驱动不兼容。已由 `zz-disable-wifi` 把 `/lib/firmware/brcm/brcmfmac43455-sdio*.bin` 改名 `.disabled`；要恢复 WiFi 就改回原名并重启 |
| honk 起不来 | 先确认 `/sys/kernel/btf/vmlinux` 在，且没自己换过内核；eBPF / BTF 不匹配会直接退出 |
| LuCI 里没有 honk 菜单 | 确认刷的是本仓库的固件；[`N1-OpenWrt`](https://github.com/mackolzjj/N1-OpenWrt) 那条线是官方 OpenWrt 底子、不带 honk |

## 目录结构

```
.github/workflows/armsr_armv8.yml      构建、产物断言、发布与保留
armsr/armv8/diy/diy.sh                 软件源、honk 源码与 Rust 工具链
armsr/armv8/N1/.config                 内置包与内核选项
armsr/armv8/N1/files/                  预置 /etc/config、sysctl、uci-defaults、crontabs
```

推送到 `main` 会触发构建（每月 1 / 16 日也有定时构建），产物发到 Releases；只改文档不想编译时，在 commit body 写 `[skip ci]`。

## 致谢

[ImmortalWrt](https://github.com/immortalwrt/immortalwrt) · [ophub/amlogic-s9xxx-openwrt](https://github.com/ophub/amlogic-s9xxx-openwrt) · [ophub/kernel](https://github.com/ophub/kernel) · [daeuniverse/honk](https://github.com/daeuniverse/honk) · [daeuniverse/openwrt-packages](https://github.com/daeuniverse/openwrt-packages) · [luci-app-podman](https://github.com/Zerogiven-OpenWRT-Packages/luci-app-podman)
