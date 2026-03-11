#!/bin/bash
# G-Everywhere v3.1
# Google Unlock via wgcf + WireGuard
# https://github.com/ctsunny/g-everywhere

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'
NC='\033[0m'; BOLD='\033[1m'

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
    echo -e "  ${BLUE}github.com/ctsunny/g-everywhere${NC}  │  ${GREEN}v3.1${NC}\n"
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
    else
        echo -e "  ${RED}IP 获取失败${NC}"
    fi
    echo -e "  ${CYAN}──────────────────────────────────${NC}\n"
}

select_region() {
    echo -e "\n${CYAN}  ── 选择出口地区 ──${NC}"
    echo -e "  ${YELLOW}v3.1 使用 wgcf+WireGuard，地区选择真实有效${NC}\n"
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
        SELECTED_REGION="🌐 自动"
        echo -e "  使用自动"
    fi
}

# ============================================================
# 安装依赖
# ============================================================
install_deps() {
    echo -e "\n${CYAN}  [1/4] 安装 wgcf + WireGuard...${NC}"

    case $OS in
        ubuntu|debian)
            apt-get update -y >/dev/null 2>&1
            # openresolv 解决 resolvconf 依赖问题
            apt-get install -y wireguard wireguard-tools curl wget \
                iptables openresolv >/dev/null 2>&1
            ;;
        centos|rhel|rocky|almalinux)
            dnf install -y epel-release >/dev/null 2>&1
            dnf install -y wireguard-tools curl wget iptables >/dev/null 2>&1
            ;;
        fedora)
            dnf install -y wireguard-tools curl wget iptables >/dev/null 2>&1
            ;;
        *)
            echo -e "${RED}不支持的系统: $OS${NC}"; exit 1 ;;
    esac

    # 加载 WireGuard 内核模块
    modprobe wireguard 2>/dev/null || true

    # 安装 wgcf
    WGCF_VER=$(curl -s --max-time 10 \
        https://api.github.com/repos/ViRb3/wgcf/releases/latest \
        | grep tag_name | cut -d'"' -f4 2>/dev/null || echo "v2.2.25")
    [ -z "$WGCF_VER" ] && WGCF_VER="v2.2.25"

    echo -e "  下载 wgcf ${WGCF_VER}..."
    curl -fsSL \
        "https://github.com/ViRb3/wgcf/releases/download/${WGCF_VER}/wgcf_${WGCF_VER#v}_linux_${ARCH}" \
        -o /usr/local/bin/wgcf 2>/dev/null

    # 下载失败则用固定版本
    if [ ! -s /usr/local/bin/wgcf ]; then
        echo -e "  ${YELLOW}尝试固定版本 v2.2.25...${NC}"
        curl -fsSL \
            "https://github.com/ViRb3/wgcf/releases/download/v2.2.25/wgcf_2.2.25_linux_${ARCH}" \
            -o /usr/local/bin/wgcf
    fi

    chmod +x /usr/local/bin/wgcf
    command -v wgcf &>/dev/null || { echo -e "${RED}wgcf 安装失败，请检查网络${NC}"; exit 1; }
    echo -e "  ${GREEN}✓ wgcf 安装成功${NC}"
    echo -e "  ${GREEN}✓ WireGuard 已就绪${NC}"
}

