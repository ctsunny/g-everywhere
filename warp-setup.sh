#!/bin/bash
# G-Everywhere v4.1
# https://github.com/ctsunny/g-everywhere

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'
NC='\033[0m'; BOLD='\033[1m'

WG_IFACE="warp0"
WG_CONF="/etc/wireguard/${WG_IFACE}.conf"
WARP_DIR="/etc/warp"
MODE_FILE="${WARP_DIR}/mode"
PORT_FILE="${WARP_DIR}/working_port"
WARP_PORTS=(2408 500 1701 4500 8854 894 7559 443)

GOOGLE_IPS="8.8.4.0/24 8.8.8.0/24 34.0.0.0/9 35.184.0.0/13 35.192.0.0/12
35.224.0.0/12 35.240.0.0/13 64.233.160.0/19 66.102.0.0/20 66.249.64.0/19
72.14.192.0/18 74.125.0.0/16 104.132.0.0/14 108.177.0.0/17 142.250.0.0/15
172.217.0.0/16 172.253.0.0/16 173.194.0.0/16 209.85.128.0/17 216.58.192.0/19
216.239.32.0/19"

declare -A ENDPOINTS=(
    ["auto"]="engage.cloudflareclient.com"
    ["us"]="162.159.193.1"
    ["jp"]="162.159.193.2"
    ["sg"]="162.159.193.3"
    ["de"]="162.159.193.4"
    ["uk"]="162.159.193.5"
    ["nl"]="162.159.193.6"
    ["au"]="162.159.193.7"
    ["kr"]="162.159.193.8"
    ["hk"]="162.159.193.9"
    ["ca"]="162.159.193.10"
    ["in"]="162.159.193.11"
    ["br"]="162.159.193.12"
)
REGION_DISPLAY=(
    "auto:🌐 自动"
    "us:🇺🇸 美国"
    "jp:🇯🇵 日本"
    "sg:🇸🇬 新加坡"
    "de:🇩🇪 德国"
    "uk:🇬🇧 英国"
    "nl:🇳🇱 荷兰"
    "au:🇦🇺 澳大利亚"
    "kr:🇰🇷 韩国"
    "hk:🇭🇰 香港"
    "ca:🇨🇦 加拿大"
    "in:🇮🇳 印度"
    "br:🇧🇷 巴西"
)
SELECTED_CODE="auto"

show_banner() {
    clear
    echo -e "${BOLD}${BLUE}"
    echo "  ██████╗       ███████╗██╗   ██╗███████╗██████╗ ██╗   ██╗"
    echo " ██╔════╝       ██╔════╝██║   ██║██╔════╝██╔══██╗╚██╗ ██╔╝"
    echo " ██║  ███╗█████╗█████╗  ██║   ██║█████╗  ██████╔╝ ╚████╔╝ "
    echo " ██║   ██║╚════╝██╔══╝  ╚██╗ ██╔╝██╔══╝  ██╔══██╗  ╚██╔╝  "
    echo " ╚██████╔╝       ███████╗ ╚████╔╝ ███████╗██║  ██║   ██║   "
    echo "  ╚═════╝        ╚══════╝  ╚═══╝  ╚══════╝╚═╝  ╚═╝   ╚═╝  "
    echo -e "${NC}"
    echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${GREEN} Google Unlock ${NC}│${YELLOW} 双引擎 WG+CLI ${NC}│${MAGENTA} UDP封锁自动降级 ${NC}"
    echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${BLUE}github.com/ctsunny/g-everywhere${NC}  │  ${GREEN}v4.1${NC}\n"
}

check_root() { [[ $EUID -ne 0 ]] && { echo -e "${RED}请用 root 运行${NC}"; exit 1; }; }

detect_os() {
    [ -f /etc/os-release ] && . /etc/os-release && OS=$ID \
        || { echo -e "${RED}无法检测系统${NC}"; exit 1; }
    ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
}

