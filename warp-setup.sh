#!/usr/bin/env bash
set -euo pipefail

APP_NAME="cf-egress"
APP_ROOT="/opt/${APP_NAME}"
BIN_DIR="${APP_ROOT}/bin"
ETC_DIR="/etc/${APP_NAME}"
RUN_DIR="/var/lib/${APP_NAME}"
LOG_DIR="/var/log/${APP_NAME}"
SETUP_BIN="/usr/local/bin/${APP_NAME}-setup"
CTL_BIN="/usr/local/bin/cfeg"
SERVICE_NAME="${APP_NAME}.service"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; NC='\033[0m'; BOLD='\033[1m'

msg()  { echo -e "${GREEN}[$APP_NAME] $*${NC}"; }
warn() { echo -e "${YELLOW}[$APP_NAME] $*${NC}"; }
err()  { echo -e "${RED}[$APP_NAME] $*${NC}" >&2; }

need_root() {
  [ "$(id -u)" -eq 0 ] || { err "请用 root 运行"; exit 1; }
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) ARCH="amd64"; XRAY_ASSET="Xray-linux-64.zip" ;;
    aarch64|arm64) ARCH="arm64"; XRAY_ASSET="Xray-linux-arm64-v8a.zip" ;;
    *)
      err "暂不支持架构: $(uname -m)"
      exit 1
      ;;
  esac
}

install_deps() {
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y >/dev/null 2>&1
    apt-get install -y curl wget unzip tar jq ca-certificates systemd >/dev/null 2>&1
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y curl wget unzip tar jq ca-certificates systemd >/dev/null 2>&1
  elif command -v yum >/dev/null 2>&1; then
    yum install -y curl wget unzip tar jq ca-certificates systemd >/dev/null 2>&1
  else
    err "未识别包管理器"
    exit 1
  fi
}

mkdirs() {
  mkdir -p "$BIN_DIR" "$ETC_DIR" "$RUN_DIR" "$LOG_DIR"
}

fetch_latest_tag() {
  local repo="$1"
  curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" \
    | grep -oP '"tag_name":\s*"\K[^"]+' | head -n1
}

download_xray() {
  local version tmpdir url
  version="${XRAY_VERSION:-$(fetch_latest_tag "XTLS/Xray-core")}"
  [ -n "$version" ] || { err "无法获取 Xray 版本"; exit 1; }

  tmpdir="$(mktemp -d)"
  url="https://github.com/XTLS/Xray-core/releases/download/${version}/${XRAY_ASSET}"

  msg "下载 Xray: ${version}"
  curl -fsSL "$url" -o "${tmpdir}/xray.zip"
  unzip -qo "${tmpdir}/xray.zip" -d "$tmpdir"
  install -m 0755 "${tmpdir}/xray" "${BIN_DIR}/xray"
  rm -rf "$tmpdir"
}

download_singbox() {
  local version pure tmpdir url asset folder
  version="${SINGBOX_VERSION:-$(fetch_latest_tag "SagerNet/sing-box")}"
  [ -n "$version" ] || { err "无法获取 sing-box 版本"; exit 1; }

  pure="${version#v}"
  asset="sing-box-${pure}-linux-${ARCH}.tar.gz"
  folder="sing-box-${pure}-linux-${ARCH}"
  tmpdir="$(mktemp -d)"
  url="https://github.com/SagerNet/sing-box/releases/download/${version}/${asset}"

  msg "下载 sing-box: ${version}"
  curl -fsSL "$url" -o "${tmpdir}/sing-box.tar.gz"
  tar -xzf "${tmpdir}/sing-box.tar.gz" -C "$tmpdir"
  install -m 0755 "${tmpdir}/${folder}/sing-box" "${BIN_DIR}/sing-box"
  rm -rf "$tmpdir"
}

prompt_config() {
  local default_core="${1:-singbox}"

  read -rp "选择核心 [xray/singbox] (默认 ${default_core}): " CORE
  CORE="${CORE:-$default_core}"
  case "$CORE" in
    xray|singbox) ;;
    *) err "核心只能是 xray 或 singbox"; exit 1 ;;
  esac

  read -rp "Worker 域名 (例如 abc.workers.dev 或 你的自定义域名): " WORKER_HOST
  [ -n "$WORKER_HOST" ] || { err "Worker 域名不能为空"; exit 1; }

  read -rp "VLESS UUID: " UUID
  [ -n "$UUID" ] || { err "UUID 不能为空"; exit 1; }

  read -rp "WS 路径前缀 (默认 /ws): " WS_BASE_PATH
  WS_BASE_PATH="${WS_BASE_PATH:-/ws}"

  read -rp "wk 地区参数 [us/sg/jp/hk] (默认 us): " WK
  WK="${WK:-us}"

  read -rp "本地 SOCKS5 端口 (默认 7892): " SOCKS_PORT
  SOCKS_PORT="${SOCKS_PORT:-7892}"

  read -rp "本地 HTTP 端口 (默认 7893): " HTTP_PORT
  HTTP_PORT="${HTTP_PORT:-7893}"

  read -rp "TLS SNI (默认与 Worker 域名相同): " SNI
  SNI="${SNI:-$WORKER_HOST}"

  cat > "${ETC_DIR}/env" <<EOF
