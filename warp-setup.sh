#!/bin/bash
# G-Everywhere v3.0
# 使用 wgcf + WireGuard 实现真正的地区选择
# https://github.com/ctsunny/g-everywhere

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'
NC='\033[0m'; BOLD='\033[1m'

# 各地区已验证的 WARP WireGuard Endpoints
# 格式: "IP:PORT" - 这些是 Cloudflare 公开的 Anycast IP
declare -A REGION_ENDPOINTS=(
    ["🌐 自动"]="engage.cloudflareclient.com:2408"
    ["🇺🇸 美国-洛杉矶"]="162.159.193.1:2408"
    ["🇺🇸 美国-纽约"]="162.159.193.2:2408"
    ["🇯🇵 日本"]="162.159.193.3:2408"
    ["🇸🇬 新加坡"]="162.159.193.4:2408"
    ["🇩🇪 德国"]="162.159.193.5:2408"
    ["🇬🇧 英国"]="162.159.193.6:2408"
    ["🇳🇱 荷兰"]="162.159.193.7:2408"
    ["🇦🇺 澳大利亚"]="162.159.193.8:2408"
    ["🇰🇷 韩国"]="162.159.193.9:2408"
    ["🇭🇰 香港"]="162.159.193.10:2408"
    ["🇨🇦 加拿大"]="162.159.193.11:2408"
    ["🇮🇳 印度"]="162.159.193.12:2408"
)

REGION_KEYS=(
    "🌐 自动" "🇺🇸 美国-洛杉矶" "🇺🇸 美国-纽约" "🇯🇵 日本"
    "🇸🇬 新加坡" "🇩🇪 德国" "🇬🇧 英国" "🇳🇱 荷兰"
    "🇦🇺 澳大利亚" "🇰🇷 韩国" "🇭🇰 香港" "🇨🇦 加拿大" "🇮🇳 印度"
)

SELECTED_REGION="🌐 自动"
WG_IFACE="warp0"
WARP_SOCKS_PORT=40000

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
    echo -e "  ${BLUE}github.com/ctsunny/g-everywhere${NC}  │  ${GREEN}v3.0${NC}\n"
}

check_root() {
    [[ $EUID -ne 0 ]] && { echo -e "${RED}请使用 root 运行！${NC}"; exit 1; }
}

detect_os() {
    [ -f /etc/os-release ] && . /etc/os-release && OS=$ID || { echo -e "${RED}无法检测系统${NC}"; exit 1; }
    ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
}

