#!/bin/bash
# G-Everywhere v3.2
# https://github.com/ctsunny/g-everywhere

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'
NC='\033[0m'; BOLD='\033[1m'

WG_IFACE="warp0"
WG_CONF="/etc/wireguard/${WG_IFACE}.conf"
WARP_DIR="/etc/warp"

GOOGLE_IPS="
8.8.4.0/24 8.8.8.0/24 34.0.0.0/9 35.184.0.0/13 35.192.0.0/12
35.224.0.0/12 35.240.0.0/13 64.233.160.0/19 66.102.0.0/20 66.249.64.0/19
72.14.192.0/18 74.125.0.0/16 104.132.0.0/14 108.177.0.0/17 142.250.0.0/15
172.217.0.0/16 172.253.0.0/16 173.194.0.0/16 209.85.128.0/17 216.58.192.0/19
216.239.32.0/19
"

declare -A ENDPOINTS=(
    ["🌐 自动"]="engage.cloudflareclient.com:2408"
    ["🇺🇸 美国"]="162.159.193.1:2408"
    ["🇯🇵 日本"]="162.159.193.2:2408"
    ["🇸🇬 新加坡"]="162.159.193.3:2408"
    ["🇩🇪 德国"]="162.159.193.4:2408"
    ["🇬🇧 英国"]="162.159.193.5:2408"
    ["🇳🇱 荷兰"]="162.159.193.6:2408"
    ["🇦🇺 澳大利亚"]="162.159.193.7:2408"
    ["🇰🇷 韩国"]="162.159.193.8:2408"
    ["🇭🇰 香港"]="162.159.193.9:2408"
    ["🇨🇦 加拿大"]="162.159.193.10:2408"
    ["🇮🇳 印度"]="162.159.193.11:2408"
    ["🇧🇷 巴西"]="162.159.193.12:2408"
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
    echo -e "  ${GREEN}  Google Unlock  ${NC}│${YELLOW}  wgcf + WireGuard  ${NC}│${MAGENTA}  真实地区选择  ${NC}"
    echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${BLUE}github.com/ctsunny/g-everywhere${NC}  │  ${GREEN}v3.2${NC}\n"
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
# 路由管理（核心）
# ============================================================
routing_start() {
    # 清理旧规则
    ip rule del fwmark 51820 table 51820 2>/dev/null || true
    ip route flush table 51820 2>/dev/null || true
    iptables -t mangle -D OUTPUT -j WARP_MARK 2>/dev/null || true
    iptables -t mangle -D PREROUTING -j WARP_MARK 2>/dev/null || true
    iptables -t mangle -F WARP_MARK 2>/dev/null || true
    iptables -t mangle -X WARP_MARK 2>/dev/null || true

    # 策略路由
    ip rule add fwmark 51820 table 51820
    ip route add default dev ${WG_IFACE} table 51820

    # iptables：打 mark
    iptables -t mangle -N WARP_MARK
    iptables -t mangle -A WARP_MARK -d 127.0.0.0/8 -j RETURN
    iptables -t mangle -A WARP_MARK -d 10.0.0.0/8 -j RETURN
    iptables -t mangle -A WARP_MARK -d 192.168.0.0/16 -j RETURN
    iptables -t mangle -A WARP_MARK -d 172.16.0.0/12 -j RETURN
    # 排除 WireGuard Endpoint IP（防止隧道断线）
    iptables -t mangle -A WARP_MARK -d 162.159.192.0/22 -j RETURN
    for ip in $GOOGLE_IPS; do
        iptables -t mangle -A WARP_MARK -d $ip -j MARK --set-mark 51820
    done
    # OUTPUT：本机发出的流量（含 xray/3x-ui 的 outbound）
    iptables -t mangle -A OUTPUT -j WARP_MARK
    # PREROUTING：经过该 VPS 转发的流量
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
# 安装
# ============================================================
install_deps() {
    echo -e "\n${CYAN}  [1/4] 安装依赖...${NC}"
    case $OS in
        ubuntu|debian)
            apt-get update -y >/dev/null 2>&1
            apt-get install -y wireguard wireguard-tools curl wget iptables openresolv >/dev/null 2>&1
            ;;
        centos|rhel|rocky|almalinux|fedora)
            dnf install -y epel-release >/dev/null 2>&1
            dnf install -y wireguard-tools curl wget iptables >/dev/null 2>&1
            ;;
    esac
    modprobe wireguard 2>/dev/null || true

    # 安装 wgcf
    ARCH_WGCF=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
    VER=$(curl -s --max-time 10 https://api.github.com/repos/ViRb3/wgcf/releases/latest \
        | grep tag_name | cut -d'"' -f4 2>/dev/null)
    [ -z "$VER" ] && VER="v2.2.25"

    curl -fsSL "https://github.com/ViRb3/wgcf/releases/download/${VER}/wgcf_${VER#v}_linux_${ARCH_WGCF}" \
        -o /usr/local/bin/wgcf 2>/dev/null
    [ ! -s /usr/local/bin/wgcf ] && \
        curl -fsSL "https://github.com/ViRb3/wgcf/releases/download/v2.2.25/wgcf_2.2.25_linux_${ARCH_WGCF}" \
        -o /usr/local/bin/wgcf
    chmod +x /usr/local/bin/wgcf
    command -v wgcf &>/dev/null || { echo -e "${RED}wgcf 安装失败${NC}"; exit 1; }
    echo -e "  ${GREEN}✓ 依赖安装完成${NC}"
}

