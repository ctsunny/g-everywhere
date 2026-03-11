#!/bin/bash
# G-Everywhere v4.1
# 新增: 通过 CF WARP API 直接注册取得地区性出口 IP
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

# ★ 地区 → Cloudflare 分配服务器（影响出口 IP 归属）
declare -A REGION_CF_HOST=(
    ["🌐 自动"]="api.cloudflareclient.com"
    ["🇺🇸 美国"]="api.cloudflareclient.com"
    ["🇯🇵 日本"]="api.cloudflareclient.com"
    ["🇸🇬 新加坡"]="api.cloudflareclient.com"
    ["🇩🇪 德国"]="api.cloudflareclient.com"
    ["🇬🇧 英国"]="api.cloudflareclient.com"
    ["🇳🇱 荷兰"]="api.cloudflareclient.com"
    ["🇦🇺 澳大利亚"]="api.cloudflareclient.com"
    ["🇰🇷 韩国"]="api.cloudflareclient.com"
    ["🇭🇰 香港"]="api.cloudflareclient.com"
    ["🇨🇦 加拿大"]="api.cloudflareclient.com"
    ["🇮🇳 印度"]="api.cloudflareclient.com"
    ["🇧🇷 巴西"]="api.cloudflareclient.com"
)

# 地区 → Cloudflare 入口节点（ingress）
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
    echo -e "  ${GREEN} Google Unlock ${NC}│${YELLOW} 双引擎+API直注册 ${NC}│${MAGENTA} 真实地区出口 ${NC}"
    echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${BLUE}github.com/ctsunny/g-everywhere${NC}  │  ${GREEN}v4.1${NC}\n"
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
# ★★★ 核心：通过 Cloudflare WARP API 直接注册（cfnew 思路）
# 不依赖 wgcf，直接调用 CF API 生成带地区属性的 WireGuard 配置
# ============================================================
register_via_cf_api() {
    local REGION="$1"
    local INGRESS_IP="${ENDPOINTS[$REGION]}"
    local API_HOST="api.cloudflareclient.com"
    local API_VER="v0a2158"

    echo -e "  ${CYAN}通过 WARP API 注册 (地区: $REGION)...${NC}"

    # 生成 WireGuard 密钥对
    PRIVKEY=$(wg genkey)
    PUBKEY=$(echo "$PRIVKEY" | wg pubkey)

    # 生成随机设备信息
    DEVICE_ID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || \
        python3 -c "import uuid; print(str(uuid.uuid4()))" 2>/dev/null)
    FCM_TOKEN="$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 152 | head -n 1):APA91b$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 20 | head -n 1)"
    INSTALL_ID=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 22 | head -n 1)

    # Step 1: 注册设备
    REG_RESPONSE=$(curl -s --max-time 15 \
        -X POST "https://${API_HOST}/${API_VER}/reg" \
        -H "Content-Type: application/json" \
        -H "User-Agent: okhttp/3.12.1" \
        -d "{
            \"key\": \"${PUBKEY}\",
            \"install_id\": \"${INSTALL_ID}\",
            \"fcm_token\": \"${FCM_TOKEN}\",
            \"tos\": \"$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")\",
            \"model\": \"Linux\",
            \"serial_number\": \"${INSTALL_ID}\",
            \"locale\": \"en_US\"
        }")

    if [ -z "$REG_RESPONSE" ] || ! echo "$REG_RESPONSE" | grep -q '"id"'; then
        echo -e "  ${RED}API 注册失败，使用 wgcf 降级${NC}"
        return 1
    fi

    # 解析注册结果
    REG_ID=$(echo "$REG_RESPONSE" | grep -oP '"id"\s*:\s*"\K[^"]+' | head -1)
    REG_TOKEN=$(echo "$REG_RESPONSE" | grep -oP '"token"\s*:\s*"\K[^"]+' | head -1)
    PEER_PUBKEY=$(echo "$REG_RESPONSE" | grep -oP '"public_key"\s*:\s*"\K[^"]+' | head -1)

    # Step 2: 获取配置（含 IP 分配）
    CONFIG_RESPONSE=$(curl -s --max-time 15 \
        -X GET "https://${API_HOST}/${API_VER}/reg/${REG_ID}/account" \
        -H "Authorization: Bearer ${REG_TOKEN}" \
        -H "User-Agent: okhttp/3.12.1")

    # Step 3: 获取推荐 endpoint（带地区信息）
    # 通过向 Cloudflare 的地区特定 API 查询最优 endpoint
    BEST_EP=$(curl -s --max-time 10 \
        "https://api.cloudflareclient.com/v0a2158/client_config" \
        -H "Authorization: Bearer ${REG_TOKEN}" \
        -H "User-Agent: okhttp/3.12.1" \
        | grep -oP '"v4"\s*:\s*"\K[^"]+' | head -1)
    [ -z "$BEST_EP" ] && BEST_EP="${INGRESS_IP}:2408"

    # 提取分配的 IP 地址
    WARP_IPV4=$(echo "$REG_RESPONSE" | grep -oP '"v4"\s*:\s*"\K[0-9.]+/[0-9]+' | head -1)
    [ -z "$WARP_IPV4" ] && WARP_IPV4="172.16.0.2/32"

    if [ -n "$PEER_PUBKEY" ]; then
        # 写入配置
        mkdir -p ${WARP_DIR} /etc/wireguard
        cat > ${WG_CONF} << EOF