# ============================================================
# 生成 wgcf 配置
# ============================================================
setup_wgcf_config() {
    echo -e "\n${CYAN}  [2/4] 生成 WARP WireGuard 配置...${NC}"

    mkdir -p /etc/warp
    cd /etc/warp

    # 注册账号
    if [ ! -f /etc/warp/wgcf-account.toml ]; then
        echo -e "  注册 WARP 设备..."
        wgcf register --accept-tos 2>/dev/null
        [ -f wgcf-account.toml ] || { echo -e "${RED}注册失败${NC}"; exit 1; }
    else
        echo -e "  ${GREEN}已有账号，跳过注册${NC}"
        cp /etc/warp/wgcf-account.toml . 2>/dev/null || true
    fi

    # 生成 WireGuard 配置
    wgcf generate 2>/dev/null
    [ -f wgcf-profile.conf ] || { echo -e "${RED}配置生成失败${NC}"; exit 1; }
    cp wgcf-profile.conf /etc/warp/wgcf-profile.conf

    # ★ 修复1：删除 DNS 行，避免 resolvconf 依赖 ★
    sed -i '/^DNS/d' /etc/warp/wgcf-profile.conf

    # ★ 修复2：删除 Table = off（之后手动管理路由）★
    sed -i '/^Table/d' /etc/warp/wgcf-profile.conf

    # 设置 Endpoint
    ENDPOINT="${REGION_ENDPOINTS[$SELECTED_REGION]}"
    echo -e "  设置 Endpoint: ${YELLOW}$ENDPOINT${NC} ($SELECTED_REGION)"
    sed -i "s/Endpoint = .*/Endpoint = $ENDPOINT/" /etc/warp/wgcf-profile.conf

    # 替换 AllowedIPs：只路由 Google IP，不全局路由
    sed -i '/^AllowedIPs/d' /etc/warp/wgcf-profile.conf

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

    # 复制到 WireGuard 目录
    mkdir -p /etc/wireguard
    cp /etc/warp/wgcf-profile.conf /etc/wireguard/${WG_IFACE}.conf

    echo -e "  ${GREEN}✓ 配置生成完成${NC}"
    echo -e "\n  ${CYAN}配置预览:${NC}"
    grep -E "^(Endpoint|Address|PublicKey)" /etc/wireguard/${WG_IFACE}.conf | sed 's/^/  /'
    echo -e "  AllowedIPs = Google IP 段 (21条)"
}

# ============================================================
# 启动 WireGuard
# ============================================================
start_wireguard() {
    # 停止旧接口
    ip link del ${WG_IFACE} 2>/dev/null || true
    sleep 1

    # 尝试启动
    wg-quick up /etc/wireguard/${WG_IFACE}.conf 2>&1
    sleep 3

    if ip link show ${WG_IFACE} &>/dev/null; then
        WG_IP=$(ip addr show ${WG_IFACE} | grep -oP '(?<=inet )\d+\.\d+\.\d+\.\d+')
        echo -e "  ${GREEN}✓ WireGuard 接口 ${WG_IFACE} 已启动 (IP: $WG_IP)${NC}"
        return 0
    else
        return 1
    fi
}

