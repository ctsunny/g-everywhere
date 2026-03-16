#!/usr/bin/env bash
set -euo pipefail

APP_NAME="cf-egress"
APP_ROOT="/opt/${APP_NAME}"
BIN_DIR="${APP_ROOT}/bin"
WRK_DIR="${APP_ROOT}/worker"
ETC_DIR="/etc/${APP_NAME}"
LOG_DIR="/var/log/${APP_NAME}"
RUN_DIR="/var/lib/${APP_NAME}"

ENV_FILE="${ETC_DIR}/env"
CF_ENV_FILE="${ETC_DIR}/cloudflare.env"
CONFIG_FILE="${ETC_DIR}/config.json"
PROXY_MAP_FILE="${ETC_DIR}/worker-proxy-map.json"

SERVICE_NAME="${APP_NAME}.service"
CTL_BIN="/usr/local/bin/cfeg"
SETUP_BIN="/usr/local/bin/${APP_NAME}-setup"
SELF_URL="https://raw.githubusercontent.com/ctsunny/g-everywhere/main/warp-setup.sh"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'
BOLD='\033[1m'; NC='\033[0m'

ARCH=""
XRAY_ASSET=""
NODE_OK="0"

banner() {
  clear 2>/dev/null || true
  echo -e "${BOLD}${BLUE}"
  echo "   ______ ______   ______"
  echo "  / ____// ____/  / ____/____ _ ____ ___"
  echo " / /    / /_     / __/  / __ \`// __ \`__ \\"
  echo "/ /___ / __/    / /___ / /_/ // / / / / /"
  echo "\\____//_/      /_____/ \\__, //_/ /_/ /_/"
  echo "                      /____/"
  echo -e "${NC}"
  echo -e " ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e " ${GREEN} Google/Gemini Egress ${NC}│${YELLOW} Worker WK Region ${NC}│${MAGENTA} Xray / Sing-box ${NC}"
  echo -e " ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

msg()  { echo -e "${GREEN}$*${NC}"; }
warn() { echo -e "${YELLOW}$*${NC}"; }
err()  { echo -e "${RED}$*${NC}" >&2; }

need_root() {
  [ "$(id -u)" -eq 0 ] || { err "请使用 root 运行"; exit 1; }
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64)
      ARCH="amd64"
      XRAY_ASSET="Xray-linux-64.zip"
      ;;
    aarch64|arm64)
      ARCH="arm64"
      XRAY_ASSET="Xray-linux-arm64-v8a.zip"
      ;;
    *)
      err "暂不支持架构: $(uname -m)"
      exit 1
      ;;
  esac
}

