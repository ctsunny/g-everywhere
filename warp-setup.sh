#!/bin/bash
# G-Everywhere v3.3
# 修复：自动探测可用 UDP 端口，解决握手超时问题
# https://github.com/ctsunny/g-everywhere

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'
NC='\033[0m'; BOLD='\033[1m'

WG_IFACE="warp0"
WG_CONF="/etc/wireguard/${WG_IFACE}.conf"
WARP_DIR="/etc/warp"

# Cloudflare WARP 支持的全部 UDP 端口
WARP_PORTS=(2408 500 1701 4500 8854 894 7559)

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
WORKING_PORT=""

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
    echo -e "  ${GREEN}  Google Unlock  ${NC}│${YELLOW}  wgcf + WireGuard  ${NC}│${MAGENTA}  真实地区选择  ${NC}"
    echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${BLUE}github.com/ctsunny/g-everywhere${NC}  │  ${GREEN}v3.3${NC}\n"
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
    read -p "  请选择 [1-${#REGION_KEYS[@]}] (默认1-自动): " c
    c=${c:-1}
    if [[ "$c" =~ ^[0-9]+$ ]] && [ "$c" -ge 1 ] && [ "$c" -le "${#REGION_KEYS[@]}" ]; then
        SELECTED_REGION="${REGION_KEYS[$((c-1))]}"
    else
        SELECTED_REGION="🌐 自动"
    fi
    echo -e "  ${GREEN}✓ 已选择: $SELECTED_REGION${NC}"
}

# ============================================================
# ★ 核心修复：自动探测可用 UDP 端口
# ============================================================
detect_working_port() {
    local TARGET_IP="$1"
    echo -e "  ${CYAN}探测可用 UDP 端口...${NC}"

    # 安装 nmap 用于 UDP 测试
    command -v nmap &>/dev/null || apt-get install -y nmap >/dev/null 2>&1 || \
        dnf install -y nmap >/dev/null 2>&1 || true

    for PORT in "${WARP_PORTS[@]}"; do
        printf "    UDP %-6s → " "$PORT"

        # 方法1: nmap UDP 扫描
        if command -v nmap &>/dev/null; then
            RESULT=$(nmap -sU -p $PORT --max-retries 2 --host-timeout 5s $TARGET_IP 2>/dev/null \
                | grep "$PORT/udp" | grep -v "closed\|filtered")
            if [ -n "$RESULT" ]; then
                echo -e "${GREEN}✓ 可用${NC}"
                WORKING_PORT=$PORT
                return 0
            fi
        fi

        # 方法2: 临时启动 WireGuard 测试握手
        if [ -f "${WG_CONF}.tmp" ]; then
            sed -i "s/Endpoint = .*/Endpoint = $TARGET_IP:$PORT/" "${WG_CONF}.tmp"
            ip link del test_warp 2>/dev/null || true
            # 用 wg 直接测试（不用 wg-quick，避免路由修改）
            ip link add test_warp type wireguard 2>/dev/null
            PRIVKEY=$(grep "PrivateKey" "${WG_CONF}.tmp" | awk '{print $3}')
            PUBKEY=$(grep "PublicKey" "${WG_CONF}.tmp" | awk '{print $3}')
            wg set test_warp private-key <(echo "$PRIVKEY") \
                peer "$PUBKEY" endpoint "$TARGET_IP:$PORT" \
                allowed-ips 0.0.0.0/0 2>/dev/null
            ip link set test_warp up 2>/dev/null
            sleep 3
            HS=$(wg show test_warp latest-handshakes 2>/dev/null | awk '{print $2}')
            ip link del test_warp 2>/dev/null
            if [ -n "$HS" ] && [ "$HS" != "0" ]; then
                echo -e "${GREEN}✓ 握手成功${NC}"
                WORKING_PORT=$PORT
                return 0
            fi
        fi

        echo -e "${RED}✗ 不可用${NC}"
    done

    echo -e "  ${RED}所有端口均不可用！${NC}"
    return 1
}

