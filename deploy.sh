#!/usr/bin/env bash
set -Eeuo pipefail

# ==========================================================
# Telegram MTProto + WebProxy 一键部署脚本
#
# 说明:
#   一个 VPS = 1 个 tproxy-server (Telegram 官方 WebProxy POC)
#              + 1 个 mtproto-proxy (Telegram 官方 MTProto 代理)
#              + 1 个 caddy (HTTPS 反向代理，自动签发证书)
#
# 用法:
#   ./deploy.sh <domain> [ad_tag] [public_ip]   # 一键部署（默认行为）
#   ./deploy.sh --ad <ad_tag>                   # 仅更新广告 tag 并重启
#   ./deploy.sh --status                        # 查看运行状态
#   ./deploy.sh --help                          # 显示帮助
#
# 必填环境变量（若本地无对应二进制）:
#   TPROXY_BIN_URL   tproxy-server 二进制下载地址
#   MTG_BIN_URL      mtproto-proxy 二进制下载地址
#
# 可选环境变量:
#   CADDY_VERSION    caddy 版本（默认 2.11.7，从 GitHub 官方下载）
#   ACME_EMAIL       ACME 邮箱（默认 admin@<domain>）
#   SWAP_SIZE_MB     swap 大小，MB（默认 512）
#   MTG_PORT         MTProto 监听端口（默认 2398）
#   MTG_STATS_PORT   统计接口端口（默认 8888）
#   MTG_WORKERS      worker 数（默认 1）
#   MTG_MAX_CONN     最大连接数（默认 2048）
#   TPROXY_LISTEN    tproxy-server 监听地址（默认 127.0.0.1:8080）
#   TPROXY_ADMIN     tproxy-server 管理地址（默认 127.0.0.1:8081）
#   FAKE_TLS_DOMAIN  若设置，secret 前会加 ee 前缀伪装 TLS
#   ROTATE_SECRET    设为 1 则重新生成 secret
#
# 二进制准备:
#   Telegram 官方 tproxy-server 和 mtproto-proxy 未提供官方预编译包，
#   可自行编译或从可信镜像下载后，放到:
#     /usr/local/bin/tproxy-server
#     /usr/local/bin/mtg-c
#   或通过 TPROXY_BIN_URL / MTG_BIN_URL 指定下载地址。
# ==========================================================

# ---------------- 解析命令 ----------------
MODE="init"
case "${1:-}" in
  --help|-h)
    sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  --ad)
    MODE="ad"; shift
    ;;
  --status)
    MODE="status"; shift
    ;;
  --init)
    MODE="init"; shift
    ;;
  "")
    echo "usage: $0 <domain> [ad_tag] [public_ip]" >&2
    echo "       $0 --ad <ad_tag>" >&2
    echo "       $0 --status" >&2
    echo "       $0 --help" >&2
    exit 1
    ;;
  *)
    # 第一个参数不是选项，视为 domain，走 init
    MODE="init"
    ;;
esac

# ---------------- 路径 ----------------
TPROXY_BIN="/usr/local/bin/tproxy-server"
TPROXY_CONF_DIR="/etc/tproxy-server"
TPROXY_CONFIG="${TPROXY_CONF_DIR}/config.json"
TPROXY_PROFILES="${TPROXY_CONF_DIR}/profiles.json"
TPROXY_TOKEN="${TPROXY_CONF_DIR}/token.key"
TPROXY_SERVICE="tproxy-server.service"
TPROXY_SERVICE_PATH="/etc/systemd/system/${TPROXY_SERVICE}"

MTG_BIN="/usr/local/bin/mtg-c"
MTPROTO_ETC_DIR="/etc/mtproto"
AD_TAG_FILE="${MTPROTO_ETC_DIR}/ad_tag"
MTG_SERVICE="mtg-c.service"
MTG_SERVICE_PATH="/etc/systemd/system/${MTG_SERVICE}"

