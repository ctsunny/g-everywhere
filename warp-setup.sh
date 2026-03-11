#!/bin/bash
# G-Everywhere v4.0 - 终极版
# 双引擎: WireGuard (UDP) → 自动降级 warp-cli (TCP fallback)
# https://github.com/ctsunny/g-everywhere

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'
NC='\033[0m'; BOLD='\033[1m'

WG_IFACE="warp0"
WG_CONF="/etc/wireguard/${WG_IFACE}.conf"
WARP_DIR="/etc/warp"
MODE_FILE="${WARP_DIR}/mode"          # "wireguard" 或 "warp-cli"
PORT_FILE="${WARP_DIR}/working_port"

# Cloudflare WARP 全部支持端口（含 UDP 443 和 MASQUE）
WARP_PORTS=(2408 500 1701 4500 8854 894 7559 443)

GOOGLE_IPS="8.8.4.0/24 8.8.8.0/24 34.0.0.0/9 35.184.0.0/13 35.192.0.0/12
35.224.0.0/12 35.240.0.0/13 64.233.160.0/19 66.102.0.0/20 66.249.64.0/19
72.14.192.0/18 74.125.0.0/16 104.132.0.0/14 108.177.0.0/17 142.250.0.0/15
172.217.0.0/16 172.253.0.0/16 173.194.0.0/16 209.85.128.0/17 216.58.192.0/19
216.239.32.0/19"

declare -A ENDPOINTS=(
    ["🌐 自动"]="engage.cloudflareclient.com"
    ["🇺🇸 美国"]="162.159.193.1"
    ["🇯🇵 日本"]="162.159.193.2"
    ["🇸🇬 新加坡"]="162.159.193.3"
    ["🇩🇪 德国"]="162.159.193.4"
    ["🇬🇧 英国"]="162.159.193.5"
    ["🇳🇱 荷兰"]="162.159.193.6"
    ["🇦🇺 澳大利亚"]="162.159.193.7"
    ["🇰🇷 韩国"]="162.159.193.8"
    ["🇭🇰 香港"]="162.159.193.9"
    ["🇨🇦 加拿大"]="162.159.193.10"
    ["🇮🇳 印度"]="162.159.193.11"
    ["🇧🇷 巴西"]="162.159.193.12"
)
REGION_KEYS=("🌐 自动" "🇺🇸 美国" "🇯🇵 日本" "🇸🇬 新加坡" "🇩🇪 德国" "🇬🇧 英国"
             "🇳🇱 荷兰" "🇦🇺 澳大利亚" "🇰🇷 韩国" "🇭🇰 香港" "🇨🇦 加拿大" "🇮🇳 印度" "🇧🇷 巴西")
SELECTED_REGION="🌐 自动"

