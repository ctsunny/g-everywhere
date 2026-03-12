#!/bin/bash
# G-Everywhere Worker Edition v5.1
# 基于 wk= 命令的地区切换机制，优化 warp-cli 地区获取
# https://github.com/ctsunny/g-everywhere

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'
NC='\033[0m'; BOLD='\033[1m'

WARP_DIR="/etc/warp"
REGION_FILE="${WARP_DIR}/wk_region"
REDSOCKS_CONF="/etc/redsocks-warp.conf"

# Google IP 段
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

# 地区映射表
declare -A WK_REGIONS=(
    ["auto"]="🌐 自动"
    ["us"]="🇺🇸 美国"       ["jp"]="🇯🇵 日本"
    ["sg"]="🇸🇬 新加坡"     ["de"]="🇩🇪 德国"
    ["uk"]="🇬🇧 英国"       ["nl"]="🇳🇱 荷兰"
    ["au"]="🇦🇺 澳大利亚"   ["kr"]="🇰🇷 韩国"
    ["hk"]="🇭🇰 香港"       ["ca"]="🇨🇦 加拿大"
    ["in"]="🇮🇳 印度"       ["br"]="🇧🇷 巴西"
)

# 国家代码映射（用于匹配 ip-api.com）
declare -A REGION_CC=(
    ["auto"]=""  ["us"]="US"  ["jp"]="JP"  ["sg"]="SG"
    ["de"]="DE"  ["uk"]="GB"  ["nl"]="NL"  ["au"]="AU"
    ["kr"]="KR"  ["hk"]="HK"  ["ca"]="CA"  ["in"]="IN"  ["br"]="BR"
)

# ============================================================
# 核心函数：wk= 地区设置
# ============================================================
wk_set_region() {
    local target="$1"
    
    if [ -z "$target" ]; then
        echo -e "${RED}错误: 请指定地区代码，如 wk=us${NC}"
        return 1
    fi
    
    # 检查地区代码是否有效
    if [[ -z "${WK_REGIONS[$target]}" && "$target" != "auto" ]]; then
        echo -e "${RED}错误: 无效的地区代码 '$target'${NC}"
        echo -e "${YELLOW}可用地区: auto, us, jp, sg, de, uk, nl, au, kr, hk, ca, in, br${NC}"
        return 1
    fi
    
    # 保存地区设置
    mkdir -p "${WARP_DIR}"
    echo "$target" > "$REGION_FILE"
    echo -e "${GREEN}✓ 地区设置为: ${WK_REGIONS[$target]}${NC}"
    
    # 如果已安装，自动切换地区
    if command -v warp-cli &>/dev/null; then
        echo -e "${YELLOW}正在切换到目标地区...${NC}"
        _wk_switch_region "$target"
    fi
}

_wk_switch_region() {
    local target="$1"
    local target_cc="${REGION_CC[$target]}"
    
    # 停止当前连接
    warp-cli --accept-tos disconnect 2>/dev/null
    systemctl stop warp-svc 2>/dev/null
    sleep 2
    
    # 启动服务
    systemctl start warp-svc 2>/dev/null
    sleep 3
    
    # 设置自定义端点（如果指定了地区）
    if [ "$target" != "auto" ]; then
        local endpoint_ip=""
        case "$target" in
            us) endpoint_ip="162.159.193.1" ;;
            jp) endpoint_ip="162.159.193.2" ;;
            sg) endpoint_ip="162.159.193.3" ;;
            de) endpoint_ip="162.159.193.4" ;;
            uk) endpoint_ip="162.159.193.5" ;;
            nl) endpoint_ip="162.159.193.6" ;;
            au) endpoint_ip="162.159.193.7" ;;
            kr) endpoint_ip="162.159.193.8" ;;
            hk) endpoint_ip="162.159.193.9" ;;
            ca) endpoint_ip="162.159.193.10" ;;
            in) endpoint_ip="162.159.193.11" ;;
            br) endpoint_ip="162.159.193.12" ;;
            *) endpoint_ip="162.159.193.1" ;;
        esac
        
        warp-cli --accept-tos set-custom-endpoint "${endpoint_ip}:2408" 2>/dev/null
        echo -e "  入口节点: ${CYAN}$endpoint_ip ($target)${NC}"
    fi
    
    # 尝试多次获取目标地区
    _wk_try_connect "$target" "$target_cc"
}

_wk_try_connect() {
    local target="$1"
    local target_cc="$2"
    local max_attempts=8
    local success=0
    
    echo -e "  尝试获取目标地区... (最多 $max_attempts 次)"
    
    for attempt in $(seq 1 $max_attempts); do
        echo -e "  尝试 ${attempt}/${max_attempts}..."
        
        # 删除旧注册（第2次起）
        if [ "$attempt" -gt 1 ]; then
            warp-cli --accept-tos registration delete 2>/dev/null || true
            sleep 1
        fi
        
        # 新注册
        warp-cli --accept-tos register 2>/dev/null || true
        sleep 1
        warp-cli --accept-tos mode proxy 2>/dev/null
        warp-cli --accept-tos proxy port 40000 2>/dev/null
        warp-cli --accept-tos connect 2>/dev/null
        sleep 12  # 给WARP更多时间分配IP
        
        # 检查连接状态
        if ! warp-cli status 2>/dev/null | grep -qi "connected"; then
            echo -e "    ${RED}连接失败，继续尝试...${NC}"
            continue
        fi
        
        # 获取出口IP信息
        local exit_ip country country_code city
        exit_ip=$(curl -x socks5://127.0.0.1:40000 -s --max-time 10 ip.sb 2>/dev/null)
        
        if [ -z "$exit_ip" ]; then
            echo -e "    ${RED}SOCKS5无响应，继续尝试...${NC}"
            continue
        fi
        
        # 查询地理位置
        local ipinfo
        ipinfo=$(curl -s --max-time 8 "http://ip-api.com/json/${exit_ip}?lang=zh-CN" 2>/dev/null)
        country_code=$(echo "$ipinfo" | grep -oP '"countryCode":"\K[^"]+' || echo "未知")
        country=$(echo "$ipinfo" | grep -oP '"country":"\K[^"]+' || echo "未知")
        city=$(echo "$ipinfo" | grep -oP '"city":"\K[^"]+' || echo "")
        
        echo -e "    当前出口: ${CYAN}$exit_ip ($country $city)${NC}"
        
        # 检查是否匹配目标地区
        if [ -z "$target_cc" ] || [ "$country_code" = "$target_cc" ]; then
            echo -e "    ${GREEN}✓ 成功获取目标地区！${NC}"
            
            # 保存出口信息
            printf '%s\n%s\n%s\n' "$exit_ip" "$country" "$city" > "${WARP_DIR}/exit_info"
            printf '%s\n%s %s\n' "$target" "$country_code" "$country" > "${WARP_DIR}/wk_info"
            
            success=1
            break
        fi
        
        echo -e "    ${YELLOW}目标: $target_cc, 当前: $country_code, 继续尝试...${NC}"
    done
    
    if [ $success -eq 0 ]; then
        echo -e "  ${YELLOW}⚠ 未能获取目标地区 $target_cc，使用当前出口${NC}"
        echo -e "  ${YELLOW}注: Google/Gemini 在此出口下依然可用${NC}"
    fi
    
    return $success
}

# ============================================================
# 显示当前地区状态
# ============================================================
wk_status() {
    if [ -f "$REGION_FILE" ]; then
        local region=$(cat "$REGION_FILE")
        echo -e "${CYAN}当前地区设置: ${GREEN}${WK_REGIONS[$region]}${NC}"
    else
        echo -e "${YELLOW}地区未设置 (默认: auto)${NC}"
    fi
    
    if [ -f "${WARP_DIR}/wk_info" ]; then
        local region_code country_code country
        read -r region_code country_code country < "${WARP_DIR}/wk_info"
        echo -e "${CYAN}出口地区: ${GREEN}$country_code - $country${NC}"
    fi
    
    if command -v warp-cli &>/dev/null; then
        echo -e "${CYAN}warp-cli 状态:${NC}"
        warp-cli status 2>/dev/null | head -3
    fi
}

# ============================================================
# 快速切换命令
# ============================================================
wk_auto()   { wk_set_region "auto"; }
wk_us()     { wk_set_region "us"; }
wk_jp()     { wk_set_region "jp"; }
wk_sg()     { wk_set_region "sg"; }
wk_de()     { wk_set_region "de"; }
wk_uk()     { wk_set_region "uk"; }
wk_nl()     { wk_set_region "nl"; }
wk_au()     { wk_set_region "au"; }
wk_kr()     { wk_set_region "kr"; }
wk_hk()     { wk_set_region "hk"; }
wk_ca()     { wk_set_region "ca"; }
wk_in()     { wk_set_region "in"; }
wk_br()     { wk_set_region "br"; }

# ============================================================
# 主安装函数（集成wk=功能）
# ============================================================
wk_install() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${GREEN}G-Everywhere Worker Edition 安装${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # 检查root权限
    [[ $EUID -ne 0 ]] && { echo -e "${RED}请用 root 运行${NC}"; return 1; }
    
    # 检测系统
    local OS ARCH
    [ -f /etc/os-release ] && . /etc/os-release && OS=$ID || { echo -e "${RED}无法检测系统${NC}"; return 1; }
    ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')
    
    echo -e "${CYAN}系统: $OS ($ARCH)${NC}"
    
    # 选择地区
    echo -e "\n${CYAN}请选择目标地区:${NC}"
    echo -e "${YELLOW}提示: 安装后可使用 wk=命令快速切换${NC}\n"
    
    local i=1
    for code in "${!WK_REGIONS[@]}"; do
        printf "  ${GREEN}%2d.${NC} %s\n" "$i" "${WK_REGIONS[$code]}"
        ((i++))
    done
    
    echo ""
    read -rp "选择 [1-${#WK_REGIONS[@]}] (默认1): " choice
    choice=${choice:-1}
    
    local region_list=("${!WK_REGIONS[@]}")
    local target_region="${region_list[$((choice-1))]}"
    
    if [ -z "$target_region" ]; then
        target_region="auto"
    fi
    
    echo -e "${GREEN}✓ 选择: ${WK_REGIONS[$target_region]}${NC}"
    
    # 安装依赖
    echo -e "\n${CYAN}[1/4] 安装依赖...${NC}"
    case $OS in
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
    
    # 安装warp-cli
    echo -e "${CYAN}[2/4] 安装 warp-cli...${NC}"
    case $OS in
        ubuntu|debian)
            local CODENAME
            CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
            curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg \
                | gpg --yes --dearmor \
                -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg 2>/dev/null
            printf 'deb [arch=%s signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ %s main\n' \
                "$ARCH" "$CODENAME" \
                > /etc/apt/sources.list.d/cloudflare-client.list
            apt-get update -y >/dev/null 2>&1
            apt-get install -y cloudflare-warp >/dev/null 2>&1
            ;;
        centos|rhel|rocky|almalinux|fedora)
            curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg \
                -o /etc/pki/rpm-gpg/cloudflare-warp.gpg
            printf '[cloudflare-warp]\nname=Cloudflare WARP\nbaseurl=https://pkg.cloudflareclient.com/rpm\nenabled=1\ngpgcheck=1\ngpgkey=file:///etc/pki/rpm-gpg/cloudflare-warp.gpg\n' \
                > /etc/yum.repos.d/cloudflare-warp.repo
            dnf install -y cloudflare-warp >/dev/null 2>&1
            ;;
    esac
    
    command -v warp-cli &>/dev/null || { echo -e "${RED}warp-cli 安装失败${NC}"; return 1; }
    command -v redsocks &>/dev/null || { echo -e "${RED}redsocks 安装失败${NC}"; return 1; }
    
    echo -e "${GREEN}✓ 依赖安装完成${NC}"
    
    # 创建wk命令
    _wk_create_commands
    
    # 设置地区
    echo -e "${CYAN}[3/4] 设置目标地区...${NC}"
    wk_set_region "$target_region"
    
    # 安装redsocks服务
    echo -e "${CYAN}[4/4] 配置透明代理...${NC}"
    _wk_setup_redsocks
    _wk_setup_routing
    
    echo -e "\n${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✓ 安装完成！${NC}"
    echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    echo -e "\n${CYAN}快速命令:${NC}"
    echo -e "  ${GREEN}wk=us${NC}      切换到美国"
    echo -e "  ${GREEN}wk=sg${NC}      切换到新加坡"
    echo -e "  ${GREEN}wk=jp${NC}      切换到日本"
    echo -e "  ${GREEN}wk status${NC}  查看状态"
    echo -e "  ${GREEN}wk help${NC}    显示帮助"
    
    echo -e "\n${CYAN}测试Google访问:${NC}"
    curl -s --max-time 8 -o /dev/null -w "Google HTTP: %{http_code}\n" https://www.google.com
}

_wk_setup_redsocks() {
    # redsocks配置
    printf 'base {\n  log_debug = off;\n  log_info = off;\n  daemon = off;\n  redirector = iptables;\n}\nredsocks {\n  local_ip = 127.0.0.1;\n  local_port = 12345;\n  ip = 127.0.0.1;\n  port = 40000;\n  type = socks5;\n}\n' \
        > "${REDSOCKS_CONF}"
    
    # systemd服务
    cat > /etc/systemd/system/redsocks-warp.service << EOF
[Unit]
Description=Redsocks WARP Transparent Proxy
After=network.target

[Service]
Type=simple
ExecStart=/usr/sbin/redsocks -c ${REDSOCKS_CONF}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable redsocks-warp 2>/dev/null
    systemctl start redsocks-warp
    sleep 2
}

_wk_setup_routing() {
    # 清理旧规则
    iptables -t nat -D OUTPUT    -j WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -D PREROUTING -j WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -F WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -X WARP_GOOGLE 2>/dev/null || true
    
    # 创建新规则
    iptables -t nat -N WARP_GOOGLE
    
    # 排除本地网络
    local SKIP_NETS=(127.0.0.0/8 10.0.0.0/8 192.168.0.0/16 172.16.0.0/12 100.64.0.0/10)
    for net in "${SKIP_NETS[@]}"; do
        iptables -t nat -A WARP_GOOGLE -d "$net" -j RETURN
    done
    
    # Google IP段走代理
    for ip in "${GOOGLE_IPS[@]}"; do
        iptables -t nat -A WARP_GOOGLE -d "$ip" -p tcp -j REDIRECT --to-ports 12345
    done
    
    iptables -t nat -A OUTPUT    -j WARP_GOOGLE
    iptables -t nat -A PREROUTING -j WARP_GOOGLE
    
    echo -e "${GREEN}✓ 路由规则已配置${NC}"
}

