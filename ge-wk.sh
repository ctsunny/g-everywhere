#!/bin/bash
# ge-wk - G-Everywhere Worker集成版管理命令
# 整合原ge功能和wk=快速切换

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; NC='\033[0m'; BOLD='\033[1m'

WARP_DIR="/etc/warp"
REDSOCKS_CONF="/etc/redsocks-warp.conf"
MODE_FILE="${WARP_DIR}/mode"
WK_REGION_FILE="${WARP_DIR}/wk_region"

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

# wk=地区映射
declare -A WK_MAP=(
    ["auto"]="🌐 自动"
    ["us"]="🇺🇸 美国"    ["jp"]="🇯🇵 日本"
    ["sg"]="🇸🇬 新加坡"  ["de"]="🇩🇪 德国"
    ["uk"]="🇬🇧 英国"    ["nl"]="🇳🇱 荷兰"
    ["au"]="🇦🇺 澳大利亚" ["kr"]="🇰🇷 韩国"
    ["hk"]="🇭🇰 香港"    ["ca"]="🇨🇦 加拿大"
    ["in"]="🇮🇳 印度"    ["br"]="🇧🇷 巴西"
)

# ============================================
# 核心路由函数
# ============================================
_routing_start() {
    _routing_stop
    
    iptables -t nat -N WARP_GOOGLE 2>/dev/null || true
    local skip_nets=(127.0.0.0/8 10.0.0.0/8 192.168.0.0/16 172.16.0.0/12 100.64.0.0/10)
    
    for net in "${skip_nets[@]}"; do
        iptables -t nat -A WARP_GOOGLE -d "$net" -j RETURN 2>/dev/null || true
    done
    
    for ip in "${GOOGLE_IPS[@]}"; do
        iptables -t nat -A WARP_GOOGLE -d "$ip" -p tcp -j REDIRECT --to-ports 12345 2>/dev/null || true
    done
    
    iptables -t nat -A OUTPUT -j WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -A PREROUTING -j WARP_GOOGLE 2>/dev/null || true
}

_routing_stop() {
    iptables -t nat -D OUTPUT -j WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -D PREROUTING -j WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -F WARP_GOOGLE 2>/dev/null || true
    iptables -t nat -X WARP_GOOGLE 2>/dev/null || true
}

_get_exit_ip() {
    curl -x socks5://127.0.0.1:40000 -s --max-time 8 ip.sb 2>/dev/null
}

# ============================================
# wk= 快速切换功能
# ============================================
_wk_switch() {
    local region="$1"
    
    if [ -z "${WK_MAP[$region]}" ] && [ "$region" != "auto" ]; then
        echo -e "${RED}无效地区: $region${NC}"
        echo -e "${YELLOW}可用: auto, us, jp, sg, de, uk, nl, au, kr, hk, ca, in, br${NC}"
        return 1
    fi
    
    echo -e "${CYAN}切换到: ${WK_MAP[$region]}${NC}"
    
    # 保存地区设置
    mkdir -p "$WARP_DIR"
    echo "$region" > "$WK_REGION_FILE"
    
    # 执行切换
    _wk_do_switch "$region"
}

_wk_do_switch() {
    local region="$1"
    
    # 停止当前连接
    warp-cli --accept-tos disconnect 2>/dev/null
    systemctl stop warp-svc 2>/dev/null
    sleep 2
    
    # 重启服务
    systemctl start warp-svc 2>/dev/null
    sleep 3
    
    # 设置入口端点
    if [ "$region" != "auto" ]; then
        local endpoint_ip=""
        case "$region" in
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
        esac
        
        warp-cli --accept-tos set-custom-endpoint "${endpoint_ip}:2408" 2>/dev/null
        echo -e "  入口节点: ${YELLOW}$endpoint_ip${NC}"
    fi
    
    # 智能重试获取目标地区
    _wk_smart_connect "$region"
}

_wk_smart_connect() {
    local region="$1"
    local target_cc=""
    
    # 目标国家代码
    case "$region" in
        us) target_cc="US" ;;
        jp) target_cc="JP" ;;
        sg) target_cc="SG" ;;
        de) target_cc="DE" ;;
        uk) target_cc="GB" ;;
        nl) target_cc="NL" ;;
        au) target_cc="AU" ;;
        kr) target_cc="KR" ;;
        hk) target_cc="HK" ;;
        ca) target_cc="CA" ;;
        in) target_cc="IN" ;;
        br) target_cc="BR" ;;
    esac
    
    echo -e "  目标地区: ${YELLOW}$target_cc${NC}"
    
    local max_attempts=8
    local best_ip="" best_country="" best_score=0
    
    for attempt in $(seq 1 $max_attempts); do
        echo -e "  尝试 $attempt/$max_attempts"
        
        # 每3次清理一次注册
        if [ $((attempt % 3)) -eq 1 ] && [ "$attempt" -gt 1 ]; then
            warp-cli --accept-tos registration delete 2>/dev/null || true
            sleep 1
        fi
        
        # 注册和连接
        warp-cli --accept-tos register 2>/dev/null || true
        warp-cli --accept-tos mode proxy 2>/dev/null
        warp-cli --accept-tos connect 2>/dev/null
        sleep 15  # 重要：给WARP时间分配IP
        
        # 检查连接
        if ! warp-cli status 2>/dev/null | grep -qi "connected"; then
            continue
        fi
        
        # 获取出口信息
        local exit_ip ipinfo country_code country city
        exit_ip=$(_get_exit_ip)
        
        if [ -n "$exit_ip" ]; then
            ipinfo=$(curl -s --max-time 8 "http://ip-api.com/json/${exit_ip}?lang=zh-CN" 2>/dev/null)
            country_code=$(echo "$ipinfo" | grep -oP '"countryCode":"\K[^"]+' || echo "")
            country=$(echo "$ipinfo" | grep -oP '"country":"\K[^"]+' || echo "")
            city=$(echo "$ipinfo" | grep -oP '"city":"\K[^"]+' || echo "")
            
            echo -e "    出口: ${CYAN}$exit_ip ($country_code)${NC}"
            
            # 评分
            local score=0
            if [ -z "$target_cc" ]; then
                score=1  # auto模式
            elif [ "$country_code" = "$target_cc" ]; then
                score=10  # 完美匹配
            fi
            
            if [ $score -gt $best_score ]; then
                best_score=$score
                best_ip="$exit_ip"
                best_country="$country"
                
                if [ $score -eq 10 ]; then
                    echo -e "    ${GREEN}✓ 成功获取目标地区！${NC}"
                    break
                fi
            fi
        fi
    done
    
    # 保存结果
    if [ -n "$best_ip" ]; then
        printf '%s\n%s\n' "$best_ip" "$best_country" > "${WARP_DIR}/exit_info"
        echo -e "  ${GREEN}✓ 最终出口: $best_ip ($best_country)${NC}"
    else
        echo -e "  ${YELLOW}⚠ 使用当前出口${NC}"
    fi
    
    # 重启redsocks和路由
    systemctl restart redsocks-warp 2>/dev/null
    sleep 1
    _routing_start
}