CADDY_BIN="/usr/local/bin/caddy"
CADDY_CONF_DIR="/etc/caddy"
CADDY_MAIN="${CADDY_CONF_DIR}/Caddyfile"
CADDY_CONF_D="${CADDY_CONF_DIR}/conf.d"
CADDY_SERVICE="caddy.service"
CADDY_SERVICE_PATH="/etc/systemd/system/${CADDY_SERVICE}"

# ---------------- 可调参数 ----------------
CADDY_VERSION="${CADDY_VERSION:-2.11.7}"

MTG_PORT="${MTG_PORT:-2398}"
MTG_STATS_PORT="${MTG_STATS_PORT:-8888}"
MTG_WORKERS="${MTG_WORKERS:-1}"
MTG_MAX_CONN="${MTG_MAX_CONN:-2048}"
MTG_MSG_BUFFERS_SIZE="${MTG_MSG_BUFFERS_SIZE:-16777216}"

TPROXY_LISTEN="${TPROXY_LISTEN:-127.0.0.1:8080}"
TPROXY_ADMIN="${TPROXY_ADMIN:-127.0.0.1:8081}"

SWAP_SIZE_MB="${SWAP_SIZE_MB:-512}"
SWAP_FILE="/swapfile"

FAKE_TLS_DOMAIN="${FAKE_TLS_DOMAIN:-}"

# 二进制下载源（若本地已存在对应二进制则可留空）
TPROXY_BIN_URL="${TPROXY_BIN_URL:-}"
MTG_BIN_URL="${MTG_BIN_URL:-}"

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) CADDY_ARCH="amd64" ;;
  aarch64|arm64) CADDY_ARCH="arm64" ;;
  *) CADDY_ARCH="amd64" ;;
esac

# ---------------- 日志 / JSON ----------------
log() { echo "[$(date '+%H:%M:%S')] $*" >&2; }
json_fail() {
  local msg="${1//\"/\\\"}"
  echo "JSON_RESULT_START"
  printf '{"status":"error","mode":"%s","message":"%s"}\n' "$MODE" "$msg"
  echo "JSON_RESULT_END"
  exit 1
}
trap 'json_fail "line:$LINENO exit:$?"' ERR

[[ ${EUID} -eq 0 ]] || json_fail "need_root"

# ==========================================================
# 通用工具
# ==========================================================
download_file() {
  local url="$1" out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 3 --connect-timeout 15 "$url" -o "$out"
  elif command -v wget >/dev/null 2>&1; then
    wget -q --tries=3 --timeout=15 -O "$out" "$url"
  else
    return 1
  fi
}

is_elf() {
  local magic
  magic="$(head -c 4 "$1" 2>/dev/null | od -An -tx1 | tr -d ' \n')"
  [[ "$magic" == "7f454c46" ]]
}

