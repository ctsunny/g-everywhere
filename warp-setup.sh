#!/bin/bash
# G-Everywhere v2.1
# Google Unlock via Cloudflare WARP
# https://github.com/ctsunny/g-everywhere

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

# ============================================================
# 正确的 WARP Endpoint IP 范围: 162.159.193.x:2408
# ============================================================
declare -A REGION_ENDPOINTS=(
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

REGION_KEYS=(
    "🌐 自动"
    "🇺🇸 美国"
    "🇯🇵 日本"
    "🇸🇬 新加坡"
    "🇩🇪 德国"
    "🇬🇧 英国"
    "🇳🇱 荷兰"
    "🇦🇺 澳大利亚"
    "🇰🇷 韩国"
    "🇭🇰 香港"
    "🇨🇦 加拿大"
    "🇮🇳 印度"
    "🇧🇷 巴西"
)

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
    echo -e "  ${GREEN}  Google Unlock  ${NC}│${YELLOW}  Cloudflare WARP  ${NC}│${MAGENTA}  Auto Routing  ${NC}"
    echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${BLUE}github.com/ctsunny/g-everywhere${NC}  │  ${GREEN}v2.1${NC}\n"
}

check_root() {
    [[ $EUID -ne 0 ]] && { echo -e "${RED}请使用 root 运行！${NC}"; exit 1; }
}

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
        CODENAME=${VERSION_CODENAME:-$(echo $VERSION_ID | tr '.' '_')}
    else
        echo -e "${RED}无法检测系统${NC}"; exit 1
    fi
    ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
}

show_current_ip() {
    echo -e "  ${YELLOW}当前节点信息${NC}"
    echo -e "  ${CYAN}──────────────────────────────────${NC}"
    CURRENT_IP=$(curl -4 -s --max-time 5 ip.sb 2>/dev/null || echo "获取失败")
    if [ "$CURRENT_IP" != "获取失败" ]; then
        IP_INFO=$(curl -s --max-time 5 "http://ip-api.com/json/$CURRENT_IP?lang=zh-CN" 2>/dev/null)
        COUNTRY=$(echo $IP_INFO | grep -oP '"country":"\K[^"]+' 2>/dev/null || echo "未知")
        CITY=$(echo $IP_INFO | grep -oP '"city":"\K[^"]+' 2>/dev/null || echo "未知")
        ISP=$(echo $IP_INFO | grep -oP '"isp":"\K[^"]+' 2>/dev/null || echo "未知")
        echo -e "  IP  : ${GREEN}$CURRENT_IP${NC}"
        echo -e "  位置: ${GREEN}$COUNTRY $CITY${NC}"
        echo -e "  ISP : ${GREEN}$ISP${NC}"
    else
        echo -e "  ${RED}IP 获取失败${NC}"
    fi
    echo -e "  ${CYAN}──────────────────────────────────${NC}\n"
}

# ============================================================
# 地区选择
# ============================================================
select_region() {
    echo -e "\n${CYAN}  ── 选择 WARP 出口地区 ──${NC}\n"
    for i in "${!REGION_KEYS[@]}"; do
        printf "  ${GREEN}%2d.${NC} %s\n" "$((i+1))" "${REGION_KEYS[$i]}"
    done
    echo ""
    read -p "  请选择 [1-${#REGION_KEYS[@]}] (默认1-自动): " region_choice
    region_choice=${region_choice:-1}
    if [[ "$region_choice" =~ ^[0-9]+$ ]] && \
       [ "$region_choice" -ge 1 ] && \
       [ "$region_choice" -le "${#REGION_KEYS[@]}" ]; then
        SELECTED_REGION="${REGION_KEYS[$((region_choice-1))]}"
        echo -e "  ${GREEN}✓ 已选择: $SELECTED_REGION${NC}"
    else
        echo -e "  ${YELLOW}无效，使用自动${NC}"
        SELECTED_REGION="🌐 自动"
    fi
}