# ============================================================
# 路由管理
# ============================================================
routing_start() {
    ip rule del fwmark 51820 table 51820 2>/dev/null || true
    ip route flush table 51820 2>/dev/null || true
    iptables -t mangle -D OUTPUT -j WARP_MARK 2>/dev/null || true
    iptables -t mangle -D PREROUTING -j WARP_MARK 2>/dev/null || true
    iptables -t mangle -F WARP_MARK 2>/dev/null || true
    iptables -t mangle -X WARP_MARK 2>/dev/null || true

    ip rule add fwmark 51820 table 51820
    ip route add default dev ${WG_IFACE} table 51820

    iptables -t mangle -N WARP_MARK
    iptables -t mangle -A WARP_MARK -d 127.0.0.0/8 -j RETURN
    iptables -t mangle -A WARP_MARK -d 10.0.0.0/8 -j RETURN
    iptables -t mangle -A WARP_MARK -d 192.168.0.0/16 -j RETURN
    iptables -t mangle -A WARP_MARK -d 172.16.0.0/12 -j RETURN
    iptables -t mangle -A WARP_MARK -d 162.159.192.0/22 -j RETURN
    for ip in $GOOGLE_IPS; do
        iptables -t mangle -A WARP_MARK -d $ip -j MARK --set-mark 51820
    done
    iptables -t mangle -A OUTPUT -j WARP_MARK
    iptables -t mangle -A PREROUTING -j WARP_MARK
}

routing_stop() {
    ip rule del fwmark 51820 table 51820 2>/dev/null || true
    ip route flush table 51820 2>/dev/null || true
    iptables -t mangle -D OUTPUT -j WARP_MARK 2>/dev/null || true
    iptables -t mangle -D PREROUTING -j WARP_MARK 2>/dev/null || true
    iptables -t mangle -F WARP_MARK 2>/dev/null || true
    iptables -t mangle -X WARP_MARK 2>/dev/null || true
}

# ============================================================
# 安装依赖
# ============================================================
install_deps() {
    echo -e "\n${CYAN}  [1/5] 安装依赖...${NC}"
    case $OS in
        ubuntu|debian)
            apt-get update -y >/dev/null 2>&1
            apt-get install -y wireguard wireguard-tools curl wget iptables openresolv nmap >/dev/null 2>&1
            ;;
        centos|rhel|rocky|almalinux|fedora)
            dnf install -y epel-release >/dev/null 2>&1
            dnf install -y wireguard-tools curl wget iptables nmap >/dev/null 2>&1
            ;;
    esac
    modprobe wireguard 2>/dev/null || true

    VER=$(curl -s --max-time 10 https://api.github.com/repos/ViRb3/wgcf/releases/latest \
        | grep tag_name | cut -d'"' -f4 2>/dev/null)
    [ -z "$VER" ] && VER="v2.2.25"
    curl -fsSL "https://github.com/ViRb3/wgcf/releases/download/${VER}/wgcf_${VER#v}_linux_${ARCH}" \
        -o /usr/local/bin/wgcf 2>/dev/null
    [ ! -s /usr/local/bin/wgcf ] && \
        curl -fsSL "https://github.com/ViRb3/wgcf/releases/download/v2.2.25/wgcf_2.2.25_linux_${ARCH}" \
        -o /usr/local/bin/wgcf
    chmod +x /usr/local/bin/wgcf
    command -v wgcf &>/dev/null || { echo -e "${RED}wgcf 安装失败${NC}"; exit 1; }
    echo -e "  ${GREEN}✓ 依赖安装完成${NC}"
}

# ============================================================
# 生成配置
# ============================================================
setup_config() {
    echo -e "\n${CYAN}  [2/5] 生成 WireGuard 配置...${NC}"
    mkdir -p ${WARP_DIR} /etc/wireguard
    cd /tmp
    rm -f /tmp/wgcf-account.toml /tmp/wgcf-profile.conf

    [ -f ${WARP_DIR}/wgcf-account.toml ] && \
        cp ${WARP_DIR}/wgcf-account.toml /tmp/ && \
        echo -e "  ${GREEN}复用已有账号${NC}" || \
        echo -e "  注册新 WARP 设备..."

    wgcf register --accept-tos >/dev/null 2>&1
    [ -f /tmp/wgcf-account.toml ] && cp /tmp/wgcf-account.toml ${WARP_DIR}/

    wgcf generate >/dev/null 2>&1
    [ ! -f /tmp/wgcf-profile.conf ] && { echo -e "${RED}配置生成失败${NC}"; exit 1; }

    # 基础配置处理
    sed -i '/^DNS/d' /tmp/wgcf-profile.conf
    sed -i '/^Table/d' /tmp/wgcf-profile.conf
    sed -i '/^\[Interface\]/a Table = off' /tmp/wgcf-profile.conf
    sed -i '/^AllowedIPs/d' /tmp/wgcf-profile.conf
    echo "AllowedIPs = 0.0.0.0/0, ::/0" >> /tmp/wgcf-profile.conf

    TARGET_IP="${ENDPOINTS[$SELECTED_REGION]}"
    # 先用默认端口写临时配置，供端口探测用
    sed -i "s/Endpoint = .*/Endpoint = $TARGET_IP:2408/" /tmp/wgcf-profile.conf
    cp /tmp/wgcf-profile.conf ${WG_CONF}.tmp

    echo -e "  ${GREEN}✓ 基础配置完成${NC}"
    echo -e "  目标 IP: ${YELLOW}$TARGET_IP${NC}"
}

