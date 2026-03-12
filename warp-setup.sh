#!/bin/bash
# G-Everywhere v3.0
# Google / Gemini Unlock — wgcf WireGuard Split-Tunnel
# 修复: 弃用 warp-cli proxy + redsocks，改用 wgcf WireGuard 直连
# 新增: --scan 自动扫描真实出口节点（网络命名空间隔离测试）

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'
NC='\033[0m'; BOLD='\033[1m'

WG_IF="wgcf"
WG_CONF="/etc/wireguard/${WG_IF}.conf"
WGCF_DIR="/etc/g-everywhere"
G_STATE="${WGCF_DIR}/state"
SETUP_BIN="/usr/local/bin/g-everywhere-setup.sh"

# Google IP 分流列表（仅这些走 WARP，其余流量不受影响）
GOOGLE_IPS=(
    "8.8.4.0/24" "8.8.8.0/24" "34.0.0.0/9"
    "35.184.0.0/13" "35.192.0.0/12" "35.224.0.0/12"
    "35.240.0.0/13" "64.233.160.0/19" "66.102.0.0/20"
    "66.249.64.0/19" "72.14.192.0/18" "74.125.0.0/16"
    "104.132.0.0/14" "108.177.0.0/17" "142.250.0.0/15"
    "172.217.0.0/16" "172.253.0.0/16" "173.194.0.0/16"
    "209.85.128.0/17" "216.58.192.0/19" "216.239.32.0/19"
)

declare -A REGION_ENDPOINTS=(
    ["自动"]="engage.cloudflareclient.com:2408"
    ["🇺🇸 美国-洛杉矶"]="162.159.192.1:2408"
    ["🇺🇸 美国-纽约"]="162.159.193.1:2408"
    ["🇯🇵 日本-东京"]="162.159.195.1:2408"
    ["🇸🇬 新加坡"]="162.159.196.1:2408"
    ["🇩🇪 德国-法兰克福"]="162.159.197.1:2408"
    ["🇬🇧 英国-伦敦"]="162.159.198.1:2408"
    ["🇳🇱 荷兰-阿姆斯特丹"]="162.159.199.1:2408"
    ["🇦🇺 澳大利亚-悉尼"]="162.159.200.1:2408"
    ["🇮🇳 印度-孟买"]="162.159.204.1:2408"
    ["🇧🇷 巴西-圣保罗"]="162.159.205.1:2408"
    ["🇨🇦 加拿大-多伦多"]="162.159.209.1:2408"
    ["🇰🇷 韩国-首尔"]="162.159.210.1:2408"
    ["🇭🇰 香港"]="162.159.211.1:2408"
)
REGION_KEYS=(
    "自动" "🇺🇸 美国-洛杉矶" "🇺🇸 美国-纽约"
    "🇯🇵 日本-东京" "🇸🇬 新加坡" "🇩🇪 德国-法兰克福"
    "🇬🇧 英国-伦敦" "🇳🇱 荷兰-阿姆斯特丹" "🇦🇺 澳大利亚-悉尼"
    "🇮🇳 印度-孟买" "🇧🇷 巴西-圣保罗" "🇨🇦 加拿大-多伦多"
    "🇰🇷 韩国-首尔" "🇭🇰 香港"
)
# 扫描目标地区 → CF endpoint IP 前缀映射
declare -A SCAN_PREFIXES=(
    ["US"]="162.159.192 162.159.193"
    ["JP"]="162.159.195"
    ["SG"]="162.159.196"
    ["DE"]="162.159.197"
    ["UK"]="162.159.198"
    ["NL"]="162.159.199"
    ["AU"]="162.159.200"
    ["IN"]="162.159.204"
    ["CA"]="162.159.209"
    ["KR"]="162.159.210"
    ["HK"]="162.159.211"
)

SELECTED_REGION="自动"

# ============================================================
# Banner
# ============================================================
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
    echo -e "  ${GREEN}  Google/Gemini  ${NC}│${YELLOW}  Cloudflare WARP  ${NC}│${MAGENTA}  wgcf v3.0  ${NC}"
    echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${BLUE}github.com/ctsunny/g-everywhere${NC}  │  ${GREEN}v3.0 (wgcf WireGuard)${NC}\n"
}

