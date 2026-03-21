#!/bin/bash
# G-Everywhere Worker Edition 一键安装脚本
# 直接从 GitHub 下载并安装

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# GitHub 仓库信息
REPO_OWNER="ctsunny"
REPO_NAME="g-everywhere"
BRANCH="master"

# 下载 URL
BASE_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}"

show_banner() {
    echo -e "${CYAN}"
    echo "  ██████╗       ███████╗██╗   ██╗███████╗██████╗ ██╗   ██╗"
    echo " ██╔════╝       ██╔════╝██║   ██║██╔════╝██╔══██╗╚██╗ ██╔╝"
    echo " ██║  ███╗█████╗█████╗  ██║   ██║█████╗  ██████╔╝ ╚████╔╝ "
    echo " ██║   ██║╚════╝██╔══╝  ╚██╗ ██╔╝██╔══╝  ██╔══██╗  ╚██╔╝  "
    echo " ╚██████╔╝       ███████╗ ╚████╔╝ ███████╗██║  ██║   ██║   "
    echo "  ╚═════╝        ╚══════╝  ╚═══╝  ╚══════╝╚═╝  ╚═╝   ╚═╝  "
    echo -e "${NC}"
    echo -e "  ${GREEN}G-Everywhere Worker Edition 一键安装${NC}"
    echo -e "  ${YELLOW}基于 wk= 命令快速切换地区${NC}"
    echo ""
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误: 请使用 root 用户运行此脚本${NC}"
        exit 1
    fi
}

download_script() {
    local script_name="$1"
    local local_path="$2"
    
    echo -e "${CYAN}下载 ${script_name}...${NC}"
    
    # 尝试使用 curl
    if command -v curl &>/dev/null; then
        curl -fsSL "${BASE_URL}/${script_name}" -o "$local_path"
    # 尝试使用 wget
    elif command -v wget &>/dev/null; then
        wget -q "${BASE_URL}/${script_name}" -O "$local_path"
    else
        echo -e "${RED}错误: 需要 curl 或 wget 来下载文件${NC}"
        echo -e "请安装 curl 或 wget:"
        echo -e "  Ubuntu/Debian: apt-get install curl"
        echo -e "  CentOS/RHEL:   yum install curl"
        exit 1
    fi
    
    if [ ! -f "$local_path" ] || [ ! -s "$local_path" ]; then
        echo -e "${RED}错误: 下载 ${script_name} 失败${NC}"
        exit 1
    fi
    
    chmod +x "$local_path"
    echo -e "${GREEN}✓ 下载完成${NC}"
}

install_main() {
    show_banner
    check_root
    
    echo -e "${CYAN}开始安装 G-Everywhere Worker Edition...${NC}"
    
    # 临时目录
    local temp_dir="/tmp/g-everywhere-$(date +%s)"
    mkdir -p "$temp_dir"
    
    # 下载主脚本
    download_script "g-everywhere-wk-final.sh" "${temp_dir}/g-everywhere-wk-final.sh"
    
    # 运行安装
    echo -e "\n${CYAN}运行安装程序...${NC}"
    bash "${temp_dir}/g-everywhere-wk-final.sh" --install
    
    # 清理临时文件
    rm -rf "$temp_dir"
    
    echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✓ 安装完成！${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    show_usage
}

show_usage() {
    echo -e "\n${CYAN}使用方法:${NC}"
    echo -e "  ${GREEN}wk=us${NC}       切换到美国"
    echo -e "  ${GREEN}wk=sg${NC}       切换到新加坡"
    echo -e "  ${GREEN}wk=jp${NC}       切换到日本"
    echo -e "  ${GREEN}ge-wk status${NC} 查看状态"
    echo -e "  ${GREEN}ge-wk test${NC}   完整测试"
    echo -e "  ${GREEN}ge-wk fix${NC}    修复问题"
    
    echo -e "\n${YELLOW}重新登录或运行以下命令使 wk= 生效:${NC}"
    echo -e "  source /etc/profile.d/wk-alias.sh"
    
    echo -e "\n${CYAN}卸载命令:${NC}"
    echo -e "  bash <(curl -fsSL ${BASE_URL}/install.sh) --uninstall"
}

uninstall_main() {
    show_banner
    check_root
    
    echo -e "${YELLOW}确定要卸载 G-Everywhere Worker Edition 吗？${NC}"
    read -rp "输入 y 确认卸载，其他键取消: " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo -e "${YELLOW}取消卸载${NC}"
        exit 0
    fi
    
    echo -e "${CYAN}开始卸载...${NC}"
    
    # 临时下载卸载脚本
    local temp_script="/tmp/g-everywhere-uninstall-$(date +%s).sh"
    download_script "g-everywhere-wk-final.sh" "$temp_script"
    
    # 运行卸载
    bash "$temp_script" --uninstall
    
    # 清理
    rm -f "$temp_script"
    
    echo -e "${GREEN}✓ 卸载完成${NC}"
}

update_main() {
    show_banner
    check_root
    
    echo -e "${CYAN}更新 G-Everywhere Worker Edition...${NC}"
    
    # 先下载最新版本
    local temp_script="/tmp/g-everywhere-update-$(date +%s).sh"
    download_script "g-everywhere-wk-final.sh" "$temp_script"
    
    # 检查当前版本和新版本
    if [ -f "/usr/local/bin/g-everywhere-wk" ]; then
        echo -e "${YELLOW}发现已安装版本，将进行更新...${NC}"
        
        # 先卸载旧版
        bash "$temp_script" --uninstall 2>/dev/null || true
        sleep 2
    fi
    
    # 安装新版
    bash "$temp_script" --install
    
    # 清理
    rm -f "$temp_script"
    
    echo -e "${GREEN}✓ 更新完成${NC}"
}

show_help() {
    show_banner
    echo -e "${CYAN}G-Everywhere Worker Edition 安装脚本${NC}"
    echo -e "一键安装基于 wk= 命令快速切换地区的 Google 解锁方案\n"
    echo -e "${GREEN}使用方法:${NC}"
    echo -e "  bash <(curl -fsSL ${BASE_URL}/install.sh) [选项]\n"
    echo -e "${YELLOW}选项:${NC}"
    echo -e "  --install     安装（默认）"
    echo -e "  --uninstall   卸载"
    echo -e "  --update      更新到最新版本"
    echo -e "  --help        显示帮助\n"
    echo -e "${CYAN}示例:${NC}"
    echo -e "  # 一键安装"
    echo -e "  bash <(curl -fsSL ${BASE_URL}/install.sh)"
    echo -e "  \n  # 卸载"
    echo -e "  bash <(curl -fsSL ${BASE_URL}/install.sh) --uninstall"
    echo -e "  \n  # 更新"
    echo -e "  bash <(curl -fsSL ${BASE_URL}/install.sh) --update"
}

# 主函数
main() {
    case "${1:-install}" in
        install|--install)
            install_main ;;
        uninstall|--uninstall)
            uninstall_main ;;
        update|--update)
            update_main ;;
        help|--help|-h)
            show_help ;;
        *)
            echo -e "${RED}未知选项: $1${NC}"
            show_help
            exit 1 ;;
    esac
}

# 检查是否直接运行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi