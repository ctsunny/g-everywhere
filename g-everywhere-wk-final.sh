#!/bin/bash
# G-Everywhere Worker Final v5.2
# 完整集成版 - wk=快速切换 + 智能地区获取
# 一键安装，极简管理

set -e

# 颜色
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'
NC='\033[0m'; BOLD='\033[1m'

# 路径
WARP_DIR="/etc/warp"
REDSOCKS_CONF="/etc/redsocks-warp.conf"
SERVICE_FILE="/etc/systemd/system/redsocks-warp.service"
GE_WK_BIN="/usr/local/bin/ge-wk"
WK_ALIAS="/etc/profile.d/wk-alias.sh"

# Google IP段
GOOGLE_IPS=(
    8.8.4.0/24   8.8.8.0/24
    34.0.0.0/9
    35.184.0.0/13 35.192.0.0/12 35.224.0.0/12 35.240.0.0/13
    64.233.160.0/19 66.102.0.0/20 66.249.64.0/19
    72.14.192.0/18  74.125.0.0/16  104.132.0.0/14
    108.177.0.0/17  142.250.0.0/15  172.217.0.0/16
    172.253.0.0/16  173.194.0.0/16  209.85.128.0/17
    216.58.192.0/19 216.239.32.0/19
)

# wk=地区系统
declare -A WK_REGIONS=(
    ["auto"]="🌐 自动（任意可用）"
    ["us"]="🇺🇸 美国"
    ["jp"]="🇯🇵 日本"
    ["sg"]="🇸🇬 新加坡"
    ["de"]="🇩🇪 德国"
    ["uk"]="🇬🇧 英国"
    ["nl"]="🇳🇱 荷兰"
    ["au"]="🇦🇺 澳大利亚"
    ["kr"]="🇰🇷 韩国"
    ["hk"]="🇭🇰 香港"
    ["ca"]="🇨🇦 加拿大"
    ["in"]="🇮🇳 印度"
    ["br"]="🇧🇷 巴西"
)

# 地区到端点的映射
declare -A ENDPOINT_MAP=(
    ["auto"]=""
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

# ============================================
# 显示横幅
# ============================================
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
    echo -e "  ${GREEN} Google 解锁 ${NC}│${YELLOW} wk=快速切换 ${NC}│${MAGENTA} 智能地区获取 ${NC}"
    echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${BLUE}G-Everywhere Worker Edition${NC}  │  ${GREEN}v5.2${NC}\n"
}