# ============================================================
# 测试 Endpoint 连通性 (UDP)
# ============================================================
test_endpoint() {
    local EP_IP=$(echo $1 | cut -d: -f1)
    local EP_PORT=$(echo $1 | cut -d: -f2)
    # 跳过域名类型的 endpoint 检测
    if [[ "$EP_IP" =~ ^[a-zA-Z] ]]; then
        return 0
    fi
    if command -v nc &>/dev/null; then
        nc -zu -w 3 "$EP_IP" "$EP_PORT" 2>/dev/null
        return $?
    fi
    # 备用：用 timeout + bash /dev/udp
    timeout 3 bash -c "echo > /dev/udp/$EP_IP/$EP_PORT" 2>/dev/null
    return $?
}

# ============================================================
# 应用 Endpoint 并验证实际出口
# ============================================================
apply_endpoint() {
    local ENDPOINT="${REGION_ENDPOINTS[$SELECTED_REGION]}"

    if [ "$SELECTED_REGION" = "🌐 自动" ]; then
        echo -e "  节点: 自动分配"
        warp-cli --accept-tos clear-custom-endpoint 2>/dev/null || true
    else
        echo -e "  测试节点连通性: ${YELLOW}$ENDPOINT${NC} ..."
        if test_endpoint "$ENDPOINT"; then
            echo -e "  ${GREEN}✓ 节点可达${NC}"
            warp-cli --accept-tos set-custom-endpoint "$ENDPOINT" 2>/dev/null || \
            warp-cli set-custom-endpoint "$ENDPOINT" 2>/dev/null || true
        else
            echo -e "  ${YELLOW}⚠ 节点不可达，回退到自动分配${NC}"
            warp-cli --accept-tos clear-custom-endpoint 2>/dev/null || true
            SELECTED_REGION="🌐 自动"
        fi
    fi

    # 重连
    warp-cli --accept-tos disconnect 2>/dev/null; sleep 1
    warp-cli --accept-tos connect 2>/dev/null
    echo -e "  连接中，等待 5 秒..."
    sleep 5

    # 验证实际出口 IP
    echo -e "  验证实际出口..."
    ACTUAL_IP=$(curl -x socks5://127.0.0.1:40000 -s --max-time 10 ip.sb 2>/dev/null)
    if [ -n "$ACTUAL_IP" ]; then
        ACTUAL_INFO=$(curl -s --max-time 5 "http://ip-api.com/json/$ACTUAL_IP?lang=zh-CN" 2>/dev/null)
        ACTUAL_COUNTRY=$(echo $ACTUAL_INFO | grep -oP '"country":"\K[^"]+' || echo "未知")
        ACTUAL_CITY=$(echo $ACTUAL_INFO | grep -oP '"city":"\K[^"]+' || echo "未知")
        echo -e "  ${GREEN}✓ 实际出口: $ACTUAL_COUNTRY $ACTUAL_CITY (${ACTUAL_IP})${NC}"
    else
        echo -e "  ${RED}✗ WARP 连接失败，请尝试其他地区或使用自动${NC}"
    fi
}

# ============================================================
# 安装 WARP
# ============================================================
install_warp() {
    echo -e "\n${CYAN}  [1/4] 安装 Cloudflare WARP...${NC}"
    case $OS in
        ubuntu|debian)
            apt-get update -y >/dev/null 2>&1
            apt-get install -y gnupg curl wget netcat-openbsd >/dev/null 2>&1
            curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | \
                gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
            echo "deb [arch=$ARCH signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] \
https://pkg.cloudflareclient.com/ $CODENAME main" \
                > /etc/apt/sources.list.d/cloudflare-client.list
            apt-get update -y >/dev/null 2>&1
            apt-get install -y cloudflare-warp
            ;;
        centos|rhel|rocky|almalinux|fedora)
            cat > /etc/yum.repos.d/cloudflare-warp.repo << 'EOF'