show_ip() {
    echo -e "  ${YELLOW}当前节点信息${NC}"
    echo -e "  ${CYAN}──────────────────────────────────${NC}"
    IP=$(curl -4 -s --max-time 5 ip.sb 2>/dev/null || echo "获取失败")
    INFO=$(curl -s --max-time 5 "http://ip-api.com/json/$IP?lang=zh-CN" 2>/dev/null)
    echo -e "  IP  : ${GREEN}$IP${NC}"
    echo -e "  位置: ${GREEN}$(echo "$INFO" | grep -oP '"country":"\K[^"]+') \
$(echo "$INFO" | grep -oP '"city":"\K[^"]+')${NC}"
    echo -e "  ISP : ${GREEN}$(echo "$INFO" | grep -oP '"isp":"\K[^"]+')${NC}"
    echo -e "  ${CYAN}──────────────────────────────────${NC}\n"
}

select_region() {
    echo -e "\n${CYAN}  ── 选择出口地区 ──${NC}\n"
    local i=1
    for item in "${REGION_DISPLAY[@]}"; do
        local label="${item#*:}"
        printf "  ${GREEN}%2d.${NC} %s\n" "$i" "$label"
        ((i++))
    done
    echo ""
    read -p "  请选择 [1-${#REGION_DISPLAY[@]}] (默认1): " c
    c=${c:-1}
    if [[ "$c" =~ ^[0-9]+$ ]] && [ "$c" -ge 1 ] && [ "$c" -le "${#REGION_DISPLAY[@]}" ]; then
        local item="${REGION_DISPLAY[$((c-1))]}"
        SELECTED_CODE="${item%%:*}"
        local label="${item#*:}"
        echo -e "  ${GREEN}✓ 已选择: $label${NC}"
    else
        SELECTED_CODE="auto"
        echo -e "  ${GREEN}✓ 已选择: 🌐 自动${NC}"
    fi
    echo "$SELECTED_CODE" > "${WARP_DIR}/region"
}

# ============================================================
# 路由管理
# ============================================================
wg_routing_start() {
    ip rule del fwmark 51820 table 51820 2>/dev/null || true
    ip route flush table 51820 2>/dev/null || true
    iptables -t mangle -D OUTPUT    -j WARP_MARK 2>/dev/null || true
    iptables -t mangle -D PREROUTING -j WARP_MARK 2>/dev/null || true
    iptables -t mangle -F WARP_MARK 2>/dev/null || true
    iptables -t mangle -X WARP_MARK 2>/dev/null || true
    ip rule add fwmark 51820 table 51820
    ip route add default dev "${WG_IFACE}" table 51820
    iptables -t mangle -N WARP_MARK
    for net in 127.0.0.0/8 10.0.0.0/8 192.168.0.0/16 172.16.0.0/12 162.159.192.0/22; do
        iptables -t mangle -A WARP_MARK -d "$net" -j RETURN
    done
    for ip in $GOOGLE_IPS; do
        iptables -t mangle -A WARP_MARK -d "$ip" -j MARK --set-mark 51820
    done
    iptables -t mangle -A OUTPUT    -j WARP_MARK
    iptables -t mangle -A PREROUTING -j WARP_MARK
}

wg_routing_stop() {
    ip rule del fwmark 51820 table 51820 2>/dev/null || true
    ip route flush table 51820 2>/dev/null || true
    iptables -t mangle -D OUTPUT    -j WARP_MARK 2>/dev/null || true
    iptables -t mangle -D PREROUTING -j WARP_MARK 2>/dev/null || true
    iptables -t mangle -F WARP_MARK 2>/dev/null || true
    iptables -t mangle -X WARP_MARK 2>/dev/null || true
}

cli_routing_start() {
    pkill -f "redsocks -c /etc/redsocks-warp.conf" 2>/dev/null || true
    sleep 1
    # ★ 用 printf 写配置，避免嵌套 heredoc 语法问题
    printf 'base {\n  log_debug = off;\n  log_info = off;\n  daemon = off;\n  redirector = iptables;\n}\nredsocks {\n  local_ip = 127.0.0.1;\n  local_port = 12345;\n  ip = 127.0.0.1;\n  port = 40000;\n  type = socks5;\n}\n' \
        > /etc/redsocks-warp.conf
    redsocks -c /etc/redsocks-warp.conf &
    sleep 1
    iptables -t nat -D OUTPUT    -j WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -D PREROUTING -j WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -F WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -X WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -N WARP_GOOGLE
    for net in 127.0.0.0/8 10.0.0.0/8 192.168.0.0/16 172.16.0.0/12 162.159.192.0/22; do
        iptables -t nat -A WARP_GOOGLE -d "$net" -j RETURN
    done
    for ip in $GOOGLE_IPS; do
        iptables -t nat -A WARP_GOOGLE -d "$ip" -p tcp -j REDIRECT --to-ports 12345
    done
    iptables -t nat -A OUTPUT    -j WARP_GOOGLE
    iptables -t nat -A PREROUTING -j WARP_GOOGLE
}

cli_routing_stop() {
    pkill -f "redsocks -c /etc/redsocks-warp.conf" 2>/dev/null || true
    iptables -t nat -D OUTPUT    -j WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -D PREROUTING -j WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -F WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -X WARP_GOOGLE 2>/dev/null || true
}

all_routing_stop() {
    wg_routing_stop
    cli_routing_stop
}

# ============================================================
# 安装依赖
# ============================================================
install_deps() {
    echo -e "\n${CYAN}  [1/4] 安装依赖...${NC}"
    case $OS in
        ubuntu|debian)
            apt-get update -y >/dev/null 2>&1
            apt-get install -y wireguard wireguard-tools curl wget \
                iptables openresolv redsocks >/dev/null 2>&1
            systemctl stop redsocks 2>/dev/null
            systemctl disable redsocks 2>/dev/null
            ;;
        centos|rhel|rocky|almalinux|fedora)
            dnf install -y epel-release >/dev/null 2>&1
            dnf install -y wireguard-tools curl wget iptables redsocks >/dev/null 2>&1
            ;;
    esac
    modprobe wireguard 2>/dev/null || true

    command -v update-alternatives &>/dev/null && {
        update-alternatives --set iptables  /usr/sbin/iptables-legacy  2>/dev/null || true
        update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true
    }

    # 禁用 IPv6
    sysctl -w net.ipv6.conf.all.disable_ipv6=1     >/dev/null 2>&1
    sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1
    grep -q "disable_ipv6" /etc/sysctl.conf 2>/dev/null || {
        echo "net.ipv6.conf.all.disable_ipv6=1"     >> /etc/sysctl.conf
        echo "net.ipv6.conf.default.disable_ipv6=1" >> /etc/sysctl.conf
    }

    # 安装 wgcf
    VER=$(curl -s --max-time 10 \
        https://api.github.com/repos/ViRb3/wgcf/releases/latest \
        | grep tag_name | cut -d'"' -f4 2>/dev/null)
    [ -z "$VER" ] && VER="v2.2.25"
    curl -fsSL \
        "https://github.com/ViRb3/wgcf/releases/download/${VER}/wgcf_${VER#v}_linux_${ARCH}" \
        -o /usr/local/bin/wgcf 2>/dev/null
    [ ! -s /usr/local/bin/wgcf ] && \
        curl -fsSL \
        "https://github.com/ViRb3/wgcf/releases/download/v2.2.25/wgcf_2.2.25_linux_${ARCH}" \
        -o /usr/local/bin/wgcf
    chmod +x /usr/local/bin/wgcf
    command -v wgcf &>/dev/null || { echo -e "${RED}  wgcf 安装失败${NC}"; exit 1; }
    echo -e "  ${GREEN}✓ 依赖安装完成${NC}"
}

# ============================================================
# 生成配置
# ============================================================
setup_config() {
    echo -e "\n${CYAN}  [2/4] 生成 WireGuard 配置...${NC}"
    mkdir -p "${WARP_DIR}" /etc/wireguard

    cd /tmp
    rm -f /tmp/wgcf-account.toml /tmp/wgcf-profile.conf

    if [ -f "${WARP_DIR}/wgcf-account.toml" ]; then
        cp "${WARP_DIR}/wgcf-account.toml" /tmp/
        echo -e "  ${GREEN}复用已有账号${NC}"
    else
        echo -e "  注册新 WARP 设备..."
    fi

    wgcf register --accept-tos >/dev/null 2>&1
    [ -f /tmp/wgcf-account.toml ] && cp /tmp/wgcf-account.toml "${WARP_DIR}/"
    wgcf generate >/dev/null 2>&1
    [ ! -f /tmp/wgcf-profile.conf ] && { echo -e "${RED}  配置生成失败${NC}"; exit 1; }

    sed -i '/^DNS/d'   /tmp/wgcf-profile.conf
    sed -i '/^Table/d' /tmp/wgcf-profile.conf
    sed -i '/^\[Interface\]/a Table = off' /tmp/wgcf-profile.conf
    # 仅保留 IPv4（系统已禁用 IPv6）
    sed -i 's/^Address = \(.*\), .*\/128$/Address = \1/' /tmp/wgcf-profile.conf
    sed -i '/^AllowedIPs/d' /tmp/wgcf-profile.conf
    echo "AllowedIPs = 0.0.0.0/0"      >> /tmp/wgcf-profile.conf
    echo "PersistentKeepalive = 25"    >> /tmp/wgcf-profile.conf

    local EP="${ENDPOINTS[$SELECTED_CODE]}"
    sed -i "s/^Endpoint = .*/Endpoint = ${EP}:2408/" /tmp/wgcf-profile.conf

    cp /tmp/wgcf-profile.conf "${WARP_DIR}/wgcf-profile.conf"
    cp /tmp/wgcf-profile.conf "${WG_CONF}"
    echo -e "  ${GREEN}✓ 配置生成完成${NC}"
    grep -E "^(Address|Endpoint)" "${WG_CONF}" | sed 's/^/  /'
}

# ============================================================
# 端口扫描
# ============================================================
scan_port() {
    local TARGET_IP="$1"
    echo -e "\n  ${CYAN}扫描可用 UDP 端口...${NC}"

    local PRIVKEY PEER_PUB
    PRIVKEY=$(grep "^PrivateKey" "${WG_CONF}" | awk '{print $3}')
    PEER_PUB=$(grep "^PublicKey"  "${WG_CONF}" | awk '{print $3}')

    for PORT in "${WARP_PORTS[@]}"; do
        printf "    UDP %-6s → " "$PORT"
        ip link del _wtest 2>/dev/null || true
        if ! ip link add _wtest type wireguard 2>/dev/null; then
            echo -e "${RED}内核不支持 WireGuard${NC}"
            return 1
        fi
        wg set _wtest \
            private-key <(echo "$PRIVKEY") \
            peer "$PEER_PUB" \
            endpoint "${TARGET_IP}:${PORT}" \
            allowed-ips 0.0.0.0/0 \
            persistent-keepalive 5 2>/dev/null
        ip link set _wtest up 2>/dev/null
        sleep 6
        local HS
        HS=$(wg show _wtest latest-handshakes 2>/dev/null | awk '{print $2}')
        ip link del _wtest 2>/dev/null
        if [ -n "$HS" ] && [ "$HS" != "0" ]; then
            echo -e "${GREEN}✓ 握手成功${NC}"
            echo "$PORT" > "${PORT_FILE}"
            sed -i "s/^Endpoint = .*/Endpoint = ${TARGET_IP}:${PORT}/" "${WG_CONF}"
            sed -i "s/^Endpoint = .*/Endpoint = ${TARGET_IP}:${PORT}/" \
                "${WARP_DIR}/wgcf-profile.conf"
            return 0
        fi
        echo -e "${RED}✗ 超时${NC}"
    done
    return 1
}

# ============================================================
# 引擎一：WireGuard
# ============================================================
engine_wireguard() {
    echo -e "\n${CYAN}  [3/4] 引擎一：WireGuard 端口扫描...${NC}"
    local TARGET_IP="${ENDPOINTS[$SELECTED_CODE]}"

    if ! scan_port "$TARGET_IP"; then
        echo -e "\n  ${YELLOW}所有 UDP 端口不可用，启动引擎二...${NC}"
        return 1
    fi

    local PORT
    PORT=$(cat "${PORT_FILE}")
    ip link del "${WG_IFACE}" 2>/dev/null || true
    sleep 1
    wg-quick up "${WG_CONF}" 2>&1
    sleep 3

    if ! ip link show "${WG_IFACE}" &>/dev/null; then
        echo -e "  ${RED}wg-quick 启动失败${NC}"
        return 1
    fi

    echo -e "  等待握手确认..."
    local i HS
    for i in $(seq 1 12); do
        sleep 2
        HS=$(wg show "${WG_IFACE}" latest-handshakes 2>/dev/null | awk '{print $2}')
        if [ -n "$HS" ] && [ "$HS" != "0" ]; then
            echo -e "  ${GREEN}✓ 握手成功 UDP $PORT${NC}"
            echo "wireguard" > "${MODE_FILE}"
            wg_routing_start
            echo -e "  ${GREEN}✓ 路由建立完成${NC}"
            return 0
        fi
    done

    echo -e "  ${RED}握手超时${NC}"
    wg-quick down "${WG_IFACE}" 2>/dev/null
    return 1
}

# ============================================================
# 引擎二：warp-cli (TCP fallback)
# ============================================================
install_warp_cli() {
    echo -e "  ${CYAN}安装 warp-cli...${NC}"
    case $OS in
        ubuntu|debian)
            local CODENAME
            CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
            curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg \
                | gpg --yes --dearmor \
                -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg 2>/dev/null
            echo "deb [arch=${ARCH} signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] \
https://pkg.cloudflareclient.com/ ${CODENAME} main" \
                > /etc/apt/sources.list.d/cloudflare-client.list
            apt-get update -y >/dev/null 2>&1
            apt-get install -y cloudflare-warp >/dev/null 2>&1
            ;;
        centos|rhel|rocky|almalinux|fedora)
            curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg \
                -o /etc/pki/rpm-gpg/cloudflare-warp.gpg
            printf '[cloudflare-warp]\nname=Cloudflare WARP\nbaseurl=https://pkg.cloudflareclient.com/rpm\nenabled=1\ngpgcheck=1\ngpgkey=file:///etc/pki/rpm-gpg/cloudflare-warp.gpg\n' \
                > /etc/yum.repos.d/cloudflare-warp.repo
            dnf install -y cloudflare-warp >/dev/null 2>&1
            ;;
    esac
    command -v warp-cli &>/dev/null || { echo -e "  ${RED}warp-cli 安装失败${NC}"; return 1; }
    echo -e "  ${GREEN}✓ warp-cli 安装完成${NC}"
}