# ============================================================
# ★ 探测端口 + 启动 WireGuard
# ============================================================
start_wg() {
    echo -e "\n${CYAN}  [3/5] 探测可用 UDP 端口...${NC}"

    TARGET_IP="${ENDPOINTS[$SELECTED_REGION]}"
    detect_working_port "$TARGET_IP"

    if [ -z "$WORKING_PORT" ]; then
        echo -e "\n  ${RED}所有端口均被封锁！${NC}"
        echo -e "  ${YELLOW}可能原因:"
        echo -e "    - VPS 防火墙封锁出站 UDP"
        echo -e "    - 运营商 QoS 限制 UDP"
        echo -e "  解决方案:"
        echo -e "    1. 在 VPS 控制台开放出站 UDP 全端口"
        echo -e "    2. 联系 VPS 提供商确认 UDP 是否可用${NC}"
        exit 1
    fi

    echo -e "\n${CYAN}  [4/5] 启动 WireGuard (端口 $WORKING_PORT)...${NC}"

    # 用探测到的可用端口更新配置
    sed -i "s/Endpoint = .*/Endpoint = $TARGET_IP:$WORKING_PORT/" /tmp/wgcf-profile.conf
    cp /tmp/wgcf-profile.conf ${WARP_DIR}/wgcf-profile.conf
    cp /tmp/wgcf-profile.conf ${WG_CONF}
    rm -f ${WG_CONF}.tmp

    # 停止旧接口
    ip link del ${WG_IFACE} 2>/dev/null || true
    sleep 1

    wg-quick up ${WG_CONF} 2>&1
    sleep 3

    if ! ip link show ${WG_IFACE} &>/dev/null; then
        echo -e "  ${RED}WireGuard 接口启动失败${NC}"
        exit 1
    fi

    # 等待握手（最多 30 秒）
    echo -e "  等待 WireGuard 握手..."
    for i in $(seq 1 15); do
        sleep 2
        HS=$(wg show ${WG_IFACE} latest-handshakes 2>/dev/null | awk '{print $2}')
        if [ -n "$HS" ] && [ "$HS" != "0" ]; then
            echo -e "  ${GREEN}✓ 握手成功！(${i}次, 端口 $WORKING_PORT)${NC}"
            # 保存可用端口供后续使用
            echo "$WORKING_PORT" > ${WARP_DIR}/working_port
            return 0
        fi
    done

    echo -e "  ${RED}握手失败！端口 $WORKING_PORT 连接超时${NC}"
    echo -e "  ${YELLOW}运行 ge scan 扫描更多端口组合${NC}"
    exit 1
}

verify_exit() {
    echo -e "\n${CYAN}  [5/5] 验证出口...${NC}"
    routing_start
    sleep 2

    CODE=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" https://www.google.com)
    if [ "$CODE" = "200" ] || [ "$CODE" = "301" ]; then
        echo -e "  ${GREEN}✓ Google 可达 HTTP $CODE${NC}"
    else
        echo -e "  ${YELLOW}Google HTTP $CODE（等待中...）${NC}"
        sleep 10
        CODE=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" https://www.google.com)
        echo -e "  重试: HTTP $CODE"
    fi

    # 通过 Google 服务测出口 IP
    OUT=$(curl -s --max-time 10 "https://dns.google/resolve?name=myip.opendns.com&type=A" \
        | grep -oP '"data":"\K[^"]+' | head -1 2>/dev/null)
    [ -z "$OUT" ] && OUT=$(curl -s --max-time 8 ip.sb 2>/dev/null)

    if [ -n "$OUT" ]; then
        INFO=$(curl -s --max-time 5 "http://ip-api.com/json/$OUT?lang=zh-CN" 2>/dev/null)
        C=$(echo $INFO | grep -oP '"country":"\K[^"]+' || echo "未知")
        T=$(echo $INFO | grep -oP '"city":"\K[^"]+' || echo "")
        ISP=$(echo $INFO | grep -oP '"isp":"\K[^"]+' || echo "")
        echo -e "  出口 IP  : ${GREEN}$OUT${NC}"
        echo -e "  出口地区 : ${GREEN}$C $T${NC}"
        echo -e "  ISP      : ${GREEN}$ISP${NC}"
    fi
}

