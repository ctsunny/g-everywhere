#!/usr/bin/env bash
set -euo pipefail

APP_NAME="cf-egress"
APP_ROOT="/opt/${APP_NAME}"
BIN_DIR="${APP_ROOT}/bin"
ETC_DIR="/etc/${APP_NAME}"
LOG_DIR="/var/log/${APP_NAME}"
RUN_DIR="/var/lib/${APP_NAME}"

SERVICE_NAME="${APP_NAME}.service"
CTL_BIN="/usr/local/bin/cfeg"
SETUP_BIN="/usr/local/bin/${APP_NAME}-setup"
SELF_URL="https://raw.githubusercontent.com/ctsunny/g-everywhere/main/warp-setup.sh"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'
BOLD='\033[1m'; NC='\033[0m'

ARCH=""
XRAY_ASSET=""

banner() {
  clear 2>/dev/null || true
  echo -e "${BOLD}${BLUE}"
  echo "   ______ ______   ______                 "
  echo "  / ____// ____/  / ____/____ _ ____ ___  "
  echo " / /    / /_     / __/  / __ \`// __ \`__ \\ "
  echo "/ /___ / __/    / /___ / /_/ // / / / / / "
  echo "\____//_/      /_____/ \__, //_/ /_/ /_/  "
  echo "                      /____/               "
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

install_deps() {
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y >/dev/null 2>&1
    apt-get install -y curl wget unzip tar jq ca-certificates systemd procps >/dev/null 2>&1
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y curl wget unzip tar jq ca-certificates systemd procps-ng >/dev/null 2>&1
  elif command -v yum >/dev/null 2>&1; then
    yum install -y curl wget unzip tar jq ca-certificates systemd procps-ng >/dev/null 2>&1
  else
    err "未识别包管理器"
    exit 1
  fi
}

mkdirs() {
  mkdir -p "$BIN_DIR" "$ETC_DIR" "$LOG_DIR" "$RUN_DIR"
}

env_file() {
  echo "${ETC_DIR}/env"
}

config_file() {
  echo "${ETC_DIR}/config.json"
}

load_env() {
  [ -f "$(env_file)" ] || return 1
  # shellcheck disable=SC1090
  source "$(env_file)"
  return 0
}

save_env() {
  cat > "$(env_file)" <<EOF
CORE=${CORE}
WORKER_HOST=${WORKER_HOST}
UUID=${UUID}
WS_BASE_PATH=${WS_BASE_PATH}
WK=${WK}
SOCKS_PORT=${SOCKS_PORT}
HTTP_PORT=${HTTP_PORT}
SNI=${SNI}
EOF
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

select_core_menu() {
  local current="${1:-}"
  echo -e "\n${CYAN}选择核心${NC}"
  echo "  1) xray"
  echo "  2) singbox"
  read -rp "请输入 [1-2] ${current:+(当前: $current)}: " c
  case "${c:-}" in
    1) CORE="xray" ;;
    2|"") CORE="${current:-singbox}" ;;
    *) warn "无效，使用 ${current:-singbox}"; CORE="${current:-singbox}" ;;
  esac
}

select_wk_menu() {
  local current="${1:-us}"
  echo -e "\n${CYAN}选择出口地区 wk${NC}"
  echo "  1) us  美国"
  echo "  2) sg  新加坡"
  echo "  3) jp  日本"
  echo "  4) hk  香港"
  read -rp "请输入 [1-4] ${current:+(当前: $current)}: " w
  case "${w:-}" in
    1) WK="us" ;;
    2) WK="sg" ;;
    3) WK="jp" ;;
    4) WK="hk" ;;
    "") WK="$current" ;;
    *) warn "无效，使用 ${current}"; WK="$current" ;;
  esac
}

prompt_install_info() {
  local old_host="" old_uuid="" old_path="/ws" old_socks="7892" old_http="7893" old_sni="" old_core="singbox" old_wk="us"

  if load_env; then
    old_host="${WORKER_HOST:-}"
    old_uuid="${UUID:-}"
    old_path="${WS_BASE_PATH:-/ws}"
    old_socks="${SOCKS_PORT:-7892}"
    old_http="${HTTP_PORT:-7893}"
    old_sni="${SNI:-${WORKER_HOST:-}}"
    old_core="${CORE:-singbox}"
    old_wk="${WK:-us}"
  fi

  select_core_menu "$old_core"
  select_wk_menu "$old_wk"

  read -rp "Worker 域名 ${old_host:+(当前: $old_host)}: " WORKER_HOST_INPUT
  WORKER_HOST="${WORKER_HOST_INPUT:-$old_host}"
  [ -n "${WORKER_HOST}" ] || { err "Worker 域名不能为空"; exit 1; }

  read -rp "UUID ${old_uuid:+(当前: $old_uuid)}: " UUID_INPUT
  UUID="${UUID_INPUT:-$old_uuid}"
  [ -n "${UUID}" ] || { err "UUID 不能为空"; exit 1; }

  read -rp "WS 路径前缀 (默认 ${old_path}): " WS_BASE_PATH_INPUT
  WS_BASE_PATH="${WS_BASE_PATH_INPUT:-$old_path}"

  read -rp "本地 SOCKS5 端口 (默认 ${old_socks}): " SOCKS_PORT_INPUT
  SOCKS_PORT="${SOCKS_PORT_INPUT:-$old_socks}"

  read -rp "本地 HTTP 端口 (默认 ${old_http}): " HTTP_PORT_INPUT
  HTTP_PORT="${HTTP_PORT_INPUT:-$old_http}"

  read -rp "TLS SNI (默认 ${old_sni:-$WORKER_HOST}): " SNI_INPUT
  SNI="${SNI_INPUT:-${old_sni:-$WORKER_HOST}}"
}