# ============================================================
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
    echo -e "  ${GREEN}  Google Unlock  ${NC}│${YELLOW}  双引擎 WG+WARP  ${NC}│${MAGENTA}  UDP封锁自动降级  ${NC}"
    echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${BLUE}github.com/ctsunny/g-everywhere${NC}  │  ${GREEN}v4.0${NC}\n"
}
check_root() { [[ $EUID -ne 0 ]] && { echo -e "${RED}请用 root 运行${NC}"; exit 1; }; }
detect_os() {
    [ -f /etc/os-release ] && . /etc/os-release && OS=$ID || { echo -e "${RED}无法检测系统${NC}"; exit 1; }
    ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
}
show_ip() {
    echo -e "  ${YELLOW}当前节点信息${NC}"
    echo -e "  ${CYAN}──────────────────────────────────${NC}"
    IP=$(curl -4 -s --max-time 5 ip.sb 2>/dev/null || echo "获取失败")
    INFO=$(curl -s --max-time 5 "http://ip-api.com/json/$IP?lang=zh-CN" 2>/dev/null)
    echo -e "  IP  : ${GREEN}$IP${NC}"
    echo -e "  位置: ${GREEN}$(echo $INFO | grep -oP '"country":"\K[^"]+') $(echo $INFO | grep -oP '"city":"\K[^"]+')${NC}"
    echo -e "  ISP : ${GREEN}$(echo $INFO | grep -oP '"isp":"\K[^"]+')${NC}"
    echo -e "  ${CYAN}──────────────────────────────────${NC}\n"
}
select_region() {
    echo -e "\n${CYAN}  ── 选择出口地区 ──${NC}\n"
    for i in "${!REGION_KEYS[@]}"; do
        printf "  ${GREEN}%2d.${NC} %s\n" "$((i+1))" "${REGION_KEYS[$i]}"
    done
    echo ""
    read -p "  请选择 [1-${#REGION_KEYS[@]}] (默认1): " c
    c=${c:-1}
    [[ "$c" =~ ^[0-9]+$ ]] && [ "$c" -ge 1 ] && [ "$c" -le "${#REGION_KEYS[@]}" ] && \
        SELECTED_REGION="${REGION_KEYS[$((c-1))]}" || SELECTED_REGION="🌐 自动"
    echo -e "  ${GREEN}✓ 已选择: $SELECTED_REGION${NC}"
}

# ============================================================
# 路由管理（WireGuard 模式：iptables mangle mark）
# ============================================================
wg_routing_start() {
    ip rule del fwmark 51820 table 51820 2>/dev/null || true
    ip route flush table 51820 2>/dev/null || true
    iptables -t mangle -D OUTPUT -j WARP_MARK 2>/dev/null || true
    iptables -t mangle -D PREROUTING -j WARP_MARK 2>/dev/null || true
    iptables -t mangle -F WARP_MARK 2>/dev/null || true
    iptables -t mangle -X WARP_MARK 2>/dev/null || true

    ip rule add fwmark 51820 table 51820
    ip route add default dev ${WG_IFACE} table 51820

    iptables -t mangle -N WARP_MARK
    iptables -t mangle -A WARP_MARK -d 127.0.0.0/8     -j RETURN
    iptables -t mangle -A WARP_MARK -d 10.0.0.0/8      -j RETURN
    iptables -t mangle -A WARP_MARK -d 192.168.0.0/16  -j RETURN
    iptables -t mangle -A WARP_MARK -d 172.16.0.0/12   -j RETURN
    iptables -t mangle -A WARP_MARK -d 162.159.192.0/22 -j RETURN
    for ip in $GOOGLE_IPS; do
        iptables -t mangle -A WARP_MARK -d $ip -j MARK --set-mark 51820
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

# ============================================================
# 路由管理（warp-cli 模式：redsocks + iptables NAT REDIRECT）
# ============================================================
cli_routing_start() {
    pkill -f "redsocks -c /etc/redsocks-warp.conf" 2>/dev/null || true
    sleep 1

    cat > /etc/redsocks-warp.conf << 'EOF'
base {
    log_debug = off; log_info = off;
    daemon = off;
    redirector = iptables;
}
redsocks {
    local_ip = 127.0.0.1; local_port = 12345;
    ip = 127.0.0.1; port = 40000;
    type = socks5;
}
EOF
    redsocks -c /etc/redsocks-warp.conf &
    sleep 1

    iptables -t nat -D OUTPUT    -j WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -D PREROUTING -j WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -F WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -X WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -N WARP_GOOGLE
    iptables -t nat -A WARP_GOOGLE -d 127.0.0.0/8    -j RETURN
    iptables -t nat -A WARP_GOOGLE -d 10.0.0.0/8     -j RETURN
    iptables -t nat -A WARP_GOOGLE -d 192.168.0.0/16 -j RETURN
    iptables -t nat -A WARP_GOOGLE -d 172.16.0.0/12  -j RETURN
    iptables -t nat -A WARP_GOOGLE -d 162.159.192.0/22 -j RETURN
    for ip in $GOOGLE_IPS; do
        iptables -t nat -A WARP_GOOGLE -d $ip -p tcp -j REDIRECT --to-ports 12345
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
            apt-get install -y wireguard wireguard-tools curl wget iptables \
                openresolv redsocks >/dev/null 2>&1
            systemctl stop redsocks 2>/dev/null; systemctl disable redsocks 2>/dev/null
            ;;
        centos|rhel|rocky|almalinux|fedora)
            dnf install -y epel-release >/dev/null 2>&1
            dnf install -y wireguard-tools curl wget iptables redsocks >/dev/null 2>&1
            ;;
    esac
    modprobe wireguard 2>/dev/null || true

    # iptables-legacy（避免 nftables 兼容问题）
    command -v update-alternatives &>/dev/null && {
        update-alternatives --set iptables  /usr/sbin/iptables-legacy  2>/dev/null || true
        update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true
    }

    # 禁用 IPv6（防止绕过 WARP）
    sysctl -w net.ipv6.conf.all.disable_ipv6=1    >/dev/null 2>&1
    sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1
    grep -q "disable_ipv6" /etc/sysctl.conf 2>/dev/null || {
        echo "net.ipv6.conf.all.disable_ipv6=1"     >> /etc/sysctl.conf
        echo "net.ipv6.conf.default.disable_ipv6=1" >> /etc/sysctl.conf
    }

    # 下载 wgcf
    VER=$(curl -s --max-time 10 \
        https://api.github.com/repos/ViRb3/wgcf/releases/latest \
        | grep tag_name | cut -d'"' -f4 2>/dev/null)
    [ -z "$VER" ] && VER="v2.2.25"
    curl -fsSL "https://github.com/ViRb3/wgcf/releases/download/${VER}/wgcf_${VER#v}_linux_${ARCH}" \
        -o /usr/local/bin/wgcf 2>/dev/null
    [ ! -s /usr/local/bin/wgcf ] && \
        curl -fsSL "https://github.com/ViRb3/wgcf/releases/download/v2.2.25/wgcf_2.2.25_linux_${ARCH}" \
        -o /usr/local/bin/wgcf
    chmod +x /usr/local/bin/wgcf
    command -v wgcf &>/dev/null || { echo -e "${RED}  wgcf 安装失败${NC}"; exit 1; }
    echo -e "  ${GREEN}✓ 依赖安装完成${NC}"
}

# ============================================================
# 生成 wgcf 配置（在 /tmp 操作，避免同文件 cp 警告）
# ============================================================
setup_wgcf_config() {
    echo -e "\n${CYAN}  [2/4] 生成 WireGuard 配置...${NC}"
    mkdir -p ${WARP_DIR} /etc/wireguard
    cd /tmp; rm -f /tmp/wgcf-account.toml /tmp/wgcf-profile.conf

    [ -f ${WARP_DIR}/wgcf-account.toml ] && \
        cp ${WARP_DIR}/wgcf-account.toml /tmp/ && \
        echo -e "  ${GREEN}复用已有账号${NC}" || echo -e "  注册新 WARP 设备..."

    wgcf register --accept-tos >/dev/null 2>&1
    [ -f /tmp/wgcf-account.toml ] && cp /tmp/wgcf-account.toml ${WARP_DIR}/

    wgcf generate >/dev/null 2>&1
    [ ! -f /tmp/wgcf-profile.conf ] && { echo -e "${RED}  配置生成失败${NC}"; exit 1; }

    sed -i '/^DNS/d'   /tmp/wgcf-profile.conf
    sed -i '/^Table/d' /tmp/wgcf-profile.conf
    sed -i '/^\[Interface\]/a Table = off' /tmp/wgcf-profile.conf
    # 仅保留 IPv4 地址（系统已禁用 IPv6）
    sed -i '/^Address/s/, .*\/128//'     /tmp/wgcf-profile.conf
    sed -i '/^AllowedIPs/d'              /tmp/wgcf-profile.conf
    echo "AllowedIPs = 0.0.0.0/0"      >> /tmp/wgcf-profile.conf
    # 加 keepalive 帮助保持连接
    grep -q "PersistentKeepalive" /tmp/wgcf-profile.conf || \
        echo "PersistentKeepalive = 25" >> /tmp/wgcf-profile.conf

    TARGET_IP="${ENDPOINTS[$SELECTED_REGION]}"
    sed -i "s/Endpoint = .*/Endpoint = $TARGET_IP:2408/" /tmp/wgcf-profile.conf

    cp /tmp/wgcf-profile.conf ${WARP_DIR}/wgcf-profile.conf
    cp /tmp/wgcf-profile.conf ${WG_CONF}
    echo -e "  ${GREEN}✓ 配置生成完成${NC}"
    grep -E "^(Address|Endpoint)" ${WG_CONF} | sed 's/^/  /'
}

# ============================================================
# ★ 核心：扫描可用端口（轻量级，用 wg 命令直接测）
# ============================================================
scan_working_port() {
    local TARGET_IP="$1"
    echo -e "\n  ${CYAN}扫描可用 UDP 端口...${NC}"

    PRIVKEY=$(grep "^PrivateKey" ${WG_CONF} | awk '{print $3}')
    PEER_PUB=$(grep "^PublicKey"  ${WG_CONF} | awk '{print $3}')

    for PORT in "${WARP_PORTS[@]}"; do
        printf "    UDP %-6s → " "$PORT"

        # 临时建一个纯 WireGuard 接口测握手（不用 wg-quick，不修改路由）
        ip link del _warp_test 2>/dev/null || true
        ip link add _warp_test type wireguard 2>/dev/null || { echo -e "${RED}内核不支持 WireGuard${NC}"; return 1; }
        wg set _warp_test \
            private-key <(echo "$PRIVKEY") \
            peer "$PEER_PUB" \
            endpoint "${TARGET_IP}:${PORT}" \
            allowed-ips 0.0.0.0/0 \
            persistent-keepalive 5 2>/dev/null
        ip link set _warp_test up 2>/dev/null
        sleep 6

        HS=$(wg show _warp_test latest-handshakes 2>/dev/null | awk '{print $2}')
        ip link del _warp_test 2>/dev/null

        if [ -n "$HS" ] && [ "$HS" != "0" ]; then
            echo -e "${GREEN}✓ 握手成功！${NC}"
            echo "$PORT" > ${PORT_FILE}
            sed -i "s/Endpoint = .*/Endpoint = ${TARGET_IP}:${PORT}/" ${WG_CONF}
            sed -i "s/Endpoint = .*/Endpoint = ${TARGET_IP}:${PORT}/" ${WARP_DIR}/wgcf-profile.conf
            return 0
        fi
        echo -e "${RED}✗ 超时${NC}"
    done
    return 1
}

# ============================================================
# ★ 引擎一：WireGuard 模式
# ============================================================
engine_wireguard() {
    echo -e "\n${CYAN}  [3/4] 引擎一：WireGuard + 端口扫描...${NC}"
    TARGET_IP="${ENDPOINTS[$SELECTED_REGION]}"

    if scan_working_port "$TARGET_IP"; then
        WORKING_PORT=$(cat ${PORT_FILE})
        echo -e "\n  ${GREEN}✓ 使用端口 UDP $WORKING_PORT${NC}"

        ip link del ${WG_IFACE} 2>/dev/null || true; sleep 1
        wg-quick up ${WG_CONF} 2>&1
        sleep 3

        if ! ip link show ${WG_IFACE} &>/dev/null; then
            echo -e "  ${RED}wg-quick 启动失败${NC}"; return 1
        fi

        # 等待正式握手
        echo -e "  等待握手确认..."
        for i in $(seq 1 10); do
            sleep 2
            HS=$(wg show ${WG_IFACE} latest-handshakes 2>/dev/null | awk '{print $2}')
            [ -n "$HS" ] && [ "$HS" != "0" ] && {
                echo -e "  ${GREEN}✓ 握手成功 (${i}次)${NC}"
                echo "wireguard" > ${MODE_FILE}
                wg_routing_start
                echo -e "  ${GREEN}✓ WireGuard 路由建立完成${NC}"
                return 0
            }
        done
        echo -e "  ${YELLOW}握手超时，尝试降级...${NC}"
        wg-quick down ${WG_IFACE} 2>/dev/null
        return 1
    fi
    echo -e "\n  ${YELLOW}所有 UDP 端口均不可用，启动降级引擎...${NC}"
    return 1
}

# ============================================================
# ★ 引擎二：warp-cli 降级模式（TCP fallback）
# ============================================================
install_warp_cli() {
    echo -e "  ${CYAN}安装 Cloudflare WARP 客户端...${NC}"
    case $OS in
        ubuntu|debian)
            CODENAME=$(. /etc/os-release && echo $VERSION_CODENAME)
            curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | \
                gpg --yes --dearmor \
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
            cat > /etc/yum.repos.d/cloudflare-warp.repo << 'EOF'
[cloudflare-warp]
name=Cloudflare WARP
baseurl=https://pkg.cloudflareclient.com/rpm
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/cloudflare-warp.gpg
EOF
            dnf install -y cloudflare-warp >/dev/null 2>&1
            ;;
    esac
    command -v warp-cli &>/dev/null || { echo -e "  ${RED}warp-cli 安装失败${NC}"; return 1; }
    echo -e "  ${GREEN}✓ warp-cli 安装完成${NC}"
}

engine_warp_cli() {
    echo -e "\n${CYAN}  [3/4] 引擎二：warp-cli (TCP fallback 模式)...${NC}"

    install_warp_cli || return 1

    systemctl start warp-svc 2>/dev/null; sleep 2
    warp-cli --accept-tos registration new 2>/dev/null || \
        warp-cli --accept-tos register 2>/dev/null || true
    sleep 1
    warp-cli --accept-tos mode proxy 2>/dev/null || \
        warp-cli --accept-tos set-mode proxy 2>/dev/null || true
    warp-cli --accept-tos proxy port 40000 2>/dev/null || \
        warp-cli --accept-tos set-proxy-port 40000 2>/dev/null || true

    # 设置地区 endpoint
    TARGET_IP="${ENDPOINTS[$SELECTED_REGION]}"
    if [ "$SELECTED_REGION" != "🌐 自动" ]; then
        warp-cli --accept-tos set-custom-endpoint "${TARGET_IP}:2408" 2>/dev/null || true
    fi

    warp-cli --accept-tos connect 2>/dev/null
    echo -e "  连接中，等待 8 秒..."
    sleep 8

    STATUS=$(warp-cli status 2>/dev/null)
    if echo "$STATUS" | grep -qi "connected"; then
        echo -e "  ${GREEN}✓ warp-cli 已连接${NC}"

        # 测试 SOCKS5 可用性
        SOCKS_IP=$(curl -x socks5://127.0.0.1:40000 -s --max-time 8 ip.sb 2>/dev/null)
        if [ -n "$SOCKS_IP" ]; then
            echo -e "  ${GREEN}✓ SOCKS5 可用，出口 IP: $SOCKS_IP${NC}"
            echo "warp-cli" > ${MODE_FILE}
            cli_routing_start
            echo -e "  ${GREEN}✓ warp-cli 透明代理建立完成${NC}"
            return 0
        fi
    fi

    echo -e "  ${RED}warp-cli 也无法连接！${NC}"
    echo -e "  ${YELLOW}请检查 VPS 出站防火墙是否允许 TCP 443 和 UDP 2408${NC}"
    return 1
}

# ============================================================
# 验证出口
# ============================================================
verify_exit() {
    echo -e "\n${CYAN}  [4/4] 验证出口...${NC}"
    sleep 2

    CODE=$(curl -s --max-time 12 -o /dev/null -w "%{http_code}" https://www.google.com)
    if [ "$CODE" = "200" ] || [ "$CODE" = "301" ]; then
        echo -e "  ${GREEN}✓ Google 可达 HTTP $CODE${NC}"
    else
        echo -e "  ${YELLOW}Google HTTP $CODE，等待 15 秒再试...${NC}"
        sleep 15
        CODE=$(curl -s --max-time 12 -o /dev/null -w "%{http_code}" https://www.google.com)
        echo -e "  重试: HTTP $CODE"
    fi

    # 获取出口 IP
    MODE=$(cat ${MODE_FILE} 2>/dev/null || echo "wireguard")
    if [ "$MODE" = "wireguard" ]; then
        EXIT_IP=$(curl -s --max-time 10 \
            "https://dns.google/resolve?name=myip.opendns.com&type=A" \
            | grep -oP '"data":"\K[^"]+' | head -1 2>/dev/null)
    else
        EXIT_IP=$(curl -x socks5://127.0.0.1:40000 -s --max-time 10 ip.sb 2>/dev/null)
    fi
    [ -z "$EXIT_IP" ] && EXIT_IP=$(curl -s --max-time 8 ip.sb 2>/dev/null)

    if [ -n "$EXIT_IP" ]; then
        INFO=$(curl -s --max-time 5 "http://ip-api.com/json/$EXIT_IP?lang=zh-CN" 2>/dev/null)
        C=$(echo $INFO | grep -oP '"country":"\K[^"]+' || echo "未知")
        T=$(echo $INFO | grep -oP '"city":"\K[^"]+' || echo "")
        ISP=$(echo $INFO | grep -oP '"isp":"\K[^"]+' || echo "")
        echo -e "  出口 IP  : ${GREEN}$EXIT_IP${NC}"
        echo -e "  出口地区 : ${GREEN}$C $T${NC}"
        echo -e "  ISP      : ${GREEN}$ISP${NC}"
    fi
}

setup_autostart() {
    MODE=$(cat ${MODE_FILE} 2>/dev/null || echo "wireguard")
    if [ "$MODE" = "wireguard" ]; then
        START_CMD="wg-quick up ${WG_CONF} && sleep 3 && /usr/local/bin/ge start-routing wg"
        STOP_CMD="/usr/local/bin/ge stop-routing && wg-quick down ${WG_IFACE}"
    else
        START_CMD="systemctl start warp-svc && sleep 3 && warp-cli --accept-tos connect && sleep 5 && /usr/local/bin/ge start-routing cli"
        STOP_CMD="/usr/local/bin/ge stop-routing && warp-cli --accept-tos disconnect"
    fi
    cat > /etc/systemd/system/g-everywhere.service << EOF
[Unit]
Description=G-Everywhere Google Routing v4.0
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c '${START_CMD}'
ExecStop=/bin/bash -c '${STOP_CMD}'

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable g-everywhere 2>/dev/null
}

# ============================================================
# 管理命令 ge
# ============================================================
create_ge() {
    rm -f /usr/local/bin/g /usr/local/bin/g-e /usr/local/bin/g-proxy

    cat > /usr/local/bin/ge << 'GEOF'
#!/bin/bash
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'
WG_IFACE="warp0"
WG_CONF="/etc/wireguard/${WG_IFACE}.conf"
WARP_DIR="/etc/warp"
MODE_FILE="${WARP_DIR}/mode"
GOOGLE_IPS="8.8.4.0/24 8.8.8.0/24 34.0.0.0/9 35.184.0.0/13 35.192.0.0/12 35.224.0.0/12
35.240.0.0/13 64.233.160.0/19 66.102.0.0/20 66.249.64.0/19 72.14.192.0/18 74.125.0.0/16
104.132.0.0/14 108.177.0.0/17 142.250.0.0/15 172.217.0.0/16 172.253.0.0/16 173.194.0.0/16
209.85.128.0/17 216.58.192.0/19 216.239.32.0/19"
WARP_PORTS=(2408 500 1701 4500 8854 894 7559 443)

_wg_routing_start() {
    ip rule del fwmark 51820 table 51820 2>/dev/null || true
    ip route flush table 51820 2>/dev/null || true
    iptables -t mangle -D OUTPUT    -j WARP_MARK 2>/dev/null || true
    iptables -t mangle -D PREROUTING -j WARP_MARK 2>/dev/null || true
    iptables -t mangle -F WARP_MARK 2>/dev/null || true
    iptables -t mangle -X WARP_MARK 2>/dev/null || true
    ip rule add fwmark 51820 table 51820
    ip route add default dev $WG_IFACE table 51820
    iptables -t mangle -N WARP_MARK
    for net in 127.0.0.0/8 10.0.0.0/8 192.168.0.0/16 172.16.0.0/12 162.159.192.0/22; do
        iptables -t mangle -A WARP_MARK -d $net -j RETURN
    done
    for ip in $GOOGLE_IPS; do
        iptables -t mangle -A WARP_MARK -d $ip -j MARK --set-mark 51820
    done
    iptables -t mangle -A OUTPUT    -j WARP_MARK
    iptables -t mangle -A PREROUTING -j WARP_MARK
}
_cli_routing_start() {
    pkill -f "redsocks -c /etc/redsocks-warp.conf" 2>/dev/null || true; sleep 1
    cat > /etc/redsocks-warp.conf << 'EOF'
base { log_debug=off; log_info=off; daemon=off; redirector=iptables; }
redsocks { local_ip=127.0.0.1; local_port=12345; ip=127.0.0.1; port=40000; type=socks5; }
EOF
    redsocks -c /etc/redsocks-warp.conf &; sleep 1
    iptables -t nat -D OUTPUT    -j WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -D PREROUTING -j WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -F WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -X WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -N WARP_GOOGLE
    for net in 127.0.0.0/8 10.0.0.0/8 192.168.0.0/16 172.16.0.0/12 162.159.192.0/22; do
        iptables -t nat -A WARP_GOOGLE -d $net -j RETURN
    done
    for ip in $GOOGLE_IPS; do
        iptables -t nat -A WARP_GOOGLE -d $ip -p tcp -j REDIRECT --to-ports 12345
    done
    iptables -t nat -A OUTPUT    -j WARP_GOOGLE
    iptables -t nat -A PREROUTING -j WARP_GOOGLE
}
_stop_routing() {
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
_get_exit_ip() {
    MODE=$(cat $MODE_FILE 2>/dev/null || echo "wireguard")
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
        [ "$2" = "cli" ] && _cli_routing_start || _wg_routing_start
        echo -e "${GREEN}✓ 路由已建立 ($(cat $MODE_FILE 2>/dev/null) 模式)${NC}" ;;

    stop-routing) _stop_routing; echo -e "${GREEN}✓ 路由已清除${NC}" ;;

    start)
        MODE=$(cat $MODE_FILE 2>/dev/null || echo "wireguard")
        if [ "$MODE" = "wireguard" ]; then
            wg-quick up $WG_CONF 2>/dev/null; sleep 3; _wg_routing_start
        else
            systemctl start warp-svc 2>/dev/null; sleep 2
            warp-cli --accept-tos connect 2>/dev/null; sleep 5; _cli_routing_start
        fi
        echo -e "${GREEN}✓ 已启动 ($MODE 模式)${NC}" ;;

    stop)
        _stop_routing
        wg-quick down $WG_IFACE 2>/dev/null
        warp-cli --accept-tos disconnect 2>/dev/null
        echo -e "${GREEN}✓ 已停止${NC}" ;;

    restart) $0 stop; sleep 2; $0 start ;;

    status)
        MODE=$(cat $MODE_FILE 2>/dev/null || echo "未知")
        echo -e "\n${CYAN}── 运行模式: $MODE ──${NC}"
        if [ "$MODE" = "wireguard" ]; then
            ip link show $WG_IFACE &>/dev/null && \
                echo -e "${GREEN}✓ WireGuard 运行中${NC}" || echo -e "${RED}✗ WireGuard 未运行${NC}"
            wg show $WG_IFACE 2>/dev/null | grep -E "endpoint|latest handshake|transfer" | sed 's/^/  /'
            PORT=$(cat $WARP_DIR/working_port 2>/dev/null || echo "?"); echo "  工作端口: UDP $PORT"
        else
            warp-cli status 2>/dev/null | head -3 | sed 's/^/  /'
            echo -e "  SOCKS5 端口: 40000"
        fi
        echo -e "\n${CYAN}── Google 出口 ──${NC}"
        CODE=$(curl -s --max-time 8 -o /dev/null -w "%{http_code}" https://www.google.com)
        echo -e "  HTTP $CODE"
        EXIT=$(_get_exit_ip)
        [ -n "$EXIT" ] && echo -e "  IP: ${GREEN}$EXIT${NC}"
        echo "" ;;

    test)
        MODE=$(cat $MODE_FILE 2>/dev/null || echo "未知")
        echo -e "\n${CYAN}── 诊断 (模式: $MODE) ──${NC}\n"
        if [ "$MODE" = "wireguard" ]; then
            HS=$(wg show $WG_IFACE latest-handshakes 2>/dev/null | awk '{print $2}')
            [ -n "$HS" ] && [ "$HS" != "0" ] && \
                echo -e "${YELLOW}[WireGuard]${NC} ${GREEN}✓ 已握手${NC}" || \
                echo -e "${YELLOW}[WireGuard]${NC} ${RED}✗ 未握手${NC}"
        else
            warp-cli status 2>/dev/null | grep -i "connected" && \
                echo -e "${YELLOW}[warp-cli]${NC} ${GREEN}✓ 已连接${NC}" || \
                echo -e "${YELLOW}[warp-cli]${NC} ${RED}✗ 未连接${NC}"
        fi
        CNT=$(iptables -t mangle -L WARP_MARK -n 2>/dev/null | grep -c MARK 2>/dev/null || \
              iptables -t nat   -L WARP_GOOGLE -n 2>/dev/null | grep -c REDIRECT 2>/dev/null || echo 0)
        echo -e "${YELLOW}[路由规则]${NC} $CNT 条"
        C=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" https://www.google.com)
        [ "$C" = "200" ] || [ "$C" = "301" ] && \
            echo -e "${YELLOW}[Google]${NC}   ${GREEN}✓ HTTP $C${NC}" || \
            echo -e "${YELLOW}[Google]${NC}   ${RED}✗ HTTP $C${NC}"
        G=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" \
            -H "User-Agent: Mozilla/5.0" https://gemini.google.com)
        [ "$G" = "200" ] || [ "$G" = "301" ] && \
            echo -e "${YELLOW}[Gemini]${NC}   ${GREEN}✓ HTTP $G${NC}" || \
            echo -e "${YELLOW}[Gemini]${NC}   ${RED}✗ HTTP $G${NC}"
        echo "" ;;

    fix)
        echo -e "${CYAN}修复中...${NC}"
        _stop_routing
        MODE=$(cat $MODE_FILE 2>/dev/null || echo "wireguard")
        if [ "$MODE" = "wireguard" ]; then
            wg-quick down $WG_IFACE 2>/dev/null; sleep 1
            # 重试端口扫描
            PRIVKEY=$(grep "^PrivateKey" $WG_CONF | awk '{print $3}')
            PEER_PUB=$(grep "^PublicKey"  $WG_CONF | awk '{print $3}')
            EP_IP=$(grep "^Endpoint" $WG_CONF | awk '{print $3}' | cut -d: -f1)
            FOUND=""
            for PORT in "${WARP_PORTS[@]}"; do
                printf "  测试端口 UDP %-6s " "$PORT"
                ip link del _warp_test 2>/dev/null || true
                ip link add _warp_test type wireguard 2>/dev/null
                wg set _warp_test private-key <(echo "$PRIVKEY") \
                    peer "$PEER_PUB" endpoint "${EP_IP}:${PORT}" \
                    allowed-ips 0.0.0.0/0 persistent-keepalive 5 2>/dev/null
                ip link set _warp_test up 2>/dev/null; sleep 6
                HS=$(wg show _warp_test latest-handshakes 2>/dev/null | awk '{print $2}')
                ip link del _warp_test 2>/dev/null
                if [ -n "$HS" ] && [ "$HS" != "0" ]; then
                    echo -e "${GREEN}✓ 成功${NC}"
                    sed -i "s/Endpoint = .*/Endpoint = ${EP_IP}:${PORT}/" $WG_CONF
                    echo "$PORT" > $WARP_DIR/working_port
                    FOUND="yes"; break
                fi; echo -e "${RED}✗${NC}"
            done
            if [ -n "$FOUND" ]; then
                wg-quick up $WG_CONF; sleep 3; _wg_routing_start
            else
                echo -e "${RED}WireGuard 无可用端口，请运行 ge 重新安装选择降级引擎${NC}"
            fi
        else
            warp-cli --accept-tos disconnect 2>/dev/null; sleep 1
            warp-cli --accept-tos connect 2>/dev/null; sleep 6
            _cli_routing_start
        fi
        C=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" https://www.google.com)
        [ "$C" = "200" ] || [ "$C" = "301" ] && \
            echo -e "${GREEN}✓ 修复成功 HTTP $C${NC}" || \
            echo -e "${RED}✗ 仍异常 HTTP $C${NC}" ;;

    ip)
        echo -e "\n${YELLOW}直连 IP:${NC}"; curl -4 -s --max-time 5 ip.sb; echo ""
        echo -e "${YELLOW}WARP 出口 IP:${NC}"
        EXIT=$(_get_exit_ip)
        if [ -n "$EXIT" ]; then
            INFO=$(curl -s --max-time 5 "http://ip-api.com/json/$EXIT?lang=zh-CN" 2>/dev/null)
            C=$(echo $INFO | grep -oP '"country":"\K[^"]+' || echo "未知")
            T=$(echo $INFO | grep -oP '"city":"\K[^"]+' || echo "")
            echo -e "${GREEN}$EXIT  ($C $T)${NC}"
        else echo -e "${RED}获取失败${NC}"; fi; echo "" ;;

    scan)
        echo -e "\n${CYAN}── 扫描节点 + 端口 ──${NC}\n"
        MODE=$(cat $MODE_FILE 2>/dev/null || echo "wireguard")
        [ "$MODE" != "wireguard" ] && { echo -e "${YELLOW}当前为 warp-cli 模式，scan 仅适用于 WireGuard 模式${NC}"; exit 0; }
        [ ! -f $WG_CONF ] && { echo -e "${RED}请先安装${NC}"; exit 1; }
        PRIVKEY=$(grep "^PrivateKey" $WG_CONF | awk '{print $3}')
        PEER_PUB=$(grep "^PublicKey"  $WG_CONF | awk '{print $3}')
        printf "  %-6s %-25s %-16s %s\n" "序号" "Endpoint" "出口IP" "Gemini"
        echo -e "  ${CYAN}──────────────────────────────────────────────────${NC}"
        BEST_EP=""; BEST_PORT=""
        for i in $(seq 1 12); do
            EP_IP="162.159.193.$i"
            for PORT in 2408 500 1701 4500; do
                ip link del _warp_test 2>/dev/null || true
                ip link add _warp_test type wireguard 2>/dev/null
                wg set _warp_test private-key <(echo "$PRIVKEY") \
                    peer "$PEER_PUB" endpoint "${EP_IP}:${PORT}" \
                    allowed-ips 0.0.0.0/0 persistent-keepalive 5 2>/dev/null
                ip link set _warp_test up 2>/dev/null; sleep 6
                HS=$(wg show _warp_test latest-handshakes 2>/dev/null | awk '{print $2}')
                ip link del _warp_test 2>/dev/null
                [ -z "$HS" ] || [ "$HS" = "0" ] && continue

                # 端口可用，测 Google
                sed -i "s/Endpoint = .*/Endpoint = ${EP_IP}:${PORT}/" $WG_CONF
                wg-quick down $WG_IFACE 2>/dev/null; sleep 1
                wg-quick up $WG_CONF 2>/dev/null; sleep 3
                _stop_routing 2>/dev/null; _wg_routing_start 2>/dev/null
                GC=$(curl -s --max-time 8 -o /dev/null -w "%{http_code}" \
                    -H "User-Agent: Mozilla/5.0" https://gemini.google.com)
                OUT=$(curl -s --max-time 6 \
                    "https://dns.google/resolve?name=myip.opendns.com&type=A" \
                    | grep -oP '"data":"\K[^"]+' | head -1 2>/dev/null || echo "?")
                INFO=$(curl -s --max-time 4 "http://ip-api.com/json/$OUT?lang=zh-CN" 2>/dev/null)
                C=$(echo $INFO | grep -oP '"country":"\K[^"]+' || echo "?")
                T=$(echo $INFO | grep -oP '"city":"\K[^"]+' || echo "")
                if [ "$GC" = "200" ] || [ "$GC" = "301" ]; then
                    printf "  ${GREEN}%-6s %-25s %-16s ✅ %s${NC}\n" "#$i" "${EP_IP}:${PORT}" "$C $T" "$GC"
                    [ -z "$BEST_EP" ] && BEST_EP="$EP_IP" && BEST_PORT="$PORT"
                else
                    printf "  ${YELLOW}%-6s %-25s %-16s ✗ %s${NC}\n" "#$i" "${EP_IP}:${PORT}" "$C $T" "$GC"
                fi
                break
            done
        done
        echo ""
        if [ -n "$BEST_EP" ]; then
            echo -e "  ${GREEN}最佳: ${BEST_EP}:${BEST_PORT}${NC}"
            read -p "  应用? [Y/n]: " yn; yn=${yn:-Y}
            [[ "$yn" =~ ^[Yy] ]] && {
                sed -i "s/Endpoint = .*/Endpoint = ${BEST_EP}:${BEST_PORT}/" $WG_CONF
                echo "$BEST_PORT" > $WARP_DIR/working_port
                _stop_routing; wg-quick down $WG_IFACE 2>/dev/null; sleep 1
                wg-quick up $WG_CONF; sleep 3; _wg_routing_start
                echo -e "  ${GREEN}✓ 已应用${NC}"
            }
        fi ;;

    region)
        bash /usr/local/bin/warp-setup.sh --change-region 2>/dev/null || \
        bash <(curl -fsSL https://raw.githubusercontent.com/ctsunny/g-everywhere/main/warp-setup.sh) --change-region ;;

    uninstall)
        _stop_routing
        wg-quick down $WG_IFACE 2>/dev/null
        warp-cli --accept-tos disconnect 2>/dev/null
        systemctl disable --now g-everywhere warp-svc 2>/dev/null
        rm -f /etc/systemd/system/g-everywhere.service
        rm -f /usr/local/bin/ge /usr/local/bin/warp-setup.sh /usr/local/bin/wgcf
        rm -rf /etc/warp; rm -f $WG_CONF
        echo -e "${GREEN}✓ 卸载完成${NC}" ;;

    *)
        echo -e "${CYAN}ge 管理命令 v4.0${NC}\n"
        MODE=$(cat $MODE_FILE 2>/dev/null || echo "未知")
        echo -e "  当前模式: ${GREEN}$MODE${NC}\n"
        echo "  start / stop / restart  status  test"
        echo "  fix   ip   region   scan   uninstall" ;;