setup_autostart() {
    cat > /etc/systemd/system/g-everywhere.service << EOF
[Unit]
Description=G-Everywhere WireGuard Google Routing
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'wg-quick up ${WG_CONF} && sleep 3 && /usr/local/bin/ge start-routing'
ExecStop=/bin/bash -c '/usr/local/bin/ge stop-routing && wg-quick down ${WG_IFACE}'

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
GOOGLE_IPS="8.8.4.0/24 8.8.8.0/24 34.0.0.0/9 35.184.0.0/13 35.192.0.0/12 35.224.0.0/12
35.240.0.0/13 64.233.160.0/19 66.102.0.0/20 66.249.64.0/19 72.14.192.0/18 74.125.0.0/16
104.132.0.0/14 108.177.0.0/17 142.250.0.0/15 172.217.0.0/16 172.253.0.0/16 173.194.0.0/16
209.85.128.0/17 216.58.192.0/19 216.239.32.0/19"
WARP_PORTS=(2408 500 1701 4500 8854 894 7559)

start_routing() {
    ip rule del fwmark 51820 table 51820 2>/dev/null || true
    ip route flush table 51820 2>/dev/null || true
    iptables -t mangle -D OUTPUT -j WARP_MARK 2>/dev/null || true
    iptables -t mangle -D PREROUTING -j WARP_MARK 2>/dev/null || true
    iptables -t mangle -F WARP_MARK 2>/dev/null || true
    iptables -t mangle -X WARP_MARK 2>/dev/null || true
    ip rule add fwmark 51820 table 51820
    ip route add default dev $WG_IFACE table 51820
    iptables -t mangle -N WARP_MARK
    iptables -t mangle -A WARP_MARK -d 127.0.0.0/8 -j RETURN
    iptables -t mangle -A WARP_MARK -d 10.0.0.0/8 -j RETURN
    iptables -t mangle -A WARP_MARK -d 192.168.0.0/16 -j RETURN
    iptables -t mangle -A WARP_MARK -d 172.16.0.0/12 -j RETURN
    iptables -t mangle -A WARP_MARK -d 162.159.192.0/22 -j RETURN
    for ip in $GOOGLE_IPS; do
        iptables -t mangle -A WARP_MARK -d $ip -j MARK --set-mark 51820
    done
    iptables -t mangle -A OUTPUT -j WARP_MARK
    iptables -t mangle -A PREROUTING -j WARP_MARK
}

stop_routing() {
    ip rule del fwmark 51820 table 51820 2>/dev/null || true
    ip route flush table 51820 2>/dev/null || true
    iptables -t mangle -D OUTPUT -j WARP_MARK 2>/dev/null || true
    iptables -t mangle -D PREROUTING -j WARP_MARK 2>/dev/null || true
    iptables -t mangle -F WARP_MARK 2>/dev/null || true
    iptables -t mangle -X WARP_MARK 2>/dev/null || true
}

case "$1" in
    start-routing) start_routing; echo -e "${GREEN}✓ 路由已建立${NC}" ;;
    stop-routing)  stop_routing;  echo -e "${GREEN}✓ 路由已清除${NC}" ;;

    start)
        wg-quick up $WG_CONF 2>/dev/null; sleep 3
        start_routing
        echo -e "${GREEN}✓ 已启动${NC}" ;;

    stop)
        stop_routing
        wg-quick down $WG_IFACE 2>/dev/null
        echo -e "${GREEN}✓ 已停止${NC}" ;;

    restart)
        stop_routing
        wg-quick down $WG_IFACE 2>/dev/null; sleep 1
        wg-quick up $WG_CONF 2>/dev/null; sleep 4
        start_routing
        echo -e "${GREEN}✓ 已重启${NC}" ;;

    status)
        echo -e "\n${CYAN}── WireGuard ──${NC}"
        ip link show $WG_IFACE &>/dev/null && \
            echo -e "${GREEN}✓ 运行中${NC}" || echo -e "${RED}✗ 未运行${NC}"
        wg show $WG_IFACE 2>/dev/null | \
            grep -E "endpoint|latest handshake|transfer" | sed 's/^/  /'
        echo -e "\n${CYAN}── 配置 ──${NC}"
        grep "Endpoint" $WG_CONF 2>/dev/null | sed 's/^/  /'
        PORT=$(cat $WARP_DIR/working_port 2>/dev/null || echo "2408")
        echo -e "  工作端口: $PORT"
        echo -e "\n${CYAN}── 路由 ──${NC}"
        ip rule show | grep 51820 | sed 's/^/  /' || echo "  无规则"
        echo -e "\n${CYAN}── 出口 ──${NC}"
        CODE=$(curl -s --max-time 6 -o /dev/null -w "%{http_code}" https://www.google.com)
        echo -e "  Google: HTTP $CODE"
        echo "" ;;

    test)
        echo -e "\n${CYAN}── 诊断 ──${NC}"
        echo -e "\n${YELLOW}[1] WireGuard 握手${NC}"
        HS=$(wg show $WG_IFACE latest-handshakes 2>/dev/null | awk '{print $2}')
        [ -n "$HS" ] && [ "$HS" != "0" ] && \
            echo -e "  ${GREEN}✓ 已握手${NC}" || echo -e "  ${RED}✗ 未握手（运行 ge fix）${NC}"
        echo -e "\n${YELLOW}[2] iptables 规则${NC}"
        CNT=$(iptables -t mangle -L WARP_MARK -n 2>/dev/null | grep -c MARK || echo 0)
        echo -e "  规则数: $CNT 条"
        echo -e "\n${YELLOW}[3] Google 透明路由${NC}"
        C=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" https://www.google.com)
        [ "$C" = "200" ] || [ "$C" = "301" ] && \
            echo -e "  ${GREEN}✓ 正常 HTTP $C${NC}" || \
            echo -e "  ${RED}✗ 异常 HTTP $C${NC}"
        echo -e "\n${YELLOW}[4] Gemini${NC}"
        G=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" \
            -H "User-Agent: Mozilla/5.0" https://gemini.google.com)
        [ "$G" = "200" ] || [ "$G" = "301" ] && \
            echo -e "  ${GREEN}✓ 可访问 HTTP $G${NC}" || \
            echo -e "  ${RED}✗ 不可访问 HTTP $G${NC}"
        echo "" ;;

    fix)
        echo -e "${CYAN}修复中...${NC}"
        echo -e "${YELLOW}重新探测可用端口...${NC}"
        CURRENT_EP=$(grep "Endpoint" $WG_CONF | awk '{print $3}' | cut -d: -f1)
        stop_routing
        wg-quick down $WG_IFACE 2>/dev/null; sleep 1

        FOUND_PORT=""
        for PORT in "${WARP_PORTS[@]}"; do
            printf "  测试端口 %-6s " "$PORT"
            sed -i "s/Endpoint = .*/Endpoint = $CURRENT_EP:$PORT/" $WG_CONF
            wg-quick up $WG_CONF 2>/dev/null; sleep 4
            HS=$(wg show $WG_IFACE latest-handshakes 2>/dev/null | awk '{print $2}')
            if [ -n "$HS" ] && [ "$HS" != "0" ]; then
                echo -e "${GREEN}✓ 握手成功${NC}"
                FOUND_PORT=$PORT
                break
            else
                echo -e "${RED}✗ 失败${NC}"
                wg-quick down $WG_IFACE 2>/dev/null; sleep 1
            fi
        done

        if [ -n "$FOUND_PORT" ]; then
            echo "$FOUND_PORT" > $WARP_DIR/working_port
            start_routing; sleep 2
            C=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" https://www.google.com)
            echo -e "${GREEN}✓ 修复成功！端口 $FOUND_PORT，Google HTTP $C${NC}"
        else
            echo -e "${RED}所有端口均不可用，VPS UDP 出站被封${NC}"
        fi ;;

    ip)
        echo -e "\n${YELLOW}直连 IP:${NC}"
        curl -4 -s --max-time 5 ip.sb; echo ""
        echo -e "${YELLOW}WARP 出口 IP:${NC}"
        OUT=$(curl -s --max-time 10 \
            "https://dns.google/resolve?name=myip.opendns.com&type=A" \
            | grep -oP '"data":"\K[^"]+' | head -1 2>/dev/null)
        [ -z "$OUT" ] && OUT=$(curl -s --max-time 8 ip.sb 2>/dev/null)
        if [ -n "$OUT" ]; then
            INFO=$(curl -s --max-time 5 "http://ip-api.com/json/$OUT?lang=zh-CN" 2>/dev/null)
            C=$(echo $INFO | grep -oP '"country":"\K[^"]+' || echo "未知")
            T=$(echo $INFO | grep -oP '"city":"\K[^"]+' || echo "")
            echo -e "${GREEN}$OUT  ($C $T)${NC}"
        fi; echo "" ;;

    scan)
        echo -e "\n${CYAN}── 扫描节点 + 端口 ──${NC}\n"
        [ ! -f $WG_CONF ] && { echo -e "${RED}请先安装${NC}"; exit 1; }
        printf "  %-6s %-10s %-22s %-16s %s\n" "序号" "端口" "Endpoint" "地区" "Gemini"
        echo -e "  ${CYAN}─────────────────────────────────────────────────────${NC}"
        BEST_EP=""; BEST_PORT=""
        for i in $(seq 1 12); do
            EP="162.159.193.$i"
            for PORT in 2408 500 1701 4500; do
                stop_routing 2>/dev/null
                wg-quick down $WG_IFACE 2>/dev/null; sleep 1
                sed -i "s/Endpoint = .*/Endpoint = $EP:$PORT/" $WG_CONF
                wg-quick up $WG_CONF 2>/dev/null; sleep 4
                HS=$(wg show $WG_IFACE latest-handshakes 2>/dev/null | awk '{print $2}')
                [ -z "$HS" ] || [ "$HS" = "0" ] && { printf "  ${RED}%-6s %-10s %-22s 握手失败${NC}\n" "#$i" "$PORT" "$EP:$PORT"; continue; }
                start_routing 2>/dev/null
                GC=$(curl -s --max-time 8 -o /dev/null -w "%{http_code}" \
                    -H "User-Agent: Mozilla/5.0" https://gemini.google.com)
                OUT=$(curl -s --max-time 6 \
                    "https://dns.google/resolve?name=myip.opendns.com&type=A" \
                    | grep -oP '"data":"\K[^"]+' | head -1 2>/dev/null || echo "?")
                INFO=$(curl -s --max-time 4 "http://ip-api.com/json/$OUT?lang=zh-CN" 2>/dev/null)
                C=$(echo $INFO | grep -oP '"country":"\K[^"]+' || echo "?")
                T=$(echo $INFO | grep -oP '"city":"\K[^"]+' || echo "")
                if [ "$GC" = "200" ] || [ "$GC" = "301" ]; then
                    printf "  ${GREEN}%-6s %-10s %-22s %-16s ✅ %s${NC}\n" "#$i" "$PORT" "$EP:$PORT" "$C $T" "$GC"
                    [ -z "$BEST_EP" ] && BEST_EP="$EP" && BEST_PORT="$PORT"
                    break
                else
                    printf "  ${YELLOW}%-6s %-10s %-22s %-16s ✗ %s${NC}\n" "#$i" "$PORT" "$EP:$PORT" "$C $T" "$GC"
                fi
            done
        done
        echo ""
        if [ -n "$BEST_EP" ]; then
            echo -e "  ${GREEN}最佳: $BEST_EP 端口 $BEST_PORT${NC}"
            read -p "  应用? [Y/n]: " yn; yn=${yn:-Y}
            if [[ "$yn" =~ ^[Yy] ]]; then
                sed -i "s/Endpoint = .*/Endpoint = $BEST_EP:$BEST_PORT/" $WG_CONF
                echo "$BEST_PORT" > $WARP_DIR/working_port
                stop_routing; wg-quick down $WG_IFACE 2>/dev/null; sleep 1
                wg-quick up $WG_CONF; sleep 4; start_routing
                echo -e "  ${GREEN}✓ 已应用${NC}"
            fi
        fi ;;

    region)
        bash /usr/local/bin/warp-setup.sh --change-region 2>/dev/null || \
        bash <(curl -fsSL https://raw.githubusercontent.com/ctsunny/g-everywhere/main/warp-setup.sh) --change-region ;;

    uninstall)
        stop_routing; wg-quick down $WG_IFACE 2>/dev/null
        systemctl disable --now g-everywhere 2>/dev/null
        rm -f /etc/systemd/system/g-everywhere.service
        rm -f /usr/local/bin/ge /usr/local/bin/warp-setup.sh /usr/local/bin/wgcf
        rm -rf /etc/warp; rm -f $WG_CONF
        echo -e "${GREEN}✓ 卸载完成${NC}" ;;

    *)
        echo -e "${CYAN}ge 管理命令 v3.3${NC}\n"
        echo "  start    启动    stop     停止"
        echo "  restart  重启    status   状态"
        echo "  test     诊断    fix      修复"
        echo "  ip       出口IP  region   换地区"
        echo "  scan     扫描    uninstall 卸载" ;;