[cloudflare-warp]
name=Cloudflare WARP
baseurl=https://pkg.cloudflareclient.com/rpm
enabled=1
gpgcheck=1
gpgkey=https://pkg.cloudflareclient.com/pubkey.gpg
EOF
            command -v dnf &>/dev/null && \
                dnf install -y cloudflare-warp nmap-ncat || \
                yum install -y cloudflare-warp nmap-ncat
            ;;
        *)
            echo -e "${RED}不支持的系统: $OS${NC}"; exit 1 ;;
    esac
    command -v warp-cli &>/dev/null || { echo -e "${RED}WARP 安装失败${NC}"; exit 1; }
    echo -e "  ${GREEN}✓ 安装完成: $(warp-cli --version 2>/dev/null)${NC}"
}

# ============================================================
# 配置 WARP
# ============================================================
configure_warp() {
    echo -e "\n${CYAN}  [2/4] 配置 WARP...${NC}"
    systemctl start warp-svc 2>/dev/null || true
    sleep 2

    # 注册（兼容新旧版本）
    warp-cli --accept-tos registration new 2>/dev/null || \
    warp-cli --accept-tos register 2>/dev/null || true
    sleep 1

    # 代理模式
    warp-cli --accept-tos mode proxy 2>/dev/null || \
    warp-cli --accept-tos set-mode proxy 2>/dev/null || true

    # 代理端口
    warp-cli --accept-tos proxy port 40000 2>/dev/null || \
    warp-cli --accept-tos set-proxy-port 40000 2>/dev/null || true

    # 应用地区 endpoint + 验证
    apply_endpoint

    STATUS=$(warp-cli --accept-tos status 2>/dev/null || warp-cli status 2>/dev/null)
    echo -e "  WARP 状态: ${GREEN}$STATUS${NC}"
    echo -e "  ${GREEN}✓ WARP 配置完成${NC}"
}

# ============================================================
# 透明代理
# ============================================================
setup_transparent_proxy() {
    echo -e "\n${CYAN}  [3/4] 配置透明代理...${NC}"

    grep -q "precedence ::ffff:0:0/96  100" /etc/gai.conf 2>/dev/null || \
        echo "precedence ::ffff:0:0/96  100" >> /etc/gai.conf

    case $OS in
        ubuntu|debian)
            apt-get install -y redsocks iptables >/dev/null 2>&1 ;;
        *)
            command -v dnf &>/dev/null && \
                dnf install -y redsocks iptables >/dev/null 2>&1 || \
                yum install -y redsocks iptables >/dev/null 2>&1 ;;
    esac

    cat > /etc/redsocks.conf << 'EOF'
base {
    log_debug = off;
    log_info = on;
    log = "syslog:daemon";
    daemon = on;
    redirector = iptables;
}
redsocks {
    local_ip = 127.0.0.1;
    local_port = 12345;
    ip = 127.0.0.1;
    port = 40000;
    type = socks5;
}
EOF

    cat > /usr/local/bin/g-proxy << 'SCRIPT'
#!/bin/bash
GOOGLE_IPS="
8.8.4.0/24
8.8.8.0/24
34.0.0.0/9
35.184.0.0/13
35.192.0.0/12
35.224.0.0/12
35.240.0.0/13
64.233.160.0/19
66.102.0.0/20
66.249.64.0/19
72.14.192.0/18
74.125.0.0/16
104.132.0.0/14
108.177.0.0/17
142.250.0.0/15
172.217.0.0/16
172.253.0.0/16
173.194.0.0/16
209.85.128.0/17
216.58.192.0/19
216.239.32.0/19
"