esac
GEOF
    chmod +x /usr/local/bin/ge
    cp "$0" /usr/local/bin/warp-setup.sh 2>/dev/null || true
    chmod +x /usr/local/bin/warp-setup.sh 2>/dev/null || true
}

change_region() {
    echo -e "\n${CYAN}  ── 切换出口地区 ──${NC}"
    MODE=$(cat ${MODE_FILE} 2>/dev/null || echo "wireguard")
    echo -e "  当前模式: ${GREEN}$MODE${NC}"
    select_region
    TARGET_IP="${ENDPOINTS[$SELECTED_REGION]}"

    if [ "$MODE" = "wireguard" ]; then
        PORT=$(cat ${PORT_FILE} 2>/dev/null || echo "2408")
        sed -i "s/Endpoint = .*/Endpoint = ${TARGET_IP}:${PORT}/" ${WG_CONF}
        sed -i "s/Endpoint = .*/Endpoint = ${TARGET_IP}:${PORT}/" ${WARP_DIR}/wgcf-profile.conf 2>/dev/null
        wg_routing_stop; wg-quick down ${WG_IFACE} 2>/dev/null; sleep 1
        wg-quick up ${WG_CONF}; sleep 4; wg_routing_start
    else
        [ "$SELECTED_REGION" != "🌐 自动" ] && \
            warp-cli --accept-tos set-custom-endpoint "${TARGET_IP}:2408" 2>/dev/null || \
            warp-cli --accept-tos clear-custom-endpoint 2>/dev/null
        cli_routing_stop
        warp-cli --accept-tos disconnect 2>/dev/null; sleep 1
        warp-cli --accept-tos connect 2>/dev/null; sleep 6
        cli_routing_start
    fi

    CODE=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" https://www.google.com)
    [ "$CODE" = "200" ] || [ "$CODE" = "301" ] && \
        echo -e "  ${GREEN}✓ 切换成功 HTTP $CODE${NC}" || \
        echo -e "  ${YELLOW}HTTP $CODE${NC}"
}