CORE=${CORE}
WORKER_HOST=${WORKER_HOST}
UUID=${UUID}
WS_BASE_PATH=${WS_BASE_PATH}
WK=${WK}
SOCKS_PORT=${SOCKS_PORT}
HTTP_PORT=${HTTP_PORT}
SNI=${SNI}
EOF

  echo "${CORE}" > "${ETC_DIR}/core"
}

load_env() {
  [ -f "${ETC_DIR}/env" ] || { err "缺少 ${ETC_DIR}/env"; exit 1; }
  # shellcheck disable=SC1090
  source "${ETC_DIR}/env"
  WS_PATH="${WS_BASE_PATH}?wk=${WK}"
}

write_xray_config() {
  cat > "${ETC_DIR}/config.json" <<EOF
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
                "encryption": "none",
                "level": 0
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
          "path": "${WS_PATH}",
          "headers": {
            "Host": "${WORKER_HOST}"
          }
        }
      }
    },
    {
      "tag": "direct",
      "protocol": "freedom"
    },
    {
      "tag": "block",
      "protocol": "blackhole"
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "domain": [
          "geosite:google",
          "domain:gemini.google.com",
          "domain:ai.google.dev",
          "domain:generativelanguage.googleapis.com",
          "domain:makerSuite.google.com",
          "domain:labs.google"
        ],
        "outboundTag": "proxy"
      },
      {
        "type": "field",
        "ip": [
          "8.8.8.8/32",
          "8.8.4.4/32"
        ],
        "outboundTag": "proxy"
      }
    ]
  }
}
EOF
}

write_singbox_config() {
  cat > "${ETC_DIR}/config.json" <<EOF
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
      "packet_encoding": "xudp",
      "tls": {
        "enabled": true,
        "server_name": "${SNI}"
      },
      "transport": {
        "type": "ws",
        "path": "${WS_PATH}",
        "headers": {
          "Host": "${WORKER_HOST}"
        }
      }
    },
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
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

render_config() {
  load_env
  case "$CORE" in
    xray) write_xray_config ;;
    singbox) write_singbox_config ;;
    *) err "未知核心: $CORE"; exit 1 ;;
  esac
  msg "配置已写入 ${ETC_DIR}/config.json"
}

write_service() {
  load_env
  local exec_bin
  case "$CORE" in
    xray) exec_bin="${BIN_DIR}/xray run -c ${ETC_DIR}/config.json" ;;
    singbox) exec_bin="${BIN_DIR}/sing-box run -c ${ETC_DIR}/config.json" ;;
    *) err "未知核心: $CORE"; exit 1 ;;
  esac

  cat > "/etc/systemd/system/${SERVICE_NAME}" <<EOF
[Unit]
Description=CF Egress Sidecar (${CORE})
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${exec_bin}
Restart=always
RestartSec=2
WorkingDirectory=${APP_ROOT}
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
ENV_FILE="/etc/cf-egress/env"
SERVICE="cf-egress.service"

show_help() {
  cat <<HLP
用法:
  cfeg install [xray|singbox]
  cfeg switch [us|sg|jp|hk]
  cfeg start
  cfeg stop
  cfeg restart
  cfeg status
  cfeg show
  cfeg test
  cfeg uninstall
HLP
}

