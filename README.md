# mtproto-telegram-proxy

> 本项目为 tproxy-server 一键部署脚本。tproxy-server 是社区概念验证项目，实现 Telegram WEB-Proxy，基于 WebView 桥接 MTProxy。  
> One-click deployment for tproxy-server — a proof-of-concept Telegram MTProxy bridged over same-origin WebView HTTPS / WebSocket.

> ⚠️ **重要提示 | NOTICE**
>
> - WEB-Proxy **仅代理 Telegram 流量，不是全局 VPN**  
>   WEB-Proxy **only forwards Telegram traffic, NOT a global VPN**
> - 客户端要求：Telegram Desktop ≥ 7.1.0、Android Beta；iOS 暂无可用客户端  
>   Client requirement: Telegram Desktop ≥ 7.1.0, Android Beta; no iOS client available yet
> - 本项目属于 **POC 概念验证实现**，稳定性有限，请勿作为唯一代理线路  
>   This is a **POC experimental project** with limited stability. Do not use it as your only proxy.

---

## ✨ 项目亮点 | Features

- 🛡️ **优秀抗 DPI 能力** — 外层为标准同源 HTTPS / WebSocket 网页流量，在 DPI 视角下与普通网站访问无差别，可规避 JA4 指纹与流量特征识别  
  *Great anti-DPI performance: outer traffic is normal same-origin HTTPS / WebSocket, indistinguishable from regular website visits to DPI, avoiding JA4 fingerprint detection.*
- 🔗 **原生 MTProto 加密** — 内层完整保留原版 MTProxy 的加密与帧格式，不改动 Telegram 代理协议  
  *Native MTProto encryption: the inner layer keeps the original MTProxy encryption and framing without modifying the Telegram proxy protocol.*
- 📱 **跨平台客户端支持** — 支持 Telegram Desktop、Android Beta；iOS 客户端正在开发中  
  *Cross-platform client support: works with Telegram Desktop and Android Beta; an iOS client is in development.*
- 🚀 **全自动一键部署** — 脚本自动完成编译、证书申请、Caddy 反向代理、systemd 开机服务与防火墙策略  
  *Fully automatic one-click install: auto build, SSL certificate, Caddy reverse proxy, systemd service, and firewall rules.*
- 🎯 **原生 TG WEB 代理链接** — 支持 `t.me/webproxy` 一键导入，Telegram 可原生识别 WEB 代理类型  
  *Native Telegram WEB proxy link: one-click import via `t.me/webproxy`; Telegram natively recognizes the WEB proxy type.*

---

## 🧠 原理简介 | Introduction

传统 FakeTLS MTProxy 容易被 JA4 指纹和流量时序特征识别。

**tproxy-server** 方案：Telegram 客户端将 MTProto 流量交给内置 WebView，外层承载为标准同源 HTTPS / WebSocket 网页流量；DPI 视角只看到普通 HTTPS 网页访问；服务端解复用后转发给后端标准 MTProxy。

*Traditional FakeTLS MTProxy is easily identified by JA4 fingerprints and traffic timing patterns.*

*With **tproxy-server**: the Telegram client hands MTProto traffic to its built-in WebView. The outer transport is standard same-origin HTTPS / WebSocket web traffic. From the DPI's perspective, it looks like a normal HTTPS website access. The server demultiplexes streams and forwards them to a standard backend MTProxy.*

---

## 📋 环境要求 | Requirements

- **系统** — Ubuntu 22.04 / Debian 12（x86_64）  
  *OS: Ubuntu 22.04 / Debian 12 (x86_64)*
- **境外 VPS**，开放 TCP `80`、`443` 端口  
  *Overseas VPS with TCP `80` & `443` open*
- **已解析到本机 IP 的域名**（用于自动申请 SSL 证书）  
  *A domain resolved to your server IP (for automatic SSL certificate)*
- **root / sudo 权限**  
  *root / sudo privileges*

---

## 🚀 快速开始 | Quick Start

### 一键安装 | One-click Install

```bash
curl -fsSL https://raw.githubusercontent.com/tgvpno/mtproto-telegram-proxy/main/deploy.sh -o install.sh
chmod +x install.sh
sudo bash install.sh
```

> **脚本自动执行任务 | What the script does:**
>
> 1. 安装编译依赖、Go 环境 | Install build dependencies & Go
> 2. 编译官方 MTProxy 后端 | Build official MTProxy backend
> 3. 编译 tproxy-server 桥接程序 | Build tproxy-server bridge
> 4. 生成 secret、token-key、profiles.json | Generate secret, token-key and profiles.json
> 5. 部署 Caddy，自动签发 HTTPS 证书 | Deploy Caddy with automatic HTTPS
> 6. 创建 systemd 服务并设置开机自启 | Create systemd services for auto-start
> 7. 防火墙限制后端端口仅本地访问 | Firewall rules to restrict backend ports to localhost only
>
> 部署结束会输出域名、密钥、一键导入链接，请妥善保存。  
> After deployment, domain, secret and import link will be printed. Save them securely.

---

## ❓ 常见 FAQ | FAQ

### Q：为什么推荐 websocket-lanes？

A：该模式多路复用会话，在封锁较强的环境下相比 HTTPS 模式有更好的抗识别表现。  
*A: This mode multiplexes sessions. It performs better against detection than HTTPS mode under heavy censorship.*