start() {
    pkill redsocks 2>/dev/null; sleep 1
    redsocks -c /etc/redsocks.conf; sleep 1
    iptables -t nat -N WARP_GOOGLE 2>/dev/null || iptables -t nat -F WARP_GOOGLE
    for ip in $GOOGLE_IPS; do
        iptables -t nat -A WARP_GOOGLE -d $ip -p tcp -j REDIRECT --to-ports 12345
    done
    ip -6 route add blackhole 2607:f8b0::/32 2>/dev/null || true
    ip6tables -t nat -N WARP_GOOGLE6 2>/dev/null || ip6tables -t nat -F WARP_GOOGLE6
    ip6tables -t nat -A WARP_GOOGLE6 -d 2607:f8b0::/32 -p tcp -j RETURN
    ip6tables -t nat -C OUTPUT -j WARP_GOOGLE6 2>/dev/null || ip6tables -t nat -A OUTPUT -j WARP_GOOGLE6
    iptables -t nat -C OUTPUT -j WARP_GOOGLE 2>/dev/null || iptables -t nat -A OUTPUT -j WARP_GOOGLE
    echo "透明代理已启动"
}

stop() {
    pkill redsocks 2>/dev/null
    iptables -t nat -D OUTPUT -j WARP_GOOGLE 2>/dev/null
    iptables -t nat -F WARP_GOOGLE 2>/dev/null
    iptables -t nat -X WARP_GOOGLE 2>/dev/null
    ip6tables -t nat -D OUTPUT -j WARP_GOOGLE6 2>/dev/null
    ip6tables -t nat -F WARP_GOOGLE6 2>/dev/null
    ip6tables -t nat -X WARP_GOOGLE6 2>/dev/null
    ip -6 route del blackhole 2607:f8b0::/32 2>/dev/null || true
    echo "透明代理已停止"
}

status() {
    echo "── WARP 客户端 ──"
    warp-cli status 2>/dev/null || echo "未运行"
    echo ""
    echo "── 代理进程 ──"
    pgrep -x redsocks >/dev/null && \
        echo "redsocks 运行中 (PID: $(pgrep -x redsocks))" || \
        echo "redsocks 未运行"
    echo ""
    echo "── iptables 规则 ──"
    COUNT=$(iptables -t nat -L WARP_GOOGLE -n 2>/dev/null | grep -c REDIRECT 2>/dev/null || echo 0)
    echo "Google 路由规则: $COUNT 条"
    echo ""
    echo "── 当前 Endpoint ──"
    warp-cli settings 2>/dev/null | grep -i endpoint || echo "默认（自动）"
    echo ""
    echo "── 实际出口 IP ──"
    WARP_IP=$(curl -x socks5://127.0.0.1:40000 -s --max-time 8 ip.sb 2>/dev/null)
    if [ -n "$WARP_IP" ]; then
        WARP_INFO=$(curl -s --max-time 5 "http://ip-api.com/json/$WARP_IP?lang=zh-CN" 2>/dev/null)
        C=$(echo $WARP_INFO | grep -oP '"country":"\K[^"]+' || echo "未知")
        T=$(echo $WARP_INFO | grep -oP '"city":"\K[^"]+' || echo "未知")
        echo "$WARP_IP  ($C $T)"
    else
        echo "获取失败（WARP 未连接）"
    fi
}

case "$1" in
    start)   start ;;
    stop)    stop ;;
    restart) stop; sleep 1; start ;;
    status)  status ;;
    *)       echo "用法: $0 {start|stop|restart|status}" ;;
esac
SCRIPT
    chmod +x /usr/local/bin/g-proxy
    /usr/local/bin/g-proxy start

    cat > /etc/systemd/system/g-everywhere.service << 'EOF'
[Unit]
Description=G-Everywhere Google Transparent Proxy
After=network.target warp-svc.service

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
    echo -e "  ${GREEN}✓ 透明代理配置完成${NC}"
}

