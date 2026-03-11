#!/bin/bash
# WARP 一键脚本 v2.0 - 支持地区选择
# 使用 Cloudflare 官方客户端 + 透明代理解锁 Google

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================
# Cloudflare WARP 各地区 Endpoint IP (UDP 2408)
# 来源: Cloudflare 公开的 Anycast 边缘节点
# ============================================================
declare -A REGION_ENDPOINTS=(
    ["自动/默认"]="engage.cloudflareclient.com:2408"
    ["美国-洛杉矶"]="162.159.192.1:2408"
    ["美国-纽约"]="162.159.193.1:2408"
    ["日本-东京"]="162.159.195.1:2408"
    ["新加坡"]="162.159.196.1:2408"
    ["德国-法兰克福"]="162.159.197.1:2408"
    ["英国-伦敦"]="162.159.198.1:2408"
    ["荷兰-阿姆斯特丹"]="162.159.199.1:2408"
    ["澳大利亚-悉尼"]="162.159.200.1:2408"
    ["印度-孟买"]="162.159.204.1:2408"
    ["巴西-圣保罗"]="162.159.205.1:2408"
    ["加拿大-多伦多"]="162.159.209.1:2408"
    ["韩国-首尔"]="162.159.210.1:2408"
    ["香港"]="162.159.211.1:2408"
)

REGION_KEYS=(
    "自动/默认"
    "美国-洛杉矶"
    "美国-纽约"
    "日本-东京"
    "新加坡"
    "德国-法兰克福"
    "英国-伦敦"
    "荷兰-阿姆斯特丹"
    "澳大利亚-悉尼"
    "印度-孟买"
    "巴西-圣保罗"
    "加拿大-多伦多"
    "韩国-首尔"
    "香港"
)

SELECTED_REGION="自动/默认"

show_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║    🌐 WARP 一键脚本 v2.0 - 支持地区选择 🌐           ║"
    echo "║        使用 Cloudflare 官方客户端 + 透明代理          ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
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
    echo -e "${GREEN}系统: $OS $VERSION ($CODENAME) $ARCH${NC}"
}

show_current_ip() {
    echo -e "\n${YELLOW}当前 IP 信息:${NC}"
    CURRENT_IP=$(curl -4 -s --max-time 5 ip.sb 2>/dev/null || echo "获取失败")
    echo -e "IP: ${GREEN}$CURRENT_IP${NC}"
    if [ "$CURRENT_IP" != "获取失败" ]; then
        IP_INFO=$(curl -s --max-time 5 "http://ip-api.com/json/$CURRENT_IP?lang=zh-CN" 2>/dev/null)
        COUNTRY=$(echo $IP_INFO | grep -oP '"country":"\K[^"]+' 2>/dev/null || echo "未知")
        CITY=$(echo $IP_INFO | grep -oP '"city":"\K[^"]+' 2>/dev/null || echo "未知")
        echo -e "位置: ${GREEN}$COUNTRY - $CITY${NC}"
    fi
}

# ============================================================
# 地区选择菜单
# ============================================================
select_region() {
    echo -e "\n${CYAN}══════════ 选择 WARP 出口地区 ══════════${NC}\n"
    echo -e "${YELLOW}注意: 地区选择通过指定 Cloudflare 边缘节点实现"
    echo -e "实际出口地区由 Cloudflare 网络决定，仅供参考${NC}\n"
    
    for i in "${!REGION_KEYS[@]}"; do
        printf "  ${GREEN}%2d.${NC} %s\n" "$((i+1))" "${REGION_KEYS[$i]}"
    done
    
    echo ""
    read -p "请选择地区 [1-${#REGION_KEYS[@]}] (默认1): " region_choice
    region_choice=${region_choice:-1}
    
    if [[ "$region_choice" =~ ^[0-9]+$ ]] && \
       [ "$region_choice" -ge 1 ] && \
       [ "$region_choice" -le "${#REGION_KEYS[@]}" ]; then
        SELECTED_REGION="${REGION_KEYS[$((region_choice-1))]}"
        echo -e "${GREEN}✓ 已选择: $SELECTED_REGION${NC}"
    else
        echo -e "${YELLOW}无效选择，使用默认${NC}"
        SELECTED_REGION="自动/默认"
    fi
}