# ============================================
# 核心: wk= 智能切换系统
# ============================================
wk_system_setup() {
    # 创建ge-wk管理命令
    cat > "$GE_WK_BIN" << 'GEWKEOF'
#!/bin/bash
# ge-wk - G-Everywhere Worker Edition 管理命令

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; NC='\033[0m'

WARP_DIR="/etc/warp"
WK_REGION_FILE="${WARP_DIR}/wk_region"

# 地区显示
declare -A WK_MAP=(
    ["auto"]="🌐 自动"
    ["us"]="🇺🇸 美国"    ["jp"]="🇯🇵 日本"
    ["sg"]="🇸🇬 新加坡"  ["de"]="🇩🇪 德国"
    ["uk"]="🇬🇧 英国"    ["nl"]="🇳🇱 荷兰"
    ["au"]="🇦🇺 澳大利亚" ["kr"]="🇰🇷 韩国"
    ["hk"]="🇭🇰 香港"    ["ca"]="🇨🇦 加拿大"
    ["in"]="🇮🇳 印度"    ["br"]="🇧🇷 巴西"
)

_wk_show_help() {
    echo -e "${CYAN}ge-wk - Worker Edition 管理命令${NC}\n"
    echo -e "${GREEN}使用方法:${NC}"
    echo "  ge-wk start      启动"
    echo "  ge-wk stop       停止"
    echo "  ge-wk status     状态"
    echo "  ge-wk test       完整测试"
    echo "  ge-wk fix        修复"
    echo -e "\n${YELLOW}wk=快速切换:${NC}"
    echo "  wk=us      切换到美国"
    echo "  wk=sg      切换到新加坡"
    echo "  wk=jp      切换到日本"
    echo "  wk=auto    自动模式"
    echo -e "\n${CYAN}快捷命令:${NC}"
    echo "  wk-us      美国"
    echo "  wk-sg      新加坡"
    echo "  wk-jp      日本"
}

_wk_switch_region() {
    local region="$1"
    
    if [ -z "${WK_MAP[$region]}" ] && [ "$region" != "auto" ]; then
        echo -e "${RED}无效地区代码${NC}"
        return 1
    fi
    
    echo -e "${CYAN}切换到: ${WK_MAP[$region]}${NC}"
    
    # 调用主脚本执行切换
    if [ -f "/usr/local/bin/g-everywhere-wk" ]; then
        /usr/local/bin/g-everywhere-wk --wk-switch "$region"
    else
        echo -e "${RED}主脚本未找到${NC}"
    fi
}

_wk_show_status() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}状态信息${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # 地区信息
    if [ -f "$WK_REGION_FILE" ]; then
        local region=$(cat "$WK_REGION_FILE")
        echo -e "地区设置: ${GREEN}${WK_MAP[$region]}${NC}"
    else
        echo -e "地区设置: ${YELLOW}未设置 (默认: auto)${NC}"
    fi
    
    # warp-cli状态
    if command -v warp-cli &>/dev/null; then
        echo -e "\n${YELLOW}warp-cli:${NC}"
        warp-cli status 2>/dev/null | head -3
    fi
    
    # 服务状态
    echo -e "\n${YELLOW}服务状态:${NC}"
    if systemctl is-active redsocks-warp &>/dev/null; then
        echo -e "  ${GREEN}✓ redsocks 运行中${NC}"
    else
        echo -e "  ${RED}✗ redsocks 未运行${NC}"
    fi
    
    # 出口IP
    echo -e "\n${YELLOW}出口IP:${NC}"
    local warp_ip direct_ip
    warp_ip=$(curl -x socks5://127.0.0.1:40000 -s --max-time 8 ip.sb 2>/dev/null)
    direct_ip=$(curl -4 -s --max-time 5 ip.sb 2>/dev/null)
    
    if [ -n "$warp_ip" ]; then
        local info country
        info=$(curl -s --max-time 5 "http://ip-api.com/json/${warp_ip}?lang=zh-CN" 2>/dev/null)
        country=$(echo "$info" | grep -oP '"country":"\K[^"]+' || echo "")
        echo -e "WARP出口: ${GREEN}$warp_ip ($country)${NC}"
    fi
    
    if [ -n "$direct_ip" ]; then
        echo -e "直连出口: ${GREEN}$direct_ip${NC}"
    fi
    
    # Google测试
    echo -e "\n${YELLOW}Google访问:${NC}"
    local code
    code=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" https://www.google.com)
    if [ "$code" = "200" ] || [ "$code" = "301" ]; then
        echo -e "${GREEN}✓ HTTP $code${NC}"
    else
        echo -e "${RED}✗ HTTP $code${NC}"
    fi
    echo ""
}

# 主处理
case "${1:-help}" in
    start)
        systemctl start warp-svc redsocks-warp 2>/dev/null
        warp-cli --accept-tos connect 2>/dev/null
        sleep 5
        echo -e "${GREEN}✓ 已启动${NC}"
        ;;
    stop)
        warp-cli --accept-tos disconnect 2>/dev/null
        systemctl stop redsocks-warp 2>/dev/null
        echo -e "${GREEN}✓ 已停止${NC}"
        ;;
    status)
        _wk_show_status ;;
    test)
        /usr/local/bin/g-everywhere-wk --test ;;
    fix)
        /usr/local/bin/g-everywhere-wk --fix ;;
    
    # wk=处理
    wk=*)
        _wk_switch_region "${1#wk=}" ;;
    
    # 快捷命令
    wk-us)      _wk_switch_region "us" ;;
    wk-sg)      _wk_switch_region "sg" ;;
    wk-jp)      _wk_switch_region "jp" ;;
    wk-de)      _wk_switch_region "de" ;;
    wk-uk)      _wk_switch_region "uk" ;;
    wk-nl)      _wk_switch_region "nl" ;;
    wk-au)      _wk_switch_region "au" ;;
    wk-kr)      _wk_switch_region "kr" ;;
    wk-hk)      _wk_switch_region "hk" ;;
    wk-ca)      _wk_switch_region "ca" ;;
    wk-in)      _wk_switch_region "in" ;;
    wk-br)      _wk_switch_region "br" ;;
    wk-auto)    _wk_switch_region "auto" ;;
    
    # 帮助
    help|*)
        _wk_show_help ;;