write_xray_config() {
  local ws_path="${WS_BASE_PATH}?wk=${WK}"
  cat > "$(config_file)" <<EOF
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
      "tag": "direct",
      "protocol": "freedom"
    },
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
      },
      {
        "type": "field",
        "ip": ["8.8.8.8/32", "8.8.4.4/32"],
        "outboundTag": "proxy"
      }
    ]
  }
}
EOF
}

write_singbox_config() {
  local ws_path="${WS_BASE_PATH}?wk=${WK}"
  cat > "$(config_file)" <<EOF
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
      "type": "direct",
      "tag": "direct"
    },
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
        "path": "${ws_path}",
        "headers": {
          "Host": "${WORKER_HOST}"
        }
      }
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
  load_env || { err "未找到配置"; exit 1; }
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

SERVICE="cf-egress.service"
ENV_FILE="/etc/cf-egress/env"
SETUP="/usr/local/bin/cf-egress-setup"
SELF_URL="https://raw.githubusercontent.com/ctsunny/g-everywhere/main/warp-setup.sh"

load_env() {
  [ -f "$ENV_FILE" ] || { echo "未安装"; exit 1; }
  # shellcheck disable=SC1090
  source "$ENV_FILE"
}

case "${1:-}" in
  menu)
    if [ -x "$SETUP" ]; then
      exec bash "$SETUP"
    else
      curl -fsSL "$SELF_URL" | bash
    fi
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
  switch)
    [ -n "${2:-}" ] || { echo "用法: cfeg switch us|sg|jp|hk"; exit 1; }
    if [ -x "$SETUP" ]; then
      exec bash "$SETUP" switch "$2"
    else
      curl -fsSL "$SELF_URL" | bash -s -- switch "$2"
    fi
    ;;
  core)
    [ -n "${2:-}" ] || { echo "用法: cfeg core xray|singbox"; exit 1; }
    if [ -x "$SETUP" ]; then
      exec bash "$SETUP" switch-core "$2"
    else
      curl -fsSL "$SELF_URL" | bash -s -- switch-core "$2"
    fi
    ;;
  test)
    load_env
    echo "== Google =="
    curl --socks5-hostname "127.0.0.1:${SOCKS_PORT}" -I -L --max-time 20 https://www.google.com 2>/dev/null | head -n 6 || true
    echo
    echo "== Gemini =="
    curl --socks5-hostname "127.0.0.1:${SOCKS_PORT}" -I -L --max-time 20 https://gemini.google.com 2>/dev/null | head -n 6 || true
    ;;
  uninstall)
    if [ -x "$SETUP" ]; then
      exec bash "$SETUP" uninstall
    else
      curl -fsSL "$SELF_URL" | bash -s -- uninstall
    fi
    ;;
  *)
    cat <<HLP
用法:
  cfeg menu
  cfeg start
  cfeg stop
  cfeg restart
  cfeg status
  cfeg show
  cfeg switch us|sg|jp|hk
  cfeg core xray|singbox
  cfeg test
  cfeg uninstall
HLP
    ;;
esac
EOF
  chmod +x "${CTL_BIN}"

  if [ -r "${BASH_SOURCE[0]}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    cp "${BASH_SOURCE[0]}" "${SETUP_BIN}" 2>/dev/null || true
    chmod +x "${SETUP_BIN}" 2>/dev/null || true
  else
    curl -fsSL "${SELF_URL}" -o "${SETUP_BIN}" 2>/dev/null || true
    chmod +x "${SETUP_BIN}" 2>/dev/null || true
  fi
}

require_installed() {
  load_env || { err "尚未安装，请先选 1 安装"; return 1; }
}

restart_service() {
  systemctl restart "${SERVICE_NAME}"
  sleep 2
}

show_status() {
  if systemctl is-enabled "${SERVICE_NAME}" >/dev/null 2>&1 || systemctl status "${SERVICE_NAME}" >/dev/null 2>&1; then
    systemctl --no-pager -l status "${SERVICE_NAME}" || true
  else
    warn "服务未安装"
  fi
}

show_config() {
  require_installed || return 1
  echo -e "\n${CYAN}当前配置${NC}"
  load_env
  echo "CORE=$CORE"
  echo "WORKER_HOST=$WORKER_HOST"
  echo "WK=$WK"
  echo "WS_BASE_PATH=$WS_BASE_PATH"
  echo "SNI=$SNI"
  echo "SOCKS=127.0.0.1:$SOCKS_PORT"
  echo "HTTP=127.0.0.1:$HTTP_PORT"
}

test_sites() {
  require_installed || return 1
  load_env
  echo -e "\n${CYAN}Google 测试${NC}"
  curl --socks5-hostname "127.0.0.1:${SOCKS_PORT}" -I -L --max-time 20 https://www.google.com 2>/dev/null | head -n 6 || true
  echo -e "\n${CYAN}Gemini 测试${NC}"
  curl --socks5-hostname "127.0.0.1:${SOCKS_PORT}" -I -L --max-time 20 https://gemini.google.com 2>/dev/null | head -n 6 || true
}

install_or_reinstall() {
  prompt_install_info
  save_env
  ensure_core_binary
  render_config
  write_launcher
  write_service
  write_ctl
  restart_service

  echo -e "\n${GREEN}安装/更新完成${NC}"
  echo -e "核心      : ${YELLOW}${CORE}${NC}"
  echo -e "节点 wk   : ${YELLOW}${WK}${NC}"
  echo -e "SOCKS5    : ${YELLOW}127.0.0.1:${SOCKS_PORT}${NC}"
  echo -e "HTTP      : ${YELLOW}127.0.0.1:${HTTP_PORT}${NC}"
  echo -e "管理命令  : ${YELLOW}cfeg menu | cfeg show | cfeg test${NC}\n"
}

switch_wk() {
  require_installed || return 1
  load_env
  case "${1:-}" in
    us|sg|jp|hk) WK="$1" ;;
    *)
      select_wk_menu "${WK:-us}"
      ;;
  esac
  save_env
  render_config
  restart_service
  msg "已切换 wk=${WK}"
}

switch_core() {
  require_installed || return 1
  load_env
  case "${1:-}" in
    xray|singbox) CORE="$1" ;;
    *)
      select_core_menu "${CORE:-singbox}"
      ;;
  esac
  save_env
  ensure_core_binary
  render_config
  write_launcher
  restart_service
  msg "已切换核心 ${CORE}"
}

do_uninstall() {
  systemctl disable --now "${SERVICE_NAME}" >/dev/null 2>&1 || true
  rm -f "/etc/systemd/system/${SERVICE_NAME}"
  systemctl daemon-reload
  rm -rf "${APP_ROOT}" "${ETC_DIR}" "${LOG_DIR}" "${RUN_DIR}"
  rm -f "${CTL_BIN}" "${SETUP_BIN}"
  msg "已卸载，未触碰 3x-ui"
}

show_menu() {
  while true; do
    banner
    echo -e " ${YELLOW}请选择操作${NC}\n"
    echo "  1) 安装 / 重装"
    echo "  2) 切换核心 xray / singbox"
    echo "  3) 切换地区节点 wk=us/sg/jp/hk"
    echo "  4) 启动服务"
    echo "  5) 停止服务"
    echo "  6) 重启服务"
    echo "  7) 查看状态"
    echo "  8) 查看当前配置"
    echo "  9) 测试 Google / Gemini"
    echo " 10) 卸载"
    echo "  0) 退出"
    echo ""
    read -rp "请输入选项 [0-10]: " choice
    echo ""

    case "${choice:-}" in
      1) install_or_reinstall ;;
      2) switch_core ;;
      3) switch_wk ;;
      4) systemctl start "${SERVICE_NAME}" && msg "已启动" || warn "启动失败" ;;
      5) systemctl stop "${SERVICE_NAME}" && msg "已停止" || warn "停止失败" ;;
      6) systemctl restart "${SERVICE_NAME}" && msg "已重启" || warn "重启失败" ;;
      7) show_status ;;
      8) show_config ;;
      9) test_sites ;;
      10)
        read -rp "确认卸载? [y/N]: " yn
        [[ "${yn:-N}" =~ ^[Yy]$ ]] && do_uninstall
        ;;
      0) echo ""; exit 0 ;;
      *) warn "无效选项" ;;
    esac

    echo ""
    read -rp "按 Enter 返回菜单..." _
  done
}

main() {
  need_root
  detect_arch
  install_deps
  mkdirs

  case "${1:-menu}" in
    install)
      if [[ "${2:-}" =~ ^(xray|singbox)$ ]]; then
        CORE="$2"
        if load_env; then
          WORKER_HOST="${WORKER_HOST:-}"
          UUID="${UUID:-}"
          WS_BASE_PATH="${WS_BASE_PATH:-/ws}"
          WK="${WK:-us}"
          SOCKS_PORT="${SOCKS_PORT:-7892}"
          HTTP_PORT="${HTTP_PORT:-7893}"
          SNI="${SNI:-${WORKER_HOST:-}}"
        else
          prompt_install_info
        fi
        save_env
        ensure_core_binary
        render_config
        write_launcher
        write_service
        write_ctl
        restart_service
        msg "已安装 ${CORE}"
      else
        install_or_reinstall
      fi
      ;;
    switch)
      switch_wk "${2:-}"
      ;;
    switch-core)
      switch_core "${2:-}"
      ;;
    uninstall)
      do_uninstall
      ;;
    menu|"")
      show_menu
      ;;
    *)
      show_menu
      ;;
  esac
}

main "$@"
