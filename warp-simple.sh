#!/bin/bash
# G-Everywhere Worker-Style v5.1
# 极简版，wk=命令快速切换地区
# 用法: bash warp-simple.sh 或 wk=us 等命令

set -e

# 颜色
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; NC='\033[0m'; BOLD='\033[1m'

WARP_DIR="/etc/warp"
REDSOCKS_CONF="/etc/redsocks-warp.conf"
WK_ALIAS="/etc/profile.d/wk-alias.sh"

# 地区定义
declare -A WK_REGION=(
    ["auto"]="🌐 自动"
    ["us"]="🇺🇸 美国"
    ["jp"]="🇯🇵 日本" 
    ["sg"]="🇸🇬 新加坡"
    ["de"]="🇩🇪 德国"
    ["uk"]="🇬🇧 英国"
    ["nl"]="🇳🇱 荷兰"
    ["au"]="🇦🇺 澳大利亚"
    ["kr"]="🇰🇷 韩国"
    ["hk"]="🇭🇰 香港"
)

# Google IP段（精简版）
GOOGLE_IPS=(
    "8.8.4.0/24" "8.8.8.0/24" "34.0.0.0/9"
    "64.233.160.0/19" "74.125.0.0/16"
    "108.177.0.0/17" "142.250.0.0/15"
    "172.217.0.0/16" "173.194.0.0/16"
    "216.58.192.0/19" "216.239.32.0/19"
)

# ============================================
# 核心: wk= 命令处理
# ============================================
wk_command() {
    local cmd="$1"
    
    case "$cmd" in
        install)
            wk_install ;;
        us|jp|sg|de|uk|nl|au|kr|hk)
            wk_switch "$cmd" ;;
        auto)
            wk_switch "auto" ;;
        status)
            wk_status ;;
        test)
            wk_test ;;
        fix)
            wk_fix ;;
        uninstall)
            wk_uninstall ;;
        help|*)
            wk_help ;;
    esac
}

wk_switch() {
    local region="$1"
    echo -e "${CYAN}切换地区到: ${WK_REGION[$region]}${NC}"
    
    # 保存地区设置
    mkdir -p "$WARP_DIR"
    echo "$region" > "$WARP_DIR/wk_region"
    
    # 执行切换
    if command -v warp-cli &>/dev/null; then
        _wk_do_switch "$region"
    else
        echo -e "${YELLOW}warp-cli 未安装，请先运行 wk install${NC}"
    fi
}

_wk_do_switch() {
    local region="$1"
    
    echo -e "  停止当前连接..."
    warp-cli --accept-tos disconnect 2>/dev/null || true
    sleep 2
    
    echo -e "  重新连接..."
    systemctl restart warp-svc 2>/dev/null
    sleep 3
    
    # 设置入口端点
    if [ "$region" != "auto" ]; then
        local endpoint=""
        case "$region" in
            us) endpoint="162.159.193.1:2408" ;;
            jp) endpoint="162.159.193.2:2408" ;;
            sg) endpoint="162.159.193.3:2408" ;;
            de) endpoint="162.159.193.4:2408" ;;
            uk) endpoint="162.159.193.5:2408" ;;
            nl) endpoint="162.159.193.6:2408" ;;
            au) endpoint="162.159.193.7:2408" ;;
            kr) endpoint="162.159.193.8:2408" ;;
            hk) endpoint="162.159.193.9:2408" ;;
        esac
        
        warp-cli --accept-tos set-custom-endpoint "$endpoint" 2>/dev/null
        echo -e "  入口: ${YELLOW}$endpoint${NC}"
    fi
    
    # 智能重试机制
    _wk_smart_retry "$region"
}