# ============================================================
# 安装 Cloudflare WARP
# ============================================================
install_warp() {
    echo -e "\n${CYAN}[1/4] 安装 Cloudflare WARP 官方客户端...${NC}"
    
    case $OS in
        ubuntu|debian)
            apt-get update -y >/dev/null 2>&1
            apt-get install -y gnupg curl wget >/dev/null 2>&1
            curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | \
                gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
            echo "deb [arch=$ARCH signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] \
https://pkg.cloudflareclient.com/ $CODENAME main" \
                > /etc/apt/sources.list.d/cloudflare-client.list
            apt-get update -y
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
            if command -v dnf &>/dev/null; then
                dnf install -y cloudflare-warp
            else
                yum install -y cloudflare-warp
            fi
            ;;
        *)
            echo -e "${RED}不支持的系统: $OS${NC}"; exit 1 ;;
    esac
    
    command -v warp-cli &>/dev/null || { echo -e "${RED}WARP 安装失败${NC}"; exit 1; }
    echo -e "${GREEN}✓ WARP 客户端已安装: $(warp-cli --version 2>/dev/null)${NC}"
}

# ============================================================
# 配置 WARP（含地区 endpoint）
# ============================================================
configure_warp() {
    echo -e "\n${CYAN}[2/4] 配置 WARP...${NC}"
    
    # 确保 warp-svc 运行
    systemctl start warp-svc 2>/dev/null || true
    sleep 2
    
    # 注册设备（兼容新旧版本）
    echo -e "注册设备..."
    warp-cli --accept-tos registration new 2>/dev/null || \
    warp-cli --accept-tos register 2>/dev/null || true
    sleep 1
    
    # 设置代理模式
    warp-cli --accept-tos mode proxy 2>/dev/null || \
    warp-cli --accept-tos set-mode proxy 2>/dev/null || true
    
    # 设置代理端口
    warp-cli --accept-tos proxy port 40000 2>/dev/null || \
    warp-cli --accept-tos set-proxy-port 40000 2>/dev/null || true
    
    # ★ 设置地区 endpoint ★
    ENDPOINT="${REGION_ENDPOINTS[$SELECTED_REGION]}"
    if [ "$SELECTED_REGION" != "自动/默认" ]; then
        echo -e "设置出口节点: ${YELLOW}$SELECTED_REGION${NC} ($ENDPOINT)"
        warp-cli --accept-tos set-custom-endpoint "$ENDPOINT" 2>/dev/null || \
        warp-cli set-custom-endpoint "$ENDPOINT" 2>/dev/null || true
    else
        # 清除自定义 endpoint，使用自动
        warp-cli --accept-tos clear-custom-endpoint 2>/dev/null || true
        echo -e "使用自动地区分配"
    fi
    
    # 连接
    echo -e "连接 WARP..."
    warp-cli --accept-tos connect 2>/dev/null || warp-cli connect 2>/dev/null
    sleep 3
    
    STATUS=$(warp-cli --accept-tos status 2>/dev/null || warp-cli status 2>/dev/null)
    echo -e "状态: ${GREEN}$STATUS${NC}"
    echo -e "${GREEN}✓ WARP 配置完成${NC}"
}