engine_warp_cli() {
    echo -e "\n${CYAN}  [3/4] 引擎二：warp-cli TCP fallback...${NC}"
    install_warp_cli || return 1

    systemctl start warp-svc 2>/dev/null
    sleep 2
    warp-cli --accept-tos registration new 2>/dev/null \
        || warp-cli --accept-tos register 2>/dev/null || true
    sleep 1
    warp-cli --accept-tos mode proxy       2>/dev/null || true
    warp-cli --accept-tos proxy port 40000 2>/dev/null || true

    # 设置入口节点
    local TARGET_IP="${ENDPOINTS[$SELECTED_CODE]}"
    if [ "$SELECTED_CODE" != "auto" ]; then
        warp-cli --accept-tos set-custom-endpoint "${TARGET_IP}:2408" 2>/dev/null || true
        echo -e "  入口节点: ${YELLOW}${TARGET_IP}${NC}"
    fi

    warp-cli --accept-tos connect 2>/dev/null
    echo -e "  连接中，等待 10 秒..."
    sleep 10

    local STATUS
    STATUS=$(warp-cli status 2>/dev/null)
    if ! echo "$STATUS" | grep -qi "connected"; then
        echo -e "  ${RED}warp-cli 连接失败${NC}"
        return 1
    fi
    echo -e "  ${GREEN}✓ warp-cli 已连接${NC}"

    local SOCKS_IP
    SOCKS_IP=$(curl -x socks5://127.0.0.1:40000 -s --max-time 8 ip.sb 2>/dev/null)
    if [ -z "$SOCKS_IP" ]; then
        echo -e "  ${RED}SOCKS5 不可用${NC}"
        return 1
    fi

    local INFO C T
    INFO=$(curl -s --max-time 5 "http://ip-api.com/json/$SOCKS_IP?lang=zh-CN" 2>/dev/null)
    C=$(echo "$INFO" | grep -oP '"country":"\K[^"]+' || echo "?")
    T=$(echo "$INFO" | grep -oP '"city":"\K[^"]+' || echo "")
    echo -e "  ${GREEN}✓ SOCKS5 可用，出口: $SOCKS_IP ($C $T)${NC}"

    echo "warp-cli" > "${MODE_FILE}"
    cli_routing_start
    echo -e "  ${GREEN}✓ 透明代理建立完成${NC}"
    return 0
}

# ============================================================
# 验证出口
# ============================================================
verify_exit() {
    echo -e "\n${CYAN}  [4/4] 验证出口...${NC}"
    sleep 2

    local G GEM EXIT_IP INFO C T ISP
    G=$(curl -s --max-time 12 -o /dev/null -w "%{http_code}" https://www.google.com)
    GEM=$(curl -s --max-time 12 -o /dev/null -w "%{http_code}" \
        -H "User-Agent: Mozilla/5.0" https://gemini.google.com)

    [ "$G" = "200" ] || [ "$G" = "301" ] && \
        echo -e "  ${GREEN}✓ Google  HTTP $G${NC}" || \
        echo -e "  ${RED}✗ Google  HTTP $G${NC}"
    [ "$GEM" = "200" ] || [ "$GEM" = "301" ] && \
        echo -e "  ${GREEN}✓ Gemini  HTTP $GEM${NC}" || \
        echo -e "  ${YELLOW}△ Gemini  HTTP $GEM${NC}"

    local MODE
    MODE=$(cat "${MODE_FILE}" 2>/dev/null || echo "wireguard")
    if [ "$MODE" = "wireguard" ]; then
        EXIT_IP=$(curl -s --max-time 10 \
            "https://dns.google/resolve?name=myip.opendns.com&type=A" \
            | grep -oP '"data":"\K[^"]+' | head -1 2>/dev/null)
    else
        EXIT_IP=$(curl -x socks5://127.0.0.1:40000 -s --max-time 10 ip.sb 2>/dev/null)
    fi

    if [ -n "$EXIT_IP" ]; then
        INFO=$(curl -s --max-time 5 "http://ip-api.com/json/$EXIT_IP?lang=zh-CN" 2>/dev/null)
        C=$(echo "$INFO" | grep -oP '"country":"\K[^"]+' || echo "未知")
        T=$(echo "$INFO" | grep -oP '"city":"\K[^"]+' || echo "")
        ISP=$(echo "$INFO" | grep -oP '"isp":"\K[^"]+' || echo "")
        echo -e "  出口 IP  : ${GREEN}$EXIT_IP${NC}"
        echo -e "  出口地区 : ${GREEN}$C $T${NC}"
        echo -e "  ISP      : ${GREEN}$ISP${NC}"
    fi
}

# ============================================================
# 开机自启
# ============================================================
setup_autostart() {
    local MODE SC EC
    MODE=$(cat "${MODE_FILE}" 2>/dev/null || echo "wireguard")
    if [ "$MODE" = "wireguard" ]; then
        SC="wg-quick up ${WG_CONF} && sleep 3 && /usr/local/bin/ge start-routing wg"
        EC="/usr/local/bin/ge stop-routing && wg-quick down ${WG_IFACE}"
    else
        SC="systemctl start warp-svc && sleep 3 && warp-cli --accept-tos connect && sleep 5 && /usr/local/bin/ge start-routing cli"
        EC="/usr/local/bin/ge stop-routing && warp-cli --accept-tos disconnect"
    fi
    cat > /etc/systemd/system/g-everywhere.service << SVCEOF
[Unit]
Description=G-Everywhere Google Routing v4.1
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c '${SC}'
ExecStop=/bin/bash -c '${EC}'

[Install]
WantedBy=multi-user.target
SVCEOF
    systemctl daemon-reload
    systemctl enable g-everywhere 2>/dev/null
}

# ============================================================
# 创建 ge 命令（★ 关键：全部用 printf 写内部配置，不用嵌套 heredoc）
# ============================================================
create_ge() {
    rm -f /usr/local/bin/g /usr/local/bin/g-e /usr/local/bin/g-proxy

    # ★ 写 ge 脚本，用 cat + 单引号 heredoc（GE_SCRIPT_END 保证不在内容中出现）
    cat > /usr/local/bin/ge << 'GE_SCRIPT_END'
#!/bin/bash
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'
WG_IFACE="warp0"
WG_CONF="/etc/wireguard/${WG_IFACE}.conf"
WARP_DIR="/etc/warp"
MODE_FILE="${WARP_DIR}/mode"
WARP_PORTS=(2408 500 1701 4500 8854 894 7559 443)
GOOGLE_IPS="8.8.4.0/24 8.8.8.0/24 34.0.0.0/9 35.184.0.0/13 35.192.0.0/12 35.224.0.0/12
35.240.0.0/13 64.233.160.0/19 66.102.0.0/20 66.249.64.0/19 72.14.192.0/18 74.125.0.0/16
104.132.0.0/14 108.177.0.0/17 142.250.0.0/15 172.217.0.0/16 172.253.0.0/16 173.194.0.0/16
209.85.128.0/17 216.58.192.0/19 216.239.32.0/19"

_wg_r_start() {
    ip rule del fwmark 51820 table 51820 2>/dev/null || true
    ip route flush table 51820 2>/dev/null || true
    iptables -t mangle -D OUTPUT    -j WARP_MARK 2>/dev/null || true
    iptables -t mangle -D PREROUTING -j WARP_MARK 2>/dev/null || true
    iptables -t mangle -F WARP_MARK 2>/dev/null || true
    iptables -t mangle -X WARP_MARK 2>/dev/null || true
    ip rule add fwmark 51820 table 51820
    ip route add default dev "$WG_IFACE" table 51820
    iptables -t mangle -N WARP_MARK
    for net in 127.0.0.0/8 10.0.0.0/8 192.168.0.0/16 172.16.0.0/12 162.159.192.0/22; do
        iptables -t mangle -A WARP_MARK -d "$net" -j RETURN
    done
    for ip in $GOOGLE_IPS; do
        iptables -t mangle -A WARP_MARK -d "$ip" -j MARK --set-mark 51820
    done
    iptables -t mangle -A OUTPUT    -j WARP_MARK
    iptables -t mangle -A PREROUTING -j WARP_MARK
}

_cli_r_start() {
    pkill -f "redsocks -c /etc/redsocks-warp.conf" 2>/dev/null || true
    sleep 1
    printf 'base {\n  log_debug = off;\n  log_info = off;\n  daemon = off;\n  redirector = iptables;\n}\nredsocks {\n  local_ip = 127.0.0.1;\n  local_port = 12345;\n  ip = 127.0.0.1;\n  port = 40000;\n  type = socks5;\n}\n' \
        > /etc/redsocks-warp.conf
    redsocks -c /etc/redsocks-warp.conf &
    sleep 1
    iptables -t nat -D OUTPUT    -j WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -D PREROUTING -j WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -F WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -X WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -N WARP_GOOGLE
    for net in 127.0.0.0/8 10.0.0.0/8 192.168.0.0/16 172.16.0.0/12 162.159.192.0/22; do
        iptables -t nat -A WARP_GOOGLE -d "$net" -j RETURN
    done
    for ip in $GOOGLE_IPS; do
        iptables -t nat -A WARP_GOOGLE -d "$ip" -p tcp -j REDIRECT --to-ports 12345
    done
    iptables -t nat -A OUTPUT    -j WARP_GOOGLE
    iptables -t nat -A PREROUTING -j WARP_GOOGLE
}

_stop_all() {
    ip rule del fwmark 51820 table 51820 2>/dev/null || true
    ip route flush table 51820 2>/dev/null || true
    iptables -t mangle -D OUTPUT    -j WARP_MARK 2>/dev/null || true
    iptables -t mangle -D PREROUTING -j WARP_MARK 2>/dev/null || true
    iptables -t mangle -F WARP_MARK 2>/dev/null || true
    iptables -t mangle -X WARP_MARK 2>/dev/null || true
    pkill -f "redsocks -c /etc/redsocks-warp.conf" 2>/dev/null || true
    iptables -t nat -D OUTPUT    -j WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -D PREROUTING -j WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -F WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -X WARP_GOOGLE 2>/dev/null || true
}

_exit_ip() {
    local MODE
    MODE=$(cat "$MODE_FILE" 2>/dev/null || echo "wireguard")
    if [ "$MODE" = "wireguard" ]; then
        curl -s --max-time 8 \
            "https://dns.google/resolve?name=myip.opendns.com&type=A" \
            | grep -oP '"data":"\K[^"]+' | head -1 2>/dev/null
    else
        curl -x socks5://127.0.0.1:40000 -s --max-time 8 ip.sb 2>/dev/null
    fi
}

case "$1" in
start-routing)
    [ "$2" = "cli" ] && _cli_r_start || _wg_r_start
    echo -e "${GREEN}OK routing up${NC}" ;;

stop-routing)
    _stop_all
    echo -e "${GREEN}OK routing down${NC}" ;;

start)
    MODE=$(cat "$MODE_FILE" 2>/dev/null || echo "wireguard")
    if [ "$MODE" = "wireguard" ]; then
        wg-quick up "$WG_CONF" 2>/dev/null
        sleep 3
        _wg_r_start
    else
        systemctl start warp-svc 2>/dev/null
        sleep 2
        warp-cli --accept-tos connect 2>/dev/null
        sleep 6
        _cli_r_start
    fi
    echo -e "${GREEN}✓ 已启动 ($MODE)${NC}" ;;

stop)
    _stop_all
    wg-quick down "$WG_IFACE" 2>/dev/null
    warp-cli --accept-tos disconnect 2>/dev/null
    echo -e "${GREEN}✓ 已停止${NC}" ;;

restart)
    /usr/local/bin/ge stop
    sleep 2
    /usr/local/bin/ge start ;;