# ============================================================
# 安装后提示（命令改为 g-e）
# ============================================================
show_post_install() {
    WARP_IP=$(curl -x socks5://127.0.0.1:40000 -s --max-time 10 ip.sb 2>/dev/null)
    WARP_COUNTRY="未知"; WARP_CITY="未知"
    if [ -n "$WARP_IP" ]; then
        WARP_INFO=$(curl -s --max-time 5 "http://ip-api.com/json/$WARP_IP?lang=zh-CN" 2>/dev/null)
        WARP_COUNTRY=$(echo $WARP_INFO | grep -oP '"country":"\K[^"]+' || echo "未知")
        WARP_CITY=$(echo $WARP_INFO | grep -oP '"city":"\K[^"]+' || echo "未知")
    fi

    echo -e "\n${BOLD}${GREEN}"
    echo "  ┌──────────────────────────────────────────┐"
    echo "  │       ✅  安装成功！Google 已解锁          │"
    echo "  └──────────────────────────────────────────┘"
    echo -e "${NC}"
    echo -e "  ${YELLOW}出口地区 :${NC} ${GREEN}$SELECTED_REGION${NC}"
    echo -e "  ${YELLOW}WARP IP  :${NC} ${GREEN}${WARP_IP:-获取失败}${NC}"
    echo -e "  ${YELLOW}WARP 位置:${NC} ${GREEN}$WARP_COUNTRY $WARP_CITY${NC}"
    echo ""
    echo -e "  ${CYAN}━━━━━━━━━ 管理命令 ━━━━━━━━━${NC}"
    echo -e "  ${GREEN}g-e${NC}              打开管理菜单"
    echo -e "  ${GREEN}g-e status${NC}       查看运行状态"
    echo -e "  ${GREEN}g-e start${NC}        启动"
    echo -e "  ${GREEN}g-e stop${NC}         停止"
    echo -e "  ${GREEN}g-e restart${NC}      重启"
    echo -e "  ${GREEN}g-e ip${NC}           查看 IP"
    echo -e "  ${GREEN}g-e test${NC}         测试 Google"
    echo -e "  ${GREEN}g-e region${NC}       切换出口地区"
    echo -e "  ${GREEN}g-e uninstall${NC}    卸载"
    echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# ============================================================
# 管理命令 /usr/local/bin/g-e（避免与系统命令冲突）
# ============================================================
create_management() {
    # 清理旧版 g 命令
    rm -f /usr/local/bin/g

    cat > /usr/local/bin/g-e << 'EOF'
#!/bin/bash
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

case "$1" in
    status)
        echo -e "\n${CYAN}  ── 运行状态 ──${NC}\n"
        /usr/local/bin/g-proxy status
        echo "" ;;
    start)
        echo -e "${CYAN}启动中...${NC}"
        systemctl start warp-svc 2>/dev/null; sleep 2
        warp-cli --accept-tos connect 2>/dev/null || warp-cli connect 2>/dev/null
        sleep 2
        /usr/local/bin/g-proxy start
        echo -e "${GREEN}✓ 已启动${NC}" ;;
    stop)
        echo -e "${CYAN}停止中...${NC}"
        /usr/local/bin/g-proxy stop
        warp-cli --accept-tos disconnect 2>/dev/null || warp-cli disconnect 2>/dev/null
        echo -e "${GREEN}✓ 已停止${NC}" ;;
    restart)
        $0 stop; sleep 2; $0 start ;;
    test)
        echo -e "${CYAN}测试 Google...${NC}"
        CODE=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" https://www.google.com)
        [ "$CODE" = "200" ] && \
            echo -e "${GREEN}✓ Google 可访问 (HTTP $CODE)${NC}" || \
            echo -e "${RED}✗ 无法访问 (HTTP $CODE)${NC}"
        echo ""
        echo -e "${CYAN}Cloudflare Trace（确认 WARP 状态）:${NC}"
        curl -x socks5://127.0.0.1:40000 -s --max-time 10 https://cloudflare.com/cdn-cgi/trace | \
            grep -E "^(ip|loc|colo|warp)=" || echo "获取失败" ;;
    ip)
        echo -e "\n${YELLOW}直连 IP:${NC}"
        D=$(curl -4 -s --max-time 5 ip.sb 2>/dev/null); echo -e "${GREEN}${D:-获取失败}${NC}"
        echo -e "${YELLOW}WARP IP:${NC}"
        W=$(curl -x socks5://127.0.0.1:40000 -s --max-time 10 ip.sb 2>/dev/null)
        if [ -n "$W" ]; then
            INFO=$(curl -s --max-time 5 "http://ip-api.com/json/$W?lang=zh-CN" 2>/dev/null)
            C=$(echo $INFO | grep -oP '"country":"\K[^"]+' || echo "未知")
            T=$(echo $INFO | grep -oP '"city":"\K[^"]+' || echo "未知")
            echo -e "${GREEN}$W  ($C $T)${NC}"
        else
            echo -e "${RED}获取失败（WARP 未连接）${NC}"
        fi
        echo "" ;;
    region)
        if [ -f /usr/local/bin/warp-setup.sh ]; then
            bash /usr/local/bin/warp-setup.sh --change-region
        else
            echo -e "${RED}请重新运行安装脚本切换地区${NC}"
            echo "bash <(curl -fsSL https://raw.githubusercontent.com/ctsunny/g-everywhere/main/warp-setup.sh) --change-region"
        fi ;;
    uninstall)
        echo -e "${YELLOW}卸载中...${NC}"
        /usr/local/bin/g-proxy stop 2>/dev/null
        warp-cli disconnect 2>/dev/null
        systemctl disable --now g-everywhere warp-svc 2>/dev/null
        rm -f /etc/systemd/system/g-everywhere.service
        rm -f /usr/local/bin/g-proxy /usr/local/bin/g-e /usr/local/bin/warp-setup.sh
        rm -f /etc/redsocks.conf
        apt-get remove -y cloudflare-warp redsocks 2>/dev/null || \
            dnf remove -y cloudflare-warp redsocks 2>/dev/null || \
            yum remove -y cloudflare-warp redsocks 2>/dev/null
        rm -f /etc/apt/sources.list.d/cloudflare-client.list \
              /etc/yum.repos.d/cloudflare-warp.repo
        echo -e "${GREEN}✓ 已完全卸载${NC}" ;;
    *)
        # 无参数：打开主菜单
        if [ -f /usr/local/bin/warp-setup.sh ]; then
            bash /usr/local/bin/warp-setup.sh
        else
            echo -e "${CYAN}G-Everywhere 管理工具 v2.1${NC}\n"
            echo "用法: g-e <命令>"
            echo ""
            echo "  status    查看状态（含实际出口 IP）"
            echo "  start     启动"
            echo "  stop      停止"
            echo "  restart   重启"
            echo "  test      测试 Google + Cloudflare Trace"
            echo "  ip        查看直连/WARP IP"
            echo "  region    切换出口地区"
            echo "  uninstall 卸载"
        fi ;;