install_deps() {
  local missing=()
  command -v tar     >/dev/null 2>&1 || missing+=(tar)
  command -v python3 >/dev/null 2>&1 || missing+=(python3)
  command -v ss      >/dev/null 2>&1 || missing+=(iproute2)
  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    missing+=(curl)
  fi
  if [[ ${#missing[@]} -gt 0 ]]; then
    json_fail "missing_deps:${missing[*]}"
  fi
}

wait_active() {
  local svc="$1" timeout="${2:-30}" i=0
  while (( i < timeout )); do
    systemctl is-active --quiet "$svc" && return 0
    sleep 1
    i=$((i + 1))
  done
  return 1
}

detect_internal_ip() {
  local ip=""
  ip="$(hostname -I 2>/dev/null | awk '{print $1}')" || true
  if [[ -z "$ip" ]]; then
    ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')" || true
  fi
  [[ -n "$ip" ]] || return 1
  printf '%s' "$ip"
}

detect_public_ip() {
  local given="${1:-}" ip=""
  if [[ -n "$given" ]]; then
    printf '%s' "$given"; return 0
  fi
  ip="$(curl -fsS --connect-timeout 3 https://api.ipify.org 2>/dev/null | tr -d '\n' || true)"
  if [[ -z "$ip" ]]; then
    ip="$(curl -fsS --connect-timeout 3 https://ifconfig.me 2>/dev/null | tr -d '\n' || true)"
  fi
  [[ -n "$ip" ]] || return 1
  printf '%s' "$ip"
}

# ==========================================================
# 系统调优
# ==========================================================
setup_swap() {
  local cur
  cur="$(awk '/^SwapTotal:/{print int($2/1024)}' /proc/meminfo)"
  if (( cur >= SWAP_SIZE_MB )); then return 0; fi
  log "创建 ${SWAP_SIZE_MB}MB Swap ..."
  if swapon --show=NAME --noheadings 2>/dev/null | grep -qx "$SWAP_FILE"; then
    swapoff "$SWAP_FILE" || true
  fi
  rm -f "$SWAP_FILE"
  if ! fallocate -l "${SWAP_SIZE_MB}M" "$SWAP_FILE" 2>/dev/null; then
    dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$SWAP_SIZE_MB" status=none
  fi
  chmod 600 "$SWAP_FILE"
  mkswap "$SWAP_FILE" >/dev/null
  swapon "$SWAP_FILE"
  grep -q "^${SWAP_FILE}" /etc/fstab || echo "${SWAP_FILE} none swap sw 0 0" >> /etc/fstab
}

setup_kernel_params() {
  local conf="/etc/sysctl.d/99-mtproto-free.conf"
  cat > "$conf" <<'EOF'
vm.swappiness = 10
kernel.pid_max = 65535
net.core.somaxconn = 8192
net.ipv4.tcp_max_syn_backlog = 8192
fs.file-max = 200000
EOF
  sysctl -p "$conf" >/dev/null 2>&1 || true
}

optimize_memory() {
  local svc
  for svc in argusagent AliYunDun AliYunDunMonito aegis; do
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
      systemctl stop "$svc" >/dev/null 2>&1 || true
      systemctl disable "$svc" >/dev/null 2>&1 || true
    fi
  done
  if command -v journalctl >/dev/null 2>&1; then
    journalctl --vacuum-size=30M >/dev/null 2>&1 || true
    mkdir -p /etc/systemd/journald.conf.d
    cat > /etc/systemd/journald.conf.d/99-mtproto-limit.conf <<'EOF'
[Journal]
SystemMaxUse=30M
EOF
    systemctl restart systemd-journald >/dev/null 2>&1 || true
  fi
}

setup_nss() {
  [[ -f /etc/nsswitch.conf ]] || return 0
  sed -i 's/^passwd:.*/passwd:     files/' /etc/nsswitch.conf
  sed -i 's/^group:.*/group:      files/'   /etc/nsswitch.conf
}

setup_selinux() {
  command -v getenforce >/dev/null 2>&1 || return 0
  [[ "$(getenforce 2>/dev/null || echo Disabled)" == "Disabled" ]] && return 0
  command -v semanage >/dev/null 2>&1 || return 0
  local p
  for p in 80 443 8080 8081 2398 8888; do
    semanage port -a -t http_port_t -p tcp "$p" 2>/dev/null || semanage port -m -t http_port_t -p tcp "$p" 2>/dev/null || true
  done
}

# ==========================================================
# 二进制安装
# ==========================================================
install_caddy_binary() {
  if [[ ! -x "$CADDY_BIN" ]]; then
    local tarball="caddy_${CADDY_VERSION}_linux_${CADDY_ARCH}.tar.gz"
    local url="https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/${tarball}"
    local tmp="$(mktemp -d)"
    download_file "$url" "$tmp/$tarball" || { rm -rf "$tmp"; json_fail "caddy_download_failed"; }
    tar -xzf "$tmp/$tarball" -C "$tmp" caddy || { rm -rf "$tmp"; json_fail "caddy_extract_failed"; }
    install -m 0755 "$tmp/caddy" "$CADDY_BIN"
    rm -rf "$tmp"
  fi

  if ! id -u caddy >/dev/null 2>&1; then
    groupadd --system caddy 2>/dev/null || true
    useradd --system --gid caddy --create-home --home-dir /var/lib/caddy --shell /usr/sbin/nologin caddy 2>/dev/null || true
  fi

  cat > "$CADDY_SERVICE_PATH" <<EOF
[Unit]
Description=Caddy
After=network.target network-online.target
Requires=network-online.target

[Service]
Type=notify
User=caddy
Group=caddy
ExecStart=${CADDY_BIN} run --environ --config ${CADDY_MAIN}
ExecReload=${CADDY_BIN} reload --config ${CADDY_MAIN} --force
TimeoutStopSec=5s
LimitNOFILE=1048576
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_BIND_SERVICE
Environment="GOMEMLIMIT=80MiB"
MemoryHigh=80M
MemoryMax=96M

[Install]
WantedBy=multi-user.target
EOF
  chmod 0644 "$CADDY_SERVICE_PATH"
  mkdir -p "$CADDY_CONF_DIR" "$CADDY_CONF_D"
  systemctl daemon-reload
  systemctl enable "$CADDY_SERVICE" >/dev/null 2>&1 || true
}

download_tproxy() {
  if [[ -x "$TPROXY_BIN" ]]; then
    log "tproxy-server 已存在: $TPROXY_BIN"
    return 0
  fi
  if [[ -z "$TPROXY_BIN_URL" ]]; then
    json_fail "tproxy_binary_missing: place tproxy-server at ${TPROXY_BIN} or set TPROXY_BIN_URL"
  fi
  local tmp="$(mktemp)"
  download_file "$TPROXY_BIN_URL" "$tmp" || { rm -f "$tmp"; json_fail "tproxy_download_failed"; }
  is_elf "$tmp" || { rm -f "$tmp"; json_fail "tproxy_not_elf"; }
  install -m 0755 "$tmp" "$TPROXY_BIN"
  rm -f "$tmp"
}

install_mtg_c() {
  if [[ ! -x "$MTG_BIN" ]]; then
    if [[ -z "$MTG_BIN_URL" ]]; then
      json_fail "mtg_binary_missing: place mtproto-proxy at ${MTG_BIN} or set MTG_BIN_URL"
    fi
    local tmp="$(mktemp)"
    download_file "$MTG_BIN_URL" "$tmp" || { rm -f "$tmp"; json_fail "mtg_download_failed"; }
    is_elf "$tmp" || { rm -f "$tmp"; json_fail "mtg_not_elf"; }
    install -m 0755 "$tmp" "$MTG_BIN"
    rm -f "$tmp"
  fi

  mkdir -p "$MTPROTO_ETC_DIR"
  if [[ ! -s "${MTPROTO_ETC_DIR}/proxy-secret" ]]; then
    download_file "https://core.telegram.org/getProxySecret" "${MTPROTO_ETC_DIR}/proxy-secret" || true
    chmod 644 "${MTPROTO_ETC_DIR}/proxy-secret" 2>/dev/null || true
  fi
  if [[ ! -s "${MTPROTO_ETC_DIR}/proxy-multi.conf" ]]; then
    download_file "https://core.telegram.org/getProxyConfig" "${MTPROTO_ETC_DIR}/proxy-multi.conf" || true
    chmod 644 "${MTPROTO_ETC_DIR}/proxy-multi.conf" 2>/dev/null || true
  fi
  [[ -s "${MTPROTO_ETC_DIR}/proxy-secret" ]] || json_fail "proxy_secret_missing"
  [[ -s "${MTPROTO_ETC_DIR}/proxy-multi.conf" ]] || json_fail "proxy_multi_missing"
}

ensure_tproxy_user() {
  if ! id -u tproxy >/dev/null 2>&1; then
    groupadd --system tproxy 2>/dev/null || true
    useradd --system --gid tproxy --create-home --home-dir /var/lib/tproxy --shell /usr/sbin/nologin tproxy 2>/dev/null || true
  fi
}

# ==========================================================
# secret / profiles
# ==========================================================
gen_secret() {
  local body="$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  if [[ -n "$FAKE_TLS_DOMAIN" ]]; then
    local hex="$(printf '%s' "$FAKE_TLS_DOMAIN" | od -An -tx1 | tr -d ' \n')"
    printf 'ee%s%s' "$body" "$hex"
  else
    printf '%s' "$body"
  fi
}

read_secret() {
  [[ -f "$TPROXY_PROFILES" ]] || return 0
  python3 - "$TPROXY_PROFILES" <<'PY' 2>/dev/null || true
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    p = d.get("profiles") or []
    if p and p[0].get("secret"): print(p[0]["secret"])
except Exception: pass
PY
}

write_profiles() {
  python3 - "$TPROXY_PROFILES" "$1" "$MTG_PORT" <<'PY'
import json, os, sys
path, secret, port = sys.argv[1], sys.argv[2], int(sys.argv[3])
data = {"profiles": [{"name": "free-0", "secret": secret, "backend": f"127.0.0.1:{port}", "carrier_mode": "https"}]}
tmp = path + ".tmp"
with open(tmp, "w") as f: json.dump(data, f, indent=2, ensure_ascii=False)
os.replace(tmp, path)
PY
  chown tproxy:tproxy "$TPROXY_PROFILES" 2>/dev/null || true
  chmod 0400 "$TPROXY_PROFILES"
}

# ==========================================================
# systemd 单元
# ==========================================================
generate_tproxy_service() {
  cat > "$TPROXY_SERVICE_PATH" <<EOF
[Unit]
Description=tproxy-server relay
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
User=tproxy
Group=tproxy
ExecStart=${TPROXY_BIN} -config ${TPROXY_CONFIG}
Restart=always
RestartSec=3
LimitNOFILE=65536
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true
MemoryHigh=64M
MemoryMax=80M
[Install]
WantedBy=multi-user.target
EOF
  chmod 0644 "$TPROXY_SERVICE_PATH"
}

generate_mtg_service() {
  local ad_tag="${1:-}"
  {
    cat <<EOF
[Unit]
Description=MTProto proxy backend
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
ExecStart=${MTG_BIN} \\
    -u nobody \\
    -p ${MTG_STATS_PORT} \\
    -H ${MTG_PORT} \\
    -M ${MTG_WORKERS} \\
    -C ${MTG_MAX_CONN} \\
EOF
    if [[ -n "$ad_tag" ]]; then printf '    -P %s \\\n' "$ad_tag"; fi
    cat <<EOF
    -S ${SECRET} \\
    --msg-buffers-size ${MTG_MSG_BUFFERS_SIZE} \\
    --nat-info ${INTERNAL_IP}:${PUBLIC_IP} \\
    --aes-pwd ${MTPROTO_ETC_DIR}/proxy-secret \\
    ${MTPROTO_ETC_DIR}/proxy-multi.conf
Restart=always
RestartSec=3
LimitNOFILE=65536
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
MemoryHigh=128M
MemoryMax=160M
[Install]
WantedBy=multi-user.target
EOF
  } > "$MTG_SERVICE_PATH"
  chmod 0644 "$MTG_SERVICE_PATH"
}

write_caddy_config() {
  local domain="$1"
  local email="${ACME_EMAIL:-admin@${domain}}"
  local slug="$(printf '%s' "$domain" | tr -c 'a-zA-Z0-9.-' '_')"
  mkdir -p "$CADDY_CONF_D"
  cat > "${CADDY_CONF_D}/${slug}.caddy" <<EOF
${domain} {
  encode zstd gzip
  header -Via
  reverse_proxy ${TPROXY_LISTEN} {
    transport http {
      response_header_timeout 40s
    }
  }
}
EOF
  chmod 0644 "${CADDY_CONF_D}/${slug}.caddy"
  cat > "$CADDY_MAIN" <<EOF
{
  email ${email}
}
import ${CADDY_CONF_D}/*.caddy
EOF
  chmod 0644 "$CADDY_MAIN"
  "$CADDY_BIN" validate --config "$CADDY_MAIN" >/dev/null 2>&1 || json_fail "caddyfile_invalid"
}

# ==========================================================
# 模式: init（默认）
# ==========================================================
mode_init() {
  local domain="${1:?usage: $0 <domain> [ad_tag] [public_ip]}"
  local ad_tag="${2:-}"
  local given_ip="${3:-}"

  if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)+$ ]]; then
    json_fail "invalid_hostname"
  fi

  ACME_EMAIL="${ACME_EMAIL:-admin@${domain}}"

  install_deps; setup_kernel_params; setup_swap; optimize_memory; setup_selinux; setup_nss
  INTERNAL_IP="$(detect_internal_ip)" || json_fail "internal_ip_detect_failed"
  PUBLIC_IP="$(detect_public_ip "$given_ip")" || json_fail "public_ip_detect_failed"
  log "内网 IP=${INTERNAL_IP} 公网 IP=${PUBLIC_IP}"

  download_tproxy; install_caddy_binary; install_mtg_c; ensure_tproxy_user

  mkdir -p "$MTPROTO_ETC_DIR" "$TPROXY_CONF_DIR"
  chown tproxy:tproxy "$TPROXY_CONF_DIR"; chmod 0750 "$TPROXY_CONF_DIR"

  SECRET="$(read_secret || true)"
  if [[ -z "$SECRET" || "${ROTATE_SECRET:-0}" == "1" ]]; then
    SECRET="$(gen_secret)"
  fi

  if [[ -z "$ad_tag" && -f "$AD_TAG_FILE" ]]; then ad_tag="$(tr -d '\n' < "$AD_TAG_FILE")"; fi
  if [[ -n "$ad_tag" ]]; then
    printf '%s' "$ad_tag" > "$AD_TAG_FILE"
  else
    : > "$AD_TAG_FILE"
  fi
  chmod 0600 "$AD_TAG_FILE"

  [[ -f "$TPROXY_PROFILES" ]] || printf '{\n  "profiles": []\n}\n' > "$TPROXY_PROFILES"
  write_profiles "$SECRET"

  if [[ ! -f "$TPROXY_TOKEN" ]]; then head -c 32 /dev/urandom > "$TPROXY_TOKEN"; fi
  chown tproxy:tproxy "$TPROXY_TOKEN"; chmod 0400 "$TPROXY_TOKEN"

  cat > "$TPROXY_CONFIG" <<EOF
{
  "listen": "${TPROXY_LISTEN}",
  "admin_listen": "${TPROXY_ADMIN}",
  "public_dir": "/srv/tproxy-site",
  "public_hostname": "${domain}",
  "profiles_file": "${TPROXY_PROFILES}",
  "token_key_file": "${TPROXY_TOKEN}"
}
EOF
  chown tproxy:tproxy "$TPROXY_CONFIG"; chmod 0640 "$TPROXY_CONFIG"

  mkdir -p /srv/tproxy-site
  if [[ ! -f /srv/tproxy-site/index.html ]]; then
    echo '<!doctype html><title>Welcome</title><h1>Welcome</h1>' > /srv/tproxy-site/index.html
  fi
  chown -R caddy:caddy /srv/tproxy-site 2>/dev/null || true
  chmod 0755 /srv/tproxy-site

  generate_tproxy_service
  generate_mtg_service "$ad_tag"
  write_caddy_config "$domain"

  systemctl daemon-reload
  systemctl enable "$MTG_SERVICE" "$TPROXY_SERVICE" "$CADDY_SERVICE" >/dev/null 2>&1 || true
  systemctl restart "$MTG_SERVICE"
  systemctl restart "$TPROXY_SERVICE"
  systemctl restart "$CADDY_SERVICE"

  wait_active "$MTG_SERVICE" 30 || json_fail "mtg_start_failed"
  wait_active "$TPROXY_SERVICE" 30 || json_fail "tproxy_start_failed"
  wait_active "$CADDY_SERVICE" 30 || json_fail "caddy_start_failed"

  local resolved
  resolved="$(getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1}' | sort -u | head -n1 || true)"
  if [[ -n "$resolved" && "$resolved" != "$PUBLIC_IP" ]]; then
    log "WARN: $domain 解析到 $resolved，与公网 IP $PUBLIC_IP 不一致"
  fi

  echo "JSON_RESULT_START"
  J_DOMAIN="$domain" J_SECRET="$SECRET" J_AD_TAG="$ad_tag" J_PUBLIC_IP="$PUBLIC_IP" J_INTERNAL_IP="$INTERNAL_IP" J_MTG_PORT="$MTG_PORT" J_TPROXY_LISTEN="$TPROXY_LISTEN" \
  python3 - <<'PY'
import json, os
print(json.dumps({
  "status": "ok",
  "mode": "init",
  "domain": os.environ["J_DOMAIN"],
  "secret": os.environ["J_SECRET"],
  "ad_tag": os.environ["J_AD_TAG"],
  "public_ip": os.environ["J_PUBLIC_IP"],
  "internal_ip": os.environ["J_INTERNAL_IP"],
  "mtg_port": int(os.environ["J_MTG_PORT"]),
  "backend": "127.0.0.1:" + os.environ["J_MTG_PORT"],
  "frontend": os.environ["J_TPROXY_LISTEN"],
}, ensure_ascii=False))
PY
  echo "JSON_RESULT_END"
}

# ==========================================================
# 模式: ad
# ==========================================================
mode_ad() {
  local ad_tag="${1:-}"
  [[ -f "$MTG_SERVICE_PATH" ]] || json_fail "not_initialized"
  SECRET="$(read_secret || true)"
  [[ -n "$SECRET" ]] || json_fail "secret_missing"

  INTERNAL_IP="$(detect_internal_ip)" || json_fail "internal_ip_detect_failed"
  PUBLIC_IP="$(awk -F'--nat-info ' '/--nat-info/{print $2; exit}' "$MTG_SERVICE_PATH" | awk -F: '{print $2}' | tr -d ' \\')"
  [[ -n "$PUBLIC_IP" ]] || PUBLIC_IP="$(detect_public_ip)" || json_fail "public_ip_detect_failed"

  printf '%s' "$ad_tag" > "$AD_TAG_FILE"; chmod 0600 "$AD_TAG_FILE"

  generate_mtg_service "$ad_tag"
  systemctl daemon-reload
  systemctl restart "$MTG_SERVICE"
  wait_active "$MTG_SERVICE" 30 || json_fail "mtg_restart_failed"

  echo "JSON_RESULT_START"
  J_AD_TAG="$ad_tag" python3 - <<'PY'
import json, os
print(json.dumps({"status": "ok", "mode": "ad", "ad_tag": os.environ["J_AD_TAG"]}))
PY
  echo "JSON_RESULT_END"
}

# ==========================================================
# 模式: status
# ==========================================================
mode_status() {
  install_deps
  local tproxy_state="$(systemctl is-active "$TPROXY_SERVICE" 2>/dev/null || true)"
  local mtg_state="$(systemctl is-active "$MTG_SERVICE" 2>/dev/null || true)"
  local caddy_state="$(systemctl is-active "$CADDY_SERVICE" 2>/dev/null || true)"
  local conn_in="$(ss -Htn state established "( sport = :${MTG_PORT} )" 2>/dev/null | wc -l | tr -d ' ')" || conn_in=0
  local conn_out="$(ss -Htnp state established "( dport = :443 )" 2>/dev/null | grep -c 'mtg-c' || true)"
  [[ -z "$conn_out" ]] && conn_out=0
  local nat_ok="false"
  if grep -q -- '--nat-info' "$MTG_SERVICE_PATH" 2>/dev/null && ! grep -q 'YOUR_PUBLIC_IP' "$MTG_SERVICE_PATH" 2>/dev/null; then nat_ok="true"; fi

  echo "JSON_RESULT_START"
  J_TPROXY_STATE="$tproxy_state" J_MTG_STATE="$mtg_state" J_CADDY_STATE="$caddy_state" J_CONN_IN="$conn_in" J_CONN_OUT="$conn_out" J_NAT_OK="$nat_ok" J_CONFIG="$TPROXY_CONFIG" J_PROFILES="$TPROXY_PROFILES" J_ADFILE="$AD_TAG_FILE" \
  python3 - <<'PY'
import json, os, time
def read_json(p):
    try:
        with open(p) as f: return json.load(f)
    except Exception: return {}
cfg = read_json(os.environ["J_CONFIG"]); prof = read_json(os.environ["J_PROFILES"])
secret = (prof.get("profiles") or [{}])[0].get("secret", "")
try: ad_tag = open(os.environ["J_ADFILE"]).read().strip()
except Exception: ad_tag = ""
def cpu_pct():
    def snap():
        with open("/proc/stat") as f: return list(map(int, f.readline().split()[1:]))
    a = snap(); time.sleep(0.5); b = snap()
    total = sum(b) - sum(a)
    return 0.0 if total <= 0 else round((1 - ((b[3] + b[4]) - (a[3] + a[4])) / total) * 100, 1)
mem = {}
with open("/proc/meminfo") as f:
    for line in f:
        k, v = line.split(":", 1); mem[k] = int(v.strip().split()[0])
states = [os.environ["J_TPROXY_STATE"], os.environ["J_MTG_STATE"], os.environ["J_CADDY_STATE"]]
out = {
  "status": "ok" if all(s == "active" for s in states) else "degraded",
  "mode": "status",
  "ts": int(time.time()),
  "domain": cfg.get("public_hostname", ""),
  "secret": secret,
  "ad_tag": ad_tag,
  "services": {"tproxy": os.environ["J_TPROXY_STATE"], "mtg": os.environ["J_MTG_STATE"], "caddy": os.environ["J_CADDY_STATE"]},
  "nat_ok": os.environ["J_NAT_OK"] == "true",
  "metrics": {
    "cpu_pct": cpu_pct(),
    "load1": float(open("/proc/loadavg").read().split()[0]),
    "mem_total_mb": mem.get("MemTotal", 0) // 1024,
    "mem_available_mb": mem.get("MemAvailable", 0) // 1024,
    "swap_total_mb": mem.get("SwapTotal", 0) // 1024,
    "swap_free_mb": mem.get("SwapFree", 0) // 1024,
    "conn_in": int(os.environ["J_CONN_IN"] or 0),
    "conn_to_443_from_mtg": int(os.environ["J_CONN_OUT"] or 0),
    "uptime_seconds": int(float(open("/proc/uptime").read().split()[0])),
  },
}
print(json.dumps(out, ensure_ascii=False))
PY
  echo "JSON_RESULT_END"
}

case "$MODE" in
  init)   mode_init "$@" ;;
  ad)     mode_ad "$@" ;;
  status) mode_status ;;
  *)      json_fail "unknown_mode_${MODE}" ;;
esac
