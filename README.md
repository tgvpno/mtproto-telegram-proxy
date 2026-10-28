# mtproto-telegram-proxy

> 本项目为 tproxy‑server 一键部署脚本，tproxy‑server 是 Telegram 官方8月份最新推出 实验性 WEB‑Proxy（WebView 桥接 MTProxy）概念验证项目。  
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

- 🛡️ **优秀抗 DPI 能力**：外层为标准同源 HTTPS / WebSocket 网页流量，在 DPI 视角下与普通网站访问无差别，可规避 JA4 指纹与流量特征识别  
  *Great anti-DPI performance: outer traffic is normal same-origin HTTPS / WebSocket, indistinguishable from regular website visits to DPI, avoiding JA4 fingerprint detection.*
- 🔗 **原生 MTProto 加密**：内层完整保留原版 MTProxy 的加密与帧格式，不改动 Telegram 代理协议  
  *Native MTProto encryption: the inner layer keeps the original MTProxy encryption and framing without modifying the Telegram proxy protocol.*
- 📱 **跨平台客户端支持**：支持 Telegram Desktop、Android Beta；iOS 客户端正在开发中  
  *Cross-platform client support: works with Telegram Desktop and Android Beta; an iOS client is in development.*
- 🚀 **全自动一键部署**：脚本自动完成编译、证书申请、Caddy 反向代理、systemd 开机服务与防火墙策略  
  *Fully automatic one-click install: auto build, SSL certificate, Caddy reverse proxy, systemd service, and firewall rules.*
- 🎯 **原生 TG WEB 代理链接**：支持 `t.me/webproxy` 一键导入，Telegram 可原生识别 WEB 代理类型  
  *Native Telegram WEB proxy link: one-click import via `t.me/webproxy`; Telegram natively recognizes the WEB proxy type.*

---

## 🧠 原理简介 | Introduction

传统 FakeTLS MTProxy 容易被 JA4 指纹和流量时序特征识别。

**tproxy-server** 方案：Telegram 客户端将 MTProto 流量交给内置 WebView，外层承载为标准同源 HTTPS / WebSocket 网页流量；DPI 视角只看到普通 HTTPS 网页访问；服务端解复用后转发给后端标准 MTProxy。

*Traditional FakeTLS MTProxy is easily identified by JA4 fingerprints and traffic timing patterns.*

*With **tproxy-server**: the Telegram client hands MTProto traffic to its built-in WebView. The outer transport is standard same-origin HTTPS / WebSocket web traffic. From the DPI's perspective, it looks like a normal HTTPS website access. The server demultiplexes streams and forwards them to a standard backend MTProxy.*

---

## 📋 环境要求 | Requirements

- **系统**：Ubuntu 22.04 / Debian 12（x86_64）  
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
curl -fsSL https://github.com/tgvpno/mtproto-telegram-proxy/blob/main/deploy.sh -o install.sh
chmod +x install.sh
sudo bash install.sh