esac
EOF
    chmod +x /usr/local/bin/g-e

    # 保存脚本自身供 g-e 调用
    cp "$0" /usr/local/bin/warp-setup.sh 2>/dev/null || true
    chmod +x /usr/local/bin/warp-setup.sh 2>/dev/null || true
}

# ============================================================
# 地区切换
# ============================================================
change_region() {
    echo -e "\n${CYAN}  ── 切换出口地区 ──${NC}"
    echo -e "\n  当前 Endpoint:"
    warp-cli settings 2>/dev/null | grep -i endpoint || echo "  默认（自动）"
    echo -e "\n  当前出口 IP:"
    CURRENT_WARP=$(curl -x socks5://127.0.0.1:40000 -s --max-time 8 ip.sb 2>/dev/null)
    [ -n "$CURRENT_WARP" ] && echo -e "  ${GREEN}$CURRENT_WARP${NC}" || echo -e "  ${RED}未连接${NC}"

    select_region
    apply_endpoint
    /usr/local/bin/g-proxy restart 2>/dev/null
    echo -e "\n  ${GREEN}✓ 地区切换完成${NC}"
}

# ============================================================
# 完整安装流程
# ============================================================
do_install() {
    select_region
    install_warp
    configure_warp
    setup_transparent_proxy
    create_management
    show_post_install
}

do_uninstall() {
    echo -e "\n${YELLOW}  卸载中...${NC}"
    /usr/local/bin/g-proxy stop 2>/dev/null || true
    warp-cli disconnect 2>/dev/null || true
    systemctl disable --now g-everywhere warp-svc 2>/dev/null || true
    rm -f /etc/systemd/system/g-everywhere.service
    rm -f /usr/local/bin/g-proxy /usr/local/bin/g-e /usr/local/bin/warp-setup.sh
    rm -f /etc/redsocks.conf
    iptables -t nat -D OUTPUT -j WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -F WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -X WARP_GOOGLE 2>/dev/null || true
    ip -6 route del blackhole 2607:f8b0::/32 2>/dev/null || true
    case $OS in
        ubuntu|debian)
            apt-get remove -y cloudflare-warp redsocks 2>/dev/null
            rm -f /etc/apt/sources.list.d/cloudflare-client.list ;;
        *)
            dnf remove -y cloudflare-warp redsocks 2>/dev/null || \
            yum remove -y cloudflare-warp redsocks 2>/dev/null
            rm -f /etc/yum.repos.d/cloudflare-warp.repo ;;
    esac
    echo -e "  ${GREEN}✓ 卸载完成${NC}\n"
}