_wk_create_commands() {
    # 创建wk命令脚本
    cat > /usr/local/bin/wk << 'WKEOF'
#!/bin/bash
# wk - G-Everywhere Worker Edition 管理命令

WARP_DIR="/etc/warp"
REGION_FILE="${WARP_DIR}/wk_region"

# 颜色定义
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; NC='\033[0m'

# 地区映射
declare -A WK_REGIONS=(
    ["auto"]="🌐 自动"
    ["us"]="🇺🇸 美国"       ["jp"]="🇯🇵 日本"
    ["sg"]="🇸🇬 新加坡"     ["de"]="🇩🇪 德国"
    ["uk"]="🇬🇧 英国"       ["nl"]="🇳🇱 荷兰"
    ["au"]="🇦🇺 澳大利亚"   ["kr"]="🇰🇷 韩国"
    ["hk"]="🇭🇰 香港"       ["ca"]="🇨🇦 加拿大"
    ["in"]="🇮🇳 印度"       ["br"]="🇧🇷 巴西"
)

_wk_set_region() {
    local target="$1"
    
    if [ -z "$target" ]; then
        echo -e "${RED}错误: 请指定地区代码${NC}"
        return 1
    fi
    
    if [[ -z "${WK_REGIONS[$target]}" && "$target" != "auto" ]]; then
        echo -e "${RED}错误: 无效的地区代码 '$target'${NC}"
        echo -e "${YELLOW}可用地区: auto, us, jp, sg, de, uk, nl, au, kr, hk, ca, in, br${NC}"
        return 1
    fi
    
    mkdir -p "${WARP_DIR}"
    echo "$target" > "$REGION_FILE"
    echo -e "${GREEN}✓ 地区设置为: ${WK_REGIONS[$target]}${NC}"
    
    # 调用主脚本切换地区
    if [ -f "/usr/local/bin/warp-worker.sh" ]; then
        bash /usr/local/bin/warp-worker.sh --switch "$target"
    fi
}

_wk_show_status() {
    if [ -f "$REGION_FILE" ]; then
        local region=$(cat "$REGION_FILE")
        echo -e "${CYAN}当前地区: ${GREEN}${WK_REGIONS[$region]}${NC}"
    else
        echo -e "${YELLOW}地区未设置 (默认: auto)${NC}"
    fi
    
    if [ -f "${WARP_DIR}/exit_info" ]; then
        local exit_ip country city
        read -r exit_ip country city < "${WARP_DIR}/exit_info"
        echo -e "${CYAN}出口IP: ${GREEN}$exit_ip ($country $city)${NC}"
    fi
    
    # 测试Google访问
    echo -e "${CYAN}Google访问测试:${NC}"
    local code
    code=$(curl -s --max-time 8 -o /dev/null -w "%{http_code}" https://www.google.com)
    if [ "$code" = "200" ] || [ "$code" = "301" ]; then
        echo -e "  ${GREEN}✓ HTTP $code${NC}"
    else
        echo -e "  ${RED}✗ HTTP $code${NC}"
    fi
}

_wk_show_help() {
    echo -e "${CYAN}wk - G-Everywhere Worker Edition 管理命令${NC}\n"
    echo -e "${GREEN}使用方式:${NC}"
    echo -e "  wk=us          切换到美国"
    echo -e "  wk=sg          切换到新加坡"
    echo -e "  wk=jp          切换到日本"
    echo -e "  wk status      查看状态"
    echo -e "  wk help        显示帮助"
    echo -e "  wk install     安装程序"
    echo -e "  wk uninstall   卸载程序\n"
    echo -e "${YELLOW}地区代码:${NC}"
    echo -e "  auto 自动  us美国  jp日本  sg新加坡"
    echo -e "  de德国  uk英国  nl荷兰  au澳大利亚"
    echo -e "  kr韩国  hk香港  ca加拿大  in印度  br巴西"
}

_wk_uninstall() {
    echo -e "${CYAN}卸载 G-Everywhere Worker Edition...${NC}"
    
    # 停止服务
    systemctl stop redsocks-warp 2>/dev/null
    systemctl disable redsocks-warp 2>/dev/null
    warp-cli --accept-tos disconnect 2>/dev/null
    
    # 清理iptables规则
    iptables -t nat -D OUTPUT -j WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -D PREROUTING -j WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -F WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -X WARP_GOOGLE 2>/dev/null || true
    
    # 删除文件
    rm -f /etc/systemd/system/redsocks-warp.service
    rm -f /etc/redsocks-warp.conf
    rm -f /usr/local/bin/wk
    rm -f /usr/local/bin/warp-worker.sh
    rm -rf /etc/warp
    
    systemctl daemon-reload
    echo -e "${GREEN}✓ 卸载完成${NC}"
}

# 主处理逻辑
case "$1" in
    status)
        _wk_show_status ;;
    help)
        _wk_show_help ;;
    install)
        if [ -f "/usr/local/bin/warp-worker.sh" ]; then
            bash /usr/local/bin/warp-worker.sh --install
        else
            echo -e "${RED}请先下载 warp-worker.sh 脚本${NC}"
        fi
        ;;
    uninstall)
        _wk_uninstall ;;
    *)
        # 处理 wk=region 格式
        if [[ "$1" == *=* ]]; then
            local region="${1#*=}"
            _wk_set_region "$region"
        elif [ -z "$1" ]; then
            _wk_show_status
        else
            echo -e "${RED}未知命令: $1${NC}"
            _wk_show_help
        fi
        ;;