setup_config() {
    echo -e "\n${CYAN}  [2/4] 生成 WireGuard 配置...${NC}"
    mkdir -p ${WARP_DIR} /etc/wireguard

    # 在 /tmp 操作避免 cp 同文件警告
    cd /tmp
    rm -f /tmp/wgcf-account.toml /tmp/wgcf-profile.conf

    # 复用已有账号
    [ -f ${WARP_DIR}/wgcf-account.toml ] && \
        cp ${WARP_DIR}/wgcf-account.toml /tmp/ && \
        echo -e "  ${GREEN}复用已有账号${NC}" || \
        echo -e "  注册新 WARP 设备..."

    wgcf register --accept-tos >/dev/null 2>&1
    cp /tmp/wgcf-account.toml ${WARP_DIR}/ 2>/dev/null || true

    wgcf generate >/dev/null 2>&1
    [ ! -f /tmp/wgcf-profile.conf ] && { echo -e "${RED}配置生成失败${NC}"; exit 1; }

    # ★ 关键修复：
    # 1. 删除 DNS（避免 resolvconf 依赖）
    sed -i '/^DNS/d' /tmp/wgcf-profile.conf
    # 2. 添加 Table = off（让 wg-quick 不自动添加路由，由我们手动管理）
    sed -i '/^\[Interface\]/a Table = off' /tmp/wgcf-profile.conf
    # 3. AllowedIPs 改为全通（允许所有流量通过隧道，路由由 iptables mark 控制）
    sed -i '/^AllowedIPs/d' /tmp/wgcf-profile.conf
    echo "AllowedIPs = 0.0.0.0/0, ::/0" >> /tmp/wgcf-profile.conf

    # 4. 设置 Endpoint
    EP="${ENDPOINTS[$SELECTED_REGION]}"
    sed -i "s/Endpoint = .*/Endpoint = $EP/" /tmp/wgcf-profile.conf
    echo -e "  Endpoint: ${YELLOW}$EP${NC}"

    # 保存配置
    cp /tmp/wgcf-profile.conf ${WARP_DIR}/wgcf-profile.conf
    cp /tmp/wgcf-profile.conf ${WG_CONF}

    echo -e "  ${GREEN}✓ 配置生成完成${NC}"
    grep -E "^(Address|Endpoint)" ${WG_CONF} | sed 's/^/  /'
}

start_wg() {
    echo -e "\n${CYAN}  [3/4] 启动 WireGuard...${NC}"

    # 停止旧接口
    ip link del ${WG_IFACE} 2>/dev/null || true
    sleep 1

    # 启动（Table=off 模式，wg-quick 不添加路由）
    if wg-quick up ${WG_CONF} 2>&1 | grep -v "^$"; then
        sleep 2
    fi

    if ip link show ${WG_IFACE} &>/dev/null; then
        echo -e "  ${GREEN}✓ WireGuard 接口启动成功${NC}"
    else
        echo -e "  ${RED}WireGuard 启动失败${NC}"
        echo -e "  ${YELLOW}排查: journalctl -xe | grep wg${NC}"
        exit 1
    fi

    # 等待握手
    echo -e "  等待 WireGuard 握手..."
    for i in $(seq 1 10); do
        sleep 2
        HS=$(wg show ${WG_IFACE} latest-handshakes 2>/dev/null | awk '{print $2}')
        if [ -n "$HS" ] && [ "$HS" != "0" ]; then
            echo -e "  ${GREEN}✓ 握手成功 (${i}次尝试)${NC}"
            break
        fi
        [ "$i" = "10" ] && echo -e "  ${YELLOW}握手超时，继续...${NC}"
    done

    # 建立路由规则
    routing_start
    echo -e "  ${GREEN}✓ 路由规则已建立${NC}"
}