status)
    MODE=$(cat "$MODE_FILE" 2>/dev/null || echo "未知")
    echo -e "\n${CYAN}── 模式: $MODE ──${NC}"
    if [ "$MODE" = "wireguard" ]; then
        ip link show "$WG_IFACE" &>/dev/null \
            && echo -e "${GREEN}✓ WireGuard 运行中${NC}" \
            || echo -e "${RED}✗ WireGuard 未运行${NC}"
        wg show "$WG_IFACE" 2>/dev/null \
            | grep -E "endpoint|handshake|transfer" | sed 's/^/  /'
        echo -e "  端口: UDP $(cat $WARP_DIR/working_port 2>/dev/null || echo '?')"
    else
        warp-cli status 2>/dev/null | head -3 | sed 's/^/  /'
    fi
    echo -e "\n${CYAN}── 访问测试 ──${NC}"
    G=$(curl -s --max-time 8 -o /dev/null -w "%{http_code}" https://www.google.com)
    GEM=$(curl -s --max-time 8 -o /dev/null -w "%{http_code}" \
        -H "User-Agent: Mozilla/5.0" https://gemini.google.com)
    [ "$G"   = "200" ] || [ "$G"   = "301" ] \
        && echo -e "  ${GREEN}✓ Google  $G${NC}" || echo -e "  ${RED}✗ Google  $G${NC}"
    [ "$GEM" = "200" ] || [ "$GEM" = "301" ] \
        && echo -e "  ${GREEN}✓ Gemini  $GEM${NC}" || echo -e "  ${YELLOW}△ Gemini  $GEM${NC}"
    EXIT=$(_exit_ip)
    [ -n "$EXIT" ] && {
        INFO=$(curl -s --max-time 5 "http://ip-api.com/json/$EXIT?lang=zh-CN" 2>/dev/null)
        C=$(echo "$INFO" | grep -oP '"country":"\K[^"]+' || echo "?")
        T=$(echo "$INFO" | grep -oP '"city":"\K[^"]+' || echo "")
        echo -e "  出口: ${GREEN}$EXIT ($C $T)${NC}"
    }
    echo "" ;;

test)
    MODE=$(cat "$MODE_FILE" 2>/dev/null || echo "未知")
    echo -e "\n${CYAN}── 诊断 ($MODE) ──${NC}\n"
    if [ "$MODE" = "wireguard" ]; then
        HS=$(wg show "$WG_IFACE" latest-handshakes 2>/dev/null | awk '{print $2}')
        [ -n "$HS" ] && [ "$HS" != "0" ] \
            && echo -e "[WireGuard] ${GREEN}✓ 已握手${NC}" \
            || echo -e "[WireGuard] ${RED}✗ 未握手 → ge fix${NC}"
    else
        warp-cli status 2>/dev/null | grep -qi "connected" \
            && echo -e "[warp-cli] ${GREEN}✓ 已连接${NC}" \
            || echo -e "[warp-cli] ${RED}✗ 未连接 → ge fix${NC}"
    fi
    for url in "https://www.google.com|Google" \
               "https://gemini.google.com|Gemini" \
               "https://www.youtube.com|YouTube"; do
        local U L C
        U="${url%%|*}"; L="${url##*|}"
        C=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" \
            -H "User-Agent: Mozilla/5.0" "$U")
        [ "$C" = "200" ] || [ "$C" = "301" ] \
            && printf "${GREEN}✓${NC} %-10s HTTP %s\n" "$L" "$C" \
            || printf "${RED}✗${NC} %-10s HTTP %s\n" "$L" "$C"
    done
    echo "" ;;

ip)
    echo -e "\n${YELLOW}直连 IP:${NC}"
    curl -4 -s --max-time 5 ip.sb; echo ""
    echo -e "${YELLOW}WARP 出口 IP:${NC}"
    EXIT=$(_exit_ip)
    if [ -n "$EXIT" ]; then
        INFO=$(curl -s --max-time 5 "http://ip-api.com/json/$EXIT?lang=zh-CN" 2>/dev/null)
        C=$(echo "$INFO" | grep -oP '"country":"\K[^"]+' || echo "?")
        T=$(echo "$INFO" | grep -oP '"city":"\K[^"]+' || echo "")
        echo -e "${GREEN}$EXIT  ($C $T)${NC}"
    else
        echo -e "${RED}获取失败${NC}"
    fi
    echo "" ;;