check_root() {
    [[ $EUID -ne 0 ]] && { echo -e "${RED}请使用 root 运行！${NC}"; exit 1; }
}

detect_os() {
    [ -f /etc/os-release ] && . /etc/os-release || { echo -e "${RED}无法检测系统${NC}"; exit 1; }
    OS=$ID; VERSION=$VERSION_ID
    CODENAME=${VERSION_CODENAME:-$(echo "$VERSION_ID" | tr '.' '_')}
    case $(uname -m) in
        x86_64)  WGCF_ARCH="amd64" ;;
        aarch64) WGCF_ARCH="arm64" ;;
        armv7l)  WGCF_ARCH="armv7" ;;
        *)       WGCF_ARCH="amd64" ;;
    esac
}

show_current_ip() {
    echo -e "  ${YELLOW}当前节点信息${NC}"
    echo -e "  ${CYAN}──────────────────────────────────${NC}"
    local ip info
    ip=$(curl -4 -s --max-time 5 ip.sb 2>/dev/null || echo "获取失败")
    if [[ "$ip" != "获取失败" ]]; then
        info=$(curl -s --max-time 5 "http://ip-api.com/json/${ip}?lang=zh-CN" 2>/dev/null)
        echo -e "  IP  : ${GREEN}${ip}${NC}"
        echo -e "  位置: ${GREEN}$(echo "$info"|grep -oP '"country":"\K[^"]+') $(echo "$info"|grep -oP '"city":"\K[^"]+')${NC}"
        echo -e "  ISP : ${GREEN}$(echo "$info"|grep -oP '"isp":"\K[^"]+')${NC}"
    else
        echo -e "  ${RED}IP 获取失败${NC}"
    fi
    ip link show "$WG_IF" &>/dev/null && \
        echo -e "  WARP: ${GREEN}运行中 [$(wg show $WG_IF 2>/dev/null | grep -oP 'endpoint: \K\S+' || echo '?')]${NC}" || \
        echo -e "  WARP: ${RED}未运行${NC}"
    echo -e "  ${CYAN}──────────────────────────────────${NC}\n"
}

select_region() {
    echo -e "\n${CYAN}  ── 选择 WARP 入口节点 ──${NC}"
    echo -e "  ${YELLOW}注意: 入口节点 ≠ 出口 IP，如需锁定出口请用 'g scan'${NC}\n"
    for i in "${!REGION_KEYS[@]}"; do
        printf "  ${GREEN}%2d.${NC} %s\n" "$((i+1))" "${REGION_KEYS[$i]}"
    done
    echo ""
    read -p "  请选择 [1-${#REGION_KEYS[@]}] (默认1-自动): " region_choice
    region_choice=${region_choice:-1}
    if [[ "$region_choice" =~ ^[0-9]+$ ]] && \
       [ "$region_choice" -ge 1 ] && [ "$region_choice" -le "${#REGION_KEYS[@]}" ]; then
        SELECTED_REGION="${REGION_KEYS[$((region_choice-1))]}"
        echo -e "  ${GREEN}✓ 已选择: $SELECTED_REGION${NC}"
    else
        SELECTED_REGION="自动"
        echo -e "  ${YELLOW}无效，使用自动${NC}"
    fi
}

# ============================================================
# [1/5] 安装依赖
# ============================================================
install_deps() {
    echo -e "\n${CYAN}  [1/5] 安装依赖 (wireguard-tools / curl / jq)...${NC}"
    case $OS in
        ubuntu|debian)
            apt-get update -y >/dev/null 2>&1
            apt-get install -y wireguard wireguard-tools curl wget jq iproute2 >/dev/null 2>&1
            ;;
        centos|rhel|rocky|almalinux)
            dnf install -y epel-release >/dev/null 2>&1 || yum install -y epel-release >/dev/null 2>&1
            dnf install -y wireguard-tools curl wget jq iproute >/dev/null 2>&1 || \
            yum install -y wireguard-tools curl wget jq iproute >/dev/null 2>&1
            ;;
        fedora)
            dnf install -y wireguard-tools curl wget jq iproute >/dev/null 2>&1 ;;
        *)
            echo -e "${RED}不支持的系统: $OS${NC}"; exit 1 ;;
    esac
    modprobe wireguard 2>/dev/null || true
    echo -e "  ${GREEN}✓ 依赖安装完成${NC}"
}