verify_exit() {
    echo -e "\n${CYAN}  [4/4] 验证出口...${NC}"
    sleep 2

    # 测试 Google 是否可达
    CODE=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" https://www.google.com)
    if [ "$CODE" = "200" ] || [ "$CODE" = "301" ]; then
        echo -e "  ${GREEN}✓ Google 可达 HTTP $CODE${NC}"
    else
        echo -e "  ${RED}✗ Google 不可达 HTTP $CODE${NC}"
        echo -e "  ${YELLOW}可能原因: WireGuard 握手未完成，等待 30 秒后重试${NC}"
        sleep 20
        CODE=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" https://www.google.com)
        echo -e "  重试结果: HTTP $CODE"
    fi

    # 获取出口 IP（通过 Google DNS，走 WireGuard 路由）
    EXIT_IP=$(curl -s --max-time 10 https://dns.google/resolve?name=myip.opendns.com\&type=A \
        | grep -oP '"data":"\K[^"]+' | head -1 2>/dev/null)
    [ -z "$EXIT_IP" ] && EXIT_IP=$(curl -s --max-time 10 http://ifconfig.me 2>/dev/null)

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
# 管理命令 /usr/local/bin/ge（精简版）
# ============================================================
create_ge() {
    # 清理旧命令
    rm -f /usr/local/bin/g /usr/local/bin/g-e /usr/local/bin/g-proxy

    cat > /usr/local/bin/ge << 'EOF'
#!/bin/bash
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'
WG_IFACE="warp0"
WG_CONF="/etc/wireguard/${WG_IFACE}.conf"
GOOGLE_IPS="8.8.4.0/24 8.8.8.0/24 34.0.0.0/9 35.184.0.0/13 35.192.0.0/12 35.224.0.0/12
35.240.0.0/13 64.233.160.0/19 66.102.0.0/20 66.249.64.0/19 72.14.192.0/18 74.125.0.0/16
104.132.0.0/14 108.177.0.0/17 142.250.0.0/15 172.217.0.0/16 172.253.0.0/16 173.194.0.0/16
209.85.128.0/17 216.58.192.0/19 216.239.32.0/19"

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
        wg-quick up $WG_CONF 2>/dev/null; sleep 3
        start_routing
        echo -e "${GREEN}✓ 已重启${NC}" ;;

    status)
        echo -e "\n${CYAN}── WireGuard ──${NC}"
        ip link show $WG_IFACE &>/dev/null && \
            echo -e "${GREEN}✓ 运行中${NC}" || echo -e "${RED}✗ 未运行${NC}"
        wg show $WG_IFACE 2>/dev/null | grep -E "endpoint|latest handshake|transfer" | sed 's/^/  /'
        echo -e "\n${CYAN}── Endpoint ──${NC}"
        grep "Endpoint" $WG_CONF 2>/dev/null | sed 's/^/  /'
        echo -e "\n${CYAN}── 路由规则 ──${NC}"
        ip rule show | grep 51820 | sed 's/^/  /' || echo "  无规则"
        echo -e "\n${CYAN}── 出口 IP ──${NC}"
        CODE=$(curl -s --max-time 6 -o /dev/null -w "%{http_code}" https://www.google.com 2>/dev/null)
        echo -e "  Google: HTTP $CODE"
        echo "" ;;

    test)
        echo -e "\n${CYAN}── 诊断测试 ──${NC}"
        echo -e "\n${YELLOW}[1] WireGuard 握手${NC}"
        HS=$(wg show $WG_IFACE latest-handshakes 2>/dev/null | awk '{print $2}')
        [ -n "$HS" ] && [ "$HS" != "0" ] && \
            echo -e "  ${GREEN}✓ 已握手${NC}" || echo -e "  ${RED}✗ 未握手${NC}"

        echo -e "\n${YELLOW}[2] iptables 规则${NC}"
        CNT=$(iptables -t mangle -L WARP_MARK -n 2>/dev/null | grep -c MARK || echo 0)
        echo -e "  规则数: $CNT 条"

        echo -e "\n${YELLOW}[3] Google 访问（透明路由）${NC}"
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

    ip)
        echo -e "\n${YELLOW}直连 IP:${NC}"
        curl -4 -s --max-time 5 ip.sb; echo ""
        echo -e "${YELLOW}Google 出口 IP（走 WARP）:${NC}"
        # 通过 Google DNS 查询
        OUT=$(curl -s --max-time 10 "https://dns.google/resolve?name=myip.opendns.com&type=A" \
            | grep -oP '"data":"\K[^"]+' | head -1 2>/dev/null)
        [ -z "$OUT" ] && OUT=$(curl -s --max-time 10 https://api.ipify.org 2>/dev/null)
        if [ -n "$OUT" ]; then
            INFO=$(curl -s --max-time 5 "http://ip-api.com/json/$OUT?lang=zh-CN" 2>/dev/null)
            C=$(echo $INFO | grep -oP '"country":"\K[^"]+' || echo "未知")
            T=$(echo $INFO | grep -oP '"city":"\K[^"]+' || echo "")
            echo -e "${GREEN}$OUT  ($C $T)${NC}"
        fi
        echo "" ;;

    fix)
        echo -e "${CYAN}修复中...${NC}"
        stop_routing
        wg-quick down $WG_IFACE 2>/dev/null; sleep 1
        wg-quick up $WG_CONF; sleep 5
        start_routing
        C=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" https://www.google.com)
        [ "$C" = "200" ] || [ "$C" = "301" ] && \
            echo -e "${GREEN}✓ 修复成功 HTTP $C${NC}" || \
            echo -e "${RED}✗ 仍异常 HTTP $C，尝试: ge scan${NC}" ;;

    scan)
        echo -e "\n${CYAN}── 扫描所有节点 ──${NC}\n"
        [ ! -f $WG_CONF ] && { echo -e "${RED}请先安装${NC}"; exit 1; }
        printf "  %-8s %-22s %-18s %s\n" "序号" "Endpoint" "地区" "Gemini"
        echo -e "  ${CYAN}──────────────────────────────────────────────────${NC}"
        BEST=""
        for i in $(seq 1 12); do
            EP="162.159.193.$i:2408"
            sed -i "s/Endpoint = .*/Endpoint = $EP/" $WG_CONF
            wg-quick down $WG_IFACE 2>/dev/null; sleep 1
            wg-quick up $WG_CONF 2>/dev/null; sleep 4
            ip rule del fwmark 51820 table 51820 2>/dev/null; ip route flush table 51820 2>/dev/null
            ip rule add fwmark 51820 table 51820; ip route add default dev $WG_IFACE table 51820
            GC=$(curl -s --max-time 8 -o /dev/null -w "%{http_code}" \
                -H "User-Agent: Mozilla/5.0" https://gemini.google.com 2>/dev/null)
            OUT=$(curl -s --max-time 8 "https://dns.google/resolve?name=myip.opendns.com&type=A" \
                | grep -oP '"data":"\K[^"]+' | head -1 2>/dev/null || echo "?")
            INFO=$(curl -s --max-time 4 "http://ip-api.com/json/$OUT?lang=zh-CN" 2>/dev/null)
            C=$(echo $INFO | grep -oP '"country":"\K[^"]+' || echo "?")
            T=$(echo $INFO | grep -oP '"city":"\K[^"]+' || echo "")
            if [ "$GC" = "200" ] || [ "$GC" = "301" ]; then
                printf "  ${GREEN}%-8s %-22s %-18s ✅ %s${NC}\n" "#$i" "$EP" "$C $T" "$GC"
                [ -z "$BEST" ] && BEST="$EP"
            else
                printf "  ${YELLOW}%-8s %-22s %-18s ✗ %s${NC}\n" "#$i" "$EP" "$C $T" "$GC"
            fi
        done
        echo ""
        if [ -n "$BEST" ]; then
            echo -e "  ${GREEN}最佳节点: $BEST${NC}"
            read -p "  应用此节点? [Y/n]: " yn; yn=${yn:-Y}
            if [[ "$yn" =~ ^[Yy] ]]; then
                sed -i "s/Endpoint = .*/Endpoint = $BEST/" $WG_CONF
                wg-quick down $WG_IFACE 2>/dev/null; sleep 1
                wg-quick up $WG_CONF; sleep 3
                ip rule del fwmark 51820 table 51820 2>/dev/null
                ip route flush table 51820 2>/dev/null
                ip rule add fwmark 51820 table 51820
                ip route add default dev $WG_IFACE table 51820
                echo -e "  ${GREEN}✓ 已应用${NC}"
            fi
        else
            echo -e "  ${RED}所有节点 Gemini 均不可用${NC}"
        fi ;;

    region)
        bash /usr/local/bin/warp-setup.sh --change-region 2>/dev/null || \
        bash <(curl -fsSL https://raw.githubusercontent.com/ctsunny/g-everywhere/main/warp-setup.sh) --change-region ;;

    uninstall)
        stop_routing
        wg-quick down $WG_IFACE 2>/dev/null
        systemctl disable --now g-everywhere 2>/dev/null
        rm -f /etc/systemd/system/g-everywhere.service
        rm -f /usr/local/bin/ge /usr/local/bin/warp-setup.sh /usr/local/bin/wgcf
        rm -rf /etc/warp; rm -f $WG_CONF
        echo -e "${GREEN}✓ 卸载完成${NC}" ;;

    *)
        echo -e "${CYAN}ge 管理命令${NC}\n"
        echo "  start     启动"
        echo "  stop      停止"
        echo "  restart   重启"
        echo "  status    查看状态"
        echo "  test      全面诊断"
        echo "  fix       一键修复"
        echo "  ip        查看出口 IP"
        echo "  region    切换地区"
        echo "  scan      扫描节点"
        echo "  uninstall 卸载" ;;