fix)
    echo -e "${CYAN}修复中...${NC}"
    MODE=$(cat "$MODE_FILE" 2>/dev/null || echo "wireguard")
    _stop_all
    if [ "$MODE" = "wireguard" ]; then
        wg-quick down "$WG_IFACE" 2>/dev/null
        sleep 1
        PRIVKEY=$(grep "^PrivateKey" "$WG_CONF" | awk '{print $3}')
        PEER_PUB=$(grep "^PublicKey"  "$WG_CONF" | awk '{print $3}')
        EP_IP=$(grep "^Endpoint" "$WG_CONF" | awk '{print $3}' | cut -d: -f1)
        FOUND=""
        for PORT in "${WARP_PORTS[@]}"; do
            printf "  UDP %-6s " "$PORT"
            ip link del _wtest 2>/dev/null || true
            ip link add _wtest type wireguard 2>/dev/null
            wg set _wtest private-key <(echo "$PRIVKEY") \
                peer "$PEER_PUB" endpoint "${EP_IP}:${PORT}" \
                allowed-ips 0.0.0.0/0 persistent-keepalive 5 2>/dev/null
            ip link set _wtest up 2>/dev/null
            sleep 6
            HS=$(wg show _wtest latest-handshakes 2>/dev/null | awk '{print $2}')
            ip link del _wtest 2>/dev/null
            if [ -n "$HS" ] && [ "$HS" != "0" ]; then
                echo -e "${GREEN}✓${NC}"
                sed -i "s/^Endpoint = .*/Endpoint = ${EP_IP}:${PORT}/" "$WG_CONF"
                echo "$PORT" > "$WARP_DIR/working_port"
                FOUND=yes
                break
            fi
            echo -e "${RED}✗${NC}"
        done
        [ -n "$FOUND" ] && {
            wg-quick up "$WG_CONF"
            sleep 3
            _wg_r_start
        } || echo -e "${RED}所有端口失败，请重新安装${NC}"
    else
        warp-cli --accept-tos disconnect 2>/dev/null
        sleep 1
        warp-cli --accept-tos connect 2>/dev/null
        sleep 8
        _cli_r_start
    fi
    G=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" https://www.google.com)
    [ "$G" = "200" ] || [ "$G" = "301" ] \
        && echo -e "${GREEN}✓ 修复成功 HTTP $G${NC}" \
        || echo -e "${RED}✗ 仍异常 HTTP $G${NC}" ;;

region)
    bash /usr/local/bin/warp-setup.sh --change-region 2>/dev/null \
        || bash <(curl -fsSL \
            https://raw.githubusercontent.com/ctsunny/g-everywhere/main/warp-setup.sh) \
            --change-region ;;

uninstall)
    _stop_all
    wg-quick down "$WG_IFACE" 2>/dev/null
    warp-cli --accept-tos disconnect 2>/dev/null
    systemctl disable --now g-everywhere warp-svc 2>/dev/null
    rm -f /etc/systemd/system/g-everywhere.service
    rm -f /usr/local/bin/ge /usr/local/bin/warp-setup.sh /usr/local/bin/wgcf
    rm -rf /etc/warp
    rm -f "$WG_CONF"
    echo -e "${GREEN}✓ 卸载完成${NC}" ;;

*)
    MODE=$(cat "$MODE_FILE" 2>/dev/null || echo "未安装")
    echo -e "${CYAN}ge v4.1  模式: $MODE${NC}\n"
    echo "  start / stop / restart"
    echo "  status   test   fix"
    echo "  ip       region"
    echo "  uninstall" ;;
esac
GE_SCRIPT_END

    chmod +x /usr/local/bin/ge
    cp "$0" /usr/local/bin/warp-setup.sh 2>/dev/null || true
    chmod +x /usr/local/bin/warp-setup.sh 2>/dev/null || true
}