_wk_smart_retry() {
    local region="$1"
    local max_attempts=6
    local best_ip=""
    local best_country=""
    local best_score=0
    
    echo -e "  智能获取目标地区..."
    
    for attempt in $(seq 1 $max_attempts); do
        echo -e "  尝试 $attempt/$max_attempts"
        
        # 清理并重新注册（每隔2次清理一次）
        if [ $((attempt % 2)) -eq 1 ]; then
            warp-cli --accept-tos registration delete 2>/dev/null || true
            sleep 1
        fi
        
        warp-cli --accept-tos register 2>/dev/null || true
        warp-cli --accept-tos mode proxy 2>/dev/null
        warp-cli --accept-tos connect 2>/dev/null
        sleep 15  # 重要：给WARP足够时间分配IP
        
        # 检查连接
        if ! warp-cli status 2>/dev/null | grep -qi "connected"; then
            continue
        fi
        
        # 获取出口信息
        local exit_ip country_code country city
        exit_ip=$(curl -x socks5://127.0.0.1:40000 -s --max-time 10 ip.sb 2>/dev/null)
        
        if [ -n "$exit_ip" ]; then
            local ipinfo
            ipinfo=$(curl -s --max-time 8 "http://ip-api.com/json/${exit_ip}?lang=zh-CN" 2>/dev/null)
            country_code=$(echo "$ipinfo" | grep -oP '"countryCode":"\K[^"]+' || echo "UN")
            country=$(echo "$ipinfo" | grep -oP '"country":"\K[^"]+' || echo "未知")
            city=$(echo "$ipinfo" | grep -oP '"city":"\K[^"]+' || echo "")
            
            echo -e "    出口: ${CYAN}$exit_ip ($country_code)${NC}"
            
            # 评分系统
            local score=0
            case "$region" in
                auto) score=1 ;;
                us) [[ "$country_code" == "US" ]] && score=10 ;;
                jp) [[ "$country_code" == "JP" ]] && score=10 ;;
                sg) [[ "$country_code" == "SG" ]] && score=10 ;;
                de) [[ "$country_code" == "DE" ]] && score=10 ;;
                uk) [[ "$country_code" == "GB" ]] && score=10 ;;
                nl) [[ "$country_code" == "NL" ]] && score=10 ;;
                au) [[ "$country_code" == "AU" ]] && score=10 ;;
                kr) [[ "$country_code" == "KR" ]] && score=10 ;;
                hk) [[ "$country_code" == "HK" ]] && score=10 ;;
            esac
            
            # 更新最佳记录
            if [ $score -gt $best_score ]; then
                best_score=$score
                best_ip="$exit_ip"
                best_country="$country"
                
                if [ $score -eq 10 ]; then
                    echo -e "    ${GREEN}✓ 完美匹配！${NC}"
                    break
                fi
            fi
        fi
    done
    
    # 保存结果
    if [ -n "$best_ip" ]; then
        printf '%s\n%s\n' "$best_ip" "$best_country" > "$WARP_DIR/exit_info"
        echo -e "  ${GREEN}✓ 最佳出口: $best_ip ($best_country)${NC}"
    else
        echo -e "  ${YELLOW}⚠ 未能获取理想出口${NC}"
    fi
}

# ============================================
# 安装函数
# ============================================
wk_install() {
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}G-Everywhere Worker 版安装${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # 检查root
    [[ $EUID -ne 0 ]] && { echo -e "${RED}请用 root 运行${NC}"; return 1; }
    
    # 检测系统
    local OS ARCH
    [ -f /etc/os-release ] && . /etc/os-release && OS=$ID
    ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
    echo -e "系统: ${YELLOW}$OS ($ARCH)${NC}"
    
    # 选择地区
    echo -e "\n${CYAN}选择目标地区:${NC}"
    local i=1
    for code in "${!WK_REGION[@]}"; do
        printf "  ${GREEN}%d.${NC} %s\n" "$i" "${WK_REGION[$code]}"
        ((i++))
    done
    
    echo ""
    read -rp "选择 [1-${#WK_REGION[@]}] (默认1): " choice
    choice=${choice:-1}
    
    local regions=(${!WK_REGION[@]})
    local selected="${regions[$((choice-1))]}"
    
    echo -e "${GREEN}✓ 选择: ${WK_REGION[$selected]}${NC}"
    
    # 安装依赖
    echo -e "\n${CYAN}[1/3] 安装依赖...${NC}"
    
    case $OS in
        ubuntu|debian)
            apt-get update -y
            apt-get install -y curl wget iptables redsocks 2>/dev/null
            ;;
        centos|rhel|rocky|almalinux)
            dnf install -y epel-release 2>/dev/null
            dnf install -y curl wget iptables redsocks 2>/dev/null
            ;;
        fedora)
            dnf install -y curl wget iptables redsocks 2>/dev/null
            ;;
    esac
    
    # 安装warp-cli
    echo -e "${CYAN}[2/3] 安装 warp-cli...${NC}"
    
    case $OS in
        ubuntu|debian)
            local codename
            codename=$(. /etc/os-release && echo "$VERSION_CODENAME")
            curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg \
                | gpg --dearmor -o /usr/share/keyrings/cloudflare-warp.gpg
            echo "deb [arch=$ARCH signed-by=/usr/share/keyrings/cloudflare-warp.gpg] \
                https://pkg.cloudflareclient.com/ $codename main" \
                > /etc/apt/sources.list.d/cloudflare.list
            apt-get update -y
            apt-get install -y cloudflare-warp 2>/dev/null
            ;;
        centos|rhel|rocky|almalinux|fedora)
            curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg \
                -o /etc/pki/rpm-gpg/cloudflare-warp.gpg
            cat > /etc/yum.repos.d/cloudflare.repo << EOF
