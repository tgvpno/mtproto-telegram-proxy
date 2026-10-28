# tproxy-server-oneclick
一键部署脚本：tproxy-server，基于 WebView 同源 HTTPS / WebSocket 桥接的 Telegram MTProxy 概念验证代理，支持 Telegram Desktop、Android Beta，iOS 客户端尚在规划中。
> One-click deployment script for tproxy-server. A proof-of-concept Telegram MTProxy proxy bridged via WebView same-origin HTTPS/WebSocket. Supported on Telegram Desktop and Android Beta. iOS client is planned.

> ⚠️ 重要提示 | NOTICE
> - WEB-Proxy **仅代理 Telegram 流量，不是全局 VPN**
> - WEB-Proxy **only forwards Telegram traffic, NOT a global VPN**
> - 客户端要求：Telegram Desktop ≥7.1.0、Android Beta；iOS 暂无可用客户端
> - Client requirement: Telegram Desktop ≥7.1.0, Android Beta; No iOS client available yet
> - 本项目属于 POC 概念验证实现，稳定性有限，请勿作为唯一代理线路
> - This is a POC experimental project with limited stability. Do not use it as your only proxy.

## 原理简介 | Introduction
传统 FakeTLS MTProxy 容易被 JA4 指纹、流量时序特征识别。
tproxy-server 方案：Telegram 客户端将 MTProto 流量交给内置 WebView，外层承载为标准同源 HTTPS / WebSocket 网页流量；DPI 视角只看到普通 HTTPS 网页访问；服务端解多路复用流后转发给后端标准 MTProxy。

Traditional FakeTLS MTProxy is easily identified by JA4 fingerprints and traffic timing patterns.
With tproxy-server: Telegram client sends MTProto traffic through its built-in WebView. The outer transport is standard same-origin HTTPS / WebSocket web traffic. From DPI view, it looks like normal HTTPS website access. The server demultiplexes streams and forwards them to a standard backend MTProxy.

## 环境要求 | Requirements
- 系统：Ubuntu 22.04 / Debian 12 (x86_64)
- OS: Ubuntu 22.04 / Debian 12 (x86_64)
- 境外 VPS，开放 TCP 80、443 端口
- Overseas VPS with TCP 80 & 443 open
- 已解析到本机 IP 的域名（用于自动申请 SSL）
- A domain resolved to your server IP (for automatic SSL certificate)
- root / sudo 权限
- root / sudo privileges

## 🚀 一键安装 | One-click Install
```bash
curl -fsSL https://raw.githubusercontent.com/你的用户名/tproxy-server-oneclick/main/install.sh -o install.sh
chmod +x install.sh
sudo bash install.sh