# ============================================
# 传统ge命令功能
# ============================================
cmd_start() {
    echo -e "${CYAN}启动中...${NC}"
    systemctl start warp-svc 2>/dev/null
    sleep 2
    warp-cli --accept-tos connect 2>/dev/null
    sleep 6
    systemctl start redsocks-warp 2>/dev/null
    sleep 1
    _routing_start
    
    local code
    code=$(curl -s --max-time 8 -o /dev/null -w "%{http_code}" https://www.google.com)
    if [ "$code" = "200" ] || [ "$code" = "301" ]; then
        echo -e "${GREEN}✓ 已启动，Google HTTP $code${NC}"
    else
        echo -e "${YELLOW}已启动，Google HTTP $code（稍等）${NC}"
    fi
}

cmd_stop() {
    _routing_stop
    warp-cli --accept-tos disconnect 2>/dev/null
    systemctl stop redsocks-warp 2>/dev/null
    echo -e "${GREEN}✓ 已停止${NC}"
}

cmd_restart() {
    cmd_stop
    sleep 2
    cmd_start
}

cmd_status() {
    echo -e "\n${CYAN}━━ warp-cli 状态 ━━${NC}"
    warp-cli status 2>/dev/null | sed 's/^/  /'
    
    echo -e "\n${CYAN}━━ redsocks 状态 ━━${NC}"
    if systemctl is-active redsocks-warp &>/dev/null; then
        echo -e "  ${GREEN}✓ redsocks 运行中 (port 12345)${NC}"
    else
        echo -e "  ${RED}✗ redsocks 未运行${NC}"
    fi
    
    echo -e "\n${CYAN}━━ wk=地区设置 ━━${NC}"
    if [ -f "$WK_REGION_FILE" ]; then
        local region=$(cat "$WK_REGION_FILE")
        echo -e "  当前设置: ${GREEN}${WK_MAP[$region]}${NC}"
    else
        echo -e "  未设置 (默认: auto)${NC}"
    fi
    
    echo -e "\n${CYAN}━━ 出口信息 ━━${NC}"
    if [ -f "${WARP_DIR}/exit_info" ]; then
        local ip country
        read -r ip country < "${WARP_DIR}/exit_info"
        echo -e "  出口IP: ${GREEN}$ip ($country)${NC}"
    fi
    
    local live_ip=$(_get_exit_ip)
    if [ -n "$live_ip" ]; then
        echo -e "  实时出口: ${GREEN}$live_ip${NC}"
    else
        echo -e "  实时出口: ${YELLOW}获取中...${NC}"
    fi
    
    echo -e "\n${CYAN}━━ 访问测试 ━━${NC}"
    local g gem
    g=$(curl -s --max-time 8 -o /dev/null -w "%{http_code}" https://www.google.com)
    gem=$(curl -s --max-time 8 -o /dev/null -w "%{http_code}" \
        -H "User-Agent: Mozilla/5.0" https://gemini.google.com)
    
    [ "$g" = "200" ] || [ "$g" = "301" ] \
        && echo -e "  ${GREEN}✓ Google  HTTP $g${NC}" \
        || echo -e "  ${RED}✗ Google  HTTP $g${NC}"
    
    [ "$gem" = "200" ] || [ "$gem" = "301" ] \
        && echo -e "  ${GREEN}✓ Gemini  HTTP $gem${NC}" \
        || echo -e "  ${YELLOW}△ Gemini  HTTP $gem${NC}"
    echo ""
}

cmd_test() {
    echo -e "\n${CYAN}━━ 完整诊断 ━━${NC}\n"
    
    echo -e "${YELLOW}[1] warp-cli 连接${NC}"
    warp-cli status 2>/dev/null | grep -qi "connected" \
        && echo -e "  ${GREEN}✓ 已连接${NC}" \
        || echo -e "  ${RED}✗ 未连接${NC}"
    
    echo -e "\n${YELLOW}[2] redsocks 服务${NC}"
    systemctl is-active redsocks-warp &>/dev/null \
        && echo -e "  ${GREEN}✓ 运行中${NC}" \
        || echo -e "  ${RED}✗ 未运行${NC}"
    
    echo -e "\n${YELLOW}[3] iptables 规则${NC}"
    local cnt
    cnt=$(iptables -t nat -L WARP_GOOGLE -n 2>/dev/null | grep -c REDIRECT || echo 0)
    [ "$cnt" -gt 0 ] \
        && echo -e "  ${GREEN}✓ $cnt 条规则${NC}" \
        || echo -e "  ${RED}✗ 无规则${NC}"
    
    echo -e "\n${YELLOW}[4] SOCKS5 测试${NC}"
    local socks_ip
    socks_ip=$(_get_exit_ip)
    [ -n "$socks_ip" ] \
        && echo -e "  ${GREEN}✓ 可用 ($socks_ip)${NC}" \
        || echo -e "  ${RED}✗ 不可用${NC}"
    
    echo -e "\n${YELLOW}[5] 网站访问${NC}"
    local sites=(
        "Google:https://www.google.com"
        "YouTube:https://www.youtube.com" 
        "Gemini:https://gemini.google.com"
    )
    
    for site in "${sites[@]}"; do
        local name="${site%%:*}" url="${site#*:}"
        local code
        code=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" \
            -H "User-Agent: Mozilla/5.0" "$url" 2>/dev/null || echo "000")
        
        if [ "$code" = "200" ] || [ "$code" = "301" ]; then
            printf "  ${GREEN}✓${NC} %-10s HTTP %s\n" "$name" "$code"
        else
            printf "  ${RED}✗${NC} %-10s HTTP %s\n" "$name" "$code"
        fi
    done
    
    echo -e "\n${YELLOW}[6] 分流验证${NC}"
    local direct_ip warp_ip
    direct_ip=$(curl -4 -s --max-time 5 ip.sb 2>/dev/null)
    warp_ip=$(_get_exit_ip)
    
    echo -e "  直连: ${GREEN}$direct_ip${NC}"
    echo -e "  WARP: ${GREEN}$warp_ip${NC}"
    
    if [ -n "$direct_ip" ] && [ -n "$warp_ip" ] && [ "$direct_ip" != "$warp_ip" ]; then
        echo -e "  ${GREEN}✓ 分流正常${NC}"
    else
        echo -e "  ${YELLOW}△ 分流检查${NC}"
    fi
    echo ""
}

cmd_ip() {
    echo -e "\n${YELLOW}直连 IP:${NC}"
    curl -4 -s --max-time 5 ip.sb 2>/dev/null || echo "获取失败"
    echo ""
    
    echo -e "${YELLOW}WARP 出口 IP:${NC}"
    local exit_ip=$(_get_exit_ip)
    if [ -n "$exit_ip" ]; then
        local ipinfo country city isp
        ipinfo=$(curl -s --max-time 8 "http://ip-api.com/json/${exit_ip}?lang=zh-CN" 2>/dev/null)
        country=$(echo "$ipinfo" | grep -oP '"country":"\K[^"]+' || echo "")
        city=$(echo "$ipinfo" | grep -oP '"city":"\K[^"]+' || echo "")
        isp=$(echo "$ipinfo" | grep -oP '"isp":"\K[^"]+' || echo "")
        
        echo -e "${GREEN}$exit_ip${NC}"
        echo -e "地区: ${GREEN}$country $city${NC}"
        echo -e "ISP:  ${GREEN}$isp${NC}"
    else
        echo -e "${RED}获取失败${NC}"
    fi
    echo ""
}

cmd_fix() {
    echo -e "${CYAN}修复中...${NC}"
    cmd_stop
    sleep 2
    cmd_start
    echo -e "${GREEN}✓ 修复完成${NC}"
}

cmd_region() {
    echo -e "\n${CYAN}选择出口地区:${NC}\n"
    
    local i=1
    for code in "${!WK_MAP[@]}"; do
        printf "  ${GREEN}%2d.${NC} %s\n" "$i" "${WK_MAP[$code]}"
        ((i++))
    done
    
    echo ""
    read -rp "选择 [1-${#WK_MAP[@]}] (默认1): " choice
    choice=${choice:-1}
    
    local regions=("${!WK_MAP[@]}")
    local target="${regions[$((choice-1))]}"
    
    if [ -n "$target" ]; then
        _wk_switch "$target"
    else
        echo -e "${RED}无效选择${NC}"
    fi
}

cmd_uninstall() {
    echo -e "${YELLOW}确定要卸载吗？(y/N): ${NC}"
    read -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}取消卸载${NC}"
        return
    fi
    
    echo -e "${CYAN}卸载中...${NC}"
    cmd_stop
    systemctl disable redsocks-warp warp-svc 2>/dev/null
    rm -f /etc/systemd/system/redsocks-warp.service
    rm -f /usr/local/bin/ge /usr/local/bin/ge-wk
    rm -rf "$WARP_DIR"
    rm -f "$REDSOCKS_CONF"
    systemctl daemon-reload
    echo -e "${GREEN}✓ 卸载完成${NC}"
}

# ============================================
# 主处理
# ============================================
main() {
    # 处理wk=格式
    if [[ "$1" == *=* ]]; then
        local region="${1#*=}"
        _wk_switch "$region"
        return
    fi
    
    # 传统命令
    case "${1:-help}" in
        start)      cmd_start ;;
        stop)       cmd_stop ;;
        restart)    cmd_restart ;;
        status)     cmd_status ;;
        test)       cmd_test ;;
        ip)         cmd_ip ;;
        fix)        cmd_fix ;;
        region)     cmd_region ;;
        uninstall)  cmd_uninstall ;;
        
        # wk快捷命令
        wk=*)       _wk_switch "${1#wk=}" ;;
        wk-auto)    _wk_switch "auto" ;;
        wk-us)      _wk_switch "us" ;;
        wk-jp)      _wk_switch "jp" ;;
        wk-sg)      _wk_switch "sg" ;;
        wk-de)      _wk_switch "de" ;;
        wk-uk)      _wk_switch "uk" ;;
        wk-nl)      _wk_switch "nl" ;;
        wk-au)      _wk_switch "au" ;;
        wk-kr)      _wk_switch "kr" ;;
        wk-hk)      _wk_switch "hk" ;;
        wk-ca)      _wk_switch "ca" ;;
        wk-in)      _wk_switch "in" ;;
        wk-br)      _wk_switch "br" ;;
        
        # 帮助
        help|*)
            echo -e "${CYAN}ge-wk v5.1 - 集成wk=快速切换${NC}\n"
            echo -e "${GREEN}传统命令:${NC}"
            echo "  start stop restart"
            echo "  status test ip fix"
            echo "  region uninstall"
            echo -e "\n${YELLOW}wk=快速切换:${NC}"
            echo "  wk=us      切换到美国"
            echo "  wk=sg      切换到新加坡"
            echo "  wk=jp      切换到日本"
            echo "  wk=auto    自动模式"
            echo -e "\n${CYAN}或使用:${NC}"
            echo "  wk-us wk-sg wk-jp 等"
            ;;
    esac
}