load_env() {
  [ -f "$ENV_FILE" ] || { echo "未安装"; exit 1; }
  # shellcheck disable=SC1090
  source "$ENV_FILE"
}

case "${1:-}" in
  install)
    bash "$SETUP" install "${2:-singbox}"
    ;;
  switch)
    [ -n "${2:-}" ] || { echo "缺少地区参数"; exit 1; }
    bash "$SETUP" switch "$2"
    ;;
  start)
    systemctl start "$SERVICE"
    ;;
  stop)
    systemctl stop "$SERVICE"
    ;;
  restart)
    systemctl restart "$SERVICE"
    ;;
  status)
    systemctl --no-pager -l status "$SERVICE" || true
    ;;
  show)
    load_env
    echo "CORE=$CORE"
    echo "WORKER_HOST=$WORKER_HOST"
    echo "WK=$WK"
    echo "SOCKS=127.0.0.1:$SOCKS_PORT"
    echo "HTTP=127.0.0.1:$HTTP_PORT"
    ;;
  test)
    load_env
    echo "== Google =="
    curl --socks5-hostname "127.0.0.1:${SOCKS_PORT}" -I -L --max-time 20 https://www.google.com 2>/dev/null | head -n 5 || true
    echo
    echo "== Gemini =="
    curl --socks5-hostname "127.0.0.1:${SOCKS_PORT}" -I -L --max-time 20 https://gemini.google.com 2>/dev/null | head -n 5 || true
    ;;
  uninstall)
    bash "$SETUP" uninstall
    ;;
  *)
    show_help
    ;;
esac
EOF
  chmod +x "${CTL_BIN}"
  cp "$0" "${SETUP_BIN}"
  chmod +x "${SETUP_BIN}"
}

start_service() {
  systemctl restart "${SERVICE_NAME}"
  sleep 2
  systemctl --no-pager -l status "${SERVICE_NAME}" || true
}

install_core() {
  load_env
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

do_install() {
  local selected="${1:-singbox}"
  mkdirs
  prompt_config "$selected"
  install_core
  render_config
  write_service
  write_ctl
  start_service

  echo
  msg "安装完成"
  echo -e "  核心     : ${GREEN}$(cat "${ETC_DIR}/core")${NC}"
  echo -e "  SOCKS5   : ${GREEN}127.0.0.1:$(grep '^SOCKS_PORT=' "${ETC_DIR}/env" | cut -d= -f2)${NC}"
  echo -e "  HTTP     : ${GREEN}127.0.0.1:$(grep '^HTTP_PORT=' "${ETC_DIR}/env" | cut -d= -f2)${NC}"
  echo -e "  管理命令 : ${GREEN}cfeg show | cfeg switch us | cfeg test${NC}"
  echo -e "  说明     : ${YELLOW}此脚本不会改动 3x-ui 的 x-ui 服务、配置目录或端口${NC}"
}

do_switch() {
  local new_wk="${1:-}"
  [ -n "$new_wk" ] || { err "请指定 wk，例如 us/sg/jp/hk"; exit 1; }
  load_env

  sed -i "s/^WK=.*/WK=${new_wk}/" "${ETC_DIR}/env"
  render_config
  systemctl restart "${SERVICE_NAME}"
  msg "已切换 wk=${new_wk}"
}

do_uninstall() {
  systemctl disable --now "${SERVICE_NAME}" >/dev/null 2>&1 || true
  rm -f "/etc/systemd/system/${SERVICE_NAME}"
  systemctl daemon-reload
  rm -rf "${APP_ROOT}" "${ETC_DIR}" "${RUN_DIR}" "${LOG_DIR}"
  rm -f "${SETUP_BIN}" "${CTL_BIN}"
  msg "已卸载（未触碰 3x-ui）"
}

main() {
  need_root
  detect_arch
  install_deps
  mkdirs

  case "${1:-}" in
    install)
      do_install "${2:-singbox}"
      ;;
    switch)
      do_switch "${2:-}"
      ;;
    render)
      render_config
      ;;
    uninstall)
      do_uninstall
      ;;
    *)
      cat <<EOF
用法:
  bash $0 install [xray|singbox]
  bash $0 switch [us|sg|jp|hk]
  bash $0 uninstall
EOF
      ;;
  esac
}

main "$@"