mkdirs() {
  mkdir -p "$APP_ROOT" "$BIN_DIR" "$WRK_DIR" "$ETC_DIR" "$LOG_DIR" "$RUN_DIR"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

install_deps() {
  if command_exists apt-get; then
    apt-get update -y >/dev/null 2>&1
    apt-get install -y curl wget unzip tar jq ca-certificates systemd procps sed grep coreutils openssl >/dev/null 2>&1
  elif command_exists dnf; then
    dnf install -y curl wget unzip tar jq ca-certificates systemd procps-ng sed grep coreutils openssl >/dev/null 2>&1
  elif command_exists yum; then
    yum install -y curl wget unzip tar jq ca-certificates systemd procps-ng sed grep coreutils openssl >/dev/null 2>&1
  else
    err "未识别包管理器"
    exit 1
  fi
}

ensure_node() {
  if command_exists node && command_exists npm; then
    local major
    major="$(node -v 2>/dev/null | sed 's/^v//' | cut -d. -f1 || echo 0)"
    if [ "${major:-0}" -ge 18 ]; then
      NODE_OK="1"
      return 0
    fi
  fi

  warn "未检测到 Node.js >= 18，尝试安装..."
  if command_exists apt-get; then
    apt-get install -y nodejs npm >/dev/null 2>&1 || true
  elif command_exists dnf; then
    dnf install -y nodejs npm >/dev/null 2>&1 || true
  elif command_exists yum; then
    yum install -y nodejs npm >/dev/null 2>&1 || true
  fi

  if command_exists node && command_exists npm; then
    local major2
    major2="$(node -v 2>/dev/null | sed 's/^v//' | cut -d. -f1 || echo 0)"
    if [ "${major2:-0}" -ge 18 ]; then
      NODE_OK="1"
      return 0
    fi
  fi

  warn "系统源安装的 Node.js 版本可能偏低；如 wrangler 安装失败，请手动升级到 Node.js 18+。"
  NODE_OK="0"
}

ensure_wrangler() {
  ensure_node
  command_exists npm || { err "npm 不存在，无法安装 wrangler"; exit 1; }

  if command_exists wrangler; then
    return 0
  fi

  msg "安装 wrangler ..."
  npm install -g wrangler >/dev/null 2>&1 || {
    err "wrangler 安装失败，请先手动安装 Node.js 18+ 再重试"
    exit 1
  }
}

save_env() {
  cat > "$ENV_FILE" <<EOF
CORE=${CORE}
WK=${WK}
UUID=${UUID}
WORKER_NAME=${WORKER_NAME}
WORKER_HOST=${WORKER_HOST}
WS_BASE_PATH=${WS_BASE_PATH}
SOCKS_PORT=${SOCKS_PORT}
HTTP_PORT=${HTTP_PORT}
SNI=${SNI}
EOF
  chmod 600 "$ENV_FILE"
}

load_env() {
  [ -f "$ENV_FILE" ] || return 1
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  return 0
}

save_cf_env() {
  cat > "$CF_ENV_FILE" <<EOF
CF_API_TOKEN=${CF_API_TOKEN}
CF_ACCOUNT_ID=${CF_ACCOUNT_ID}
CF_WORKERS_SUBDOMAIN=${CF_WORKERS_SUBDOMAIN:-}
EOF
  chmod 600 "$CF_ENV_FILE"
}

load_cf_env() {
  [ -f "$CF_ENV_FILE" ] || return 1
  # shellcheck disable=SC1090
  source "$CF_ENV_FILE"
  return 0
}

random_lower() {
  tr -dc 'a-z0-9' </dev/urandom | head -c "${1:-8}"
}

generate_worker_name() {
  local raw="ge-$(random_lower 10)"
  raw="$(echo "$raw" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')"
  echo "${raw:0:30}"
}

fetch_latest_tag() {
  local repo="$1"
  curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" \
    | grep -oP '"tag_name"\s*:\s*"\K[^"]+' | head -n1
}

download_xray() {
  local version url tmpdir
  version="${XRAY_VERSION:-$(fetch_latest_tag "XTLS/Xray-core")}"
  [ -n "$version" ] || { err "获取 Xray 版本失败"; exit 1; }

  url="https://github.com/XTLS/Xray-core/releases/download/${version}/${XRAY_ASSET}"
  tmpdir="$(mktemp -d)"
  msg "下载 Xray: ${version}"
  curl -fsSL "$url" -o "${tmpdir}/xray.zip"
  unzip -qo "${tmpdir}/xray.zip" -d "$tmpdir"
  install -m 0755 "${tmpdir}/xray" "${BIN_DIR}/xray"
  rm -rf "$tmpdir"
}

download_singbox() {
  local version pure asset folder url tmpdir
  version="${SINGBOX_VERSION:-$(fetch_latest_tag "SagerNet/sing-box")}"
  [ -n "$version" ] || { err "获取 sing-box 版本失败"; exit 1; }

  pure="${version#v}"
  asset="sing-box-${pure}-linux-${ARCH}.tar.gz"
  folder="sing-box-${pure}-linux-${ARCH}"
  url="https://github.com/SagerNet/sing-box/releases/download/${version}/${asset}"
  tmpdir="$(mktemp -d)"

  msg "下载 sing-box: ${version}"
  curl -fsSL "$url" -o "${tmpdir}/sing-box.tar.gz"
  tar -xzf "${tmpdir}/sing-box.tar.gz" -C "$tmpdir"
  install -m 0755 "${tmpdir}/${folder}/sing-box" "${BIN_DIR}/sing-box"
  rm -rf "$tmpdir"
}

ensure_core_binary() {
  case "$CORE" in
    xray)
      [ -x "${BIN_DIR}/xray" ] || download_xray
      ;;
    singbox)
      [ -x "${BIN_DIR}/sing-box" ] || download_singbox
      ;;
    *)
      err "未知核心: $CORE"
      exit 1
      ;;
  esac
}

cf_api() {
  local method="$1"
  local url="$2"
  local data="${3:-}"

  if [ -n "$data" ]; then
    curl -fsSL -X "$method" "$url" \
      -H "Authorization: Bearer ${CF_API_TOKEN}" \
      -H "Content-Type: application/json" \
      --data "$data"
  else
    curl -fsSL -X "$method" "$url" \
      -H "Authorization: Bearer ${CF_API_TOKEN}"
  fi
}

prompt_cf_credentials_once() {
  if load_cf_env; then
    if [ -n "${CF_API_TOKEN:-}" ] && [ -n "${CF_ACCOUNT_ID:-}" ]; then
      return 0
    fi
  fi

  echo -e "\n${CYAN}首次需要 Cloudflare 凭据${NC}"
  read -rp "CF_API_TOKEN: " CF_API_TOKEN
  read -rp "CF_ACCOUNT_ID: " CF_ACCOUNT_ID
  [ -n "${CF_API_TOKEN:-}" ] || { err "CF_API_TOKEN 不能为空"; exit 1; }
  [ -n "${CF_ACCOUNT_ID:-}" ] || { err "CF_ACCOUNT_ID 不能为空"; exit 1; }
  save_cf_env
}

