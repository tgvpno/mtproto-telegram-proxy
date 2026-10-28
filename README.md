# mtproto-telegram-proxy
本项目为 tproxy‑server 一键部署脚本，tproxy‑server 是 Telegram 实验性 WEB‑Proxy（WebView 桥接 MTProxy）概念验证项目。外层流量是标准 HTTPS/WebSocket 网页流量，对抗 DPI 识别，内层完整保留 MTProto 加密与帧格式。
⚠️ 重要提醒
WEB‑Proxy仅代理 Telegram 流量，不是全局 VPN。
客户端支持：Telegram Desktop ≥7.1.0、Android Beta；iOS 暂无客户端支持。
属于 POC 概念验证项目，请勿作为唯一生产链路，建议保留备用代理。
原理简述
传统 FakeTLS MTProxy 依靠伪造 TLS 握手，容易被 JA4 指纹、流量行为特征识别封禁。
tproxy‑server 方案：Telegram 客户端把 MTProto 流量交给内置 WebView，生成标准同源 HTTPS/WebSocket 流量对外传输；DPI 只能看到普通网页访问；服务端桥接后转发给后端原版 MTProxy 服务。
环境要求
操作系统：Ubuntu 22.04 / Debian 12（x86_64）
境外 VPS，TCP 80、443 端口对外开放
已解析至服务器 IP 的域名，可正常申请 SSL 证书
root /sudo 权限
🚀 一键安装
bash
curl -fsSL https://raw.githubusercontent.com/你的仓库/tproxy-server-oneclick/main/install.sh -o install.sh
chmod +x install.sh
sudo bash install.sh
脚本将自动完成：
安装编译依赖、Go 环境
编译官方 MTProxy 后端
编译 tproxy‑server 桥接程序
自动生成 32 位 hex 密钥、token 密钥、profiles.json配置
安装配置 Caddy，自动申请 HTTPS 证书
生成 systemd 服务，配置开机自启
iptables 屏蔽后端端口公网访问，后端仅监听回环127.0.0.1
部署完成后输出信息：域名、密钥、一键导入链接，请保存。
手动部署参考（供排错参考）
1. 生成客户端密钥
bash
openssl rand -hex 16
2. 编译官方 MTProxy 后端
bash
apt update && apt install git build-essential -y
git clone https://github.com/TelegramMessenger/MTProxy.git
cd MTProxy
make
curl -s https://core.telegram.org/getProxySecret -o proxy-secret
curl -s https://core.telegram.org/getProxyConfig -o proxy-multi.conf
# 仅监听回环 127.0.0.1:2398
./mtproxy --secret proxy-secret --config proxy-multi.conf -p 127.0.0.1:2398
3. 编译 tproxy‑server
bash
# 安装Go环境
wget https://go.dev/dl/go1.23.1.linux-amd64.tar.gz
rm -rf /usr/local/go && tar -C /usr/local -xzf go1.23.1.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin

git clone https://github.com/cy1234561/tproxy-server.git
cd tproxy-server
go build -o tproxy-server ./cmd/tproxy-server

# 生成鉴权token密钥
./tproxy-server --generate-token-key token.key
chmod 600 token.key
profiles.json配置示例
json
{
  "profiles": [
    {
      "secret": "此处替换openssl生成的32位hex密钥",
      "carrier": "websocket‑lanes",
      "mtproxy_addr": "127.0.0.1:2398"
    }
  ],
  "max_sessions_global": 128,
  "max_streams_global": 4096
}
carrier 可选模式：https / https‑lanes / websocket / websocket‑lanes；封锁较强环境优先 websocket‑lanes。
前台测试启动：
bash
./tproxy-server --listen 127.0.0.1:8080 --token-key ./token.key --profile ./profiles.json
4. Caddy 反向代理配置
caddy‑tproxy.conf
caddy
{
  email "填写申请证书的邮箱"
  log default {
    exclude http.log.access
  }
}

你的域名.com {
  reverse_proxy 127.0.0.1:8080 {
    header_up Host {host}
    header_up X‑Real‑IP {remote}
    header_up X‑Forwarded‑For {remote}
    retry 0
    transport http {
      keepalive_idle 120s
    }
  }
  header Strict‑Transport‑Security "max‑age=31536000; includeSubDomains"
}
重载配置：
bash
caddy reload
5. systemd 开机自启
mtproxy.service
ini
[Unit]
Description=Telegram Official MTProxy Backend
After=network.target

[Service]
Type=simple
User=nobody
WorkingDirectory=/opt/mtproxy
ExecStart=/opt/mtproxy/mtproxy --secret proxy-secret --config proxy-multi.conf -p 127.0.0.1:2398
Restart=on‑failure

[Install]
WantedBy=multi‑user.target
tproxy‑server.service
ini
[Unit]
Description=tproxy‑server Telegram Web‑Proxy Bridge
After=network.target mtproxy.service

[Service]
Type=simple
User=nobody
WorkingDirectory=/opt/tproxy‑server
ExecStart=/opt/tproxy‑server/tproxy‑server --listen 127.0.0.1:8080 --token‑key ./token.key --profile ./profiles.json
Restart=on‑failure

[Install]
WantedBy=multi‑user.target
启用服务
bash
systemctl daemon‑reload
systemctl enable --now mtproxy tproxy‑server
systemctl status mtproxy tproxy‑server

# 防火墙禁止外部访问后端端口
iptables -A INPUT -p tcp --dport 2398 -j DROP
iptables -A INPUT -p tcp --dport 8080 -j DROP
Telegram 客户端配置 WEB 代理
一键导入链接（推荐）
plaintext
https://t.me/webproxy?server=你的域名.com&secret=你的32位密钥
将链接发送到 Telegram「收藏夹」
点击链接，自动弹出添加 WEB 代理窗口，确认添加
手动配置
设置 → 数据和存储 → 代理 → 添加代理
代理类型必须选择 WEB，不要选 MTProto/SOCKS5
服务器填写域名（不带https://，不加端口）
粘贴 32 位十六进制 secret，保存启用
连接成功状态：代理列表显示 web: connected
故障排查
找不到 WEB 代理选项：Desktop 版本低于 7.1.0；Android 需要 Beta 客户端；iOS 暂不支持。
连接失败：检查域名解析、SSL 证书状态：caddy list‑certificates；查看日志：journalctl -u tproxy‑server -f；切换carrier传输模式测试。
安全提示：关闭 Caddy 访问日志，日志会泄露桥接令牌；后端端口禁止对公网开放。
代理方案对比
表格
方案	抗 DPI 能力	客户端支持	部署难度	说明
FakeTLS MTProxy(mtg)	中等	全平台	低	容易 JA4 指纹识别，普及度高
Web‑Proxy tproxy‑server	高	Desktop / Android Beta	高	外层 WebView 真实浏览器流量，POC 实验项目
VLESS+Reality	高	第三方代理客户端	中等	通用全局代理，无法使用 tg://proxy 一键导入
风险提示
Web‑Proxy不能当做全局 VPN，仅代理 Telegram。
tproxy‑server 为实验项目，接口可能变动，不要作为唯一链路，准备备用代理。
域名是核心风险，域名一旦被标记，整套服务直接失效，建议准备备用域名。
参考项目
原版仓库：https://github.com/cy1234561/tproxy-server
Telegram MTProxy：https://github.com/TelegramMessenger/MTProxy
