#!/bin/bash
# G-Everywhere Worker Edition 推送到 GitHub 脚本

set -e

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# 配置
REPO_URL=""
DEFAULT_REPO="https://github.com/yourusername/g-everywhere.git"

show_help() {
    echo -e "${CYAN}G-Everywhere 推送到 GitHub 脚本${NC}"
    echo -e "用于将 Worker Edition 部署到 GitHub 仓库\n"
    echo -e "${GREEN}使用方法:${NC}"
    echo -e "  bash push_to_github.sh [GitHub仓库URL]\n"
    echo -e "${YELLOW}示例:${NC}"
    echo -e "  # 使用默认仓库"
    echo -e "  bash push_to_github.sh\n"
    echo -e "  # 指定仓库"
    echo -e "  bash push_to_github.sh https://github.com/yourusername/g-everywhere.git\n"
    echo -e "${CYAN}注意:${NC}"
    echo -e "  1. 需要先安装 git"
    echo -e "  2. 需要有 GitHub 仓库的推送权限"
    echo -e "  3. 第一次运行需要配置仓库信息"
}

check_git() {
    if ! command -v git &>/dev/null; then
        echo -e "${RED}错误: 需要安装 git${NC}"
        echo -e "安装命令:"
        echo -e "  Ubuntu/Debian: sudo apt-get install git"
        echo -e "  CentOS/RHEL:   sudo yum install git"
        echo -e "  macOS:         brew install git"
        exit 1
    fi
    echo -e "${GREEN}✓ Git 已安装${NC}"
}

setup_repo() {
    local repo_url="$1"
    
    if [ -z "$repo_url" ]; then
        read -rp "请输入 GitHub 仓库 URL (默认: $DEFAULT_REPO): " input_url
        repo_url="${input_url:-$DEFAULT_REPO}"
    fi
    
    echo -e "${CYAN}设置 Git 仓库: $repo_url${NC}"
    
    # 检查是否已经是 Git 仓库
    if [ -d ".git" ]; then
        echo -e "${YELLOW}检测到现有 Git 仓库${NC}"
        
        # 检查远程仓库
        local current_remote
        current_remote=$(git remote get-url origin 2>/dev/null || echo "")
        
        if [ -n "$current_remote" ]; then
            echo -e "当前远程仓库: $current_remote"
            read -rp "是否更新为 $repo_url? (y/N): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                git remote set-url origin "$repo_url"
                echo -e "${GREEN}✓ 远程仓库已更新${NC}"
            else
                echo -e "${YELLOW}保持当前仓库${NC}"
                repo_url="$current_remote"
            fi
        else
            git remote add origin "$repo_url"
            echo -e "${GREEN}✓ 添加远程仓库${NC}"
        fi
    else
        # 初始化新仓库
        git init
        git remote add origin "$repo_url"
        echo -e "${GREEN}✓ 初始化 Git 仓库${NC}"
    fi
    
    REPO_URL="$repo_url"
}

update_install_script() {
    local username
    
    # 从仓库 URL 提取用户名
    if [[ "$REPO_URL" =~ github\.com/([^/]+)/ ]]; then
        username="${BASH_REMATCH[1]}"
        echo -e "${CYAN}检测到 GitHub 用户名: $username${NC}"
        
        # 更新 install.sh 中的用户名
        if [ -f "install.sh" ]; then
            sed -i "s/REPO_OWNER=\"yourusername\"/REPO_OWNER=\"$username\"/" install.sh
            echo -e "${GREEN}✓ 更新 install.sh 中的仓库信息${NC}"
        else
            echo -e "${YELLOW}⚠ install.sh 文件不存在${NC}"
        fi
    else
        echo -e "${YELLOW}⚠ 无法从 URL 提取用户名，请手动更新 install.sh${NC}"
    fi
}

add_and_commit() {
    echo -e "${CYAN}添加文件到 Git...${NC}"
    
    # 添加所有文件
    git add .
    
    # 显示更改状态
    echo -e "${YELLOW}更改状态:${NC}"
    git status --short
    
    # 提交信息
    local commit_message
    if [ -n "$1" ]; then
        commit_message="$1"
    else
        read -rp "输入提交信息 (默认: 'feat: 发布 G-Everywhere Worker Edition'): " input_msg
        commit_message="${input_msg:-feat: 发布 G-Everywhere Worker Edition}"
    fi
    
    echo -e "${CYAN}提交更改: $commit_message${NC}"
    git commit -m "$commit_message"
    
    echo -e "${GREEN}✓ 提交完成${NC}"
}

push_to_github() {
    echo -e "${CYAN}推送到 GitHub...${NC}"
    
    # 检查当前分支
    local current_branch
    current_branch=$(git branch --show-current 2>/dev/null || echo "")
    
    if [ -z "$current_branch" ]; then
        # 如果没有分支，创建 main 分支
        git branch -M main
        current_branch="main"
    fi
    
    echo -e "推送到: $REPO_URL (分支: $current_branch)"
    
    # 推送
    if git push -u origin "$current_branch"; then
        echo -e "${GREEN}✓ 推送成功${NC}"
    else
        echo -e "${YELLOW}第一次推送可能需要指定分支${NC}"
        echo -e "尝试: git push -u origin ${current_branch:-main}"
        
        read -rp "是否继续? (Y/n): " confirm
        if [[ "$confirm" != "n" && "$confirm" != "N" ]]; then
            git push -u origin "${current_branch:-main}" || {
                echo -e "${RED}推送失败${NC}"
                echo -e "请手动执行: git push -u origin ${current_branch:-main}"
            }
        fi
    fi
}

show_next_steps() {
    echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✓ 推送完成！${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    local repo_name
    if [[ "$REPO_URL" =~ github\.com/([^/]+)/([^/.]+) ]]; then
        repo_name="${BASH_REMATCH[2]}"
        local username="${BASH_REMATCH[1]}"
        
        echo -e "\n${CYAN}下一步:${NC}"
        echo -e "1. 访问仓库: ${YELLOW}https://github.com/$username/$repo_name${NC}"
        echo -e "2. 检查文件是否正确上传"
        echo -e "3. 创建 Release (可选)"
        echo -e "   - 版本号: v5.2.0"
        echo -e "   - 标签: v5.2.0"
        echo -e "   - 描述: G-Everywhere Worker Edition v5.2"
        
        echo -e "\n${CYAN}一键安装链接:${NC}"
        echo -e "${YELLOW}bash <(curl -fsSL https://raw.githubusercontent.com/$username/$repo_name/main/install.sh)${NC}"
        
        echo -e "\n${CYAN}测试安装:${NC}"
        echo -e "curl -fsSL https://raw.githubusercontent.com/$username/$repo_name/main/install.sh | bash -s -- --help"
    fi
    
    echo -e "\n${YELLOW}部署指南:${NC}"
    echo -e "查看 DEPLOY_GUIDE.md 获取完整部署说明"
}

main() {
    echo -e "${CYAN}开始部署 G-Everywhere Worker Edition 到 GitHub${NC}"
    echo -e "${YELLOW}当前目录: $(pwd)${NC}"
    
    # 检查 Git
    check_git
    
    # 设置仓库
    setup_repo "$1"
    
    # 更新安装脚本
    update_install_script
    
    # 添加和提交
    add_and_commit "$2"
    
    # 推送到 GitHub
    push_to_github
    
    # 显示下一步
    show_next_steps
}

# 显示帮助
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    show_help
    exit 0
fi

# 运行主函数
main "$1" "$2"