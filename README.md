*最后更新：2026-10-17*

# 🚀 Xray 一键安装脚本

> 基于 **Xray + Caddy** 的多协议一键部署脚本。交互式菜单选择协议，脚本自动完成依赖、防火墙、BBR、证书、systemd 服务与节点链接/二维码输出，开箱即用。

## 📜 更新日志

- 2026/05/01：新增域名检测、信息查询功能；增加二维码展示功能。
- 2026/05/05：修复 Trojan 协议的二维码；修复 caddy 检查安装。增加 VLESS-REALITY-xhttp 协议。
- 2026/05/08：增加各种验证、排错，去掉 apt lock 暴力解决，修改安全性配置；增加安装过程中可能出现的错误提示。
- 2026/05/10：增加 BBR 安装菜单，增加防火墙智能策略，修复可能出现的错误提示，优化代码。
- 2026/05/15：合并协议 1、协议 2 的函数，修复 `check_current_protocol` 函数，优化代码。
- 2026/05/19：全面重构主菜单逻辑，将显示状态、菜单布局与交互处理拆分为独立函数。
- 2026/05/20：增强用户输入校验，杜绝非法输入；优化系统环境信息的展示逻辑。
- 2026/06/09：修复部分 bug，升级 caddy 安装版本号到最新版。
- 2026/06/22：添加 Xray 核心升级功能。
- 2026/09/25：优化 vnstat 流量统计功能，自动检测出口网卡并写入配置。
- 2026/10/17：安装阶段自动检测出口网卡并写进 `vnstat.conf` 的 `Interface` 项（兼容 `#` / `;` 注释行，配置文件缺失则自动生成），同时清理系统里已不存在的网卡统计，只监控真实网卡。

---

## 🖥️ 支持系统

| 项目 | 要求 |
| :--- | :--- |
| 系统 | Debian 12 / 13、Ubuntu 25 / 26 |
| 架构 | `x86_64`、`aarch64`、`armv8l`（→ arm64）、`armv7l`（→ arm32-v7a）；其他架构脚本直接退出 |
| 权限 | 必须 root 运行（非 root 直接报错退出） |
| 网络 | 需能访问 GitHub、Cloudsmith（Caddy 源）与 Xray 官方安装脚本 |
| 端口 | 80/tcp、443/tcp、443/udp 必须可用（脚本会自动放行，申请证书需要 80/443） |

---

## ⚠️ 安装前准备

### 1️⃣ VPS 服务器

- 一台带公网 IPv4 或 IPv6 的服务器。
- 推荐 Vultr，可以随时换 VPS 换 IP，按时计费。
  - vultr：(https://www.vultr.com/?ref=6999923)
  - racknerd：(https://my.racknerd.com/aff.php?aff=19920)
  - Evoxt：(https://console.evoxt.com/aff.php?aff=4352)

### 2️⃣ 域名（可选）

- 只有 **REALITY 系列（菜单 1、2）不需要域名**，其余 7 种协议都需要一个已解析到本机的域名。
- 配置 A（或 AAAA）记录指向服务器 IP，脚本会 `dig` 校验解析结果是否等于本机 IP。
- 已接入 CDN（如 Cloudflare）的域名，可在校验失败时选择「2. 强制跳过」。

📌 若只装 REALITY，整台机器不需要任何域名。

---

## 📥 一键安装

没有 wget / curl 先装：

```bash
apt update && apt install wget curl -y
```

然后执行：

```bash
wget -N https://raw.githubusercontent.com/linuxhobby/xray-v2ray-install/main/install.sh && chmod +x install.sh && ./install.sh
```

---

## 🎛️ 主菜单

```
【1】 安装 VLESS-REALITY-Vision      【推荐，最强隐蔽/不依赖域名】
【2】 安装 VLESS-REALITY-xhttp       【最新黑科技/综合最强】
【3】 安装 VLESS-WS-TLS              【CDN兼容/标准WebSocket】
【4】 安装 VLESS-gRPC-TLS            【低延迟/多路复用】
【5】 安装 VLESS-XHTTP-TLS           【流式传输/防指纹】
【6】 安装 Trojan-WS-TLS             【仿HTTPS/老牌稳定】
【7】 安装 Trojan-gRPC-TLS           【高效转发/适合游戏】
【8】 安装 VMess-WS-TLS              【广泛兼容/传统方案】
【9】 安装 VMess-gRPC-TLS            【兼容gRPC新特性】
-----------------------------------------------------------
【c】 查看当前协议信息与链接
【v】 查看流量统计 (vnstat)
【b】 管理网络加速 (BBR)
【d】 卸载与清理
【q】 退出脚本
```

选择 1 ~ 9 后会先跑一遍「环境准备」（装依赖、防火墙、BBR、vnstat、Xray、systemd 服务），再生成对应协议配置。

---

## 📖 协议矩阵

| 菜单 | 协议 | 传输 | 需要域名 | Xray 监听 | 对外端口 | 特点 |
| :-- | :--- | :--- | :--: | :--- | :--: | :--- |
| 1 | VLESS-REALITY-Vision | tcp | ❌ | `0.0.0.0:443` | 443 | 最强隐蔽/极致性能：无需域名证书，借用大站身份消除 TLS 指纹，Vision 流控消除内层 TLS 特征，直连延迟极低 |
| 2 | VLESS-REALITY-xHTTP | xhttp | ❌ | `0.0.0.0:443` | 443 | 继承 REALITY 借壳特性，改用 XHTTP 模拟标准 Web 交互，主动探测防御更强 |
| 3 | VLESS-WS-TLS | ws | ✅ | `127.0.0.1:10001` | 443（Caddy） | CDN 兼容/高通用性，可接入 Cloudflare 隐藏真实 IP |
| 4 | VLESS-gRPC-TLS | grpc | ✅ | `127.0.0.1:10002` | 443（Caddy） | 长连接多路复用，高丢包网络更稳，握手快 |
| 5 | VLESS-XHTTP-TLS | xhttp | ✅ | `127.0.0.1:10003` | 443（Caddy） | 模拟浏览器 HTTP 行为，封装更轻量，防指纹更现代 |
| 6 | Trojan-WS-TLS | ws | ✅ | `127.0.0.1:10004` | 443（Caddy） | 完全伪装成 HTTPS 网站访问，结构简单，老设备兼容性好 |
| 7 | Trojan-gRPC-TLS | grpc | ✅ | `127.0.0.1:10005` | 443（Caddy） | Trojan 简洁 + gRPC 高性能，高频小包（游戏）表现出色 |
| 8 | VMess-WS-TLS | ws | ✅ | `127.0.0.1:10006` | 443（Caddy） | 最经典抗封锁方案，客户端支持度最广，适合保底节点 |
| 9 | VMess-gRPC-TLS | grpc | ✅ | `127.0.0.1:10007` | 443（Caddy） | 传统 VMess 注入 gRPC 优势，兼顾成熟度与灵活性 |

- 非 REALITY 协议均由 **Caddy 在 443 端口反代**本机高位端口，Xray 只监听 `127.0.0.1`，外网只暴露 Caddy。
- 端口为**固定值**（10001 ~ 10007），脚本不做随机端口；安装前会检测端口占用。
- 选择 REALITY（1、2）时，脚本会 **停止并禁用 Caddy**，把 443 交给 Xray 直接监听。

---

## ✨ 功能特性

✔ 交互式菜单，9 种协议一键部署，无需懂 Linux  
✔ REALITY 系列免域名，`dest` 从 `cloudflare / amazon / adobe / oracle / ibm / cisco` 随机取，密钥用 `xray x25519` 现场生成  
✔ 其余协议由 Caddy 自动申请并续期 TLS 证书（`FIX_VER=1` 时会 `apt-mark hold` 锁定 Caddy 版本）  
✔ 域名解析自动校验（A/AAAA 与本机 IP 比对），CDN 场景可强制跳过  
✔ 自动生成节点分享链接，并用 `qrencode` 在终端直接打印二维码  
✔ 自动配置防火墙：ufw 放行 SSH（limit）、80/tcp、443/tcp、443/udp（firewalld 系统自动走 firewalld 分支）  
✔ 自动开启 BBR（内核 ≥ 6.4 走 BBRv3），并提供 BBR 管理子菜单  
✔ 集成 vnstat 流量统计，**安装时自动把真实出口网卡写进 `/etc/vnstat.conf` 的 `Interface` 项**  
✔ 重复安装新协议会覆盖原有协议配置，一台机一次只跑一种  
✔ Xray 以 `xray` 系统用户运行，systemd 单元带 `CapabilityBoundingSet`、`NoNewPrivileges`、`ProtectSystem=full` 等加固项  

---

## 📂 关键路径

| 用途 | 路径 |
| :--- | :--- |
| Xray 配置 | `/usr/local/etc/xray/config.json` |
| REALITY 公钥 | `/usr/local/etc/xray/pub.key` |
| Xray 二进制 | `/usr/local/bin/xray`（软链 `/usr/bin/xray`） |
| Xray systemd 服务 | `/etc/systemd/system/xray.service` |
| Caddy 配置 | `/etc/caddy/Caddyfile` |
| vnstat 配置 | `/etc/vnstat.conf`（改动前自动备份为 `.bak`） |
| 内置版本 | Xray `26.3.27`、Caddy `2.11.4`（脚本顶部变量，可自行修改） |

> 节点信息（链接、二维码）只在终端打印，**不写入文件**，请自行保存。

---

## 📊 流量统计（菜单 v）

脚本在安装阶段就会把 vnstat 配好，无需手动改配置：

1. 自动探测出口网卡：默认路由网卡 → `ip -4 route default` → 首个 up 的非 lo 网卡 → `/sys/class/net`。
2. 把网卡名写入 `/etc/vnstat.conf` 的 `Interface` 项，兼容 `Interface "eth0"`、`Interface ""`、`;Interface ""`、`#Interface` 四种写法；配置文件缺失时自动生成。
3. 同时写入 `AlwaysAddNewInterfaces 0`、`RescanDatabaseOnSave 0`，避免 docker0 等虚拟网卡被自动纳入统计。
4. 清掉数据库里系统已不存在的网卡统计（例如默认的 `eth0` 幽灵条目）。
5. `vnstat --add -i <网卡>` 建库后重启服务（vnstat 1.x 自动回退为 `-u`）。

菜单 `v` 会先校正一次配置，再按该网卡输出日/月流量报表（`vnstat -d -i` / `vnstat -m -i`）。

---

## 🚀 网络加速（菜单 b）

| 子项 | 说明 |
| :-- | :--- |
| 1 | 开启 BBR 原版 v1（内核 ≥ 6.4 时自动以 BBRv3 运行） |
| 2 | 开启 BBRv3（需内核 ≥ 6.4） |
| 3 | 开启 BBRplus（需更换内核，有风险，会下载第三方 `tcp.sh`，需二次确认） |
| 4 | 关闭 BBR（恢复 `fq_codel` + `cubic`） |
| q | 返回主菜单 |

安装流程默认会开启 BBR（已是 bbr 则跳过），写入 `net.core.default_qdisc` 与 `net.ipv4.tcp_congestion_control` 到 `/etc/sysctl.conf`。

---

## ❌ 卸载

运行脚本，选择 **【d】** 并输入 `y` 确认，会执行：

- 停止并禁用 `xray`、`caddy`；调用 Xray 官方脚本 `remove --purge`
- `apt-get purge caddy`，删除 `/etc/caddy`、`/var/log/caddy` 等
- 删除 `/usr/local/bin/xray`、`/usr/local/etc/xray`、`/usr/local/share/xray`、`/var/log/xray`、xray 的 systemd 单元、Caddy apt 源与密钥
- `userdel -r xray` 并 `daemon-reload`

⚠️ 卸载**不会**清理：防火墙已放行规则、`/usr/bin/xray` 软链残留、vnstat 及其数据、`/tmp/domain`。如需彻底干净请手动处理。

---

## 🧩 常见问题

**Q：REALITY 需要域名和证书吗？**  
不需要。REALITY 借用大站身份，脚本会停掉 Caddy 让 Xray 直接占用 443。

**Q：能同时装多个协议吗？**  
不能。每次选择都会覆盖 `/usr/local/etc/xray/config.json` 与 `/etc/caddy/Caddyfile`，一台机器当前只有一种协议。

**Q：怎么升级 Xray 核心？**  
菜单里没有升级项。修改脚本顶部的 `XRAY_VERSION` 后重跑安装，或先卸载再装。

**Q：Caddy 会做伪装网站吗？**  
不会。Caddyfile 只有反向代理，没有 `file_server` 伪装站点。

**Q：装 REALITY 后还能用 Caddy 吗？**  
REALITY 会被 `systemctl stop/disable caddy`；改回 WS/gRPC/XHTTP 类协议时脚本会重新启用。

**Q：域名解析没生效能装吗？**  
3 ~ 9 号协议会校验解析，不匹配会要求重输；已上 CDN 的可选「2. 强制跳过」，但证书申请仍需 80/443 可达。

---

## 🖼️ 脚本界面展示

<img width="667" height="703" alt="image" src="https://github.com/user-attachments/assets/a1ce1dfe-0663-4a10-98eb-0ac9920f5a4b" />

## 🖼️ 安装成功后信息展示

<img width="667" height="703" alt="image" src="https://github.com/user-attachments/assets/76e7d2d0-fc81-4ca0-b99f-babd9fe09400" />

---

## ⚖️ 免责声明

仅供学习研究。

---

## 📢 BUG 反馈

如果你发现任何问题，欢迎提交：
👉 [反馈BUG](https://github.com/linuxhobby/xray-v2ray-install/issues/1)

---

## ✍️ 作者

人生若只如初见