[cloudflare-warp]
name=Cloudflare WARP
baseurl=https://pkg.cloudflareclient.com/rpm
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/cloudflare-warp.gpg
EOF
            dnf install -y cloudflare-warp 2>/dev/null
            ;;
    esac
    
    command -v warp-cli &>/dev/null || { echo -e "${RED}warp-cli安装失败${NC}"; return 1; }
    
    # 配置服务
    echo -e "${CYAN}[3/3] 配置服务...${NC}"
    
    # redsocks配置
    cat > "$REDSOCKS_CONF" << EOF
base {
    log_debug = off;
    log_info = off;
    daemon = off;
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
    
    # systemd服务
    cat > /etc/systemd/system/redsocks-warp.service << EOF
[Unit]
Description=Redsocks WARP Proxy
After=network.target

[Service]
Type=simple
ExecStart=/usr/sbin/redsocks -c $REDSOCKS_CONF
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable redsocks-warp
    systemctl start redsocks-warp
    
    # 创建wk命令
    _create_wk_command
    
    # 设置地区
    wk_switch "$selected"
    
    # 配置路由
    _setup_routing
    
    echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${GREEN}✓ 安装完成！${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    echo -e "\n${CYAN}使用命令:${NC}"
    echo -e "  ${GREEN}wk=us${NC}       切换到美国"
    echo -e "  ${GREEN}wk=sg${NC}       切换到新加坡"
    echo -e "  ${GREEN}wk status${NC}   查看状态"
    echo -e "  ${GREEN}wk test${NC}     测试连接"
    echo -e "  ${GREEN}wk fix${NC}      修复问题"
}

_create_wk_command() {
    # 创建wk命令脚本
    cat > /usr/local/bin/wk << 'WKEOF'
#!/bin/bash
# wk命令 - 极简版

case "$1" in
    install)
        bash /usr/local/bin/warp-simple.sh install ;;
    us|jp|sg|de|uk|nl|au|kr|hk|auto)
        bash /usr/local/bin/warp-simple.sh "$1" ;;
    status)
        bash /usr/local/bin/warp-simple.sh status ;;
    test)
        bash /usr/local/bin/warp-simple.sh test ;;
    fix)
        bash /usr/local/bin/warp-simple.sh fix ;;
    uninstall)
        bash /usr/local/bin/warp-simple.sh uninstall ;;
    *)
        echo "wk命令帮助:"
        echo "  wk install     安装"
        echo "  wk=us          切换到美国"
        echo "  wk=sg          切换到新加坡"
        echo "  wk status      状态"
        echo "  wk test        测试"
        echo "  wk fix         修复"
        echo "  wk uninstall   卸载"
        ;;
esac
WKEOF
    
    chmod +x /usr/local/bin/wk
    
    # 创建别名文件
    cat > /etc/profile.d/wk-alias.sh << 'ALIASEOF'
alias wk='bash /usr/local/bin/wk'
alias 'wk=us'='bash /usr/local/bin/wk us'
alias 'wk=sg'='bash /usr/local/bin/wk sg'
alias 'wk=jp'='bash /usr/local/bin/wk jp'
alias 'wk=de'='bash /usr/local/bin/wk de'
alias 'wk=uk'='bash /usr/local/bin/wk uk'
alias 'wk=nl'='bash /usr/local/bin/wk nl'
alias 'wk=au'='bash /usr/local/bin/wk au'
alias 'wk=kr'='bash /usr/local/bin/wk kr'
alias 'wk=hk'='bash /usr/local/bin/wk hk'
ALIASEOF
    
    source /etc/profile.d/wk-alias.sh 2>/dev/null
    echo -e "${GREEN}✓ wk命令已创建${NC}"
}