do_install() {
    select_region
    install_deps
    setup_wgcf_config

    # 尝试引擎一（WireGuard）
    if engine_wireguard; then
        ENGINE_USED="WireGuard (UDP $(cat ${PORT_FILE} 2>/dev/null))"
    # 降级到引擎二（warp-cli）
    elif engine_warp_cli; then
        ENGINE_USED="warp-cli (TCP fallback)"
    else
        echo -e "\n${RED}  两个引擎均无法连接！${NC}"
        echo -e "  ${YELLOW}VPS 出站 UDP 和 TCP 443 均被封锁${NC}"
        echo -e "  ${YELLOW}请联系 VPS 提供商开放出站防火墙${NC}"
        exit 1
    fi

    setup_autostart
    create_ge
    verify_exit

    MODE=$(cat ${MODE_FILE} 2>/dev/null)
    echo -e "\n${BOLD}${GREEN}"
    echo "  ┌──────────────────────────────────────────┐"
    echo "  │       ✅  安装成功！Google 已解锁          │"
    echo "  └──────────────────────────────────────────┘"
    echo -e "${NC}"
    echo -e "  ${YELLOW}出口地区 :${NC} ${GREEN}$SELECTED_REGION${NC}"
    echo -e "  ${YELLOW}引擎模式 :${NC} ${GREEN}$ENGINE_USED${NC}"
    echo -e "\n  ${CYAN}━━━━━ 管理命令 (ge) ━━━━━${NC}"
    echo -e "  start/stop/restart  status  test"
    echo -e "  fix  ip  region  scan  uninstall"
    echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

do_uninstall() {
    all_routing_stop
    wg-quick down ${WG_IFACE} 2>/dev/null || true
    warp-cli --accept-tos disconnect 2>/dev/null || true
    systemctl disable --now g-everywhere warp-svc 2>/dev/null || true
    rm -f /etc/systemd/system/g-everywhere.service
    rm -f /usr/local/bin/ge /usr/local/bin/warp-setup.sh /usr/local/bin/wgcf
    rm -f /usr/local/bin/g /usr/local/bin/g-e /usr/local/bin/g-proxy
    rm -rf /etc/warp; rm -f ${WG_CONF}
    echo -e "  ${GREEN}✓ 卸载完成${NC}\n"
}

show_menu() {
    while true; do
        show_banner; show_ip
        MODE=$(cat ${MODE_FILE} 2>/dev/null)
        [ -n "$MODE" ] && echo -e "  ${CYAN}当前引擎: $MODE${NC}\n"
        echo -e "  ${YELLOW}请选择:${NC}\n"
        echo -e "  ${GREEN}1.${NC} 安装"
        echo -e "  ${GREEN}2.${NC} 切换地区"
        echo -e "  ${GREEN}3.${NC} 查看状态"
        echo -e "  ${GREEN}4.${NC} 扫描节点"
        echo -e "  ${GREEN}5.${NC} 卸载"
        echo -e "  ${GREEN}0.${NC} 退出\n"
        read -p "  选项 [0-5]: " ch; echo ""
        case $ch in
            1) do_install ;;
            2) change_region ;;
            3) command -v ge &>/dev/null && ge status || echo -e "  ${RED}未安装${NC}" ;;
            4) command -v ge &>/dev/null && ge scan  || echo -e "  ${RED}未安装${NC}" ;;
            5) do_uninstall ;;
            0) echo -e "  ${GREEN}Bye!${NC}\n"; exit 0 ;;
            *) echo -e "  ${RED}无效${NC}" ;;
        esac
        echo ""; read -p "  按 Enter 继续..." _
    done
}

main() {
    check_root; detect_os
    case "${1:-}" in
        --install)        show_banner; do_install ;;
        --uninstall)      show_banner; do_uninstall ;;
        --change-region)  show_banner; change_region ;;
        --scan)           show_banner; ge scan 2>/dev/null ;;
        *)                show_menu ;;
    esac
}
main "$@"