# ============================================================
# [2/5] 安装 wgcf
# ============================================================
install_wgcf() {
    echo -e "\n${CYAN}  [2/5] 安装 wgcf...${NC}"
    if command -v wgcf &>/dev/null; then
        echo -e "  ${GREEN}已安装: $(wgcf --version 2>/dev/null)${NC}"; return
    fi
    local ver
    ver=$(curl -s --max-time 10 "https://api.github.com/repos/ViRb3/wgcf/releases/latest" \
        | grep -oP '"tag_name":"\Kv[\d.]+' | head -1)
    [ -z "$ver" ] && ver="v2.2.25"
    local base="https://github.com/ViRb3/wgcf/releases/download/${ver}/wgcf_${ver#v}_linux_${WGCF_ARCH}"
    echo -e "  下载 wgcf ${ver} (${WGCF_ARCH})..."
    wget -qO /usr/local/bin/wgcf "$base" 2>/dev/null || \
    wget -qO /usr/local/bin/wgcf "https://ghproxy.com/${base}" 2>/dev/null || {
        echo -e "${RED}下载失败！手动: wget -O /usr/local/bin/wgcf ${base}${NC}"; exit 1
    }
    chmod +x /usr/local/bin/wgcf
    echo -e "  ${GREEN}✓ wgcf $(wgcf --version 2>/dev/null)${NC}"
}

# ============================================================
# [3/5] 注册 WARP 账户
# ============================================================
register_warp() {
    echo -e "\n${CYAN}  [3/5] 注册 WARP 账户...${NC}"
    mkdir -p "$WGCF_DIR" && cd "$WGCF_DIR" || exit 1
    if [ -f "$WGCF_DIR/wgcf-profile.conf" ]; then
        echo -e "  ${GREEN}已有配置，跳过注册${NC}"; return
    fi
    wgcf register --accept-tos 2>/dev/null || true
    wgcf generate 2>/dev/null || true
    [ ! -f "$WGCF_DIR/wgcf-profile.conf" ] && {
        echo -e "${RED}注册失败！请手动: cd $WGCF_DIR && wgcf register --accept-tos && wgcf generate${NC}"
        exit 1
    }
    echo -e "  ${GREEN}✓ WARP 账户注册完成${NC}"
}

# ============================================================
# [4/5] 生成 WireGuard 分流配置
# 核心改进: AllowedIPs 仅含 Google CIDRs → 纯分流，无需 redsocks
# ============================================================
build_wg_conf() {
    local endpoint="${1:-${REGION_ENDPOINTS[$SELECTED_REGION]}}"
    echo -e "\n${CYAN}  [4/5] 生成 WireGuard 分流配置...${NC}"
    echo -e "  入口节点 : ${YELLOW}$SELECTED_REGION${NC} ($endpoint)"
    echo -e "  分流模式 : ${CYAN}仅 Google ${#GOOGLE_IPS[@]} 个 CIDR 走 WARP${NC}"

    local src="$WGCF_DIR/wgcf-profile.conf"
    local priv pub addr
    priv=$(awk '/^PrivateKey/{print $3}' "$src")
    pub=$(awk '/^PublicKey/{print $3}' "$src")
    addr=$(awk '/^Address/{print $3}' "$src" | grep -v ':' | head -1)
    [ -z "$addr" ] && addr=$(awk '/^Address/{print $3}' "$src" | head -1)

    local allowed_ips
    allowed_ips=$(printf "%s," "${GOOGLE_IPS[@]}"); allowed_ips="${allowed_ips%,}"

    mkdir -p /etc/wireguard
    cat > "$WG_CONF" << EOF
[Interface]
PrivateKey = ${priv}
Address = ${addr}
DNS = 1.1.1.1,8.8.8.8
MTU = 1280

[Peer]
PublicKey = ${pub}
AllowedIPs = ${allowed_ips}
Endpoint = ${endpoint}
PersistentKeepalive = 25
EOF
    mkdir -p "$WGCF_DIR"
    printf "SELECTED_REGION=%s\nENDPOINT=%s\n" "$SELECTED_REGION" "$endpoint" > "$G_STATE"
    echo -e "  ${GREEN}✓ 配置完成 → ${WG_CONF}${NC}"
}