# ============================================================
# 切换地区
# ============================================================
change_region() {
    echo -e "\n${CYAN}  ── 切换出口地区 ──${NC}"
    local MODE
    MODE=$(cat "${MODE_FILE}" 2>/dev/null || echo "wireguard")
    select_region
    local TARGET_IP="${ENDPOINTS[$SELECTED_CODE]}"
    all_routing_stop
    if [ "$MODE" = "wireguard" ]; then
        wg-quick down "${WG_IFACE}" 2>/dev/null
        sleep 1
        sed -i "s/^Endpoint = .*/Endpoint = ${TARGET_IP}:$(cat ${PORT_FILE} 2>/dev/null || echo 2408)/" \
            "${WG_CONF}"
        wg-quick up "${WG_CONF}"
        sleep 4
        wg_routing_start
    else
        warp-cli --accept-tos disconnect 2>/dev/null
        sleep 1
        [ "$SELECTED_CODE" != "auto" ] && \
            warp-cli --accept-tos set-custom-endpoint "${TARGET_IP}:2408" 2>/dev/null || true
        warp-cli --accept-tos connect 2>/dev/null
        sleep 8
        cli_routing_start
    fi
    local G
    G=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" https://www.google.com)
    [ "$G" = "200" ] || [ "$G" = "301" ] && \
        echo -e "  ${GREEN}✓ 切换成功 HTTP $G${NC}" || \
        echo -e "  ${YELLOW}HTTP $G${NC}"
}