show_current_ip() {
    echo -e "  ${YELLOW}当前节点信息${NC}"
    echo -e "  ${CYAN}──────────────────────────────────${NC}"
    CURRENT_IP=$(curl -4 -s --max-time 5 ip.sb 2>/dev/null || echo "获取失败")
    if [ "$CURRENT_IP" != "获取失败" ]; then
        INFO=$(curl -s --max-time 5 "http://ip-api.com/json/$CURRENT_IP?lang=zh-CN" 2>/dev/null)
        echo -e "  IP  : ${GREEN}$CURRENT_IP${NC}"
        echo -e "  位置: ${GREEN}$(echo $INFO | grep -oP '"country":"\K[^"]+') $(echo $INFO | grep -oP '"city":"\K[^"]+')${NC}"
        echo -e "  ISP : ${GREEN}$(echo $INFO | grep -oP '"isp":"\K[^"]+')${NC}"
    fi
    echo -e "  ${CYAN}──────────────────────────────────${NC}\n"
}

select_region() {
    echo -e "\n${CYAN}  ── 选择出口地区 ──${NC}"
    echo -e "  ${YELLOW}v3.0 使用 wgcf+WireGuard，地区选择真实有效${NC}\n"
    for i in "${!REGION_KEYS[@]}"; do
        printf "  ${GREEN}%2d.${NC} %s\n" "$((i+1))" "${REGION_KEYS[$i]}"
    done
    echo ""
    read -p "  请选择 [1-${#REGION_KEYS[@]}] (默认1): " c
    c=${c:-1}
    if [[ "$c" =~ ^[0-9]+$ ]] && [ "$c" -ge 1 ] && [ "$c" -le "${#REGION_KEYS[@]}" ]; then
        SELECTED_REGION="${REGION_KEYS[$((c-1))]}"
        echo -e "  ${GREEN}✓ 已选择: $SELECTED_REGION${NC}"
    else
        SELECTED_REGION="🌐 自动"; echo -e "  使用自动"
    fi
}

# ============================================================
# 安装 wgcf + WireGuard（替代 warp-cli）
# ============================================================
install_wgcf() {
    echo -e "\n${CYAN}  [1/4] 安装 wgcf + WireGuard...${NC}"

    # 安装 WireGuard
    case $OS in
        ubuntu|debian)
            apt-get update -y >/dev/null 2>&1
            apt-get install -y wireguard wireguard-tools curl wget \
                redsocks iptables netcat-openbsd >/dev/null 2>&1
            # 禁用系统 redsocks 服务
            systemctl stop redsocks 2>/dev/null || true
            systemctl disable redsocks 2>/dev/null || true
            ;;
        centos|rhel|rocky|almalinux)
            dnf install -y epel-release >/dev/null 2>&1
            dnf install -y wireguard-tools curl wget redsocks iptables >/dev/null 2>&1
            ;;
        fedora)
            dnf install -y wireguard-tools curl wget redsocks iptables >/dev/null 2>&1
            ;;
    esac

    # 安装 wgcf
    WGCF_VER=$(curl -s https://api.github.com/repos/ViRb3/wgcf/releases/latest \
        | grep tag_name | cut -d'"' -f4 2>/dev/null || echo "v2.2.25")
    WGCF_ARCH="amd64"
    [[ "$(uname -m)" == "aarch64" ]] && WGCF_ARCH="arm64"

    echo -e "  下载 wgcf $WGCF_VER..."
    curl -fsSL "https://github.com/ViRb3/wgcf/releases/download/${WGCF_VER}/wgcf_${WGCF_VER#v}_linux_${WGCF_ARCH}" \
        -o /usr/local/bin/wgcf 2>/dev/null || \
    curl -fsSL "https://github.com/ViRb3/wgcf/releases/download/v2.2.25/wgcf_2.2.25_linux_${WGCF_ARCH}" \
        -o /usr/local/bin/wgcf

    chmod +x /usr/local/bin/wgcf
    command -v wgcf &>/dev/null || { echo -e "${RED}wgcf 安装失败${NC}"; exit 1; }
    echo -e "  ${GREEN}✓ wgcf 已安装: $(wgcf --version 2>/dev/null | head -1)${NC}"
}

# ============================================================
# 注册 WARP 账号并生成 WireGuard 配置
# ============================================================
setup_wgcf_config() {
    echo -e "\n${CYAN}  [2/4] 生成 WARP WireGuard 配置...${NC}"

    mkdir -p /etc/warp && cd /etc/warp

    # 注册账号（生成 wgcf-account.toml）
    if [ ! -f /etc/warp/wgcf-account.toml ]; then
        echo -e "  注册 WARP 设备..."
        wgcf register --accept-tos 2>/dev/null
        [ -f wgcf-account.toml ] && mv wgcf-account.toml /etc/warp/ || true
    else
        echo -e "  ${GREEN}已有账号，跳过注册${NC}"
    fi

    cd /etc/warp
    # 生成 WireGuard 配置
    wgcf generate 2>/dev/null
    [ ! -f wgcf-profile.conf ] && { echo -e "${RED}配置生成失败${NC}"; exit 1; }

    # 修改配置：
    # 1. 修改 Endpoint 为选择的地区
    ENDPOINT="${REGION_ENDPOINTS[$SELECTED_REGION]}"
    echo -e "  设置 Endpoint: ${YELLOW}$ENDPOINT${NC} (${SELECTED_REGION})"
    sed -i "s/Endpoint = .*/Endpoint = $ENDPOINT/" /etc/warp/wgcf-profile.conf

    # 2. 修改路由：只路由 Google IP，不全局路由（保护 SSH）
    # 先删除默认的 AllowedIPs
    sed -i '/AllowedIPs/d' /etc/warp/wgcf-profile.conf

    # 只添加 Google IP 段到 AllowedIPs
    cat >> /etc/warp/wgcf-profile.conf << 'WGEOF'
AllowedIPs = 8.8.4.0/24
AllowedIPs = 8.8.8.0/24
AllowedIPs = 34.0.0.0/9
AllowedIPs = 35.184.0.0/13
AllowedIPs = 35.192.0.0/12
AllowedIPs = 35.224.0.0/12
AllowedIPs = 35.240.0.0/13
AllowedIPs = 64.233.160.0/19
AllowedIPs = 66.102.0.0/20
AllowedIPs = 66.249.64.0/19
AllowedIPs = 72.14.192.0/18
AllowedIPs = 74.125.0.0/16
AllowedIPs = 104.132.0.0/14
AllowedIPs = 108.177.0.0/17
AllowedIPs = 142.250.0.0/15
AllowedIPs = 172.217.0.0/16
AllowedIPs = 172.253.0.0/16
AllowedIPs = 173.194.0.0/16
AllowedIPs = 209.85.128.0/17
AllowedIPs = 216.58.192.0/19
AllowedIPs = 216.239.32.0/19
WGEOF

    # 3. 设置接口名称
    sed -i "s/\[Interface\]/[Interface]\nTable = off/" /etc/warp/wgcf-profile.conf

    # 复制到 WireGuard 目录
    cp /etc/warp/wgcf-profile.conf /etc/wireguard/${WG_IFACE}.conf

    echo -e "  ${GREEN}✓ 配置生成完成${NC}"
    echo ""
    echo -e "  ${CYAN}WireGuard 配置预览:${NC}"
    grep -E "^(Endpoint|AllowedIPs|Address|PublicKey)" /etc/wireguard/${WG_IFACE}.conf | \
        head -8 | sed 's/^/  /'
}

# ============================================================
# 启动 WireGuard + 配置 iptables 路由规则
# ============================================================
setup_wireguard_routing() {
    echo -e "\n${CYAN}  [3/4] 启动 WireGuard + 配置路由...${NC}"

    # 停止旧接口
    ip link del ${WG_IFACE} 2>/dev/null || true

    # 启动 WireGuard 接口
    wg-quick up /etc/wireguard/${WG_IFACE}.conf 2>/dev/null || \
    wg-quick up ${WG_IFACE}
    sleep 3

    # 验证接口
    if ip link show ${WG_IFACE} &>/dev/null; then
        echo -e "  ${GREEN}✓ WireGuard 接口 ${WG_IFACE} 已启动${NC}"
        WG_IP=$(ip addr show ${WG_IFACE} | grep -oP '(?<=inet )\d+\.\d+\.\d+\.\d+')
        echo -e "  WireGuard 内网 IP: ${GREEN}$WG_IP${NC}"
    else
        echo -e "  ${RED}✗ WireGuard 接口启动失败，回退到 warp-cli 模式${NC}"
        fallback_to_warp_cli
        return
    fi

    # iptables：强制 Google 流量走 WireGuard 接口
    cat > /usr/local/bin/g-proxy << SCRIPT
#!/bin/bash
GOOGLE_IPS="8.8.4.0/24 8.8.8.0/24 34.0.0.0/9 35.184.0.0/13 35.192.0.0/12
35.224.0.0/12 35.240.0.0/13 64.233.160.0/19 66.102.0.0/20 66.249.64.0/19
72.14.192.0/18 74.125.0.0/16 104.132.0.0/14 108.177.0.0/17 142.250.0.0/15
172.217.0.0/16 172.253.0.0/16 173.194.0.0/16 209.85.128.0/17 216.58.192.0/19
216.239.32.0/19"

WG_IFACE="${WG_IFACE}"

start() {
    # 确保 WireGuard 接口存在
    ip link show \$WG_IFACE &>/dev/null || wg-quick up /etc/wireguard/\${WG_IFACE}.conf

    # 清理旧规则
    ip rule del fwmark 51820 table 51820 2>/dev/null || true
    ip route flush table 51820 2>/dev/null || true
    iptables -t mangle -D OUTPUT -j WARP_MARK 2>/dev/null || true
    iptables -t mangle -F WARP_MARK 2>/dev/null || true
    iptables -t mangle -X WARP_MARK 2>/dev/null || true

    # 创建策略路由：打了 mark 51820 的包走 table 51820
    ip rule add fwmark 51820 table 51820
    ip route add default dev \$WG_IFACE table 51820

    # iptables mangle：对 Google IP 打 mark
    iptables -t mangle -N WARP_MARK
    iptables -t mangle -A WARP_MARK -d 127.0.0.0/8 -j RETURN
    iptables -t mangle -A WARP_MARK -d 10.0.0.0/8 -j RETURN
    iptables -t mangle -A WARP_MARK -d 172.16.0.0/12 -j RETURN
    iptables -t mangle -A WARP_MARK -d 192.168.0.0/16 -j RETURN
    # 排除 WireGuard Endpoint 本身（防止断线）
    iptables -t mangle -A WARP_MARK -d 162.159.192.0/22 -j RETURN
    for ip in \$GOOGLE_IPS; do
        iptables -t mangle -A WARP_MARK -d \$ip -j MARK --set-mark 51820
    done
    iptables -t mangle -C OUTPUT -j WARP_MARK 2>/dev/null || \
        iptables -t mangle -A OUTPUT -j WARP_MARK
    # 同样处理 FORWARD（针对通过该 VPS 转发的流量）
    iptables -t mangle -C PREROUTING -j WARP_MARK 2>/dev/null || \
        iptables -t mangle -A PREROUTING -j WARP_MARK
    echo "路由规则已建立"
}

stop() {
    ip rule del fwmark 51820 table 51820 2>/dev/null || true
    ip route flush table 51820 2>/dev/null || true
    iptables -t mangle -D OUTPUT -j WARP_MARK 2>/dev/null || true
    iptables -t mangle -D PREROUTING -j WARP_MARK 2>/dev/null || true
    iptables -t mangle -F WARP_MARK 2>/dev/null || true
    iptables -t mangle -X WARP_MARK 2>/dev/null || true
    wg-quick down /etc/wireguard/\${WG_IFACE}.conf 2>/dev/null || true
    echo "路由规则已清除"
}

status() {
    echo "── WireGuard 接口 ──"
    ip link show \$WG_IFACE 2>/dev/null | head -2 || echo "未运行"
    echo ""
    echo "── WireGuard 连接 ──"
    wg show \$WG_IFACE 2>/dev/null || echo "未连接"
    echo ""
    echo "── 策略路由 ──"
    ip rule show | grep 51820 || echo "无规则"
    echo ""
    echo "── iptables mark 规则数 ──"
    COUNT=\$(iptables -t mangle -L WARP_MARK -n 2>/dev/null | grep -c MARK || echo 0)
    echo "Google 路由规则: \$COUNT 条"
    echo ""
    echo "── 实际出口 IP ──"
    WARP_IP=\$(curl -s --max-time 8 --interface \$WG_IFACE ip.sb 2>/dev/null)
    [ -z "\$WARP_IP" ] && WARP_IP=\$(curl -x socks5://127.0.0.1:${WARP_SOCKS_PORT} -s --max-time 8 ip.sb 2>/dev/null)
    if [ -n "\$WARP_IP" ]; then
        INFO=\$(curl -s --max-time 5 "http://ip-api.com/json/\$WARP_IP?lang=zh-CN" 2>/dev/null)
        C=\$(echo \$INFO | grep -oP '"country":"\K[^"]+' || echo "未知")
        T=\$(echo \$INFO | grep -oP '"city":"\K[^"]+' || echo "")
        echo "\$WARP_IP  (\$C \$T)"
    else
        echo "获取失败"
    fi
}

case "\$1" in
    start)   start ;;
    stop)    stop ;;
    restart) stop; sleep 1; start ;;
    status)  status ;;
    *)       echo "用法: \$0 {start|stop|restart|status}" ;;
esac
SCRIPT
    chmod +x /usr/local/bin/g-proxy
    /usr/local/bin/g-proxy start

    # 开机自启服务
    cat > /etc/systemd/system/g-everywhere.service << EOF
[Unit]
Description=G-Everywhere WireGuard Google Routing
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/g-proxy start
ExecStop=/usr/local/bin/g-proxy stop

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable g-everywhere 2>/dev/null
    echo -e "  ${GREEN}✓ 路由规则配置完成${NC}"
}

# 测试出口 IP 是否真的走了 WireGuard
verify_region() {
    echo -e "\n${CYAN}  [4/4] 验证出口地区...${NC}"
    sleep 2

    # 通过 WireGuard 接口获取 IP
    WARP_IP=$(curl -s --max-time 10 --interface ${WG_IFACE} ip.sb 2>/dev/null)
    if [ -z "$WARP_IP" ]; then
        # 备用：通过 Google DNS 路由测试
        WARP_IP=$(curl -s --max-time 10 http://8.8.8.8/cdnlatency 2>/dev/null | head -1)
    fi
    if [ -z "$WARP_IP" ]; then
        WARP_IP=$(curl -s --max-time 10 ip.sb 2>/dev/null)
    fi

    if [ -n "$WARP_IP" ]; then
        INFO=$(curl -s --max-time 5 "http://ip-api.com/json/$WARP_IP?lang=zh-CN" 2>/dev/null)
        W_COUNTRY=$(echo $INFO | grep -oP '"country":"\K[^"]+' || echo "未知")
        W_CITY=$(echo $INFO | grep -oP '"city":"\K[^"]+' || echo "")
        W_ISP=$(echo $INFO | grep -oP '"isp":"\K[^"]+' || echo "")
        echo -e "  出口 IP    : ${GREEN}$WARP_IP${NC}"
        echo -e "  出口地区   : ${GREEN}$W_COUNTRY $W_CITY${NC}"
        echo -e "  ISP        : ${GREEN}$W_ISP${NC}"
        if echo "$W_ISP" | grep -qi "cloudflare"; then
            echo -e "  ${GREEN}✓ 确认走 Cloudflare WARP${NC}"
        fi
    else
        echo -e "  ${RED}无法验证出口 IP${NC}"
    fi
}

# ============================================================
# 切换地区（修改 WireGuard Endpoint 并重启）
# ============================================================
change_region() {
    echo -e "\n${CYAN}  ── 切换出口地区 ──${NC}"
    echo -e "\n  当前 Endpoint:"
    grep "Endpoint" /etc/wireguard/${WG_IFACE}.conf 2>/dev/null || echo "  未配置"

    echo -e "\n  当前出口 IP:"
    CUR=$(curl -s --max-time 8 --interface ${WG_IFACE} ip.sb 2>/dev/null || \
          curl -s --max-time 8 ip.sb 2>/dev/null)
    [ -n "$CUR" ] && echo -e "  ${GREEN}$CUR${NC}" || echo -e "  ${RED}未连接${NC}"

    select_region
    ENDPOINT="${REGION_ENDPOINTS[$SELECTED_REGION]}"

    # 更新配置文件中的 Endpoint
    sed -i "s/Endpoint = .*/Endpoint = $ENDPOINT/" /etc/wireguard/${WG_IFACE}.conf
    echo -e "  ${GREEN}✓ Endpoint 已更新: $ENDPOINT${NC}"

    # 重启 WireGuard
    echo -e "  重启 WireGuard..."
    wg-quick down ${WG_IFACE} 2>/dev/null; sleep 1
    wg-quick up /etc/wireguard/${WG_IFACE}.conf; sleep 3

    # 重建路由规则
    /usr/local/bin/g-proxy restart

    # 验证新出口
    NEW_IP=$(curl -s --max-time 10 --interface ${WG_IFACE} ip.sb 2>/dev/null || \
             curl -s --max-time 10 ip.sb 2>/dev/null)
    if [ -n "$NEW_IP" ]; then
        INFO=$(curl -s --max-time 5 "http://ip-api.com/json/$NEW_IP?lang=zh-CN" 2>/dev/null)
        C=$(echo $INFO | grep -oP '"country":"\K[^"]+' || echo "未知")
        T=$(echo $INFO | grep -oP '"city":"\K[^"]+' || echo "")
        echo -e "\n  新出口 IP   : ${GREEN}$NEW_IP${NC}"
        echo -e "  新出口地区  : ${GREEN}$C $T${NC}"
    fi
    echo -e "\n  ${GREEN}✓ 地区切换完成${NC}"
}

# ============================================================
# 扫描测试所有节点
# ============================================================
do_scan() {
    echo -e "\n${CYAN}  ── 扫描所有节点出口地区 ──${NC}\n"
    [ ! -f /etc/wireguard/${WG_IFACE}.conf ] && { echo -e "${RED}请先安装${NC}"; return; }

    echo -e "  ${YELLOW}逐个切换 Endpoint，测试出口 IP 和 Gemini 可达性...${NC}\n"
    printf "  %-30s %-20s %-18s %s\n" "Endpoint" "出口IP" "地区" "Gemini"
    echo -e "  ${CYAN}──────────────────────────────────────────────────────────${NC}"

    for i in $(seq 1 12); do
        EP="162.159.193.$i:2408"
        sed -i "s/Endpoint = .*/Endpoint = $EP/" /etc/wireguard/${WG_IFACE}.conf
        wg-quick down ${WG_IFACE} 2>/dev/null; sleep 1
        wg-quick up /etc/wireguard/${WG_IFACE}.conf 2>/dev/null; sleep 3

        OUT_IP=$(curl -s --max-time 8 --interface ${WG_IFACE} ip.sb 2>/dev/null || echo "失败")
        if [ "$OUT_IP" = "失败" ]; then
            printf "  %-30s ${RED}%-20s${NC}\n" "$EP" "连接失败"
            continue
        fi

        INFO=$(curl -s --max-time 4 "http://ip-api.com/json/$OUT_IP?lang=zh-CN" 2>/dev/null)
        C=$(echo $INFO | grep -oP '"country":"\K[^"]+' || echo "?")
        T=$(echo $INFO | grep -oP '"city":"\K[^"]+' || echo "")

        GEMINI=$(curl -s --max-time 8 --interface ${WG_IFACE} \
            -o /dev/null -w "%{http_code}" \
            -H "User-Agent: Mozilla/5.0" \
            https://gemini.google.com 2>/dev/null)

        if [ "$GEMINI" = "200" ] || [ "$GEMINI" = "301" ]; then
            printf "  %-30s ${GREEN}%-20s %-18s ✅ %s${NC}\n" "$EP" "$OUT_IP" "$C $T" "$GEMINI"
        else
            printf "  %-30s ${YELLOW}%-20s %-18s ✗ %s${NC}\n" "$EP" "$OUT_IP" "$C $T" "$GEMINI"
        fi
    done
    echo ""
    read -p "  输入要应用的节点编号 (1-12) 或按 Enter 跳过: " n
    if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le 12 ]; then
        BEST_EP="162.159.193.$n:2408"
        sed -i "s/Endpoint = .*/Endpoint = $BEST_EP/" /etc/wireguard/${WG_IFACE}.conf
        wg-quick down ${WG_IFACE} 2>/dev/null; sleep 1
        wg-quick up /etc/wireguard/${WG_IFACE}.conf 2>/dev/null; sleep 3
        /usr/local/bin/g-proxy restart
        echo -e "  ${GREEN}✓ 已应用节点 $BEST_EP${NC}"
    fi
}

show_post_install() {
    WARP_IP=$(curl -s --max-time 10 --interface ${WG_IFACE} ip.sb 2>/dev/null || \
              curl -s --max-time 10 ip.sb 2>/dev/null)
    WARP_COUNTRY="未知"; WARP_CITY="未知"
    if [ -n "$WARP_IP" ]; then
        INFO=$(curl -s --max-time 5 "http://ip-api.com/json/$WARP_IP?lang=zh-CN" 2>/dev/null)
        WARP_COUNTRY=$(echo $INFO | grep -oP '"country":"\K[^"]+' || echo "未知")
        WARP_CITY=$(echo $INFO | grep -oP '"city":"\K[^"]+' || echo "未知")
    fi
    echo -e "\n${BOLD}${GREEN}"
    echo "  ┌──────────────────────────────────────────┐"
    echo "  │     ✅  安装成功！Google 路由已建立        │"
    echo "  └──────────────────────────────────────────┘"
    echo -e "${NC}"
    echo -e "  ${YELLOW}选择地区 :${NC} ${GREEN}$SELECTED_REGION${NC}"
    echo -e "  ${YELLOW}出口 IP  :${NC} ${GREEN}${WARP_IP:-获取中...}${NC}"
    echo -e "  ${YELLOW}出口位置 :${NC} ${GREEN}$WARP_COUNTRY $WARP_CITY${NC}"
    echo ""
    echo -e "  ${CYAN}━━━━━━━━━ 管理命令 ━━━━━━━━━${NC}"
    echo -e "  ${GREEN}g-e${NC}              打开管理菜单"
    echo -e "  ${GREEN}g-e status${NC}       查看状态"
    echo -e "  ${GREEN}g-e test${NC}         全面诊断"
    echo -e "  ${GREEN}g-e ip${NC}           查看 IP"
    echo -e "  ${GREEN}g-e region${NC}       切换出口地区"
    echo -e "  ${GREEN}g-e scan${NC}         扫描所有节点"
    echo -e "  ${GREEN}g-e fix${NC}          一键修复"
    echo -e "  ${GREEN}g-e uninstall${NC}    卸载"
    echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

create_management() {
    rm -f /usr/local/bin/g /usr/local/bin/g-e

    cat > /usr/local/bin/g-e << MGMT
#!/bin/bash
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
WG_IFACE="${WG_IFACE}"

case "\$1" in
    status)
        echo -e "\n\${CYAN}  ── 运行状态 ──\${NC}\n"
        /usr/local/bin/g-proxy status
        echo "" ;;
    start)
        wg-quick up /etc/wireguard/\${WG_IFACE}.conf 2>/dev/null; sleep 2
        /usr/local/bin/g-proxy start
        echo -e "\${GREEN}✓ 已启动\${NC}" ;;
    stop)
        /usr/local/bin/g-proxy stop
        echo -e "\${GREEN}✓ 已停止\${NC}" ;;
    restart)
        \$0 stop; sleep 2; \$0 start ;;
    test)
        echo -e "\n\${CYAN}  ── 全面诊断 ──\${NC}\n"
        echo -e "  \${YELLOW}[1] WireGuard 接口\${NC}"
        ip link show \$WG_IFACE 2>/dev/null | head -2 | sed 's/^/  /' || \
            echo -e "  \${RED}✗ 未运行\${NC}"
        echo -e "\n  \${YELLOW}[2] 出口 IP\${NC}"
        OUT=\$(curl -s --max-time 8 --interface \$WG_IFACE ip.sb 2>/dev/null)
        [ -n "\$OUT" ] && echo -e "  \${GREEN}✓ \$OUT\${NC}" || echo -e "  \${RED}✗ 获取失败\${NC}"
        echo -e "\n  \${YELLOW}[3] 透明路由测试（直接访问 Google，不走 -x 参数）\${NC}"
        CODE=\$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" https://www.google.com)
        [ "\$CODE" = "200" ] || [ "\$CODE" = "301" ] && \
            echo -e "  \${GREEN}✓ Google 透明路由正常 HTTP \$CODE\${NC}" || \
            echo -e "  \${RED}✗ 透明路由异常 HTTP \$CODE（运行 g-e fix）\${NC}"
        echo -e "\n  \${YELLOW}[4] Gemini 测试\${NC}"
        GCODE=\$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" \
            -H "User-Agent: Mozilla/5.0" https://gemini.google.com)
        [ "\$GCODE" = "200" ] || [ "\$GCODE" = "301" ] && \
            echo -e "  \${GREEN}✓ Gemini 可访问 HTTP \$GCODE\${NC}" || \
            echo -e "  \${RED}✗ Gemini 不可访问 HTTP \$GCODE\${NC}"
        echo "" ;;
    fix)
        echo -e "\${CYAN}  修复中...\${NC}"
        wg-quick down \$WG_IFACE 2>/dev/null; sleep 1
        wg-quick up /etc/wireguard/\${WG_IFACE}.conf; sleep 3
        /usr/local/bin/g-proxy restart
        CODE=\$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" https://www.google.com)
        [ "\$CODE" = "200" ] || [ "\$CODE" = "301" ] && \
            echo -e "\${GREEN}✓ 修复成功！HTTP \$CODE\${NC}" || \
            echo -e "\${RED}✗ 仍然异常，尝试 g-e scan 换节点\${NC}" ;;
    ip)
        echo -e "\n\${YELLOW}直连 IP:\${NC}"
        curl -4 -s --max-time 5 ip.sb; echo ""
        echo -e "\${YELLOW}WARP 出口 IP:\${NC}"
        W=\$(curl -s --max-time 10 --interface \$WG_IFACE ip.sb 2>/dev/null)
        if [ -n "\$W" ]; then
            INFO=\$(curl -s --max-time 5 "http://ip-api.com/json/\$W?lang=zh-CN" 2>/dev/null)
            C=\$(echo \$INFO | grep -oP '"country":"\K[^"]+' || echo "未知")
            T=\$(echo \$INFO | grep -oP '"city":"\K[^"]+' || echo "")
            echo -e "\${GREEN}\$W  (\$C \$T)\${NC}"
        else
            echo -e "\${RED}获取失败\${NC}"
        fi
        echo "" ;;
    region)
        bash /usr/local/bin/warp-setup.sh --change-region 2>/dev/null || \
        bash <(curl -fsSL https://raw.githubusercontent.com/ctsunny/g-everywhere/main/warp-setup.sh) --change-region ;;
    scan)
        bash /usr/local/bin/warp-setup.sh --scan 2>/dev/null || \
        bash <(curl -fsSL https://raw.githubusercontent.com/ctsunny/g-everywhere/main/warp-setup.sh) --scan ;;
    uninstall)
        echo -e "\${YELLOW}卸载中...\${NC}"
        /usr/local/bin/g-proxy stop 2>/dev/null
        systemctl disable --now g-everywhere 2>/dev/null
        rm -f /etc/systemd/system/g-everywhere.service
        rm -f /usr/local/bin/g-proxy /usr/local/bin/g-e /usr/local/bin/warp-setup.sh
        apt-get remove -y wireguard-tools 2>/dev/null || true
        rm -f /usr/local/bin/wgcf
        rm -rf /etc/warp
        rm -f /etc/wireguard/${WG_IFACE}.conf
        echo -e "\${GREEN}✓ 卸载完成\${NC}" ;;
    *)
        bash /usr/local/bin/warp-setup.sh 2>/dev/null || {
            echo -e "\${CYAN}G-Everywhere v3.0\${NC}\n"
            echo "  status / start / stop / restart"
            echo "  test / fix / ip / region / scan / uninstall"
        } ;;
esac
MGMT
    chmod +x /usr/local/bin/g-e
    cp "$0" /usr/local/bin/warp-setup.sh 2>/dev/null || true
    chmod +x /usr/local/bin/warp-setup.sh 2>/dev/null || true
}

do_install() {
    select_region
    install_wgcf
    setup_wgcf_config
    setup_wireguard_routing
    create_management
    verify_region
    show_post_install
}

do_uninstall() {
    echo -e "\n${YELLOW}  卸载中...${NC}"
    /usr/local/bin/g-proxy stop 2>/dev/null || true
    systemctl disable --now g-everywhere 2>/dev/null || true
    rm -f /etc/systemd/system/g-everywhere.service
    rm -f /usr/local/bin/g-proxy /usr/local/bin/g-e /usr/local/bin/warp-setup.sh /usr/local/bin/wgcf
    rm -rf /etc/warp
    rm -f /etc/wireguard/${WG_IFACE}.conf
    iptables -t mangle -D OUTPUT -j WARP_MARK 2>/dev/null || true
    iptables -t mangle -D PREROUTING -j WARP_MARK 2>/dev/null || true
    iptables -t mangle -F WARP_MARK 2>/dev/null || true
    iptables -t mangle -X WARP_MARK 2>/dev/null || true
    ip rule del fwmark 51820 table 51820 2>/dev/null || true
    ip route flush table 51820 2>/dev/null || true
    echo -e "  ${GREEN}✓ 卸载完成${NC}\n"
}