# ============================================================
# [5/5] 启动 WireGuard
# ============================================================
start_wg() {
    wg-quick down "$WG_IF" 2>/dev/null || ip link del "$WG_IF" 2>/dev/null || true
    sleep 1
    wg-quick up "$WG_CONF" || {
        echo -e "${RED}WireGuard 启动失败！配置内容:${NC}"
        cat "$WG_CONF"; return 1
    }
    systemctl enable "wg-quick@${WG_IF}" 2>/dev/null || true
    sleep 2
    echo -e "  ${GREEN}✓ WireGuard 接口 ${WG_IF} 已启动${NC}"
}

# ============================================================
# 验证 Google / Gemini 连通性
# ============================================================
verify_and_test() {
    echo -e "\n${CYAN}  验证连通性...${NC}"
    ip link show "$WG_IF" &>/dev/null || { echo -e "  ${RED}✗ WireGuard 未运行${NC}"; return 1; }

    local g_code gemini_code
    g_code=$(curl -s --max-time 15 -o /dev/null -w "%{http_code}" https://www.google.com 2>/dev/null)
    gemini_code=$(curl -s --max-time 15 -o /dev/null -w "%{http_code}" https://gemini.google.com 2>/dev/null)

    [[ "$g_code" =~ ^(200|301|302)$ ]] && \
        echo -e "  ${GREEN}✓ Google 可访问 (HTTP $g_code)${NC}" || \
        echo -e "  ${RED}✗ Google 不可访问 (HTTP $g_code)${NC}"

    [[ "$gemini_code" =~ ^(200|301|302)$ ]] && \
        echo -e "  ${GREEN}✓ Gemini 可访问 (HTTP $gemini_code)${NC}" || {
        echo -e "  ${RED}✗ Gemini 不可访问 (HTTP $gemini_code)${NC}"
        echo -e "  ${YELLOW}  → 原因: 出口 IP 可能在香港/中国大陆/受限地区${NC}"
        echo -e "  ${YELLOW}  → 解决: g scan US  （扫描美国真实出口节点）${NC}"
    }

    echo -e "\n  ${CYAN}WireGuard 连接详情:${NC}"
    wg show "$WG_IF" 2>/dev/null | grep -E "endpoint|transfer|latest handshake" | sed 's/^/  /'
}

# ============================================================
# Endpoint 扫描 — 核心功能
# 原理: CF WARP 的 exit IP 由 CF anycast 内部路由决定，
#       与 entry endpoint 无关。通过遍历同一 IP 段的多个
#       endpoint，利用网络命名空间隔离测试，找到实际出口
#       在目标国家的节点。
# 用法: scan_endpoints US / JP / SG / DE / UK 等
# ============================================================
scan_endpoints() {
    local target="${1:-US}"
    local ranges="${SCAN_PREFIXES[$target]}"
    [ -z "$ranges" ] && { echo -e "${RED}未知目标: $target，支持: ${!SCAN_PREFIXES[*]}${NC}"; return 1; }

    echo -e "\n${CYAN}  ── Endpoint 扫描 (目标出口: ${target}) ──${NC}"
    echo -e "  ${YELLOW}扫描原理: 入口 endpoint ≠ 出口 IP (CF anycast 路由)${NC}"
    echo -e "  ${YELLOW}使用网络命名空间隔离测试，不影响现有连接${NC}\n"

    local src="$WGCF_DIR/wgcf-profile.conf"
    [ ! -f "$src" ] && { echo -e "${RED}请先安装 (选项1)${NC}"; return 1; }

    local priv pub addr
    priv=$(awk '/^PrivateKey/{print $3}' "$src")
    pub=$(awk '/^PublicKey/{print $3}' "$src")
    addr=$(awk '/^Address/{print $3}' "$src" | grep -v ':' | head -1)
    [ -z "$addr" ] && addr=$(awk '/^Address/{print $3}' "$src" | head -1)
    # 去掉 CIDR 前缀，仅保留 IP
    local wg_ip="${addr%%/*}"

    local ns="wgcf_scan_ns"
    local scan_if="wgcfscan"
    local best_ep="" best_country="" best_city="" found=0

    # 清理残留
    ip netns del "$ns" 2>/dev/null || true

    for prefix in $ranges; do
        for suffix in 1 2 3 4 5 6 7 8; do
            local ep="${prefix}.${suffix}:2408"
            printf "  测试 ${CYAN}%-24s${NC}" "$ep"

            # 创建独立网络命名空间，完全隔离路由
            ip netns add "$ns" 2>/dev/null || { echo -e "${RED}netns 创建失败，跳过${NC}"; continue; }
            ip link add "$scan_if" type wireguard 2>/dev/null
            ip link set "$scan_if" netns "$ns" 2>/dev/null

            # 在 ns 内配置 WireGuard
            ip netns exec "$ns" wg set "$scan_if" \
                private-key <(echo "$priv") \
                peer "$pub" \
                endpoint "$ep" \
                allowed-ips "0.0.0.0/0" \
                persistent-keepalive 5 2>/dev/null

            ip netns exec "$ns" ip link set lo up 2>/dev/null
            ip netns exec "$ns" ip addr add "${wg_ip}/32" dev "$scan_if" 2>/dev/null
            ip netns exec "$ns" ip link set "$scan_if" up 2>/dev/null
            ip netns exec "$ns" ip route add default dev "$scan_if" 2>/dev/null

            sleep 4  # 等待 WireGuard 握手

            # 在 ns 内检测出口 IP
            local exit_ip
            exit_ip=$(ip netns exec "$ns" curl -s --max-time 8 ip.sb 2>/dev/null)

            # 清理 ns
            ip netns del "$ns" 2>/dev/null || true

            if [ -n "$exit_ip" ]; then
                local info country_code country_name city
                info=$(curl -s --max-time 5 "http://ip-api.com/json/${exit_ip}?lang=zh-CN" 2>/dev/null)
                country_code=$(echo "$info" | grep -oP '"countryCode":"\K[^"]+')
                country_name=$(echo "$info" | grep -oP '"country":"\K[^"]+')
                city=$(echo "$info" | grep -oP '"city":"\K[^"]+')
                echo -e "→ ${GREEN}${exit_ip}${NC} [${country_name} ${city}]"

                if [ "$country_code" = "$target" ]; then
                    echo -e "\n  ${BOLD}${GREEN}★ 找到目标出口! $ep → $exit_ip [$country_name $city]${NC}"
                    best_ep="$ep"; best_country="$country_name"; best_city="$city"; found=1
                    break 2
                fi
            else
                echo -e "${YELLOW}超时/握手失败${NC}"
            fi
            sleep 1
        done
    done

    ip netns del "$ns" 2>/dev/null || true  # 确保清理

    if [ $found -eq 1 ]; then
        echo -e "\n  ${GREEN}扫描完成: $best_ep → $best_country $best_city${NC}"
        read -rp "  是否立即切换到此节点? [Y/n]: " apply
        if [[ "${apply:-Y}" =~ ^[Yy]$ ]]; then
            [ -f "$WG_CONF" ] && sed -i "s|^Endpoint = .*|Endpoint = ${best_ep}|" "$WG_CONF"
            wg-quick down "$WG_IF" 2>/dev/null || true
            sleep 1
            wg-quick up "$WG_CONF" && {
                printf "SELECTED_REGION=扫描-%s\nENDPOINT=%s\n" "$target" "$best_ep" > "$G_STATE"
                echo -e "  ${GREEN}✓ 已切换并重启 → $best_ep${NC}"
                verify_and_test
            } || echo -e "  ${RED}✗ 重启失败${NC}"
        fi
    else
        echo -e "\n  ${YELLOW}⚠ 在 $target 的 endpoint 范围内未找到目标出口${NC}"
        echo -e "  ${YELLOW}建议方案:${NC}"
        echo -e "  ${CYAN}1. 尝试扩大扫描: g scan JP  或  g scan SG${NC}"
        echo -e "  ${CYAN}2. 使用 Cloudflare Zero Trust 锁定出口国家（最可靠）${NC}"
        echo -e "     → dash.cloudflare.com → Zero Trust → Gateway → Egress Policies"
    fi
}

# ============================================================
# 安装后提示
# ============================================================
show_post_install() {
    [ -f "$G_STATE" ] && source "$G_STATE"
    echo -e "\n${BOLD}${GREEN}"
    echo "  ┌───────────────────────────────────────────────┐"
    echo "  │     ✅  G-Everywhere v3.0 安装成功！            │"
    echo "  └───────────────────────────────────────────────┘"
    echo -e "${NC}"
    echo -e "  ${YELLOW}入口节点 :${NC} ${GREEN}${SELECTED_REGION}${NC}"
    echo -e "  ${YELLOW}WG 接口  :${NC} ${GREEN}${WG_IF}${NC}"
    echo -e "  ${YELLOW}配置文件 :${NC} ${GREEN}${WG_CONF}${NC}"
    echo -e "  ${YELLOW}分流 CIDR:${NC} ${GREEN}${#GOOGLE_IPS[@]} 条 Google 地址段${NC}"
    echo ""
    echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━ 常用命令 ━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${GREEN}g${NC}                  打开管理菜单"
    echo -e "  ${GREEN}g status${NC}           查看运行状态"
    echo -e "  ${GREEN}g start/stop${NC}       启动/停止"
    echo -e "  ${GREEN}g restart${NC}          重启"
    echo -e "  ${GREEN}g test${NC}             测试 Google / Gemini"
    echo -e "  ${GREEN}g ip${NC}               查看出口 IP"
    echo -e "  ${GREEN}g region${NC}           切换入口节点"
    echo -e "  ${GREEN}g scan US${NC}          扫描美国真实出口 ← Gemini 推荐"
    echo -e "  ${GREEN}g scan JP${NC}          扫描日本真实出口"
    echo -e "  ${GREEN}g scan SG${NC}          扫描新加坡真实出口"
    echo -e "  ${GREEN}g uninstall${NC}        卸载"
    echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo -e "  ${YELLOW}💡 Gemini 无法访问? 运行: ${GREEN}g scan US${NC}"
    echo -e "  ${YELLOW}   出口 IP 锁定最可靠方案: Cloudflare Zero Trust Egress Policy${NC}\n"
}

# ============================================================
# 创建 /usr/local/bin/g 管理命令
# ============================================================
create_management() {
    cat > /usr/local/bin/g << 'MGMT'
#!/bin/bash
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
WG_IF="wgcf"; WG_CONF="/etc/wireguard/${WG_IF}.conf"
SETUP="/usr/local/bin/g-everywhere-setup.sh"

_wg_up()   { wg-quick down "$WG_IF" 2>/dev/null||true; sleep 1; wg-quick up "$WG_CONF"; }
_wg_down() { wg-quick down "$WG_IF" 2>/dev/null||true; }

case "$1" in
    status)
        echo -e "\n${CYAN}── WireGuard 状态 ──${NC}"
        ip link show "$WG_IF" &>/dev/null && \
            { echo -e "  WARP: ${GREEN}运行中${NC}"; wg show "$WG_IF" 2>/dev/null|grep -E "endpoint|transfer|handshake"|sed 's/^/  /'; } || \
            echo -e "  WARP: ${RED}未运行${NC}"
        echo "" ;;
    start)
        echo -e "${CYAN}启动...${NC}"
        _wg_up && echo -e "${GREEN}✓ 已启动${NC}" || echo -e "${RED}✗ 失败${NC}" ;;
    stop)
        _wg_down && echo -e "${GREEN}✓ 已停止${NC}" ;;
    restart)
        _wg_down; sleep 2; _wg_up && echo -e "${GREEN}✓ 已重启${NC}" ;;
    test)
        echo -e "${CYAN}测试中...${NC}"
        for url in "https://www.google.com" "https://gemini.google.com"; do
            code=$(curl -s --max-time 12 -o /dev/null -w "%{http_code}" "$url")
            name=$(echo "$url"|grep -oP '(?<=//)[^/]+')
            [[ "$code" =~ ^(200|301|302)$ ]] && \
                echo -e "  ${GREEN}✓ $name (HTTP $code)${NC}" || \
                echo -e "  ${RED}✗ $name (HTTP $code)${NC}"
        done ;;
    ip)
        echo -e "\n${YELLOW}本机直连 IP:${NC}"
        curl -4 -s --max-time 5 ip.sb | xargs -I{} echo -e "  ${GREEN}{}${NC}"
        echo -e "${YELLOW}WARP 出口 IP 检测:${NC}"
        if ip link show "$WG_IF" &>/dev/null; then
            # 临时添加 ip.sb 路由走 wgcf 测试出口
            IPSB_IP=$(dig +short ip.sb 2>/dev/null | head -1 || curl -4 -s ifconfig.me)
            [ -n "$IPSB_IP" ] && ip route add "${IPSB_IP}/32" dev "$WG_IF" 2>/dev/null
            WARP_IP=$(curl -s --max-time 10 ip.sb 2>/dev/null)
            [ -n "$IPSB_IP" ] && ip route del "${IPSB_IP}/32" dev "$WG_IF" 2>/dev/null
            [ -n "$WARP_IP" ] && {
                info=$(curl -s --max-time 5 "http://ip-api.com/json/${WARP_IP}?lang=zh-CN")
                echo -e "  ${GREEN}$WARP_IP${NC} [$(echo "$info"|grep -oP '"country":"\K[^"]+') $(echo "$info"|grep -oP '"city":"\K[^"]+')]"
            } || echo -e "  ${RED}获取失败${NC}"
        else
            echo -e "  ${RED}WARP 未运行${NC}"
        fi
        echo "" ;;
    region)
        [ -f "$SETUP" ] && bash "$SETUP" --change-region || echo -e "${RED}请重新运行安装脚本${NC}" ;;
    scan)
        [ -f "$SETUP" ] && bash "$SETUP" --scan "${2:-US}" || echo -e "${RED}请先安装${NC}" ;;
    uninstall)
        echo -e "${YELLOW}卸载中...${NC}"
        _wg_down
        systemctl disable "wg-quick@${WG_IF}" 2>/dev/null||true
        rm -f "$WG_CONF" "$SETUP" /usr/local/bin/g
        rm -rf /etc/g-everywhere
        echo -e "${GREEN}✓ 卸载完成${NC}" ;;
    *)
        [ -f "$SETUP" ] && bash "$SETUP" || {
            echo -e "${CYAN}G-Everywhere v3.0${NC}\n用法: g <命令>"
            echo -e "  status|start|stop|restart|test|ip|region"
            echo -e "  scan [US|JP|SG|DE|UK|NL|AU]  ← 扫描真实出口"
            echo -e "  uninstall"
        } ;;