esac
GEOF
    chmod +x /usr/local/bin/ge
    cp "$0" /usr/local/bin/warp-setup.sh 2>/dev/null || true
    chmod +x /usr/local/bin/warp-setup.sh 2>/dev/null || true
}

change_region() {
    echo -e "\n${CYAN}  ── 切换地区 ──${NC}"
    [ ! -f $WG_CONF ] && { echo -e "  ${RED}未安装${NC}"; return 1; }
    echo -e "\n  当前:"; grep "Endpoint" $WG_CONF | sed 's/^/  /'

    select_region
    TARGET_IP="${ENDPOINTS[$SELECTED_REGION]}"
    PORT=$(cat ${WARP_DIR}/working_port 2>/dev/null || echo "2408")

    routing_stop
    wg-quick down ${WG_IFACE} 2>/dev/null; sleep 1

    echo -e "  ${YELLOW}探测端口...${NC}"
    WORKING_PORT=""
    detect_working_port "$TARGET_IP"

    [ -z "$WORKING_PORT" ] && WORKING_PORT=$PORT
    sed -i "s/Endpoint = .*/Endpoint = $TARGET_IP:$WORKING_PORT/" $WG_CONF
    echo "$WORKING_PORT" > ${WARP_DIR}/working_port

    wg-quick up ${WG_CONF}; sleep 4
    routing_start

    CODE=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" https://www.google.com)
    [ "$CODE" = "200" ] || [ "$CODE" = "301" ] && \
        echo -e "  ${GREEN}✓ 切换成功！HTTP $CODE${NC}" || \
        echo -e "  ${YELLOW}HTTP $CODE，若不稳定运行 ge fix${NC}"
}