esac
EOF
    chmod +x /usr/local/bin/ge
    cp "$0" /usr/local/bin/warp-setup.sh 2>/dev/null || true
    chmod +x /usr/local/bin/warp-setup.sh 2>/dev/null || true
}

change_region() {
    echo -e "\n${CYAN}  ── 切换出口地区 ──${NC}"
    [ ! -f $WG_CONF ] && { echo -e "  ${RED}未安装，请先安装${NC}"; return 1; }
    echo -e "\n  当前:"; grep "Endpoint" $WG_CONF | sed 's/^/  /'
    select_region
    EP="${ENDPOINTS[$SELECTED_REGION]}"
    sed -i "s/Endpoint = .*/Endpoint = $EP/" $WG_CONF
    sed -i "s/Endpoint = .*/Endpoint = $EP/" ${WARP_DIR}/wgcf-profile.conf 2>/dev/null || true
    routing_stop
    wg-quick down ${WG_IFACE} 2>/dev/null; sleep 1
    wg-quick up ${WG_CONF}; sleep 5
    routing_start
    CODE=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" https://www.google.com)
    [ "$CODE" = "200" ] || [ "$CODE" = "301" ] && \
        echo -e "  ${GREEN}✓ 切换成功！Google HTTP $CODE${NC}" || \
        echo -e "  ${YELLOW}切换完成，Google HTTP $CODE${NC}"
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
    echo -e "  ${YELLOW}出口地区:${NC} ${GREEN}$SELECTED_REGION${NC}"
    echo -e "\n  ${CYAN}━━━━━ 管理命令 ━━━━━${NC}"
    echo -e "  ${GREEN}ge${NC}          菜单"
    echo -e "  ${GREEN}ge status${NC}   状态"
    echo -e "  ${GREEN}ge test${NC}     诊断"
    echo -e "  ${GREEN}ge ip${NC}       出口IP"
    echo -e "  ${GREEN}ge region${NC}   换地区"
    echo -e "  ${GREEN}ge scan${NC}     扫描节点"
    echo -e "  ${GREEN}ge fix${NC}      修复"
    echo -e "  ${GREEN}ge uninstall${NC} 卸载"
    echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━${NC}\n"
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
            3) /usr/local/bin/ge status 2>/dev/null || echo -e "  ${RED}未安装${NC}" ;;
            4) /usr/local/bin/ge scan 2>/dev/null || echo -e "  ${RED}未安装${NC}" ;;
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
        --scan)           show_banner; /usr/local/bin/ge scan 2>/dev/null ;;
        *)                show_menu ;;
    esac
}
main "$@"