esac
MGMT
    chmod +x /usr/local/bin/g
    cp "$0" "$SETUP" 2>/dev/null && chmod +x "$SETUP" || true
    echo -e "  ${GREEN}✓ 管理命令 'g' 已创建${NC}"
}

# ============================================================
# 切换入口节点
# ============================================================
change_region() {
    echo -e "\n${CYAN}  ── 切换入口节点 ──${NC}"
    [ -f "$G_STATE" ] && source "$G_STATE"
    echo -e "  当前: ${YELLOW}${SELECTED_REGION:-未知}${NC} (${ENDPOINT:-未知})"
    select_region
    local ep="${REGION_ENDPOINTS[$SELECTED_REGION]}"
    [ -f "$WG_CONF" ] && sed -i "s|^Endpoint = .*|Endpoint = ${ep}|" "$WG_CONF" || \
        { echo -e "${RED}配置不存在，请重新安装${NC}"; return 1; }
    printf "SELECTED_REGION=%s\nENDPOINT=%s\n" "$SELECTED_REGION" "$ep" > "$G_STATE"
    wg-quick down "$WG_IF" 2>/dev/null||true; sleep 1
    wg-quick up "$WG_CONF" && echo -e "  ${GREEN}✓ 已切换: $SELECTED_REGION ($ep)${NC}" || \
        echo -e "  ${RED}✗ 重启失败${NC}"
}