esac
GEWKEOF

    chmod +x "$GE_WK_BIN"
    
    # 创建wk别名文件
    cat > "$WK_ALIAS" << 'ALIASEOF'
#!/bin/bash
# wk命令别名

alias ge-wk='/usr/local/bin/ge-wk'
alias wk='ge-wk'

# wk=快速切换别名
alias wk=us='ge-wk wk=us'
alias wk=sg='ge-wk wk=sg'
alias wk=jp='ge-wk wk=jp'
alias wk=de='ge-wk wk=de'
alias wk=uk='ge-wk wk=uk'
alias wk=nl='ge-wk wk=nl'
alias wk=au='ge-wk wk=au'
alias wk=kr='ge-wk wk=kr'
alias wk=hk='ge-wk wk=hk'
alias wk=ca='ge-wk wk=ca'
alias wk=in='ge-wk wk=in'
alias wk=br='ge-wk wk=br'
alias wk=auto='ge-wk wk=auto'

# 快捷命令别名
alias wk-us='ge-wk wk=us'
alias wk-sg='ge-wk wk=sg'
alias wk-jp='ge-wk wk=jp'
alias wk-de='ge-wk wk=de'
alias wk-uk='ge-wk wk=uk'
alias wk-nl='ge-wk wk=nl'
alias wk-au='ge-wk wk=au'
alias wk-kr='ge-wk wk=kr'
alias wk-hk='ge-wk wk=hk'
alias wk-ca='ge-wk wk=ca'
alias wk-in='ge-wk wk=in'
alias wk-br='ge-wk wk=br'
alias wk-auto='ge-wk wk=auto'
ALIASEOF

    chmod +x "$WK_ALIAS"
    
    # 应用到当前shell
    source "$WK_ALIAS" 2>/dev/null || true
    
    echo -e "${GREEN}✓ wk=命令系统已配置${NC}"
}

# ============================================
# 智能地区获取引擎
# ============================================
wk_smart_region_engine() {
    local target="$1"
    local endpoint="${ENDPOINT_MAP[$target]}"
    
    echo -e "${CYAN}智能获取地区: ${WK_REGIONS[$target]}${NC}"
    
    # 停止当前连接
    warp-cli --accept-tos disconnect 2>/dev/null
    systemctl stop warp-svc 2>/dev/null
    sleep 2
    
    # 重启服务
    systemctl start warp-svc 2>/dev/null
    sleep 3
    
    # 设置入口端点
    if [ -n "$endpoint" ]; then
        warp-cli --accept-tos set-custom-endpoint "${endpoint}:2408" 2>/dev/null
        echo -e "  入口节点: ${YELLOW}$endpoint${NC}"
    fi
    
    # 智能重试机制
    local max_attempts=8
    local best_ip="" best_country="" best_attempt=0
    
    for attempt in $(seq 1 $max_attempts); do
        echo -e "  尝试 $attempt/$max_attempts"
        
        # 智能清理策略
        if [ $attempt -eq 1 ] || [ $((attempt % 3)) -eq 0 ]; then
            warp-cli --accept-tos registration delete 2>/dev/null || true
            sleep 1
        fi
        
        # 注册和连接
        warp-cli --accept-tos register 2>/dev/null || true
        warp-cli --accept-tos mode proxy 2>/dev/null
        warp-cli --accept-tos connect 2>/dev/null
        
        # 动态等待时间（首次等待长，后续短）
        local wait_time=$((10 + attempt * 2))
        [ $wait_time -gt 25 ] && wait_time=25
        sleep $wait_time
        
        # 检查连接
        if ! warp-cli status 2>/dev/null | grep -qi "connected"; then
            echo -e "    ${RED}连接失败${NC}"
            continue
        fi
        
        # 获取出口信息
        local exit_ip ipinfo country_code country city
        exit_ip=$(curl -x socks5://127.0.0.1:40000 -s --max-time 10 ip.sb 2>/dev/null)
        
        if [ -z "$exit_ip" ]; then
            echo -e "    ${RED}出口IP获取失败${NC}"
            continue
        fi
        
        ipinfo=$(curl -s --max-time 8 "http://ip-api.com/json/${exit_ip}?lang=zh-CN" 2>/dev/null)
        country_code=$(echo "$ipinfo" | grep -oP '"countryCode":"\K[^"]+' || echo "")
        country=$(echo "$ipinfo" | grep -oP '"country":"\K[^"]+' || echo "")
        city=$(echo "$ipinfo" | grep -oP '"city":"\K[^"]+' || echo "")
        
        echo -e "    出口: ${CYAN}$exit_ip ($country_code)${NC}"
        
        # 如果是auto模式，使用第一个成功的
        if [ "$target" = "auto" ]; then
            best_ip="$exit_ip"
            best_country="$country"
            best_attempt=$attempt
            break
        fi
        
        # 检查是否匹配目标
        if [ "$country_code" = "$target" ]; then
            best_ip="$exit_ip"
            best_country="$country"
            best_attempt=$attempt
            echo -e "    ${GREEN}✓ 成功获取目标地区！${NC}"
            break
        fi
        
        # 记录最佳匹配
        if [ -z "$best_ip" ] || [ $attempt -lt $best_attempt ]; then
            best_ip="$exit_ip"
            best_country="$country"
            best_attempt=$attempt
        fi
    done
    
    # 保存结果
    if [ -n "$best_ip" ]; then
        printf '%s\n%s\n' "$best_ip" "$best_country" > "${WARP_DIR}/exit_info"
        echo "$target" > "${WARP_DIR}/wk_region"
        echo -e "  ${GREEN}✓ 最终出口: $best_ip ($best_country)${NC}"
        
        if [ "$target" != "auto" ] && [ $best_attempt -eq $max_attempts ]; then
            echo -e "  ${YELLOW}⚠ 未能获取精确地区，使用当前最佳出口${NC}"
        fi
    else
        echo -e "  ${RED}✗ 地区获取失败${NC}"
        return 1
    fi
    
    return 0
}

# ============================================
# 安装warp-cli和依赖
# ============================================
install_warp_deps() {
    local os="$1"
    local arch="$2"
    
    echo -e "${CYAN}安装系统依赖...${NC}"
    
    case $os in
        ubuntu|debian)
            apt-get update -y >/dev/null 2>&1
            apt-get install -y curl wget iptables redsocks >/dev/null 2>&1
            systemctl stop redsocks 2>/dev/null
            systemctl disable redsocks 2>/dev/null
            ;;
        centos|rhel|rocky|almalinux|fedora)
            dnf install -y epel-release >/dev/null 2>&1
            dnf install -y curl wget iptables redsocks >/dev/null 2>&1
            ;;
    esac
    
    echo -e "${CYAN}安装 warp-cli...${NC}"
    
    case $os in
        ubuntu|debian)
            local codename
            codename=$(. /etc/os-release && echo "$VERSION_CODENAME")
            curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg \
                | gpg --dearmor -o /usr/share/keyrings/cloudflare-warp.gpg 2>/dev/null
            echo "deb [arch=$arch signed-by=/usr/share/keyrings/cloudflare-warp.gpg] \
                https://pkg.cloudflareclient.com/ $codename main" \
                > /etc/apt/sources.list.d/cloudflare.list
            apt-get update -y >/dev/null 2>&1
            apt-get install -y cloudflare-warp >/dev/null 2>&1
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
            dnf install -y cloudflare-warp >/dev/null 2>&1
            ;;
    esac
    
    command -v warp-cli &>/dev/null || { echo -e "${RED}warp-cli安装失败${NC}"; return 1; }
    command -v redsocks &>/dev/null || { echo -e "${RED}redsocks安装失败${NC}"; return 1; }
    
    echo -e "${GREEN}✓ 依赖安装完成${NC}"
    return 0
}