ensure_workers_subdomain() {
  load_cf_env || prompt_cf_credentials_once

  if [ -n "${CF_WORKERS_SUBDOMAIN:-}" ]; then
    return 0
  fi

  local api resp sub ok
  api="https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/workers/subdomain"
  resp="$(cf_api GET "$api" 2>/dev/null || true)"
  sub="$(echo "$resp" | jq -r '.result.subdomain // empty' 2>/dev/null || true)"

  if [ -n "$sub" ] && [ "$sub" != "null" ]; then
    CF_WORKERS_SUBDOMAIN="$sub"
    save_cf_env
    return 0
  fi

  sub="ge$(random_lower 8)"
  warn "未发现 workers.dev 子域，自动创建: ${sub}.workers.dev"
  resp="$(cf_api PUT "$api" "{\"subdomain\":\"${sub}\"}" 2>/dev/null || true)"
  ok="$(echo "$resp" | jq -r '.success // false' 2>/dev/null || echo false)"
  if [ "$ok" = "true" ]; then
    CF_WORKERS_SUBDOMAIN="$(echo "$resp" | jq -r '.result.subdomain // empty' 2>/dev/null || true)"
    [ -n "$CF_WORKERS_SUBDOMAIN" ] || CF_WORKERS_SUBDOMAIN="$sub"
    save_cf_env
    return 0
  fi

  err "自动创建 workers.dev 子域失败"
  echo "$resp" | jq . 2>/dev/null || echo "$resp"
  exit 1
}

init_proxy_map_if_missing() {
  [ -f "$PROXY_MAP_FILE" ] && return 0
  cat > "$PROXY_MAP_FILE" <<'EOF'
{
  "us": "",
  "sg": "",
  "jp": "",
  "hk": ""
}
EOF
  chmod 600 "$PROXY_MAP_FILE"
}

select_core_menu() {
  local current="${1:-singbox}"
  echo -e "\n${CYAN}选择核心${NC}"
  echo "  1) xray"
  echo "  2) singbox"
  read -rp "请输入 [1-2] (默认 2): " c
  case "${c:-2}" in
    1) CORE="xray" ;;
    2) CORE="singbox" ;;
    *) CORE="$current" ;;
  esac
}

select_wk_menu() {
  local current="${1:-us}"
  echo -e "\n${CYAN}选择 wk 地区${NC}"
  echo "  1) us  美国"
  echo "  2) sg  新加坡"
  echo "  3) jp  日本"
  echo "  4) hk  香港"
  read -rp "请输入 [1-4] (默认 1): " w
  case "${w:-1}" in
    1) WK="us" ;;
    2) WK="sg" ;;
    3) WK="jp" ;;
    4) WK="hk" ;;
    *) WK="$current" ;;
  esac
}

quick_install_choices() {
  load_env || true
  CORE="${CORE:-singbox}"
  WK="${WK:-us}"

  echo -e "\n${CYAN}快速安装模式${NC}"
  echo "  1) singbox + us"
  echo "  2) singbox + sg"
  echo "  3) xray + us"
  echo "  4) xray + sg"
  echo "  5) 自定义选择"
  read -rp "请输入 [1-5] (默认 1): " q

  case "${q:-1}" in
    1) CORE="singbox"; WK="us" ;;
    2) CORE="singbox"; WK="sg" ;;
    3) CORE="xray"; WK="us" ;;
    4) CORE="xray"; WK="sg" ;;
    5)
      select_core_menu "$CORE"
      select_wk_menu "$WK"
      ;;
    *)
      CORE="singbox"; WK="us" ;;
  esac
}

init_install_defaults() {
  load_env || true
  UUID="${UUID:-$(cat /proc/sys/kernel/random/uuid)}"
  WORKER_NAME="${WORKER_NAME:-$(generate_worker_name)}"
  WS_BASE_PATH="${WS_BASE_PATH:-/ws}"
  SOCKS_PORT="${SOCKS_PORT:-7892}"
  HTTP_PORT="${HTTP_PORT:-7893}"
}

write_worker_files() {
  init_proxy_map_if_missing
  local region_map
  region_map="$(cat "$PROXY_MAP_FILE" | jq -c .)"

  cat > "${WRK_DIR}/wrangler.toml" <<EOF
name = "${WORKER_NAME}"
main = "worker.mjs"
compatibility_date = "2026-03-12"
workers_dev = true
EOF

  cat > "${WRK_DIR}/worker.template.mjs" <<'EOF'
import { connect } from 'cloudflare:sockets';

const UUID = '__UUID__';
const REGION_PROXY_MAP = __REGION_MAP__;

function json(data, status = 200) {
  return new Response(JSON.stringify(data, null, 2), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' }
  });
}