do_status() {
    echo -e "\n${CYAN}  ── 运行状态 ──${NC}\n"
    if command -v warp-cli &>/dev/null; then
        /usr/local/bin/g-proxy status 2>/dev/null || {
            echo -e "  ${YELLOW}WARP 已安装，透明代理未运行${NC}"
            warp-cli status 2>/dev/null
        }
    else
        echo -e "  ${RED}WARP 未安装，请选择选项 1 进行安装${NC}"
    fi
    echo ""
}

# ============================================================
# 主菜单（循环，不自动退出）
# ============================================================
show_menu() {
    while true; do
        show_banner
        show_current_ip
        echo -e "  ${YELLOW}请选择操作:${NC}\n"
        echo -e "  ${GREEN}1.${NC} 安装 WARP（Google 解锁 + 地区选择）"
        echo -e "  ${GREEN}2.${NC} 切换出口地区"
        echo -e "  ${GREEN}3.${NC} 查看运行状态"
        echo -e "  ${GREEN}4.${NC} 卸载 WARP"
        echo -e "  ${GREEN}0.${NC} 退出\n"
        read -p "  请输入选项 [0-4]: " choice
        echo ""
        case $choice in
            1) do_install ;;
            2)
                if ! command -v warp-cli &>/dev/null; then
                    echo -e "  ${RED}请先安装 WARP（选项 1）${NC}"
                else
                    change_region
                fi ;;
            3) do_status ;;
            4) do_uninstall ;;
            0) echo -e "  ${GREEN}Bye!${NC}\n"; exit 0 ;;
            *) echo -e "  ${RED}无效选项，请重新输入${NC}" ;;
        esac
        echo ""
        read -p "  按 Enter 返回菜单..." _
    done
}

# ============================================================
# 主入口
# ============================================================
main() {
    check_root
    detect_os

    case "${1:-}" in
        --install)        show_banner; do_install ;;
        --uninstall)      show_banner; do_uninstall ;;
        --status)         show_banner; do_status ;;
        --change-region)  show_banner; change_region ;;
        *)                show_menu ;;
    esac
}

main "$@"