# ============================================
# 配置透明代理
# ============================================
setup_transparent_proxy() {
    echo -e "${CYAN}配置透明代理...${NC}"
    
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
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Redsocks WARP Transparent Proxy
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
    systemctl enable redsocks-warp >/dev/null 2>&1
    systemctl start redsocks-warp
    
    # iptables规则
    _setup_iptables_rules
    
    echo -e "${GREEN}✓ 透明代理配置完成${NC}"
}

_setup_iptables_rules() {
    # 清理旧规则
    iptables -t nat -F WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -X WARP_GOOGLE 2>/dev/null || true
    
    # 创建规则链
    iptables -t nat -N WARP_GOOGLE
    
    # 排除本地网络
    local skip_nets=(127.0.0.0/8 10.0.0.0/8 192.168.0.0/16 172.16.0.0/12 100.64.0.0/10)
    for net in "${skip_nets[@]}"; do
        iptables -t nat -A WARP_GOOGLE -d "$net" -j RETURN
    done
    
    # Google IP走代理
    for ip in "${GOOGLE_IPS[@]}"; do
        iptables -t nat -A WARP_GOOGLE -d "$ip" -p tcp -j REDIRECT --to-ports 12345
    done
    
    # 应用到系统
    iptables -t nat -A OUTPUT -j WARP_GOOGLE
    iptables -t nat -A PREROUTING -j WARP_GOOGLE
    
    echo -e "  ${GREEN}✓ iptables规则已配置${NC}"
}