esac
WKEOF

    chmod +x /usr/local/bin/wk
    
    # 创建别名
    cat > /etc/profile.d/wk-aliases.sh << 'ALIASEOF'
#!/bin/bash
# wk命令别名
alias wk='bash /usr/local/bin/wk'
alias wk=us='bash /usr/local/bin/wk us'
alias wk=sg='bash /usr/local/bin/wk sg'
alias wk=jp='bash /usr/local/bin/wk jp'
alias wk=de='bash /usr/local/bin/wk de'
alias wk=uk='bash /usr/local/bin/wk uk'
alias wk=nl='bash /usr/local/bin/wk nl'
alias wk=au='bash /usr/local/bin/wk au'
alias wk=kr='bash /usr/local/bin/wk kr'
alias wk=hk='bash /usr/local/bin/wk hk'
alias wk=ca='bash /usr/local/bin/wk ca'
alias wk=in='bash /usr/local/bin/wk in'
alias wk=br='bash /usr/local/bin/wk br'
ALIASEOF
    
    chmod +x /etc/profile.d/wk-aliases.sh
    source /etc/profile.d/wk-aliases.sh 2>/dev/null || true
    
    echo -e "${GREEN}✓ wk命令已安装${NC}"
}

# ============================================================
# 主函数
# ============================================================
main() {
    case "${1:-}" in
        --install)
            wk_install ;;
        --switch)
            wk_set_region "${2:-auto}" ;;
        --status)
            wk_status ;;
        --help)
            echo -e "${CYAN}G-Everywhere Worker Edition v5.1${NC}"
            echo -e "使用: $0 [选项]"
            echo -e "  --install       安装"
            echo -e "  --switch REGION 切换地区"
            echo -e "  --status        查看状态"
            echo -e "  --help          显示帮助"
            ;;
        *)
            # 交互式菜单
            echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${BOLD}${GREEN}G-Everywhere Worker Edition v5.1${NC}"
            echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "\n${YELLOW}请选择操作:${NC}"
            echo -e "  ${GREEN}1.${NC} 安装"
            echo -e "  ${GREEN}2.${NC} 切换地区"
            echo -e "  ${GREEN}3.${NC} 查看状态"
            echo -e "  ${GREEN}4.${NC} 卸载"
            echo -e "  ${GREEN}0.${NC} 退出"
            echo ""
            read -rp "选项 [0-4]: " choice
            
            case "$choice" in
                1) wk_install ;;
                2) 
                    echo -e "\n${CYAN}选择目标地区:${NC}"
                    local i=1
                    for code in "${!WK_REGIONS[@]}"; do
                        printf "  ${GREEN}%2d.${NC} %s\n" "$i" "${WK_REGIONS[$code]}"
                        ((i++))
                    done
                    echo ""
                    read -rp "选择 [1-${#WK_REGIONS[@]}]: " region_choice
                    local region_list=("${!WK_REGIONS[@]}")
                    local target="${region_list[$((region_choice-1))]}"
                    wk_set_region "$target"
                    ;;
                3) wk_status ;;
                4) 
                    echo -e "${YELLOW}确定要卸载吗？(y/N): ${NC}"
                    read -r confirm
                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                        _wk_uninstall
                    fi
                    ;;
                0) echo -e "${GREEN}Bye!${NC}" ;;
                *) echo -e "${RED}无效选项${NC}" ;;
            esac
            ;;
    esac
}

# 如果作为脚本直接运行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