# ============================================================
# 安装流程
# ============================================================
do_install() {
    select_region
    install_deps
    setup_config

    local ENGINE_USED
    if engine_wireguard; then
        ENGINE_USED="WireGuard UDP $(cat ${PORT_FILE} 2>/dev/null)"
    elif engine_warp_cli; then
        ENGINE_USED="warp-cli TCP fallback"
    else
        echo -e "\n${RED}  两个引擎均失败！请检查 VPS 出站防火墙${NC}"
        exit 1
    fi

    setup_autostart
    create_ge
    verify_exit

    local MODE REGION_LABEL
    MODE=$(cat "${MODE_FILE}" 2>/dev/null)
    REGION_LABEL=$(grep "^${SELECTED_CODE}:" \
        <(printf '%s\n' "${REGION_DISPLAY[@]}") \
        | cut -d: -f2- || echo "$SELECTED_CODE")

    echo -e "\n${BOLD}${GREEN}"
    echo "  ┌──────────────────────────────────────────┐"
    echo "  │       ✅  安装成功！Google 已解锁          │"
    echo "  └──────────────────────────────────────────┘"
    echo -e "${NC}"
    echo -e "  ${YELLOW}出口地区 :${NC} ${GREEN}$REGION_LABEL${NC}"
    echo -e "  ${YELLOW}引擎模式 :${NC} ${GREEN}$ENGINE_USED${NC}"
    echo -e "\n  ${CYAN}━━━━━ ge 管理命令 ━━━━━${NC}"
    echo -e "  start stop restart  status test"
    echo -e "  fix ip region       uninstall"
    echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

do_uninstall() {
    all_routing_stop
    wg-quick down "${WG_IFACE}" 2>/dev/null || true
    warp-cli --accept-tos disconnect 2>/dev/null || true
    systemctl disable --now g-everywhere warp-svc 2>/dev/null || true
    rm -f /etc/systemd/system/g-everywhere.service
    rm -f /usr/local/bin/ge /usr/local/bin/warp-setup.sh /usr/local/bin/wgcf
    rm -f /usr/local/bin/g /usr/local/bin/g-e /usr/local/bin/g-proxy
    rm -rf "${WARP_DIR}"
    rm -f "${WG_CONF}"
    echo -e "  ${GREEN}✓ 卸载完成${NC}\n"
}

show_menu() {
    while true; do
        show_banner
        show_ip
        local MODE
        MODE=$(cat "${MODE_FILE}" 2>/dev/null)
        [ -n "$MODE" ] && echo -e "  ${CYAN}当前引擎: $MODE${NC}\n"
        echo -e "  ${YELLOW}请选择:${NC}\n"
        echo -e "  ${GREEN}1.${NC} 安装"
        echo -e "  ${GREEN}2.${NC} 切换地区"
        echo -e "  ${GREEN}3.${NC} 查看状态"
        echo -e "  ${GREEN}4.${NC} 扫描节点"
        echo -e "  ${GREEN}5.${NC} 卸载"
        echo -e "  ${GREEN}0.${NC} 退出\n"
        read -p "  选项 [0-5]: " ch
        echo ""
        case $ch in
            1) do_install ;;
            2) change_region ;;
            3) command -v ge &>/dev/null && ge status \
                || echo -e "  ${RED}未安装${NC}" ;;
            4) command -v ge &>/dev/null && ge test \
                || echo -e "  ${RED}未安装${NC}" ;;
            5) do_uninstall ;;
            0) echo -e "  ${GREEN}Bye!${NC}\n"; exit 0 ;;
            *) echo -e "  ${RED}无效选项${NC}" ;;
        esac
        echo ""
        read -p "  按 Enter 继续..." _
    done
}

main() {
    check_root
    detect_os
    mkdir -p "${WARP_DIR}"
    case "${1:-}" in
        --install)       show_banner; do_install ;;
        --uninstall)     show_banner; do_uninstall ;;
        --change-region) show_banner; change_region ;;
        *)               show_menu ;;
    esac
}

main "$@"