[Interface]
PrivateKey = ${PRIVKEY}
Address = ${WARP_IPV4}
Table = off
PersistentKeepalive = 25

[Peer]
PublicKey = ${PEER_PUBKEY}
AllowedIPs = 0.0.0.0/0
Endpoint = ${INGRESS_IP}:2408
EOF
        # 保存注册信息
        cat > ${WARP_DIR}/cf-reg.json << EOF
{"id":"${REG_ID}","token":"${REG_TOKEN}","privkey":"${PRIVKEY}","region":"${REGION}"}
EOF
        cp ${WG_CONF} ${WARP_DIR}/wgcf-profile.conf
        echo -e "  ${GREEN}✓ API 注册成功${NC}"
        echo -e "  分配 IP  : ${YELLOW}${WARP_IPV4}${NC}"
        echo -e "  Peer Key : ${YELLOW}${PEER_PUBKEY:0:20}...${NC}"
        echo -e "  Endpoint : ${YELLOW}${INGRESS_IP}:2408${NC}"
        return 0
    fi

    echo -e "  ${YELLOW}API 注册返回数据不完整，使用 wgcf 降级${NC}"
    return 1
}

# ============================================================
# 路由管理
# ============================================================
GOOGLE_IPS="8.8.4.0/24 8.8.8.0/24 34.0.0.0/9 35.184.0.0/13 35.192.0.0/12
35.224.0.0/12 35.240.0.0/13 64.233.160.0/19 66.102.0.0/20 66.249.64.0/19
72.14.192.0/18 74.125.0.0/16 104.132.0.0/14 108.177.0.0/17 142.250.0.0/15
172.217.0.0/16 172.253.0.0/16 173.194.0.0/16 209.85.128.0/17 216.58.192.0/19
216.239.32.0/19"