# 如果是直接运行，创建别名文件
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # 复制到/usr/local/bin
    if [ "$0" != "/usr/local/bin/ge-wk" ]; then
        cp "$0" /usr/local/bin/ge-wk 2>/dev/null || true
        chmod +x /usr/local/bin/ge-wk 2>/dev/null || true
    fi
    
    # 创建别名文件
    cat > /etc/profile.d/ge-wk-aliases.sh << 'ALIASEOF'
#!/bin/bash
# ge-wk 命令别名
alias ge='ge-wk'
alias ge-wk='ge-wk'

# wk=快速切换别名
alias 'wk=us'='ge-wk wk=us'
alias 'wk=sg'='ge-wk wk=sg'
alias 'wk=jp'='ge-wk wk=jp'
alias 'wk=de'='ge-wk wk=de'
alias 'wk=uk'='ge-wk wk=uk'
alias 'wk=nl'='ge-wk wk=nl'
alias 'wk=au'='ge-wk wk=au'
alias 'wk=kr'='ge-wk wk=kr'
alias 'wk=hk'='ge-wk wk=hk'
alias 'wk=ca'='ge-wk wk=ca'
alias 'wk=in'='ge-wk wk=in'
alias 'wk=br'='ge-wk wk=br'
alias 'wk=auto'='ge-wk wk=auto'

# 快捷命令
alias wk-us='ge-wk wk=us'
alias wk-sg='ge-wk wk=sg'
alias wk-jp='ge-wk wk=jp'
ALIASEOF
    
    chmod +x /etc/profile.d/ge-wk-aliases.sh
    source /etc/profile.d/ge-wk-aliases.sh 2>/dev/null || true
    
    main "$@"
fi