do_install() {
    select_region
    install_deps
    setup_config
    start_wg
    setup_autostart
    create_ge
    verify_exit

    echo -e "\n${BOLD}${GREEN}"
    echo "  ┌──────────────────────────────────────────┐"
    echo "  │       ✅  安装成功！Google 已解锁          │"
    echo "  └──────────────────────────────────────────┘"
    echo -e "${NC}"
    echo -e "  ${YELLOW}出口地区 :${NC} ${GREEN}$SELECTED_REGION${NC}"
    PORT=$(cat ${WARP_DIR}/working_port 2>/dev/null || echo "2408")
    echo -e "  ${YELLOW}工作端口 :${NC} ${GREEN}UDP $PORT${NC}"
    echo -e "\n  ${CYAN}━━━━━ 管理命令 (ge) ━━━━━${NC}"
    echo -e "  start/stop/restart  status  test"
    echo -e "  fix  ip  region  scan  uninstall"
    echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

do_uninstall() {
    routing_stop
    wg-quick down ${WG_IFACE} 2>/dev/null || true
    systemctl disable --now g-everywhere 2>/dev/null || true
    rm -f /etc/systemd/system/g-everywhere.service
    rm -f /usr/local/bin/ge /usr/local/bin/warp-setup.sh /usr/local/bin/wgcf
    rm -f /usr/local/bin/g /usr/local/bin/g-e /usr/local/bin/g-proxy
    rm -rf /etc/warp; rm -f ${WG_CONF}
    echo -e "  ${GREEN}✓ 卸载完成${NC}\n"
}

show_menu() {
    while true; do
        show_banner; show_ip
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
            4) command -v ge &>/dev/null && ge scan || echo -e "  ${RED}未安装${NC}" ;;
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