function normalizeUUID(v) {
  return String(v || '').toLowerCase();
}

function bytesToUUID(bytes) {
  const h = [...bytes].map(v => v.toString(16).padStart(2, '0')).join('');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20, 32)}`;
}

function parseHostPort(v, defaultPort) {
  const s = String(v || '').trim();
  if (!s) return null;
  if (s.startsWith('[') && s.includes(']:')) {
    const idx = s.lastIndexOf(']:');
    return { host: s.slice(1, idx), port: Number(s.slice(idx + 2)) || defaultPort };
  }
  const parts = s.split(':');
  if (parts.length === 2 && /^\d+$/.test(parts[1])) {
    return { host: parts[0], port: Number(parts[1]) || defaultPort };
  }
  return { host: s, port: defaultPort };
}

function concatU8(a, b) {
  const out = new Uint8Array(a.length + b.length);
  out.set(a, 0);
  out.set(b, a.length);
  return out;
}

async function toU8(data) {
  if (data instanceof Uint8Array) return data;
  if (data instanceof ArrayBuffer) return new Uint8Array(data);
  if (ArrayBuffer.isView(data)) return new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
  if (typeof data === 'string') return new TextEncoder().encode(data);
  if (data && typeof data.arrayBuffer === 'function') return new Uint8Array(await data.arrayBuffer());
  throw new Error('unsupported websocket payload');
}

function parseAddress(buffer, type, offset) {
  if (type === 1) {
    if (buffer.length < offset + 4) throw new Error('invalid ipv4');
    return {
      host: `${buffer[offset]}.${buffer[offset + 1]}.${buffer[offset + 2]}.${buffer[offset + 3]}`,
      next: offset + 4
    };
  }
  if (type === 2) {
    const len = buffer[offset];
    const start = offset + 1;
    const end = start + len;
    if (buffer.length < end) throw new Error('invalid domain');
    return {
      host: new TextDecoder().decode(buffer.slice(start, end)),
      next: end
    };
  }
  if (type === 3) {
    if (buffer.length < offset + 16) throw new Error('invalid ipv6');
    const view = [];
    for (let i = 0; i < 8; i++) {
      const val = (buffer[offset + i * 2] << 8) | buffer[offset + i * 2 + 1];
      view.push(val.toString(16));
    }
    return {
      host: view.join(':'),
      next: offset + 16
    };
  }
  throw new Error(`unsupported address type: ${type}`);
}

function parseVlessHeader(u8) {
  if (u8.length < 24) throw new Error('header too short');

  const version = u8[0];
  const uuidBytes = u8.slice(1, 17);
  const user = bytesToUUID(uuidBytes);
  const optLen = u8[17];
  const cmdIndex = 18 + optLen;
  if (u8.length < cmdIndex + 4) throw new Error('invalid request');

  const command = u8[cmdIndex];
  const port = (u8[cmdIndex + 1] << 8) | u8[cmdIndex + 2];
  const addrType = u8[cmdIndex + 3];
  const addrInfo = parseAddress(u8, addrType, cmdIndex + 4);

  return {
    version,
    user,
    command,
    port,
    host: addrInfo.host,
    payloadIndex: addrInfo.next
  };
}

function buildVlessResponseHeader(version) {
  return new Uint8Array([version, 0]);
}

async function pipeSocketToWS(socket, ws, respHeader) {
  let sent = false;
  const reader = socket.readable.getReader();
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      if (!(value instanceof Uint8Array)) continue;
      if (!sent) {
        ws.send(concatU8(respHeader, value));
        sent = true;
      } else {
        ws.send(value);
      }
    }
  } catch (_) {
  } finally {
    try { reader.releaseLock(); } catch (_) {}
    try { ws.close(); } catch (_) {}
  }
}

function regionProxyFor(wk, port) {
  const key = String(wk || 'us').toLowerCase();
  const mapValue = REGION_PROXY_MAP[key];
  if (!mapValue) return null;
  if (Number(port) !== 443) return null;
  return parseHostPort(mapValue, port);
}

async function handleVlessWS(request) {
  const url = new URL(request.url);
  const wk = url.searchParams.get('wk') || 'us';

  const pair = new WebSocketPair();
  const client = pair[0];
  const server = pair[1];
  server.accept();

  let upstreamSocket = null;
  let upstreamWriter = null;
  let initialized = false;
  let responseHeader = null;

  const closeAll = async () => {
    try { if (upstreamWriter) await upstreamWriter.close(); } catch (_) {}
    try { if (upstreamSocket) await upstreamSocket.close(); } catch (_) {}
    try { server.close(); } catch (_) {}
  };

  server.addEventListener('message', async (event) => {
    try {
      const chunk = await toU8(event.data);

      if (!initialized) {
        const req = parseVlessHeader(chunk);
        if (normalizeUUID(req.user) !== normalizeUUID(UUID)) {
          server.close(1008, 'invalid uuid');
          return;
        }
        if (req.command !== 1) {
          server.close(1003, 'only tcp supported');
          return;
        }

        const proxy = regionProxyFor(wk, req.port);
        const dialHost = proxy?.host || req.host;
        const dialPort = proxy?.port || req.port;

        upstreamSocket = connect({
          hostname: dialHost,
          port: dialPort
        });
        upstreamWriter = upstreamSocket.writable.getWriter();
        responseHeader = buildVlessResponseHeader(req.version);
        initialized = true;

        const remain = chunk.slice(req.payloadIndex);
        if (remain.length > 0) {
          await upstreamWriter.write(remain);
        }

        pipeSocketToWS(upstreamSocket, server, responseHeader);
        return;
      }

      await upstreamWriter.write(chunk);
    } catch (_) {
      await closeAll();
    }
  });

  server.addEventListener('close', async () => {
    await closeAll();
  });

  server.addEventListener('error', async () => {
    await closeAll();
  });

  return new Response(null, { status: 101, webSocket: client });
}

export default {
  async fetch(request) {
    const upgrade = request.headers.get('Upgrade');

    if (upgrade && upgrade.toLowerCase() === 'websocket') {
      return handleVlessWS(request);
    }

    const url = new URL(request.url);
    if (url.pathname === '/health') {
      return json({
        ok: true,
        wk: url.searchParams.get('wk') || 'us',
        region_proxy_map: REGION_PROXY_MAP,
        note: 'wk 仅在对应地区映射已填写时才会改为连接该 proxy host'
      });
    }

    return new Response('cf-egress worker is running', {
      status: 200,
      headers: { 'content-type': 'text/plain; charset=utf-8' }
    });
  }
};
EOF

  sed \
    -e "s|__UUID__|${UUID}|g" \
    -e "s|__REGION_MAP__|${region_map}|g" \
    "${WRK_DIR}/worker.template.mjs" > "${WRK_DIR}/worker.mjs"
}

deploy_worker() {
  load_cf_env || prompt_cf_credentials_once
  ensure_workers_subdomain
  ensure_wrangler
  write_worker_files

  export CLOUDFLARE_API_TOKEN="${CF_API_TOKEN}"
  export CLOUDFLARE_ACCOUNT_ID="${CF_ACCOUNT_ID}"
  export CF_API_TOKEN="${CF_API_TOKEN}"
  export CF_ACCOUNT_ID="${CF_ACCOUNT_ID}"

  msg "部署 Worker: ${WORKER_NAME}"
  (
    cd "$WRK_DIR"
    wrangler deploy >/tmp/cfeg-wrangler.log 2>&1 || {
      cat /tmp/cfeg-wrangler.log
      exit 1
    }
  )

  WORKER_HOST="${WORKER_NAME}.${CF_WORKERS_SUBDOMAIN}.workers.dev"
  SNI="${WORKER_HOST}"
  save_env
  msg "Worker 已部署: ${WORKER_HOST}"
}

write_xray_config() {
  local ws_path="${WS_BASE_PATH}?wk=${WK}"
  cat > "$CONFIG_FILE" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "socks-in",
      "listen": "127.0.0.1",
      "port": ${SOCKS_PORT},
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    },
    {
      "tag": "http-in",
      "listen": "127.0.0.1",
      "port": ${HTTP_PORT},
      "protocol": "http",
      "settings": {},
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
  ],
  "outbounds": [
    {
      "tag": "proxy",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "${WORKER_HOST}",
            "port": 443,
            "users": [
              {
                "id": "${UUID}",
                "encryption": "none"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "serverName": "${SNI}",
          "allowInsecure": false
        },
        "wsSettings": {
          "path": "${ws_path}",
          "headers": {
            "Host": "${WORKER_HOST}"
          }
        }
      }
    },
    {
      "tag": "direct",
      "protocol": "freedom"
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "domain": [
          "domain:google.com",
          "domain:googleapis.com",
          "domain:gstatic.com",
          "domain:googlevideo.com",
          "domain:ggpht.com",
          "domain:withgoogle.com",
          "full:gemini.google.com",
          "full:ai.google.dev",
          "full:generativelanguage.googleapis.com",
          "full:makersuite.google.com",
          "full:labs.google"
        ],
        "outboundTag": "proxy"
      }
    ]
  }
}
EOF
}

write_singbox_config() {
  local ws_path="${WS_BASE_PATH}?wk=${WK}"
  cat > "$CONFIG_FILE" <<EOF
{
  "log": {
    "level": "warn"
  },
  "inbounds": [
    {
      "type": "socks",
      "tag": "socks-in",
      "listen": "127.0.0.1",
      "listen_port": ${SOCKS_PORT},
      "sniff": true,
      "sniff_override_destination": true
    },
    {
      "type": "http",
      "tag": "http-in",
      "listen": "127.0.0.1",
      "listen_port": ${HTTP_PORT}
    }
  ],
  "outbounds": [
    {
      "type": "vless",
      "tag": "proxy",
      "server": "${WORKER_HOST}",
      "server_port": 443,
      "uuid": "${UUID}",
      "flow": "",
      "tls": {
        "enabled": true,
        "server_name": "${SNI}"
      },
      "transport": {
        "type": "ws",
        "path": "${ws_path}",
        "headers": {
          "Host": "${WORKER_HOST}"
        }
      }
    },
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "auto_detect_interface": true,
    "rules": [
      {
        "domain_suffix": [
          "google.com",
          "googleapis.com",
          "gstatic.com",
          "googlevideo.com",
          "ggpht.com",
          "withgoogle.com"
        ],
        "outbound": "proxy"
      },
      {
        "domain": [
          "gemini.google.com",
          "ai.google.dev",
          "generativelanguage.googleapis.com",
          "makersuite.google.com",
          "labs.google"
        ],
        "outbound": "proxy"
      }
    ],
    "final": "direct"
  }
}
EOF
}

render_client_config() {
  load_env || { err "未找到环境文件"; exit 1; }
  case "$CORE" in
    xray) write_xray_config ;;
    singbox) write_singbox_config ;;
    *) err "未知核心: $CORE"; exit 1 ;;
  esac
}

write_launcher() {
  cat > "${BIN_DIR}/start.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source /etc/cf-egress/env

case "${CORE}" in
  xray)
    exec /opt/cf-egress/bin/xray run -c /etc/cf-egress/config.json
    ;;
  singbox)
    exec /opt/cf-egress/bin/sing-box run -c /etc/cf-egress/config.json
    ;;
  *)
    echo "Unknown CORE=${CORE}" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "${BIN_DIR}/start.sh"
}

write_service() {
  cat > "/etc/systemd/system/${SERVICE_NAME}" <<EOF
[Unit]
Description=CF Egress Sidecar
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${BIN_DIR}/start.sh
WorkingDirectory=${APP_ROOT}
Restart=always
RestartSec=2
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable "${SERVICE_NAME}" >/dev/null 2>&1 || true
}

write_ctl() {
  cat > "${CTL_BIN}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
SETUP="/usr/local/bin/cf-egress-setup"
SELF_URL="https://raw.githubusercontent.com/ctsunny/g-everywhere/main/warp-setup.sh"
SERVICE="cf-egress.service"
ENV_FILE="/etc/cf-egress/env"

load_env() {
  [ -f "$ENV_FILE" ] || { echo "未安装"; exit 1; }
  # shellcheck disable=SC1090
  source "$ENV_FILE"
}

case "${1:-}" in
  menu)
    if [ -x "$SETUP" ]; then exec bash "$SETUP"; else curl -fsSL "$SELF_URL" | bash; fi
    ;;
  start) systemctl start "$SERVICE" ;;
  stop) systemctl stop "$SERVICE" ;;
  restart) systemctl restart "$SERVICE" ;;
  status) systemctl --no-pager -l status "$SERVICE" || true ;;
  show)
    load_env
    echo "CORE=$CORE"
    echo "WK=$WK"
    echo "UUID=$UUID"
    echo "WORKER_NAME=$WORKER_NAME"
    echo "WORKER_HOST=$WORKER_HOST"
    echo "SOCKS=127.0.0.1:$SOCKS_PORT"
    echo "HTTP=127.0.0.1:$HTTP_PORT"
    ;;
  switch)
    if [ -x "$SETUP" ]; then exec bash "$SETUP" switch "${2:-}"; else curl -fsSL "$SELF_URL" | bash -s -- switch "${2:-}"; fi
    ;;
  core)
    if [ -x "$SETUP" ]; then exec bash "$SETUP" switch-core "${2:-}"; else curl -fsSL "$SELF_URL" | bash -s -- switch-core "${2:-}"; fi
    ;;
  redeploy)
    if [ -x "$SETUP" ]; then exec bash "$SETUP" redeploy; else curl -fsSL "$SELF_URL" | bash -s -- redeploy; fi
    ;;
  test)
    load_env
    echo "== Worker health =="
    curl -s --max-time 15 "https://${WORKER_HOST}/health?wk=${WK}" || true
    echo
    echo
    echo "== Google =="
    curl --socks5-hostname "127.0.0.1:${SOCKS_PORT}" -I -L --max-time 20 https://www.google.com 2>/dev/null | head -n 6 || true
    echo
    echo "== Gemini =="
    curl --socks5-hostname "127.0.0.1:${SOCKS_PORT}" -I -L --max-time 20 https://gemini.google.com 2>/dev/null | head -n 6 || true
    ;;
  proxy-map)
    echo "/etc/cf-egress/worker-proxy-map.json"
    ;;
  uninstall)
    if [ -x "$SETUP" ]; then exec bash "$SETUP" uninstall; else curl -fsSL "$SELF_URL" | bash -s -- uninstall; fi
    ;;
  *)
    cat <<HLP
用法:
  cfeg menu
  cfeg start|stop|restart|status
  cfeg show
  cfeg switch us|sg|jp|hk
  cfeg core xray|singbox
  cfeg redeploy
  cfeg test
  cfeg proxy-map
  cfeg uninstall
HLP
    ;;
esac
EOF
  chmod +x "${CTL_BIN}"

  if [ -r "${BASH_SOURCE[0]}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    cp "${BASH_SOURCE[0]}" "${SETUP_BIN}" 2>/dev/null || true
  else
    curl -fsSL "${SELF_URL}" -o "${SETUP_BIN}" 2>/dev/null || true
  fi
  chmod +x "${SETUP_BIN}" 2>/dev/null || true
}

restart_service() {
  systemctl restart "${SERVICE_NAME}"
  sleep 2
}

show_status() {
  systemctl --no-pager -l status "${SERVICE_NAME}" || true
}

show_current_config() {
  load_env || { warn "尚未安装"; return 1; }
  echo -e "\n${CYAN}当前配置${NC}"
  echo "CORE=$CORE"
  echo "WK=$WK"
  echo "UUID=$UUID"
  echo "WORKER_NAME=$WORKER_NAME"
  echo "WORKER_HOST=$WORKER_HOST"
  echo "WS_BASE_PATH=$WS_BASE_PATH"
  echo "SOCKS=127.0.0.1:$SOCKS_PORT"
  echo "HTTP=127.0.0.1:$HTTP_PORT"
  echo "PROXY_MAP_FILE=$PROXY_MAP_FILE"
}

test_sites() {
  load_env || { warn "尚未安装"; return 1; }
  echo -e "\n${CYAN}Worker 健康检查${NC}"
  curl -s --max-time 15 "https://${WORKER_HOST}/health?wk=${WK}" || true
  echo -e "\n\n${CYAN}Google 测试${NC}"
  curl --socks5-hostname "127.0.0.1:${SOCKS_PORT}" -I -L --max-time 20 https://www.google.com 2>/dev/null | head -n 6 || true
  echo -e "\n${CYAN}Gemini 测试${NC}"
  curl --socks5-hostname "127.0.0.1:${SOCKS_PORT}" -I -L --max-time 20 https://gemini.google.com 2>/dev/null | head -n 6 || true
  echo ""
}

install_or_reinstall() {
  prompt_cf_credentials_once
  quick_install_choices
  init_install_defaults
  ensure_workers_subdomain
  init_proxy_map_if_missing

  read -rp "UUID (默认自动生成，回车使用当前): " UUID_INPUT
  UUID="${UUID_INPUT:-$UUID}"

  read -rp "本地 SOCKS5 端口 (默认 ${SOCKS_PORT}): " SOCKS_PORT_INPUT
  SOCKS_PORT="${SOCKS_PORT_INPUT:-$SOCKS_PORT}"

  read -rp "本地 HTTP 端口 (默认 ${HTTP_PORT}): " HTTP_PORT_INPUT
  HTTP_PORT="${HTTP_PORT_INPUT:-$HTTP_PORT}"

  read -rp "WS 路径前缀 (默认 ${WS_BASE_PATH}): " WS_BASE_PATH_INPUT
  WS_BASE_PATH="${WS_BASE_PATH_INPUT:-$WS_BASE_PATH}"

  read -rp "自动生成 Worker 名称 (默认 ${WORKER_NAME}): " WORKER_NAME_INPUT
  WORKER_NAME="${WORKER_NAME_INPUT:-$WORKER_NAME}"
  WORKER_NAME="$(echo "$WORKER_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')"
  WORKER_NAME="${WORKER_NAME:0:63}"
  [ -n "$WORKER_NAME" ] || WORKER_NAME="$(generate_worker_name)"

  save_env
  ensure_core_binary
  deploy_worker
  render_client_config
  write_launcher
  write_service
  write_ctl
  restart_service

  echo -e "\n${GREEN}安装/更新完成${NC}"
  echo -e "核心         : ${YELLOW}${CORE}${NC}"
  echo -e "wk           : ${YELLOW}${WK}${NC}"
  echo -e "Worker 名称  : ${YELLOW}${WORKER_NAME}${NC}"
  echo -e "Worker 域名  : ${YELLOW}${WORKER_HOST}${NC}"
  echo -e "SOCKS5       : ${YELLOW}127.0.0.1:${SOCKS_PORT}${NC}"
  echo -e "HTTP         : ${YELLOW}127.0.0.1:${HTTP_PORT}${NC}"
  echo -e "代理映射文件 : ${YELLOW}${PROXY_MAP_FILE}${NC}"
  echo -e "管理命令     : ${YELLOW}cfeg menu | cfeg show | cfeg test | cfeg redeploy${NC}\n"
}

switch_wk() {
  load_env || { err "尚未安装"; return 1; }
  case "${1:-}" in
    us|sg|jp|hk) WK="$1" ;;
    *) select_wk_menu "$WK" ;;
  esac
  save_env
  render_client_config
  restart_service
  msg "已切换 wk=${WK}"
}

switch_core() {
  load_env || { err "尚未安装"; return 1; }
  case "${1:-}" in
    xray|singbox) CORE="$1" ;;
    *) select_core_menu "$CORE" ;;
  esac
  save_env
  ensure_core_binary
  render_client_config
  write_launcher
  restart_service
  msg "已切换核心 ${CORE}"
}

redeploy_worker() {
  load_env || { err "尚未安装"; return 1; }
  load_cf_env || prompt_cf_credentials_once
  deploy_worker
  render_client_config
  restart_service
  msg "Worker 已重新部署并重启本地客户端"
}

edit_proxy_map() {
  init_proxy_map_if_missing
  echo -e "\n${CYAN}当前地区代理映射文件${NC}: ${PROXY_MAP_FILE}"
  cat "$PROXY_MAP_FILE"
  echo ""
  echo "示例:"
  echo '  {'
  echo '    "us": "104.16.1.1:443",'
  echo '    "sg": "104.16.2.2:443",'
  echo '    "jp": "",'
  echo '    "hk": ""'
  echo '  }'
  echo ""
  if command_exists nano; then
    read -rp "是否用 nano 编辑? [Y/n]: " yn
    if [[ "${yn:-Y}" =~ ^[Yy]$ ]]; then
      nano "$PROXY_MAP_FILE"
    fi
  else
    warn "未安装 nano，请手动编辑: $PROXY_MAP_FILE"
  fi
}

do_uninstall() {
  systemctl disable --now "${SERVICE_NAME}" >/dev/null 2>&1 || true
  rm -f "/etc/systemd/system/${SERVICE_NAME}"
  systemctl daemon-reload
  rm -rf "$APP_ROOT" "$ETC_DIR" "$LOG_DIR" "$RUN_DIR"
  rm -f "$CTL_BIN" "$SETUP_BIN"
  msg "已卸载，未触碰 3x-ui"
}

show_menu() {
  while true; do
    banner
    echo -e " ${YELLOW}请选择操作${NC}\n"
    echo "  1) 安装 / 重装"
    echo "  2) 切换核心 xray / singbox"
    echo "  3) 切换地区 wk=us/sg/jp/hk"
    echo "  4) 编辑地区代理映射"
    echo "  5) 重新部署 Worker"
    echo "  6) 启动服务"
    echo "  7) 停止服务"
    echo "  8) 重启服务"
    echo "  9) 查看状态"
    echo " 10) 查看当前配置"
    echo " 11) 测试 Worker / Google / Gemini"
    echo " 12) 卸载"
    echo "  0) 退出"
    echo ""
    read -rp "请输入选项 [0-12]: " choice
    echo ""

    case "${choice:-}" in
      1) install_or_reinstall ;;
      2) switch_core ;;
      3) switch_wk ;;
      4) edit_proxy_map ;;
      5) redeploy_worker ;;
      6) systemctl start "${SERVICE_NAME}" && msg "已启动" || warn "启动失败" ;;
      7) systemctl stop "${SERVICE_NAME}" && msg "已停止" || warn "停止失败" ;;
      8) systemctl restart "${SERVICE_NAME}" && msg "已重启" || warn "重启失败" ;;
      9) show_status ;;
      10) show_current_config ;;
      11) test_sites ;;
      12)
        read -rp "确认卸载? [y/N]: " yn
        [[ "${yn:-N}" =~ ^[Yy]$ ]] && do_uninstall
        ;;
      0) exit 0 ;;
      *) warn "无效选项" ;;
    esac

    echo ""
    read -rp "按 Enter 返回菜单..." _
  done
}

main() {
  need_root
  detect_arch
  mkdirs
  install_deps

  case "${1:-menu}" in
    install) install_or_reinstall ;;
    switch) switch_wk "${2:-}" ;;
    switch-core) switch_core "${2:-}" ;;
    redeploy) redeploy_worker ;;
    uninstall) do_uninstall ;;
    menu|"") show_menu ;;
    *) show_menu ;;
  esac
}

main "$@"