_setup_routing() {
    # 清理旧规则
    iptables -t nat -F 2>/dev/null || true
    
    # 创建新规则链
    iptables -t nat -N WARP_GOOGLE 2>/dev/null || true
    
    # 排除本地网络
    local nets=(127.0.0.0/8 10.0.0.0/8 192.168.0.0/16 172.16.0.0/12)
    for net in "${nets[@]}"; do
        iptables -t nat -A WARP_GOOGLE -d "$net" -j RETURN 2>/dev/null
    done
    
    # Google IP走代理
    for ip in "${GOOGLE_IPS[@]}"; do
        iptables -t nat -A WARP_GOOGLE -d "$ip" -p tcp -j REDIRECT --to-ports 12345 2>/dev/null
    done
    
    # 应用到OUTPUT和PREROUTING
    iptables -t nat -A OUTPUT -j WARP_GOOGLE 2>/dev/null
    iptables -t nat -A PREROUTING -j WARP_GOOGLE 2>/dev/null
    
    echo -e "${GREEN}✓ 路由规则已配置${NC}"
}

# ============================================
# 状态和测试
# ============================================
wk_status() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}状态检查${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # 地区信息
    if [ -f "$WARP_DIR/wk_region" ]; then
        local region=$(cat "$WARP_DIR/wk_region")
        echo -e "地区设置: ${GREEN}${WK_REGION[$region]}${NC}"
    fi
    
    # warp-cli状态
    if command -v warp-cli &>/dev/null; then
        echo -e "\n${YELLOW}warp-cli:${NC}"
        warp-cli status 2>/dev/null | head -3
    fi
    
    # redsocks状态
    if systemctl is-active redsocks-warp &>/dev/null; then
        echo -e "${GREEN}✓ redsocks 运行中${NC}"
    else
        echo -e "${RED}✗ redsocks 未运行${NC}"
    fi
    
    # 出口IP
    echo -e "\n${YELLOW}出口IP:${NC}"
    local warp_ip direct_ip
    warp_ip=$(curl -x socks5://127.0.0.1:40000 -s --max-time 8 ip.sb 2>/dev/null)
    direct_ip=$(curl -4 -s --max-time 5 ip.sb 2>/dev/null)
    
    if [ -n "$warp_ip" ]; then
        local info
        info=$(curl -s --max-time 5 "http://ip-api.com/json/${warp_ip}?lang=zh-CN" 2>/dev/null)
        local country=$(echo "$info" | grep -oP '"country":"\K[^"]+' || echo "未知")
        echo -e "WARP出口: ${GREEN}$warp_ip ($country)${NC}"
    fi
    
    if [ -n "$direct_ip" ]; then
        echo -e "直连出口: ${GREEN}$direct_ip${NC}"
    fi
    
    # Google测试
    echo -e "\n${YELLOW}访问测试:${NC}"
    local code
    code=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" https://www.google.com)
    if [ "$code" = "200" ] || [ "$code" = "301" ]; then
        echo -e "${GREEN}✓ Google HTTP $code${NC}"
    else
        echo -e "${RED}✗ Google HTTP $code${NC}"
    fi
}

wk_test() {
    echo -e "${CYAN}完整测试...${NC}"
    
    # 测试warp-cli
    echo -e "1. warp-cli连接测试"
    if warp-cli status 2>/dev/null | grep -qi "connected"; then
        echo -e "  ${GREEN}✓ 已连接${NC}"
    else
        echo -e "  ${RED}✗ 未连接${NC}"
    fi
    
    # 测试SOCKS5
    echo -e "2. SOCKS5代理测试"
    local socks_ip
    socks_ip=$(curl -x socks5://127.0.0.1:40000 -s --max-time 10 ip.sb 2>/dev/null)
    if [ -n "$socks_ip" ]; then
        echo -e "  ${GREEN}✓ 可用 ($socks_ip)${NC}"
    else
        echo -e "  ${RED}✗ 不可用${NC}"
    fi
    
    # 测试网站访问
    echo -e "3. 网站访问测试"
    local sites=(
        "Google:https://www.google.com"
        "YouTube:https://www.youtube.com"
        "Gemini:https://gemini.google.com"
    )
    
    for site in "${sites[@]}"; do
        local name="${site%%:*}"
        local url="${site#*:}"
        local code
        code=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" \
            -H "User-Agent: Mozilla/5.0" "$url" 2>/dev/null || echo "000")
        
        if [ "$code" = "200" ] || [ "$code" = "301" ]; then
            echo -e "  ${GREEN}✓${NC} $name HTTP $code"
        else
            echo -e "  ${YELLOW}△${NC} $name HTTP $code"
        fi
    done
    
    # 分流测试
    echo -e "4. 分流测试"
    local warp_ip direct_ip
    warp_ip=$(curl -x socks5://127.0.0.1:40000 -s --max-time 8 ip.sb 2>/dev/null)
    direct_ip=$(curl -4 -s --max-time 5 ip.sb 2>/dev/null)
    
    if [ -n "$warp_ip" ] && [ -n "$direct_ip" ] && [ "$warp_ip" != "$direct_ip" ]; then
        echo -e "  ${GREEN}✓ 分流正常${NC}"
        echo -e "    WARP IP: $warp_ip"
        echo -e "    直连 IP: $direct_ip"
    else
        echo -e "  ${YELLOW}△ 分流可能异常${NC}"
    fi
}

wk_fix() {
    echo -e "${CYAN}修复中...${NC}"
    
    # 停止服务
    systemctl stop redsocks-warp 2>/dev/null
    warp-cli --accept-tos disconnect 2>/dev/null
    sleep 2
    
    # 清理iptables
    iptables -t nat -F WARP_GOOGLE 2>/dev/null || true
    
    # 重启服务
    systemctl restart warp-svc 2>/dev/null
    sleep 3
    
    # 重新连接
    warp-cli --accept-tos connect 2>/dev/null
    sleep 10
    
    # 启动redsocks
    systemctl start redsocks-warp 2>/dev/null
    
    # 重新配置路由
    _setup_routing
    
    echo -e "${GREEN}✓ 修复完成${NC}"
    wk_status
}

# ============================================
# 卸载
# ============================================
wk_uninstall() {
    echo -e "${YELLOW}卸载 G-Everywhere...${NC}"
    
    # 停止服务
    systemctl stop redsocks-warp 2>/dev/null
    systemctl disable redsocks-warp 2>/dev/null
    warp-cli --accept-tos disconnect 2>/dev/null
    
    # 清理iptables
    iptables -t nat -F WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -X WARP_GOOGLE 2>/dev/null || true
    
    # 删除文件
    rm -f /usr/local/bin/wk
    rm -f /usr/local/bin/warp-simple.sh
    rm -f /etc/profile.d/wk-alias.sh
    rm -f /etc/systemd/system/redsocks-warp.service
    rm -f /etc/redsocks-warp.conf
    rm -rf /etc/warp
    
    systemctl daemon-reload
    echo -e "${GREEN}✓ 卸载完成${NC}"
}

# ============================================
# 帮助
# ============================================
wk_help() {
    echo -e "${CYAN}G-Everywhere Worker-Style v5.1${NC}"
    echo -e "极简版，wk=命令快速切换地区\n"
    echo -e "${GREEN}使用方法:${NC}"
    echo -e "  bash $0 install      安装"
    echo -e "  bash $0 us           切换到美国"
    echo -e "  bash $0 sg           切换到新加坡"
    echo -e "  bash $0 jp           切换到日本"
    echo -e "  bash $0 status       查看状态"
    echo -e "  bash $0 test         完整测试"
    echo -e "  bash $0 fix          修复"
    echo -e "  bash $0 uninstall    卸载\n"
    echo -e "${YELLOW}安装后可用命令:${NC}"
    echo -e "  wk=us        快速切换到美国"
    echo -e "  wk=sg        快速切换到新加坡"
    echo -e "  wk status    查看状态"
}

# ============================================
# 主函数
# ============================================
main() {
    # 如果使用wk=格式，直接处理
    if [[ "$1" == *=* ]]; then
        local region="${1#*=}"
        wk_switch "$region"
        return
    fi
    
    # 正常参数处理
    case "${1:-help}" in
        install)    wk_install ;;
        us|jp|sg|de|uk|nl|au|kr|hk|auto)
                    wk_switch "$1" ;;
        status)     wk_status ;;
        test)       wk_test ;;
        fix)        wk_fix ;;
        uninstall)  wk_uninstall ;;
        help|*)     wk_help ;;
    esac
}

# 复制自身到/usr/local/bin以便后续使用
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # 如果不是从/usr/local/bin运行，则复制自身
    if [ "$0" != "/usr/local/bin/warp-simple.sh" ]; then
        cp "$0" /usr/local/bin/warp-simple.sh 2>/dev/null || true
        chmod +x /usr/local/bin/warp-simple.sh 2>/dev/null || true
    fi
    
    main "$@"
fi