# ============================================================
# 配置透明代理 (redsocks + iptables)
# ============================================================
setup_transparent_proxy() {
    echo -e "\n${CYAN}[3/4] 配置透明代理规则...${NC}"
    
    # 优先使用 IPv4
    grep -q "precedence ::ffff:0:0/96  100" /etc/gai.conf 2>/dev/null || \
        echo "precedence ::ffff:0:0/96  100" >> /etc/gai.conf
    
    # 安装 redsocks + iptables
    case $OS in
        ubuntu|debian)
            apt-get install -y redsocks iptables >/dev/null 2>&1 ;;
        centos|rhel|rocky|almalinux|fedora)
            command -v dnf &>/dev/null && \
                dnf install -y redsocks iptables >/dev/null 2>&1 || \
                yum install -y redsocks iptables >/dev/null 2>&1 ;;
    esac
    
    # redsocks 配置
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

    # Google IP 段（Google ASN AS15169 主要段）
    cat > /usr/local/bin/warp-google << 'SCRIPT'
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
    redsocks -c /etc/redsocks.conf
    sleep 1
    iptables -t nat -N WARP_GOOGLE 2>/dev/null || iptables -t nat -F WARP_GOOGLE
    for ip in $GOOGLE_IPS; do
        iptables -t nat -A WARP_GOOGLE -d $ip -p tcp -j REDIRECT --to-ports 12345
    done
    # IPv6 Google 黑洞（避免 IPv6 绕过）
    ip -6 route add blackhole 2607:f8b0::/32 2>/dev/null || true
    ip6tables -t nat -N WARP_GOOGLE6 2>/dev/null || ip6tables -t nat -F WARP_GOOGLE6
    ip6tables -t nat -A WARP_GOOGLE6 -d 2607:f8b0::/32 -p tcp -j RETURN
    ip6tables -t nat -C OUTPUT -j WARP_GOOGLE6 2>/dev/null || ip6tables -t nat -A OUTPUT -j WARP_GOOGLE6
    iptables -t nat -C OUTPUT -j WARP_GOOGLE 2>/dev/null || iptables -t nat -A OUTPUT -j WARP_GOOGLE
    echo "Google 透明代理已启动"
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
    echo "Google 透明代理已停止"
}

status() {
    echo "=== WARP 状态 ==="
    warp-cli status 2>/dev/null || echo "WARP 未运行"
    echo ""
    echo "=== Redsocks ==="
    pgrep -x redsocks >/dev/null && echo "运行中 (PID: $(pgrep -x redsocks))" || echo "未运行"
    echo ""
    echo "=== iptables 规则数 ==="
    COUNT=$(iptables -t nat -L WARP_GOOGLE -n 2>/dev/null | grep -c REDIRECT || echo 0)
    echo "Google 规则: $COUNT 条"
    echo ""
    echo "=== 当前 WARP Endpoint ==="
    warp-cli settings 2>/dev/null | grep -i endpoint || echo "使用默认"
}

case "$1" in
    start) start ;;
    stop) stop ;;
    restart) stop; sleep 1; start ;;
    status) status ;;
    *) echo "用法: $0 {start|stop|restart|status}" ;;
esac
SCRIPT
    chmod +x /usr/local/bin/warp-google
    /usr/local/bin/warp-google start
    
    # systemd 服务
    cat > /etc/systemd/system/warp-google.service << 'EOF'
[Unit]
Description=WARP Google Transparent Proxy
After=network.target warp-svc.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/warp-google start
ExecStop=/usr/local/bin/warp-google stop

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable warp-google 2>/dev/null
    echo -e "${GREEN}✓ 透明代理配置完成${NC}"
}