# ============================================================
# 配置 iptables 策略路由
# ============================================================
setup_routing() {
    cat > /usr/local/bin/g-proxy << SCRIPT
#!/bin/bash
WG_IFACE="${WG_IFACE}"
GOOGLE_IPS="
8.8.4.0/24 8.8.8.0/24 34.0.0.0/9 35.184.0.0/13 35.192.0.0/12
35.224.0.0/12 35.240.0.0/13 64.233.160.0/19 66.102.0.0/20 66.249.64.0/19
72.14.192.0/18 74.125.0.0/16 104.132.0.0/14 108.177.0.0/17 142.250.0.0/15
172.217.0.0/16 172.253.0.0/16 173.194.0.0/16 209.85.128.0/17 216.58.192.0/19
216.239.32.0/19
"

start() {
    # 确保 WireGuard 运行
    ip link show \$WG_IFACE &>/dev/null || wg-quick up /etc/wireguard/\${WG_IFACE}.conf
    sleep 2

    # 清理旧规则
    ip rule del fwmark 51820 table 51820 2>/dev/null || true
    ip route flush table 51820 2>/dev/null || true
    iptables -t mangle -D OUTPUT -j WARP_MARK 2>/dev/null || true
    iptables -t mangle -D PREROUTING -j WARP_MARK 2>/dev/null || true
    iptables -t mangle -F WARP_MARK 2>/dev/null || true
    iptables -t mangle -X WARP_MARK 2>/dev/null || true

    # 策略路由：mark 51820 的包走 table 51820（通过 WireGuard）
    ip rule add fwmark 51820 table 51820
    ip route add default dev \$WG_IFACE table 51820

    # iptables mangle：对 Google IP 打 mark 51820
    iptables -t mangle -N WARP_MARK

    # 排除规则（先处理，避免影响本机管理流量）
    iptables -t mangle -A WARP_MARK -d 127.0.0.0/8 -j RETURN
    iptables -t mangle -A WARP_MARK -d 10.0.0.0/8 -j RETURN
    iptables -t mangle -A WARP_MARK -d 172.16.0.0/12 -j RETURN
    iptables -t mangle -A WARP_MARK -d 192.168.0.0/16 -j RETURN
    # 排除 WireGuard Endpoint IP（防止隧道流量被重定向导致断线）
    iptables -t mangle -A WARP_MARK -d 162.159.192.0/22 -j RETURN
    iptables -t mangle -A WARP_MARK -d 162.159.193.0/24 -j RETURN

    # Google IP 打 mark
    for ip in \$GOOGLE_IPS; do
        iptables -t mangle -A WARP_MARK -d \$ip -j MARK --set-mark 51820
    done

    # 应用到 OUTPUT（本机发出的流量）和 PREROUTING（转发流量，覆盖 xray/3x-ui）
    iptables -t mangle -C OUTPUT -j WARP_MARK 2>/dev/null || \
        iptables -t mangle -A OUTPUT -j WARP_MARK
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
    if ip link show \$WG_IFACE &>/dev/null; then
        echo "\$WG_IFACE 运行中"
        wg show \$WG_IFACE 2>/dev/null | grep -E "endpoint|transfer"
    else
        echo "未运行"
    fi
    echo ""
    echo "── 策略路由 ──"
    ip rule show | grep 51820 || echo "无规则"
    echo ""
    echo "── iptables mark 规则 ──"
    COUNT=\$(iptables -t mangle -L WARP_MARK -n 2>/dev/null | grep -c MARK 2>/dev/null || echo 0)
    echo "Google 路由规则: \$COUNT 条"
    echo ""
    echo "── 当前 Endpoint ──"
    grep "Endpoint" /etc/wireguard/\${WG_IFACE}.conf 2>/dev/null || echo "未知"
    echo ""
    echo "── 实际出口 IP ──"
    WARP_IP=\$(curl -s --max-time 8 --interface \$WG_IFACE ip.sb 2>/dev/null)
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
}

setup_wireguard_routing() {
    echo -e "\n${CYAN}  [3/4] 启动 WireGuard + 配置路由...${NC}"

    if start_wireguard; then
        setup_routing
        /usr/local/bin/g-proxy start

        # systemd 开机自启
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
        echo -e "  ${GREEN}✓ WireGuard + 路由规则配置完成${NC}"
    else
        echo -e "  ${RED}WireGuard 启动失败，检查原因...${NC}"
        # 检查内核模块
        if ! modprobe wireguard 2>/dev/null; then
            echo -e "  ${RED}内核不支持 WireGuard！${NC}"
            echo -e "  ${YELLOW}解决方案:"
            echo -e "    1. 升级内核: apt-get install -y linux-image-generic && reboot"
            echo -e "    2. 或换一台支持 WireGuard 的 VPS${NC}"
        else
            echo -e "  ${YELLOW}内核模块已加载，重试启动...${NC}"
            if start_wireguard; then
                setup_routing
                /usr/local/bin/g-proxy start
                echo -e "  ${GREEN}✓ 重试成功${NC}"
            else
                echo -e "  ${RED}仍然失败，请运行: journalctl -u wg-quick@warp0 查看详情${NC}"
                exit 1
            fi
        fi
    fi
}

# ============================================================
# 验证出口地区
# ============================================================
verify_region() {
    echo -e "\n${CYAN}  [4/4] 验证出口地区...${NC}"
    sleep 2

    WARP_IP=$(curl -s --max-time 10 --interface ${WG_IFACE} ip.sb 2>/dev/null)
    if [ -n "$WARP_IP" ]; then
        INFO=$(curl -s --max-time 5 "http://ip-api.com/json/$WARP_IP?lang=zh-CN" 2>/dev/null)
        W_COUNTRY=$(echo $INFO | grep -oP '"country":"\K[^"]+' || echo "未知")
        W_CITY=$(echo $INFO | grep -oP '"city":"\K[^"]+' || echo "")
        W_ISP=$(echo $INFO | grep -oP '"isp":"\K[^"]+' || echo "")
        echo -e "  出口 IP   : ${GREEN}$WARP_IP${NC}"
        echo -e "  出口地区  : ${GREEN}$W_COUNTRY $W_CITY${NC}"
        echo -e "  ISP       : ${GREEN}$W_ISP${NC}"
        echo $W_ISP | grep -qi "cloudflare" && \
            echo -e "  ${GREEN}✓ 确认走 Cloudflare WARP${NC}" || true
    else
        echo -e "  ${RED}无法获取出口 IP，请运行 g-e fix${NC}"
    fi
}

# ============================================================
# 切换地区
# ============================================================
change_region() {
    echo -e "\n${CYAN}  ── 切换出口地区 ──${NC}"

    if [ ! -f /etc/wireguard/${WG_IFACE}.conf ]; then
        echo -e "  ${RED}WireGuard 未安装，请先安装（选项1）${NC}"
        return 1
    fi

    echo -e "\n  当前配置:"
    grep "Endpoint" /etc/wireguard/${WG_IFACE}.conf | sed 's/^/  /'

    echo -e "\n  当前出口 IP:"
    CUR=$(curl -s --max-time 8 --interface ${WG_IFACE} ip.sb 2>/dev/null || echo "未连接")
    echo -e "  ${GREEN}$CUR${NC}"

    select_region
    ENDPOINT="${REGION_ENDPOINTS[$SELECTED_REGION]}"

    # 更新配置
    sed -i "s/Endpoint = .*/Endpoint = $ENDPOINT/" /etc/wireguard/${WG_IFACE}.conf
    sed -i "s/Endpoint = .*/Endpoint = $ENDPOINT/" /etc/warp/wgcf-profile.conf 2>/dev/null || true

    echo -e "  ${GREEN}✓ Endpoint 已更新: $ENDPOINT${NC}"
    echo -e "  重启 WireGuard..."

    wg-quick down ${WG_IFACE} 2>/dev/null || true
    sleep 1
    wg-quick up /etc/wireguard/${WG_IFACE}.conf
    sleep 3

    # 重建路由规则
    /usr/local/bin/g-proxy restart

    # 显示新出口
    NEW_IP=$(curl -s --max-time 10 --interface ${WG_IFACE} ip.sb 2>/dev/null)
    if [ -n "$NEW_IP" ]; then
        INFO=$(curl -s --max-time 5 "http://ip-api.com/json/$NEW_IP?lang=zh-CN" 2>/dev/null)
        C=$(echo $INFO | grep -oP '"country":"\K[^"]+' || echo "未知")
        T=$(echo $INFO | grep -oP '"city":"\K[^"]+' || echo "")
        echo -e "\n  ${GREEN}✓ 切换成功！${NC}"
        echo -e "  新出口 IP : ${GREEN}$NEW_IP${NC}"
        echo -e "  新出口地区: ${GREEN}$C $T${NC}"
    else
        echo -e "  ${RED}切换后无法获取出口 IP，运行 g-e fix${NC}"
    fi
}

# ============================================================
# 扫描所有节点
# ============================================================
do_scan() {
    echo -e "\n${CYAN}  ── 扫描所有节点 ──${NC}\n"

    if [ ! -f /etc/wireguard/${WG_IFACE}.conf ]; then
        echo -e "  ${RED}请先安装${NC}"; return 1
    fi

    echo -e "  ${YELLOW}逐个切换 Endpoint，测试真实出口...${NC}\n"
    printf "  %-8s %-22s %-18s %-18s %s\n" "节点" "Endpoint" "出口IP" "地区" "Gemini"
    echo -e "  ${CYAN}────────────────────────────────────────────────────────────────${NC}"

    BEST_EP=""
    for i in $(seq 1 12); do
        EP="162.159.193.$i:2408"
        sed -i "s/Endpoint = .*/Endpoint = $EP/" /etc/wireguard/${WG_IFACE}.conf
        wg-quick down ${WG_IFACE} 2>/dev/null; sleep 1
        wg-quick up /etc/wireguard/${WG_IFACE}.conf 2>/dev/null; sleep 3

        OUT=$(curl -s --max-time 8 --interface ${WG_IFACE} ip.sb 2>/dev/null)
        if [ -z "$OUT" ]; then
            printf "  %-8s %-22s ${RED}连接失败${NC}\n" "#$i" "$EP"
            continue
        fi

        INFO=$(curl -s --max-time 4 "http://ip-api.com/json/$OUT?lang=zh-CN" 2>/dev/null)
        C=$(echo $INFO | grep -oP '"country":"\K[^"]+' || echo "?")
        T=$(echo $INFO | grep -oP '"city":"\K[^"]+' || echo "")

        GC=$(curl -s --max-time 8 --interface ${WG_IFACE} \
            -o /dev/null -w "%{http_code}" \
            -H "User-Agent: Mozilla/5.0" \
            https://gemini.google.com 2>/dev/null)

        if [ "$GC" = "200" ] || [ "$GC" = "301" ] || [ "$GC" = "302" ]; then
            printf "  %-8s %-22s ${GREEN}%-18s %-18s ✅ %s${NC}\n" "#$i" "$EP" "$OUT" "$C $T" "$GC"
            [ -z "$BEST_EP" ] && BEST_EP="$EP"
        else
            printf "  %-8s %-22s ${YELLOW}%-18s %-18s ✗ %s${NC}\n" "#$i" "$EP" "$OUT" "$C $T" "$GC"
        fi
    done

    echo ""
    if [ -n "$BEST_EP" ]; then
        echo -e "  ${GREEN}✅ 最佳节点: $BEST_EP${NC}"
        read -p "  是否应用此节点？[Y/n]: " yn
        yn=${yn:-Y}
        if [[ "$yn" =~ ^[Yy] ]]; then
            sed -i "s/Endpoint = .*/Endpoint = $BEST_EP/" /etc/wireguard/${WG_IFACE}.conf
            wg-quick down ${WG_IFACE} 2>/dev/null; sleep 1
            wg-quick up /etc/wireguard/${WG_IFACE}.conf; sleep 3
            /usr/local/bin/g-proxy restart
            echo -e "  ${GREEN}✓ 最佳节点已应用${NC}"
        fi
    else
        echo -e "  ${RED}所有节点 Gemini 均不可用${NC}"
        read -p "  手动输入要应用的节点编号 [1-12]: " n
        if [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le 12 ]; then
            EP="162.159.193.$n:2408"
            sed -i "s/Endpoint = .*/Endpoint = $EP/" /etc/wireguard/${WG_IFACE}.conf
            wg-quick down ${WG_IFACE} 2>/dev/null; sleep 1
            wg-quick up /etc/wireguard/${WG_IFACE}.conf; sleep 3
            /usr/local/bin/g-proxy restart
            echo -e "  ${GREEN}✓ 已应用节点 $EP${NC}"
        fi
    fi
}

show_post_install() {
    WARP_IP=$(curl -s --max-time 10 --interface ${WG_IFACE} ip.sb 2>/dev/null)
    WARP_COUNTRY="获取中"; WARP_CITY=""
    if [ -n "$WARP_IP" ]; then
        INFO=$(curl -s --max-time 5 "http://ip-api.com/json/$WARP_IP?lang=zh-CN" 2>/dev/null)
        WARP_COUNTRY=$(echo $INFO | grep -oP '"country":"\K[^"]+' || echo "未知")
        WARP_CITY=$(echo $INFO | grep -oP '"city":"\K[^"]+' || echo "")
    fi
    echo -e "\n${BOLD}${GREEN}"
    echo "  ┌──────────────────────────────────────────┐"
    echo "  │     ✅  安装成功！Google 路由已建立        │"
    echo "  └──────────────────────────────────────────┘"
    echo -e "${NC}"
    echo -e "  ${YELLOW}选择地区 :${NC} ${GREEN}$SELECTED_REGION${NC}"
    echo -e "  ${YELLOW}出口 IP  :${NC} ${GREEN}${WARP_IP:-获取失败}${NC}"
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

# ============================================================
# 管理命令 g-e
# ============================================================
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
        ip link show \$WG_IFACE &>/dev/null && \
            echo -e "  \${GREEN}✓ \$WG_IFACE 运行中\${NC}" || \
            echo -e "  \${RED}✗ \$WG_IFACE 未运行（运行 g-e fix）\${NC}"

        echo -e "\n  \${YELLOW}[2] WireGuard 出口 IP\${NC}"
        OUT=\$(curl -s --max-time 8 --interface \$WG_IFACE ip.sb 2>/dev/null)
        if [ -n "\$OUT" ]; then
            INFO=\$(curl -s --max-time 5 "http://ip-api.com/json/\$OUT?lang=zh-CN" 2>/dev/null)
            C=\$(echo \$INFO | grep -oP '"country":"\K[^"]+' || echo "未知")
            T=\$(echo \$INFO | grep -oP '"city":"\K[^"]+' || echo "")
            echo -e "  \${GREEN}✓ \$OUT  (\$C \$T)\${NC}"
        else
            echo -e "  \${RED}✗ 获取失败\${NC}"
        fi

        echo -e "\n  \${YELLOW}[3] iptables 路由规则\${NC}"
        COUNT=\$(iptables -t mangle -L WARP_MARK -n 2>/dev/null | grep -c MARK || echo 0)
        [ "\$COUNT" -gt 0 ] && \
            echo -e "  \${GREEN}✓ 已加载 \$COUNT 条 Google 路由规则\${NC}" || \
            echo -e "  \${RED}✗ 无路由规则（运行 g-e fix）\${NC}"

        echo -e "\n  \${YELLOW}[4] 透明路由测试（直接访问，不走 -x 参数）\${NC}"
        CODE=\$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" https://www.google.com)
        [ "\$CODE" = "200" ] || [ "\$CODE" = "301" ] && \
            echo -e "  \${GREEN}✓ Google 透明路由正常 HTTP \$CODE\${NC}" || \
            echo -e "  \${RED}✗ 透明路由异常 HTTP \$CODE（运行 g-e fix）\${NC}"

        echo -e "\n  \${YELLOW}[5] Gemini 测试\${NC}"
        GC=\$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" \
            -H "User-Agent: Mozilla/5.0" https://gemini.google.com)
        [ "\$GC" = "200" ] || [ "\$GC" = "301" ] && \
            echo -e "  \${GREEN}✓ Gemini 可访问 HTTP \$GC\${NC}" || \
            echo -e "  \${RED}✗ Gemini 不可访问 HTTP \$GC（运行 g-e scan 换节点）\${NC}"
        echo "" ;;

    fix)
        echo -e "\n\${CYAN}  修复中...\${NC}"
        wg-quick down \$WG_IFACE 2>/dev/null; sleep 1
        wg-quick up /etc/wireguard/\${WG_IFACE}.conf; sleep 3
        /usr/local/bin/g-proxy restart
        sleep 2
        CODE=\$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" https://www.google.com)
        [ "\$CODE" = "200" ] || [ "\$CODE" = "301" ] && \
            echo -e "\${GREEN}✓ 修复成功！HTTP \$CODE\${NC}" || \
            echo -e "\${RED}✗ 仍异常，尝试: g-e scan\${NC}" ;;

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
            echo -e "\${RED}获取失败（运行 g-e fix）\${NC}"
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
        rm -f /usr/local/bin/wgcf
        rm -rf /etc/warp
        rm -f /etc/wireguard/${WG_IFACE}.conf
        echo -e "\${GREEN}✓ 卸载完成\${NC}" ;;

    *)
        bash /usr/local/bin/warp-setup.sh 2>/dev/null || {
            echo -e "\${CYAN}G-Everywhere v3.1 管理工具\${NC}\n"
            echo "  status   查看状态"
            echo "  start    启动"
            echo "  stop     停止"
            echo "  restart  重启"
            echo "  test     全面诊断"
            echo "  fix      一键修复"
            echo "  ip       查看 IP"
            echo "  region   切换地区"
            echo "  scan     扫描节点"
            echo "  uninstall 卸载"
        } ;;
esac
MGMT
    chmod +x /usr/local/bin/g-e
    cp "$0" /usr/local/bin/warp-setup.sh 2>/dev/null || true
    chmod +x /usr/local/bin/warp-setup.sh 2>/dev/null || true
}

# ============================================================
# 主流程
# ============================================================
do_install() {
    select_region
    install_deps
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
    /usr/local/bin/g-proxy status 2>/dev/null || \
        echo -e "  ${RED}未安装，请选择选项 1 安装${NC}"
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
        echo -e "  ${GREEN}4.${NC} 扫描节点"
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