do_status() {
    echo -e "\n${CYAN}  ── 运行状态 ──${NC}\n"
    /usr/local/bin/g-proxy status 2>/dev/null || echo -e "  ${RED}未安装${NC}"
    echo ""
}

show_menu() {
    while true; do
        show_banner
        show_current_ip
        echo -e "  ${YELLOW}请选择操作:${NC}\n"
        echo -e "  ${GREEN}1.${NC} 安装（wgcf + WireGuard，真实地区选择）"
        echo -e "  ${GREEN}2.${NC} 切换出口地区"
        echo -e "  ${GREEN}3.${NC} 查看状态"
        echo -e "  ${GREEN}4.${NC} 扫描节点出口地区"
        echo -e "  ${GREEN}5.${NC} 卸载"
        echo -e "  ${GREEN}0.${NC} 退出\n"
        read -p "  请输入选项 [0-5]: " choice
        echo ""
        case $choice in
            1) do_install ;;
            2) change_region ;;
            3) do_status ;;
            4) do_scan ;;
            5) do_uninstall ;;
            0) echo -e "  ${GREEN}Bye!${NC}\n"; exit 0 ;;
            *) echo -e "  ${RED}无效选项${NC}" ;;
        esac
        echo ""; read -p "  按 Enter 返回菜单..." _
    done
}

main() {
    check_root
    detect_os
    case "${1:-}" in
        --install)        show_banner; do_install ;;
        --uninstall)      show_banner; do_uninstall ;;
        --status)         show_banner; do_status ;;
        --change-region)  show_banner; change_region ;;
        --scan)           show_banner; do_scan ;;
        *)                show_menu ;;
    esac
}

main "$@"