# ============================================================
# 完整安装流程
# ============================================================
do_install() {
    select_region
    install_deps
    install_wgcf
    register_warp
    build_wg_conf
    start_wg
    create_management
    verify_and_test
    show_post_install
}

do_uninstall() {
    echo -e "\n${YELLOW}  卸载中...${NC}"
    wg-quick down "$WG_IF" 2>/dev/null||true
    ip link del "$WG_IF" 2>/dev/null||true
    systemctl disable "wg-quick@${WG_IF}" 2>/dev/null||true
    rm -f "$WG_CONF" "$SETUP" /usr/local/bin/g
    rm -rf "$WGCF_DIR"
    echo -e "  ${GREEN}✓ 卸载完成${NC}\n"
}

do_status() {
    echo -e "\n${CYAN}  ── 运行状态 ──${NC}"
    if ip link show "$WG_IF" &>/dev/null; then
        echo -e "  WireGuard: ${GREEN}运行中${NC}"
        wg show "$WG_IF" 2>/dev/null | sed 's/^/  /'
    else
        echo -e "  WireGuard: ${RED}未运行${NC}"
    fi
    [ -f "$G_STATE" ] && { echo -e "\n  ${CYAN}配置状态:${NC}"; cat "$G_STATE" | sed 's/^/  /'; }
    echo ""
}

# ============================================================
# 主菜单
# ============================================================
show_menu() {
    while true; do
        show_banner
        show_current_ip
        echo -e "  ${YELLOW}请选择操作:${NC}\n"
        echo -e "  ${GREEN}1.${NC} 安装 G-Everywhere (wgcf + WireGuard)"
        echo -e "  ${GREEN}2.${NC} 切换入口节点"
        echo -e "  ${GREEN}3.${NC} 扫描真实出口节点 ${YELLOW}← 解决 Gemini 无法访问${NC}"
        echo -e "  ${GREEN}4.${NC} 查看状态"
        echo -e "  ${GREEN}5.${NC} 卸载"
        echo -e "  ${GREEN}0.${NC} 退出\n"
        read -rp "  请输入选项 [0-5]: " choice
        echo ""
        case $choice in
            1) do_install ;;
            2) [ ! -f "$WG_CONF" ] && echo -e "  ${RED}请先安装 (选项1)${NC}" || change_region ;;
            3)
                [ ! -f "$WGCF_DIR/wgcf-profile.conf" ] && { echo -e "  ${RED}请先安装 (选项1)${NC}"; } || {
                    echo -e "\n  支持目标: ${CYAN}US JP SG DE UK NL AU IN CA KR HK${NC}"
                    read -rp "  输入目标地区代码 [默认 US]: " st
                    scan_endpoints "${st:-US}"
                } ;;
            4) do_status ;;
            5) do_uninstall ;;
            0) echo -e "  ${GREEN}Bye!${NC}\n"; exit 0 ;;
            *) echo -e "  ${RED}无效选项${NC}" ;;
        esac
        echo ""
        read -rp "  按 Enter 返回菜单..." _
    done
}

# 主入口
main() {
    check_root
    detect_os
    case "${1:-}" in
        --install)       show_banner; do_install ;;
        --uninstall)     show_banner; do_uninstall ;;
        --status)        show_banner; do_status ;;
        --change-region) show_banner; change_region ;;
        --scan)          show_banner; scan_endpoints "${2:-US}" ;;
        *)               show_menu ;;
    esac
}
main "$@"