# ============================================
# 测试功能
# ============================================
run_tests() {
    echo -e "${CYAN}运行测试...${NC}"
    
    local tests_passed=0
    local total_tests=4
    
    # 测试1: warp-cli连接
    echo -e "1. warp-cli连接测试"
    if warp-cli status 2>/dev/null | grep -qi "connected"; then
        echo -e "  ${GREEN}✓ 通过${NC}"
        ((tests_passed++))
    else
        echo -e "  ${RED}✗ 失败${NC}"
    fi
    
    # 测试2: SOCKS5代理
    echo -e "2. SOCKS5代理测试"
    local socks_ip
    socks_ip=$(curl -x socks5://127.0.0.1:40000 -s --max-time 10 ip.sb 2>/dev/null)
    if [ -n "$socks_ip" ]; then
        echo -e "  ${GREEN}✓ 通过 ($socks_ip)${NC}"
        ((tests_passed++))
    else
        echo -e "  ${RED}✗ 失败${NC}"
    fi
    
    # 测试3: redsocks服务
    echo -e "3. redsocks服务测试"
    if systemctl is-active redsocks-warp &>/dev/null; then
        echo -e "  ${GREEN}✓ 通过${NC}"
        ((tests_passed++))
    else
        echo -e "  ${RED}✗ 失败${NC}"
    fi
    
    # 测试4: Google访问
    echo -e "4. Google访问测试"
    local google_code
    google_code=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" https://www.google.com)
    if [ "$google_code" = "200" ] || [ "$google_code" = "301" ]; then
        echo -e "  ${GREEN}✓ 通过 (HTTP $google_code)${NC}"
        ((tests_passed++))
    else
        echo -e "  ${RED}✗ 失败 (HTTP $google_code)${NC}"
    fi
    
    echo -e "\n${CYAN}测试结果: $tests_passed/$total_tests 通过${NC}"
    
    if [ $tests_passed -eq $total_tests ]; then
        echo -e "${GREEN}✓ 所有测试通过！${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠ 部分测试失败，运行 ge-wk fix 修复${NC}"
        return 1
    fi
}

# ============================================
# 主安装函数
# ============================================
main_install() {
    show_banner
    
    # 检查root
    [[ $EUID -ne 0 ]] && { echo -e "${RED}请用 root 用户运行${NC}"; exit 1; }
    
    # 检测系统
    local os arch
    [ -f /etc/os-release ] && . /etc/os-release && os=$ID
    arch=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
    
    echo -e "系统: ${YELLOW}$os ($arch)${NC}"
    
    # 选择地区
    echo -e "\n${CYAN}选择目标地区:${NC}"
    echo -e "${YELLOW}提示: 安装后可使用 wk=命令快速切换${NC}\n"
    
    local i=1
    for code in "${!WK_REGIONS[@]}"; do
        printf "  ${GREEN}%2d.${NC} %s\n" "$i" "${WK_REGIONS[$code]}"
        ((i++))
    done
    
    echo ""
    read -rp "选择 [1-${#WK_REGIONS[@]}] (默认1): " choice
    choice=${choice:-1}
    
    local region_codes=("${!WK_REGIONS[@]}")
    local selected="${region_codes[$((choice-1))]}"
    
    if [ -z "$selected" ]; then
        selected="auto"
    fi
    
    echo -e "${GREEN}✓ 选择: ${WK_REGIONS[$selected]}${NC}"
    
    # 安装依赖
    echo -e "\n${CYAN}[1/4] 安装依赖...${NC}"
    install_warp_deps "$os" "$arch" || exit 1
    
    # 配置wk=命令系统
    echo -e "${CYAN}[2/4] 配置wk=命令系统...${NC}"
    wk_system_setup
    
    # 配置透明代理
    echo -e "${CYAN}[3/4] 配置透明代理...${NC}"
    setup_transparent_proxy
    
    # 获取目标地区
    echo -e "${CYAN}[4/4] 获取目标地区...${NC}"
    wk_smart_region_engine "$selected"
    
    # 运行测试
    echo -e "\n${CYAN}最终验证...${NC}"
    run_tests
    
    # 完成信息
    echo -e "\n${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✓ 安装完成！${NC}"
    echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    echo -e "\n${CYAN}核心命令:${NC}"
    echo -e "  ${GREEN}wk=us${NC}       切换到美国"
    echo -e "  ${GREEN}wk=sg${NC}       切换到新加坡"
    echo -e "  ${GREEN}wk=jp${NC}       切换到日本"
    echo -e "  ${GREEN}ge-wk status${NC} 查看状态"
    echo -e "  ${GREEN}ge-wk test${NC}   完整测试"
    echo -e "  ${GREEN}ge-wk fix${NC}    修复问题"
    
    echo -e "\n${YELLOW}重新登录或运行以下命令生效:${NC}"
    echo -e "  source /etc/profile.d/wk-alias.sh"
    
    # 显示当前出口
    if [ -f "${WARP_DIR}/exit_info" ]; then
        local exit_ip country
        read -r exit_ip country < "${WARP_DIR}/exit_info"
        echo -e "\n${CYAN}当前出口: ${GREEN}$exit_ip ($country)${NC}"
    fi
}

# ============================================
# 卸载函数
# ============================================
main_uninstall() {
    echo -e "${YELLOW}卸载 G-Everywhere Worker Edition...${NC}"
    
    # 停止服务
    systemctl stop redsocks-warp 2>/dev/null
    systemctl disable redsocks-warp 2>/dev/null
    warp-cli --accept-tos disconnect 2>/dev/null
    
    # 清理iptables
    iptables -t nat -F WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -X WARP_GOOGLE 2>/dev/null || true
    
    # 删除文件
    rm -f "$GE_WK_BIN"
    rm -f "$WK_ALIAS"
    rm -f "$REDSOCKS_CONF"
    rm -f "$SERVICE_FILE"
    rm -f /usr/local/bin/g-everywhere-wk
    rm -rf "$WARP_DIR"
    
    systemctl daemon-reload
    echo -e "${GREEN}✓ 卸载完成${NC}"
}

# ============================================
# 主函数
# ============================================
main() {
    # 复制自身到/usr/local/bin
    if [ "$0" != "/usr/local/bin/g-everywhere-wk" ]; then
        cp "$0" /usr/local/bin/g-everywhere-wk 2>/dev/null || true
        chmod +x /usr/local/bin/g-everywhere-wk 2>/dev/null || true
    fi
    
    case "${1:-}" in
        --install)
            main_install ;;
        --uninstall)
            main_uninstall ;;
        --wk-switch)
            wk_smart_region_engine "${2:-auto}" ;;
        --test)
            run_tests ;;
        --fix)
            echo -e "${CYAN}修复中...${NC}"
            systemctl restart warp-svc redsocks-warp 2>/dev/null
            warp-cli --accept-tos disconnect 2>/dev/null
            sleep 2
            warp-cli --accept-tos connect 2>/dev/null
            sleep 10
            echo -e "${GREEN}✓ 修复完成${NC}"
            ;;
        --help)
            show_banner
            echo -e "${CYAN}使用方法:${NC}"
            echo "  $0 --install       安装"
            echo "  $0 --uninstall     卸载"
            echo "  $0 --wk-switch REGION  切换地区"
            echo "  $0 --test          运行测试"
            echo "  $0 --fix           修复"
            echo -e "\n${YELLOW}直接运行以显示交互菜单${NC}"
            ;;
        *)
            show_banner
            echo -e "\n${YELLOW}请选择操作:${NC}\n"
            echo -e "  ${GREEN}1.${NC} 安装"
            echo -e "  ${GREEN}2.${NC} 切换地区"
            echo -e "  ${GREEN}3.${NC} 运行测试"
            echo -e "  ${GREEN}4.${NC} 修复"
            echo -e "  ${GREEN}5.${NC} 卸载"
            echo -e "  ${GREEN}0.${NC} 退出"
            echo ""
            read -rp "选择 [0-5]: " choice
            
            case $choice in
                1) main_install ;;
                2) 
                    echo -e "\n${CYAN}选择地区:${NC}"
                    local i=1
                    for code in "${!WK_REGIONS[@]}"; do
                        printf "  ${GREEN}%d.${NC} %s\n" "$i" "${WK_REGIONS[$code]}"
                        ((i++))
                    done
                    echo ""
                    read -rp "选择 [1-${#WK_REGIONS[@]}]: " region_choice
                    local regions=("${!WK_REGIONS[@]}")
                    local target="${regions[$((region_choice-1))]}"
                    wk_smart_region_engine "${target:-auto}"
                    ;;
                3) run_tests ;;
                4) 
                    echo -e "${CYAN}修复中...${NC}"
                    systemctl restart warp-svc redsocks-warp 2>/dev/null
                    warp-cli --accept-tos disconnect 2>/dev/null
                    sleep 2
                    warp-cli --accept-tos connect 2>/dev/null
                    sleep 10
                    echo -e "${GREEN}✓ 修复完成${NC}"
                    ;;
                5) 
                    echo -e "${YELLOW}确定要卸载吗？(y/N): ${NC}"
                    read -r confirm
                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                        main_uninstall
                    else
                        echo -e "${YELLOW}取消卸载${NC}"
                    fi
                    ;;
                0) echo -e "${GREEN}Bye!${NC}" ;;
                *) echo -e "${RED}无效选择${NC}" ;;
            esac
            ;;
    esac
}

# 执行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi