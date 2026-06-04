*最后更新：2026-05-30*
- 2026/05/01：新增域名检测、信息查询功能；增加二维码展示功能。
- 2026/05/05：修复Trojan协议的二维码；修复caddy检查安装。增加VLESS-REALITY-xhttp协议。
- 2026/05/08：增加各种验证、排错、去掉apt lock暴力解决，修改安全性配置；增加安装过程中可能出现的错误提示；
- 2026/05/10：增加BBR安装菜单，增加防火墙智能策略，修复可能出现的错误提示，优化代码。
- 2026/05/15：合并协议1、协议2的函数，修复check_current_protocol函数，优化代码。
- 2026/05/19：全面重构主菜单逻辑，将显示状态、菜单布局与交互处理拆分为独立函数；
- 2026/05/20：增强用户输入校验，杜绝了非法输入；优化系统环境信息的展示逻辑，确保在不同系统版本下均能稳定运行。
- 2026/05/31：修复部分bug。
## 📖 项目介绍
# 🚀 Xray 一键安装脚本
> 基于 **Xray + Caddy** 的多协议一键部署脚本，快速部署 Xray 服务端，集成 Caddy 自动配置 TLS，支持 Reality / WS / gRPC / XHTTP / Trojan / VMess 等多种主流协议，开箱即用。
## ⚠️ 安装前准备

### 1️⃣ VPS 服务器
- 一台带公网 IPv4 或 IPv6 的服务器。
- 推荐Vultr，可以随时换vps换IP，按时计费。
- vultr:(https://www.vultr.com/?ref=6999923)  
- racknerd:(https://my.racknerd.com/aff.php?aff=19920)
### 2️⃣ 域名（可选）
- 配置 A 记录解析到服务器 IP

📌 VLESS-REALITY 协议无需域名
## 📥 一键安装
如果没有安装wget或curl，请先安装
```
apt update && apt install wget curl -y
```
然后执行：
```
wget -N https://raw.githubusercontent.com/linuxhobby/xray-v2ray-install/main/install.sh && chmod +x install.sh && ./install.sh
```
---
 ## 📖 支持协议矩阵
- VLESS-REALITY-Vision			✅【推荐，最强隐蔽/不依赖域名】
- VLESS-REALITY-xhttp			✅【最新黑科技/综合最强】
- VLESS-WS-TLS			✅【推荐，需要域名/CDN兼容/标准】
- VLESS-gRPC-TLS			 ✅【低延迟/多路复用】
- VLESS-XHTTP-TLS			✅【流式传输/防指纹】
- Trojan-WS-TLS			✅【仿HTTPS/老牌稳定】
- Trojan-gRPC-TLS			 ✅【高效转发/适合游戏】
- VMess-WS-TLS			✅【广泛兼容/传统方案】  
- VMess-gRPC-TLS			✅【兼容gRPC新特性】  

✔ 一键自动化安装  
✔ 自动申请 HTTPS 证书  
✔ 多协议一键切换，再生成新的协议时自动覆盖原先的协议配置  
✔ 极简交互操作，Linux知识零基础也无妨  
✔ 自动将节点链接生成二维码，方便手机扫码加入节点。

## 🖥️ 推荐系统，已测试
- ✅ Debian 12 / 13  
- ✅ Ubuntu 25 / 26  

---

## 🖼️ 脚本界面展示
<img width="579" height="628" alt="image" src="https://github.com/user-attachments/assets/057d86ac-2ea3-4cc6-953a-8cffc7ed8458" />


## 🖼️ 安装成功后信息展示
<img width="715" height="595" alt="image" src="https://github.com/user-attachments/assets/df0ccc71-d692-4360-bed2-c6c3a4b1208f" />


---
# 🔗 Xray 协议矩阵技术特性详解

| 协议类型 | 特点 |
| :--- | :--- |
| **VLESS-REALITY-Vision** | **最强隐蔽/极致性能**：无需自备域名与证书，借用大站身份彻底消灭 TLS 指纹；Vision 流控消除内层 TLS 特征，直连延迟极低，是目前防封锁的首选方案。 |
| **VLESS-REALITY-xhttp** | **最新黑科技/深度伪装**：继承 Reality 借壳特性，改用 XHTTP 模拟标准 Web 交互逻辑；具备极强的主动探测防御能力，能有效规避针对 TLS 流量统计规律的识别。 |
| **VLESS-WS-TLS** | **CDN 兼容/高通用性**：采用标准 WebSocket 传输，配合 TLS 加密可完美接入 Cloudflare 等 CDN 隐藏真实 IP；通过 443 端口反代，适合在严苛防火墙环境下生存。 |
| **VLESS-gRPC-TLS** | **低延迟/多路复用**：利用 gRPC 协议的长连接特性，显著提升在高丢包网络环境下的稳定性；原生支持多路复用，握手速度快，适合对响应速度有要求的移动端场景。 |
| **VLESS-XHTTP-TLS** | **流式传输/防指纹**：Xray 核心新推出的传输方式，模拟真实浏览器的 HTTP 请求行为；相比 WebSocket 拥有更轻量级的封装，且具备更现代化的防指纹识别机制。 |
| **Trojan-WS-TLS** | **仿 HTTPS/老牌稳定**：将流量完全伪装成正常的网站访问行为，隐蔽性极佳；协议结构简单高效，在各种老旧设备和客户端上拥有极高的兼容性与稳定性。 |
| **Trojan-gRPC-TLS** | **高效转发/适合游戏**：结合了 Trojan 的简洁与 gRPC 的高性能，数据转发开销极小；在处理高频小包（如在线游戏流量）时表现出色，有效降低游戏跳 ping 现象。 |
| **VMess-WS-TLS** | **广泛兼容/传统方案**：最经典的抗封锁方案之一，几乎所有现存客户端均能完美支持；适合作为保底节点，配合 CDN 转发可有效拯救被封锁的服务器 IP。 |
| **VMess-gRPC-TLS** | **兼容新特性/均衡之选**：为传统 VMess 协议注入 gRPC 的传输优势，兼顾了协议的成熟度与传输的灵活性；适合需要多端同步且对网络链路质量有一定要求的用户。 |

---
## ❌ 卸载

运行脚本，选择【d】即可卸载。

---

## ⚖️ 免责声明

仅供学习研究。

---
## 📢 BUG 反馈

如果你发现任何问题，欢迎提交：
👉[反馈BUG](https://github.com/linuxhobby/xray-v2ray-install/issues/1)
---

## ✍️ 作者

人生若只如初见

测试版链接：
```
wget -N https://raw.githubusercontent.com/linuxhobby/xray-v2ray-install/main/install_test.sh && chmod +x install_test.sh && ./install_test.sh
```