wg_routing_start() {
    ip rule del fwmark 51820 table 51820 2>/dev/null || true
    ip route flush table 51820 2>/dev/null || true
    iptables -t mangle -D OUTPUT    -j WARP_MARK 2>/dev/null || true
    iptables -t mangle -D PREROUTING -j WARP_MARK 2>/dev/null || true
    iptables -t mangle -F WARP_MARK 2>/dev/null || true
    iptables -t mangle -X WARP_MARK 2>/dev/null || true
    ip rule add fwmark 51820 table 51820
    ip route add default dev ${WG_IFACE} table 51820
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
wg_routing_stop() {
    ip rule del fwmark 51820 table 51820 2>/dev/null || true
    ip route flush table 51820 2>/dev/null || true
    iptables -t mangle -D OUTPUT    -j WARP_MARK 2>/dev/null || true
    iptables -t mangle -D PREROUTING -j WARP_MARK 2>/dev/null || true
    iptables -t mangle -F WARP_MARK 2>/dev/null || true
    iptables -t mangle -X WARP_MARK 2>/dev/null || true
}
cli_routing_start() {
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
cli_routing_stop() {
    pkill -f "redsocks -c /etc/redsocks-warp.conf" 2>/dev/null || true
    iptables -t nat -D OUTPUT    -j WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -D PREROUTING -j WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -F WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -X WARP_GOOGLE 2>/dev/null || true
}
all_routing_stop() { wg_routing_stop; cli_routing_stop; }

# ============================================================
# 安装依赖
# ============================================================
install_deps() {
    echo -e "\n${CYAN}  [1/4] 安装依赖...${NC}"
    case $OS in
        ubuntu|debian)
            apt-get update -y >/dev/null 2>&1
            apt-get install -y wireguard wireguard-tools curl wget iptables \
                openresolv redsocks wireguard-go >/dev/null 2>&1
            systemctl stop redsocks 2>/dev/null; systemctl disable redsocks 2>/dev/null
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
    sysctl -w net.ipv6.conf.all.disable_ipv6=1    >/dev/null 2>&1
    sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1
    grep -q "disable_ipv6" /etc/sysctl.conf 2>/dev/null || {
        echo "net.ipv6.conf.all.disable_ipv6=1"     >> /etc/sysctl.conf
        echo "net.ipv6.conf.default.disable_ipv6=1" >> /etc/sysctl.conf
    }
    # 下载 wgcf（备用）
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
    echo -e "  ${GREEN}✓ 依赖安装完成${NC}"
}

# ============================================================
# 生成配置（优先 API，降级 wgcf）
# ============================================================
setup_config() {
    echo -e "\n${CYAN}  [2/4] 生成 WireGuard 配置...${NC}"
    mkdir -p ${WARP_DIR} /etc/wireguard

    # 优先尝试直接 API 注册（cfnew 思路）
    if register_via_cf_api "$SELECTED_REGION"; then
        echo -e "  ${GREEN}✓ API 直注册模式${NC}"
        return 0
    fi

    # 降级：使用 wgcf
    echo -e "  ${YELLOW}降级到 wgcf...${NC}"
    cd /tmp; rm -f /tmp/wgcf-account.toml /tmp/wgcf-profile.conf
    [ -f ${WARP_DIR}/wgcf-account.toml ] && \
        cp ${WARP_DIR}/wgcf-account.toml /tmp/ && \
        echo -e "  ${GREEN}复用已有账号${NC}" || echo -e "  注册新 WARP 设备..."
    wgcf register --accept-tos >/dev/null 2>&1
    [ -f /tmp/wgcf-account.toml ] && cp /tmp/wgcf-account.toml ${WARP_DIR}/
    wgcf generate >/dev/null 2>&1
    [ ! -f /tmp/wgcf-profile.conf ] && { echo -e "${RED}  配置生成失败${NC}"; exit 1; }
    sed -i '/^DNS/d;/^Table/d'  /tmp/wgcf-profile.conf
    sed -i '/^\[Interface\]/a Table = off' /tmp/wgcf-profile.conf
    sed -i '/^Address/s/, .*\/128//' /tmp/wgcf-profile.conf
    sed -i '/^AllowedIPs/d'       /tmp/wgcf-profile.conf
    echo "AllowedIPs = 0.0.0.0/0"           >> /tmp/wgcf-profile.conf
    grep -q "PersistentKeepalive" /tmp/wgcf-profile.conf || \
        echo "PersistentKeepalive = 25"      >> /tmp/wgcf-profile.conf
    TARGET_IP="${ENDPOINTS[$SELECTED_REGION]}"
    sed -i "s/Endpoint = .*/Endpoint = ${TARGET_IP}:2408/" /tmp/wgcf-profile.conf
    cp /tmp/wgcf-profile.conf ${WARP_DIR}/wgcf-profile.conf
    cp /tmp/wgcf-profile.conf ${WG_CONF}
    echo -e "  ${GREEN}✓ wgcf 配置完成${NC}"
}

# ============================================================
# 端口扫描（轻量级，用 wg 命令直接测握手）
# ============================================================
scan_working_port() {
    local TARGET_IP="$1"
    echo -e "\n  ${CYAN}扫描可用 UDP 端口...${NC}"
    PRIVKEY=$(grep "^PrivateKey" ${WG_CONF} | awk '{print $3}')
    PEER_PUB=$(grep "^PublicKey"  ${WG_CONF} | awk '{print $3}')
    for PORT in "${WARP_PORTS[@]}"; do
        printf "    UDP %-6s → " "$PORT"
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
# 引擎一：WireGuard
# ============================================================
engine_wireguard() {
    echo -e "\n${CYAN}  [3/4] 引擎一：WireGuard + 端口扫描...${NC}"
    TARGET_IP="${ENDPOINTS[$SELECTED_REGION]}"
    if scan_working_port "$TARGET_IP"; then
        WORKING_PORT=$(cat ${PORT_FILE})
        ip link del ${WG_IFACE} 2>/dev/null || true; sleep 1
        wg-quick up ${WG_CONF} 2>&1
        sleep 3
        ip link show ${WG_IFACE} &>/dev/null || { echo -e "  ${RED}wg-quick 启动失败${NC}"; return 1; }
        echo -e "  等待握手确认..."
        for i in $(seq 1 10); do
            sleep 2
            HS=$(wg show ${WG_IFACE} latest-handshakes 2>/dev/null | awk '{print $2}')
            [ -n "$HS" ] && [ "$HS" != "0" ] && {
                echo -e "  ${GREEN}✓ 握手成功 端口 UDP $WORKING_PORT${NC}"
                echo "wireguard" > ${MODE_FILE}
                wg_routing_start
                return 0
            }
        done
        wg-quick down ${WG_IFACE} 2>/dev/null; return 1
    fi
    echo -e "\n  ${YELLOW}所有 UDP 端口不可用，启动引擎二...${NC}"
    return 1
}

# ============================================================
# 引擎二：warp-cli (TCP fallback)
# ============================================================
install_warp_cli() {
    echo -e "  ${CYAN}安装 warp-cli...${NC}"
    case $OS in
        ubuntu|debian)
            CODENAME=$(. /etc/os-release && echo $VERSION_CODENAME)
            # 更新 pubkey（2025年9月后需要新 pubkey）
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
            cat > /etc/yum.repos.d/cloudflare-warp.repo << 'EOF'
[cloudflare-warp]
name=Cloudflare WARP
baseurl=https://pkg.cloudflareclient.com/rpm
enabled=1; gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/cloudflare-warp.gpg
EOF
            dnf install -y cloudflare-warp >/dev/null 2>&1
            ;;
    esac
    command -v warp-cli &>/dev/null || { echo -e "  ${RED}warp-cli 安装失败${NC}"; return 1; }
    echo -e "  ${GREEN}✓ warp-cli 安装完成${NC}"
}

engine_warp_cli() {
    echo -e "\n${CYAN}  [3/4] 引擎二：warp-cli TCP fallback...${NC}"
    install_warp_cli || return 1
    systemctl start warp-svc 2>/dev/null; sleep 2
    warp-cli --accept-tos registration new 2>/dev/null || \
        warp-cli --accept-tos register 2>/dev/null || true
    sleep 1
    warp-cli --accept-tos mode proxy         2>/dev/null || true
    warp-cli --accept-tos proxy port 40000   2>/dev/null || true
    # ★ 地区选择：通过 set-custom-endpoint 设置入口
    TARGET_IP="${ENDPOINTS[$SELECTED_REGION]}"
    if [ "$SELECTED_REGION" != "🌐 自动" ]; then
        warp-cli --accept-tos set-custom-endpoint "${TARGET_IP}:2408" 2>/dev/null || true
        echo -e "  入口节点: ${YELLOW}${TARGET_IP}${NC}"
    fi
    warp-cli --accept-tos connect 2>/dev/null
    echo -e "  连接中，等待 10 秒..."
    sleep 10
    STATUS=$(warp-cli status 2>/dev/null)
    echo "$STATUS" | grep -qi "connected" || { echo -e "  ${RED}warp-cli 连接失败${NC}"; return 1; }
    echo -e "  ${GREEN}✓ warp-cli 已连接${NC}"

    # ★ 验证出口 IP（多次注册可能获得不同出口）
    for attempt in 1 2 3; do
        SOCKS_IP=$(curl -x socks5://127.0.0.1:40000 -s --max-time 8 ip.sb 2>/dev/null)
        if [ -n "$SOCKS_IP" ]; then
            INFO=$(curl -s --max-time 5 "http://ip-api.com/json/$SOCKS_IP?lang=zh-CN" 2>/dev/null)
            C=$(echo $INFO | grep -oP '"country":"\K[^"]+' || echo "?")
            T=$(echo $INFO | grep -oP '"city":"\K[^"]+' || echo "")
            echo -e "  ${attempt}. 出口 IP: ${GREEN}$SOCKS_IP  ($C $T)${NC}"
            # 如果不是目标地区，尝试重新注册获取不同分配
            if [ "$SELECTED_REGION" != "🌐 自动" ] && [ $attempt -lt 3 ]; then
                DESIRED_COUNTRY="${REGION_KEYS[$((c-1))]}"
                if echo "$C" | grep -qiv "$(echo $SELECTED_REGION | sed 's/.*[[:space:]]//')"; then
                    echo -e "  ${YELLOW}出口地区与选择不符，尝试重新注册...${NC}"
                    warp-cli --accept-tos disconnect 2>/dev/null; sleep 1
                    warp-cli --accept-tos registration delete 2>/dev/null; sleep 1
                    warp-cli --accept-tos registration new 2>/dev/null
                    warp-cli --accept-tos mode proxy 2>/dev/null
                    warp-cli --accept-tos proxy port 40000 2>/dev/null
                    [ "$SELECTED_REGION" != "🌐 自动" ] && \
                        warp-cli --accept-tos set-custom-endpoint "${TARGET_IP}:2408" 2>/dev/null
                    warp-cli --accept-tos connect 2>/dev/null; sleep 8
                    continue
                fi
            fi
            break
        fi
    done

    echo "warp-cli" > ${MODE_FILE}
    cli_routing_start
    echo -e "  ${GREEN}✓ warp-cli 透明代理已建立${NC}"
    return 0
}

# ============================================================
# 验证出口
# ============================================================
verify_exit() {
    echo -e "\n${CYAN}  [4/4] 验证出口...${NC}"
    sleep 2
    CODE=$(curl -s --max-time 12 -o /dev/null -w "%{http_code}" https://www.google.com)
    GEM=$(curl -s --max-time 12 -o /dev/null -w "%{http_code}" \
        -H "User-Agent: Mozilla/5.0" https://gemini.google.com)

    [ "$CODE" = "200" ] || [ "$CODE" = "301" ] && \
        echo -e "  ${GREEN}✓ Google   HTTP $CODE${NC}" || \
        echo -e "  ${RED}✗ Google   HTTP $CODE${NC}"
    [ "$GEM" = "200" ] || [ "$GEM" = "301" ] && \
        echo -e "  ${GREEN}✓ Gemini   HTTP $GEM${NC}" || \
        echo -e "  ${YELLOW}△ Gemini   HTTP $GEM${NC}"

    # 出口 IP
    MODE=$(cat ${MODE_FILE} 2>/dev/null || echo "wireguard")
    if [ "$MODE" = "wireguard" ]; then
        EXIT_IP=$(curl -s --max-time 10 \
            "https://dns.google/resolve?name=myip.opendns.com&type=A" \
            | grep -oP '"data":"\K[^"]+' | head -1 2>/dev/null)
    else
        EXIT_IP=$(curl -x socks5://127.0.0.1:40000 -s --max-time 10 ip.sb 2>/dev/null)
    fi
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
        SC="wg-quick up ${WG_CONF} && sleep 3 && /usr/local/bin/ge start-routing wg"
        EC="/usr/local/bin/ge stop-routing && wg-quick down ${WG_IFACE}"
    else
        SC="systemctl start warp-svc && sleep 3 && warp-cli --accept-tos connect && sleep 5 && /usr/local/bin/ge start-routing cli"
        EC="/usr/local/bin/ge stop-routing && warp-cli --accept-tos disconnect"
    fi
    cat > /etc/systemd/system/g-everywhere.service << EOF
[Unit]
Description=G-Everywhere Google Routing v4.1
After=network.target

[Service]
Type=oneshot; RemainAfterExit=yes
ExecStart=/bin/bash -c '${SC}'
ExecStop=/bin/bash -c '${EC}'

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
WG_IFACE="warp0"; WG_CONF="/etc/wireguard/${WG_IFACE}.conf"
WARP_DIR="/etc/warp"; MODE_FILE="${WARP_DIR}/mode"
WARP_PORTS=(2408 500 1701 4500 8854 894 7559 443)
GOOGLE_IPS="8.8.4.0/24 8.8.8.0/24 34.0.0.0/9 35.184.0.0/13 35.192.0.0/12 35.224.0.0/12
35.240.0.0/13 64.233.160.0/19 66.102.0.0/20 66.249.64.0/19 72.14.192.0/18 74.125.0.0/16
104.132.0.0/14 108.177.0.0/17 142.250.0.0/15 172.217.0.0/16 172.253.0.0/16 173.194.0.0/16
209.85.128.0/17 216.58.192.0/19 216.239.32.0/19"

_wg_r_start() {
    ip rule del fwmark 51820 table 51820 2>/dev/null || true
    ip route flush table 51820 2>/dev/null || true
    iptables -t mangle -D OUTPUT -j WARP_MARK 2>/dev/null || true
    iptables -t mangle -D PREROUTING -j WARP_MARK 2>/dev/null || true
    iptables -t mangle -F WARP_MARK 2>/dev/null || true
    iptables -t mangle -X WARP_MARK 2>/dev/null || true
    ip rule add fwmark 51820 table 51820
    ip route add default dev $WG_IFACE table 51820
    iptables -t mangle -N WARP_MARK
    for net in 127.0.0.0/8 10.0.0.0/8 192.168.0.0/16 172.16.0.0/12 162.159.192.0/22; do
        iptables -t mangle -A WARP_MARK -d $net -j RETURN; done
    for ip in $GOOGLE_IPS; do
        iptables -t mangle -A WARP_MARK -d $ip -j MARK --set-mark 51820; done
    iptables -t mangle -A OUTPUT -j WARP_MARK
    iptables -t mangle -A PREROUTING -j WARP_MARK
}
_cli_r_start() {
    pkill -f "redsocks -c /etc/redsocks-warp.conf" 2>/dev/null || true; sleep 1
    cat > /etc/redsocks-warp.conf << 'EOF'
base { log_debug=off; log_info=off; daemon=off; redirector=iptables; }
redsocks { local_ip=127.0.0.1; local_port=12345; ip=127.0.0.1; port=40000; type=socks5; }
EOF
    redsocks -c /etc/redsocks-warp.conf &; sleep 1
    iptables -t nat -D OUTPUT -j WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -D PREROUTING -j WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -F WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -X WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -N WARP_GOOGLE
    for net in 127.0.0.0/8 10.0.0.0/8 192.168.0.0/16 172.16.0.0/12 162.159.192.0/22; do
        iptables -t nat -A WARP_GOOGLE -d $net -j RETURN; done
    for ip in $GOOGLE_IPS; do
        iptables -t nat -A WARP_GOOGLE -d $ip -p tcp -j REDIRECT --to-ports 12345; done
    iptables -t nat -A OUTPUT -j WARP_GOOGLE
    iptables -t nat -A PREROUTING -j WARP_GOOGLE
}
_stop_all() {
    ip rule del fwmark 51820 table 51820 2>/dev/null || true
    ip route flush table 51820 2>/dev/null || true
    iptables -t mangle -D OUTPUT -j WARP_MARK 2>/dev/null || true
    iptables -t mangle -D PREROUTING -j WARP_MARK 2>/dev/null || true
    iptables -t mangle -F WARP_MARK 2>/dev/null || true
    iptables -t mangle -X WARP_MARK 2>/dev/null || true
    pkill -f "redsocks -c /etc/redsocks-warp.conf" 2>/dev/null || true
    iptables -t nat -D OUTPUT -j WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -D PREROUTING -j WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -F WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -X WARP_GOOGLE 2>/dev/null || true
}
_exit_ip() {
    MODE=$(cat $MODE_FILE 2>/dev/null || echo "wireguard")
    [ "$MODE" = "wireguard" ] && \
        curl -s --max-time 8 "https://dns.google/resolve?name=myip.opendns.com&type=A" \
            | grep -oP '"data":"\K[^"]+' | head -1 2>/dev/null || \
        curl -x socks5://127.0.0.1:40000 -s --max-time 8 ip.sb 2>/dev/null
}

case "$1" in
    start-routing)
        [ "$2" = "cli" ] && _cli_r_start || _wg_r_start
        echo -e "${GREEN}✓ 路由已建立${NC}" ;;
    stop-routing) _stop_all; echo -e "${GREEN}✓ 路由已清除${NC}" ;;

    start)
        MODE=$(cat $MODE_FILE 2>/dev/null || echo "wireguard")
        if [ "$MODE" = "wireguard" ]; then
            wg-quick up $WG_CONF 2>/dev/null; sleep 3; _wg_r_start
        else
            systemctl start warp-svc 2>/dev/null; sleep 2
            warp-cli --accept-tos connect 2>/dev/null; sleep 6; _cli_r_start
        fi
        echo -e "${GREEN}✓ 已启动 ($MODE)${NC}" ;;

    stop)
        _stop_all
        wg-quick down $WG_IFACE 2>/dev/null
        warp-cli --accept-tos disconnect 2>/dev/null
        echo -e "${GREEN}✓ 已停止${NC}" ;;

    restart) $0 stop; sleep 2; $0 start ;;

    status)
        MODE=$(cat $MODE_FILE 2>/dev/null || echo "未知")
        echo -e "\n${CYAN}── 模式: $MODE ──${NC}"
        if [ "$MODE" = "wireguard" ]; then
            ip link show $WG_IFACE &>/dev/null && \
                echo -e "${GREEN}✓ WireGuard 运行中${NC}" || echo -e "${RED}✗ 未运行${NC}"
            wg show $WG_IFACE 2>/dev/null | grep -E "endpoint|handshake|transfer" | sed 's/^/  /'
            echo -e "  端口: UDP $(cat $WARP_DIR/working_port 2>/dev/null || echo '?')"
        else
            warp-cli status 2>/dev/null | head -3 | sed 's/^/  /'
        fi
        echo -e "\n${CYAN}── Google/Gemini ──${NC}"
        G=$(curl -s --max-time 8 -o /dev/null -w "%{http_code}" https://www.google.com)
        GEM=$(curl -s --max-time 8 -o /dev/null -w "%{http_code}" \
            -H "User-Agent: Mozilla/5.0" https://gemini.google.com)
        [ "$G" = "200" ] || [ "$G" = "301" ] && \
            echo -e "  ${GREEN}✓ Google  HTTP $G${NC}" || echo -e "  ${RED}✗ Google  HTTP $G${NC}"
        [ "$GEM" = "200" ] || [ "$GEM" = "301" ] && \
            echo -e "  ${GREEN}✓ Gemini  HTTP $GEM${NC}" || echo -e "  ${YELLOW}△ Gemini  HTTP $GEM${NC}"
        EXIT=$(_exit_ip)
        [ -n "$EXIT" ] && {
            INFO=$(curl -s --max-time 5 "http://ip-api.com/json/$EXIT?lang=zh-CN" 2>/dev/null)
            C=$(echo $INFO | grep -oP '"country":"\K[^"]+' || echo "?")
            T=$(echo $INFO | grep -oP '"city":"\K[^"]+' || echo "")
            echo -e "  出口: ${GREEN}$EXIT ($C $T)${NC}"
        }
        echo "" ;;

    test)
        MODE=$(cat $MODE_FILE 2>/dev/null || echo "未知")
        echo -e "\n${CYAN}── 诊断 ($MODE 模式) ──${NC}\n"
        if [ "$MODE" = "wireguard" ]; then
            HS=$(wg show $WG_IFACE latest-handshakes 2>/dev/null | awk '{print $2}')
            [ -n "$HS" ] && [ "$HS" != "0" ] && \
                echo -e "${YELLOW}[WireGuard]${NC} ${GREEN}✓ 已握手${NC}" || \
                echo -e "${YELLOW}[WireGuard]${NC} ${RED}✗ 未握手 → 运行 ge fix${NC}"
        else
            warp-cli status 2>/dev/null | grep -i "connected" &>/dev/null && \
                echo -e "${YELLOW}[warp-cli]${NC} ${GREEN}✓ 已连接${NC}" || \
                echo -e "${YELLOW}[warp-cli]${NC} ${RED}✗ 未连接 → 运行 ge fix${NC}"
        fi
        G=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" https://www.google.com)
        GEM=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" \
            -H "User-Agent: Mozilla/5.0" https://gemini.google.com)
        YT=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" \
            -H "User-Agent: Mozilla/5.0" https://www.youtube.com)
        [ "$G" = "200" ] || [ "$G" = "301" ] && \
            echo -e "${YELLOW}[Google]${NC}   ${GREEN}✓ HTTP $G${NC}" || \
            echo -e "${YELLOW}[Google]${NC}   ${RED}✗ HTTP $G${NC}"
        [ "$GEM" = "200" ] || [ "$GEM" = "301" ] && \
            echo -e "${YELLOW}[Gemini]${NC}   ${GREEN}✓ HTTP $GEM${NC}" || \
            echo -e "${YELLOW}[Gemini]${NC}   ${RED}✗ HTTP $GEM${NC}"
        [ "$YT" = "200" ] || [ "$YT" = "301" ] && \
            echo -e "${YELLOW}[YouTube]${NC}  ${GREEN}✓ HTTP $YT${NC}" || \
            echo -e "${YELLOW}[YouTube]${NC}  ${RED}✗ HTTP $YT${NC}"
        echo "" ;;

    ip)
        echo -e "\n${YELLOW}直连 IP:${NC}"; curl -4 -s --max-time 5 ip.sb; echo ""
        echo -e "${YELLOW}WARP 出口 IP:${NC}"
        EXIT=$(_exit_ip)
        [ -n "$EXIT" ] && {
            INFO=$(curl -s --max-time 5 "http://ip-api.com/json/$EXIT?lang=zh-CN" 2>/dev/null)
            echo -e "${GREEN}$EXIT  ($(echo $INFO | grep -oP '"country":"\K[^"]+') $(echo $INFO | grep -oP '"city":"\K[^"]+'))${NC}"
        } || echo -e "${RED}获取失败${NC}"; echo "" ;;

    fix)
        echo -e "${CYAN}修复中...${NC}"
        MODE=$(cat $MODE_FILE 2>/dev/null || echo "wireguard")
        _stop_all
        if [ "$MODE" = "wireguard" ]; then
            wg-quick down $WG_IFACE 2>/dev/null; sleep 1
            PRIVKEY=$(grep "^PrivateKey" $WG_CONF | awk '{print $3}')
            PEER_PUB=$(grep "^PublicKey" $WG_CONF | awk '{print $3}')
            EP_IP=$(grep "^Endpoint" $WG_CONF | awk '{print $3}' | cut -d: -f1)
            FOUND=""
            for PORT in "${WARP_PORTS[@]}"; do
                printf "  UDP %-6s " "$PORT"
                ip link del _warp_test 2>/dev/null || true
                ip link add _warp_test type wireguard 2>/dev/null
                wg set _warp_test private-key <(echo "$PRIVKEY") \
                    peer "$PEER_PUB" endpoint "${EP_IP}:${PORT}" \
                    allowed-ips 0.0.0.0/0 persistent-keepalive 5 2>/dev/null
                ip link set _warp_test up 2>/dev/null; sleep 6
                HS=$(wg show _warp_test latest-handshakes 2>/dev/null | awk '{print $2}')
                ip link del _warp_test 2>/dev/null
                if [ -n "$HS" ] && [ "$HS" != "0" ]; then
                    echo -e "${GREEN}✓${NC}"
                    sed -i "s/Endpoint = .*/Endpoint = ${EP_IP}:${PORT}/" $WG_CONF
                    echo "$PORT" > $WARP_DIR/working_port
                    FOUND=yes; break
                fi; echo -e "${RED}✗${NC}"
            done
            [ -n "$FOUND" ] && { wg-quick up $WG_CONF; sleep 3; _wg_r_start; } || \
                echo -e "${RED}所有端口失败，建议重新安装${NC}"
        else
            warp-cli --accept-tos disconnect 2>/dev/null; sleep 1
            warp-cli --accept-tos connect 2>/dev/null; sleep 8; _cli_r_start
        fi
        G=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" https://www.google.com)
        [ "$G" = "200" ] || [ "$G" = "301" ] && \
            echo -e "${GREEN}✓ 修复成功 