# ============================================================
# 地区切换功能（已安装后使用）
# ============================================================
change_region() {
    echo -e "\n${CYAN}切换 WARP 出口地区${NC}"
    
    echo -e "\n${YELLOW}当前 Endpoint:${NC}"
    warp-cli settings 2>/dev/null | grep -i endpoint || echo "默认（自动）"
    
    select_region
    
    ENDPOINT="${REGION_ENDPOINTS[$SELECTED_REGION]}"
    
    if [ "$SELECTED_REGION" = "自动/默认" ]; then
        warp-cli --accept-tos clear-custom-endpoint 2>/dev/null || true
    else
        warp-cli --accept-tos set-custom-endpoint "$ENDPOINT" 2>/dev/null || \
        warp-cli set-custom-endpoint "$ENDPOINT" 2>/dev/null || true
    fi
    
    # 重连
    warp-cli --accept-tos disconnect 2>/dev/null; sleep 1
    warp-cli --accept-tos connect 2>/dev/null
    sleep 3
    
    echo -e "\n${GREEN}✓ 地区已切换: $SELECTED_REGION${NC}"
    
    # 显示新 WARP IP
    echo -e "\n${YELLOW}新 WARP IP:${NC}"
    WARP_IP=$(curl -x socks5://127.0.0.1:40000 -s --max-time 10 ip.sb 2>/dev/null)
    if [ -n "$WARP_IP" ]; then
        WARP_INFO=$(curl -s --max-time 5 "http://ip-api.com/json/$WARP_IP?lang=zh-CN" 2>/dev/null)
        echo -e "IP: ${GREEN}$WARP_IP${NC}"
        COUNTRY=$(echo $WARP_INFO | grep -oP '"country":"\K[^"]+' || echo "未知")
        CITY=$(echo $WARP_INFO | grep -oP '"city":"\K[^"]+' || echo "未知")
        echo -e "位置: ${GREEN}$COUNTRY - $CITY${NC}"
    else
        echo -e "${RED}无法获取（请稍后再试）${NC}"
    fi
}

# ============================================================
# 管理命令 /usr/local/bin/warp
# ============================================================
create_management() {
    cat > /usr/local/bin/warp << 'EOF'
#!/bin/bash
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'

case "$1" in
    status)
        /usr/local/bin/warp-google status ;;
    start)
        warp-cli connect 2>/dev/null
        /usr/local/bin/warp-google start ;;
    stop)
        /usr/local/bin/warp-google stop
        warp-cli disconnect 2>/dev/null ;;
    restart)
        $0 stop; sleep 2; $0 start ;;
    test)
        echo -e "${CYAN}测试 Google 连接...${NC}"
        CODE=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" https://www.google.com)
        [ "$CODE" = "200" ] && \
            echo -e "${GREEN}✓ Google 可访问 (HTTP $CODE)${NC}" || \
            echo -e "${RED}✗ 失败 (HTTP $CODE)${NC}" ;;
    ip)
        echo -e "${YELLOW}直连 IP:${NC}"
        curl -4 -s --max-time 5 ip.sb; echo ""
        echo -e "${YELLOW}WARP IP:${NC}"
        curl -x socks5://127.0.0.1:40000 -s --max-time 10 ip.sb; echo "" ;;
    region)
        # 重新运行主脚本的地区切换功能
        if [ -f /usr/local/bin/warp-setup.sh ]; then
            bash /usr/local/bin/warp-setup.sh --change-region
        else
            echo -e "${RED}请重新运行安装脚本进行地区切换${NC}"
        fi ;;
    uninstall)
        echo -e "${YELLOW}卸载 WARP...${NC}"
        /usr/local/bin/warp-google stop 2>/dev/null
        warp-cli disconnect 2>/dev/null
        systemctl disable --now warp-google warp-svc 2>/dev/null
        rm -f /etc/systemd/system/warp-google.service
        rm -f /usr/local/bin/warp-google /usr/local/bin/warp
        rm -f /etc/redsocks.conf
        # 卸载包
        apt-get remove -y cloudflare-warp redsocks 2>/dev/null || \
            (dnf remove -y cloudflare-warp redsocks 2>/dev/null || \
             yum remove -y cloudflare-warp redsocks 2>/dev/null)
        rm -f /etc/apt/sources.list.d/cloudflare-client.list \
              /etc/yum.repos.d/cloudflare-warp.repo
        echo -e "${GREEN}✓ WARP 已完全卸载${NC}" ;;
    *)
        echo -e "${CYAN}WARP 管理工具 v2.0${NC}\n"
        echo "用法: warp <命令>"
        echo ""
        echo "  status    查看状态（含 endpoint）"
        echo "  start     启动 WARP"
        echo "  stop      停止 WARP"
        echo "  restart   重启 WARP"
        echo "  test      测试 Google 连接"
        echo "  ip        查看直连/WARP IP"
        echo "  region    切换出口地区"
        echo "  uninstall 卸载 WARP" ;;
esac
EOF
    chmod +x /usr/local/bin/warp
    # 保存脚本自身供 region 命令调用
    cp "$0" /usr/local/bin/warp-setup.sh 2>/dev/null || true
    chmod +x /usr/local/bin/warp-setup.sh 2>/dev/null || true
}

test_connection() {
    echo -e "\n${CYAN}[4/4] 测试连接...${NC}"
    sleep 2
    CODE=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" https://www.google.com)
    [ "$CODE" = "200" ] && \
        echo -e "${GREEN}✓ Google 连接成功！${NC}" || \
        echo -e "${YELLOW}Google 返回: $CODE（可能需要等待几秒）${NC}"
    
    WARP_IP=$(curl -x socks5://127.0.0.1:40000 -s --max-time 10 ip.sb 2>/dev/null)
    if [ -n "$WARP_IP" ]; then
        WARP_INFO=$(curl -s --max-time 5 "http://ip-api.com/json/$WARP_IP?lang=zh-CN" 2>/dev/null)
        echo -e "WARP IP: ${GREEN}$WARP_IP${NC}"
        COUNTRY=$(echo $WARP_INFO | grep -oP '"country":"\K[^"]+' || echo "未知")
        CITY=$(echo $WARP_INFO | grep -oP '"city":"\K[^"]+' || echo "未知")
        echo -e "WARP 位置: ${GREEN}$COUNTRY - $CITY${NC}"
    fi
}

do_install() {
    select_region
    install_warp
    configure_warp
    setup_transparent_proxy
    create_management
    test_connection
    
    echo -e "\n${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║         🎉 安装完成！Google 已通过 WARP 解锁 🎉      ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
    echo -e "\n${YELLOW}出口地区: ${CYAN}$SELECTED_REGION${NC}"
    echo -e "${YELLOW}所有 Google 流量自动走 WARP，无需额外配置${NC}"
    echo -e "\n管理命令: ${CYAN}warp {status|start|stop|restart|test|ip|region|uninstall}${NC}\n"
}

do_uninstall() {
    echo -e "\n${YELLOW}卸载 WARP...${NC}"
    /usr/local/bin/warp-google stop 2>/dev/null || true
    warp-cli disconnect 2>/dev/null || true
    systemctl disable --now warp-google warp-svc 2>/dev/null || true
    rm -f /etc/systemd/system/warp-google.service
    rm -f /usr/local/bin/warp-google /usr/local/bin/warp /usr/local/bin/warp-setup.sh
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
    echo -e "${GREEN}✓ WARP 已完全卸载${NC}\n"
}

do_status() {
    echo -e "\n${CYAN}══════════════ WARP 状态 ══════════════${NC}"
    /usr/local/bin/warp-google status 2>/dev/null || {
        echo -e "${RED}透明代理未安装或未运行${NC}"
        command -v warp-cli &>/dev/null && warp-cli status 2>/dev/null
    }
    echo -e "${CYAN}════════════════════════════════════════${NC}\n"
}

show_menu() {
    show_current_ip
    echo -e "\n${YELLOW}请选择操作:${NC}\n"
    echo -e "  ${GREEN}1.${NC} 安装 WARP（解锁 Google，含地区选择）"
    echo -e "  ${GREEN}2.${NC} 切换出口地区"
    echo -e "  ${GREEN}3.${NC} 查看状态"
    echo -e "  ${GREEN}4.${NC} 卸载 WARP"
    echo -e "  ${GREEN}0.${NC} 退出\n"
    
    read -p "请输入选项 [0-4]: " choice
    case $choice in
        1) do_install ;;
        2)
            if ! command -v warp-cli &>/dev/null; then
                echo -e "${RED}请先安装 WARP（选项1）${NC}"
            else
                detect_os
                change_region
            fi ;;
        3) do_status ;;
        4) do_uninstall ;;
        0) echo -e "\n${GREEN}再见！${NC}\n"; exit 0 ;;
        *) echo -e "\n${RED}无效选项${NC}\n" ;;
    esac
}

# 主入口
main() {
    show_banner
    check_root
    detect_os
    
    # 支持参数直接调用
    case "${1:-}" in
        --install)   do_install ;;
        --uninstall) do_uninstall ;;
        --status)    do_status ;;
        --change-region) change_region ;;
        *) show_menu ;;
    esac
}

main "$@"