### Q：必须用域名吗？IP 可以部署 Web-Proxy 吗？

A：Web-Proxy 依赖 HTTPS 证书，IP 无法签发可信 SSL 证书，**必须使用域名**。  
*A: Web-Proxy relies on HTTPS certificates. Trusted SSL certificates cannot be issued for bare IP addresses. **A domain name is mandatory**.*

### Q：可以同时配置多套 secret 支持多用户吗？

A：修改 `profiles.json` 增加多条 profile 配置，即可支持多密钥、多用户。  
*A: Add multiple profile entries in `profiles.json` to support multiple secrets for different users.*

### Q：服务重启后连接会断开吗？

A：tproxy-server 重启会断开现存会话，客户端会自动重连。  
*A: Existing sessions will drop when tproxy-server restarts, but the Telegram client will reconnect automatically.*

### Q：tproxy-server 和普通 FakeTLS mtg 的区别是什么？

A：普通 FakeTLS 容易被 JA4 指纹识别；tproxy-server 外层是标准网页 HTTPS / WebSocket 流量，抗 DPI 识别能力更强，但仅支持 Telegram 自带 WEB 代理客户端。  
*A: Regular FakeTLS is vulnerable to JA4 fingerprint detection. tproxy-server uses standard web-like HTTPS / WebSocket outer transport for better anti-DPI performance, but only works with the Telegram built-in WEB-proxy client.*

### Q：为什么 Bing 搜不到本项目？

A：GitHub 新项目需要等待 Bingbot 爬虫抓取，一般需要 7–21 天，可使用 `site:<repo-url>` 查询是否被收录。  
*A: New GitHub repos need time for Bingbot crawling, normally 7–21 days. Use `site:<repo-url>` to check index status.*

---

## 📱 Telegram 客户端添加 Web 代理 | Add Web Proxy in Telegram

### 一键导入链接（推荐） | Import link (recommended)

将下面的链接中 `你的域名.com` 与 `YOUR_SECRET` 替换为部署输出的实际值，发送到 Telegram 收藏夹并点击：

```
https://t.me/webproxy?server=你的域名.com&secret=YOUR_SECRET
```

1. 发送链接到 Telegram 收藏夹 | Send the link to Saved Messages
2. 点击链接，弹窗添加 WEB 代理 | Click the link to add a WEB proxy

### 手动添加 | Manual setup

1. 设置 → 数据和存储 → 代理 → 添加代理  
   Settings → Data and Storage → Proxy → Add proxy
2. 代理类型 **必须选择 WEB**，不要选 MTProto / SOCKS5  
   Proxy type **must be WEB**, not MTProto / SOCKS5
3. 服务器：填写域名（不带 `https://`，不带端口）  
   Server: your domain (no `https://`, no port)
4. 填入 32 位十六进制 secret，保存并启用  
   Paste the 32-hex secret and save

> 正常状态：代理列表显示 `web: connected`  
> Success status: `web: connected`

---

## 🔧 故障排查 | Troubleshooting

- **没有 WEB 代理选项** — Desktop 版本低于 7.1.0；Android 需要 Beta 版；iOS 暂不支持  
  *No WEB proxy option: Desktop < 7.1.0; Android Beta required; iOS unsupported*
- **连接失败** — 检查域名解析与 SSL 证书；查看日志 `journalctl -u tproxy-server -f`；尝试切换 carrier 模式  
  *Connection failed: Check DNS & SSL; view logs with `journalctl -u tproxy-server -f`; switch carrier mode*
- **安全建议** — 关闭 Caddy 访问日志（日志会泄露桥接信息）；后端端口禁止对公网开放  
  *Security tip: Disable Caddy access log (it may leak bridge info); never expose backend ports to the public*

---

## 📊 方案对比 | Comparison

| 方案 / Solution | 抗 DPI / Anti-DPI | 客户端支持 / Client | 部署难度 / Deploy | 备注 / Note |
| --- | --- | --- | --- | --- |
| FakeTLS MTProxy (mtg) | 中等 / Medium | 全平台 / All | 低 / Low | 易被 JA4 指纹识别 / Vulnerable to JA4 |
| Web-Proxy (tproxy-server) | 高 / High | Desktop / Android Beta | 高 / High | 外层为标准网页流量，POC 实验项目 / Looks like normal website, POC |
| VLESS + Reality | 高 / High | 第三方客户端 / Third-party | 中等 / Medium | 全局代理，不支持 `tg://proxy` 一键导入 / Global proxy, no `tg://proxy` import |

---

## ⚠️ 风险声明 | Disclaimer

1. 仅代理 Telegram，**不是全局代理**  
   *Only proxies Telegram traffic, NOT a global proxy*
2. 属于实验项目，接口可能变更，建议准备备用代理线路  
   *Experimental project; API may change. Prepare a backup proxy*
3. 域名是核心依赖，域名一旦被标记服务即失效，建议准备备用域名  
   *Domain is critical. Service fails once the domain is flagged. Prepare a backup domain*

---

## 📚 参考 | References

- 原版仓库 / Original repo：<https://github.com/cy1234561/tproxy-server>
- 官方 MTProxy / Official MTProxy：<https://github.com/TelegramMessenger/MTProxy>
- TGV 体验 / TGV demo：<https://tgvpn.io/zh-CN/index.html#free-nodes-section>
