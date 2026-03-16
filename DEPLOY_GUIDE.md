# G-Everywhere Worker Edition 部署指南

## 📦 项目文件概览

```
g-everywhere-1/
├── g-everywhere-wk-final.sh    # 主安装脚本（推荐）
├── ge-wk.sh                    # 集成管理命令
├── warp-simple.sh              # 极简版
├── warp-worker.sh              # 详细配置版
├── warp-setup.sh               # 原版 v5.0
├── README_WORKER.md            # 项目说明文档
├── install.sh                  # 一键安装脚本
└── DEPLOY_GUIDE.md            # 本部署指南
```

## 🚀 快速部署到 GitHub

### 步骤 1: 准备 GitHub 仓库

1. **登录 GitHub** 并创建新仓库
   - 仓库名: `g-everywhere`
   - 描述: "G-Everywhere Worker Edition - Google解锁工具，支持wk=快速切换地区"
   - 选择 Public（公开）
   - 可勾选 "Add a README file"

2. **或 Fork 到你的账户**
   - 如果要保留原项目，可以先 fork 原仓库
   - 然后在此基础上修改

### 步骤 2: 本地 Git 配置

```bash
# 1. 进入项目目录
cd c:/Users/ronal/g-everywhere-1

# 2. 初始化 Git（如果还没有）
git init

# 3. 添加所有文件
git add .

# 4. 提交更改
git commit -m "feat: 发布 G-Everywhere Worker Edition v5.2"

# 5. 添加远程仓库
git remote add origin https://github.com/你的用户名/g-everywhere.git

# 6. 推送代码
git branch -M main
git push -u origin main
```

### 步骤 3: 更新 install.sh 中的仓库信息

编辑 `install.sh` 文件，修改第 13 行：
```bash
# 将 yourusername 替换为你的 GitHub 用户名
REPO_OWNER="yourusername"  # ← 修改这里
REPO_NAME="g-everywhere"
BRANCH="main"
```

### 步骤 4: 创建 GitHub Release

1. 进入你的 GitHub 仓库页面
2. 点击 "Create a new release"
3. 版本号: `v5.2.0`
4. 标签: `v5.2.0`
5. 标题: "G-Everywhere Worker Edition v5.2"
6. 描述:
   ```
   ## 🎉 新特性
   - wk= 命令快速切换地区
   - 智能地区获取引擎
   - 简化的管理命令
   
   ## 🚀 一键安装
   ```bash
   bash <(curl -fsSL https://raw.githubusercontent.com/你的用户名/g-everywhere/main/install.sh)
   ```
   ```
7. 上传所有脚本文件作为附件
8. 点击 "Publish release"

## 🔗 使用链接

### 一键安装链接
```bash
# 直接安装
bash <(curl -fsSL https://raw.githubusercontent.com/你的用户名/g-everywhere/main/install.sh)

# 或指定版本
bash <(curl -fsSL https://raw.githubusercontent.com/你的用户名/g-everywhere/v5.2.0/install.sh)
```

### 直接下载链接
- 主脚本: `https://raw.githubusercontent.com/你的用户名/g-everywhere/main/g-everywhere-wk-final.sh`
- 安装脚本: `https://raw.githubusercontent.com/你的用户名/g-everywhere/main/install.sh`

## 📝 更新 README.md

创建或更新仓库的 README.md 文件：

```markdown
# G-Everywhere Worker Edition

[![GitHub release](https://img.shields.io/github/v/release/你的用户名/g-everywhere)](https://github.com/你的用户名/g-everywhere/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

基于 wk= 命令快速切换地区的 Google 解锁方案。

## 🚀 一键安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/你的用户名/g-everywhere/main/install.sh)
```

## ✨ 特性

- **wk= 快速切换**: `wk=us` `wk=sg` `wk=jp` 等
- **智能地区获取**: 8次智能重试，动态等待
- **简化管理**: `ge-wk status` `ge-wk test` `ge-wk fix`
- **仅 Google 走代理**: 其他流量直连不受影响

## 📖 详细文档

查看 [README_WORKER.md](README_WORKER.md) 获取完整使用指南。

## 📞 支持

- 提交 Issue: [问题反馈](https://github.com/你的用户名/g-everywhere/issues)
- 参与讨论: [Discussions](https://github.com/你的用户名/g-everywhere/discussions)

## 📄 许可证

MIT License
```

## 🔄 后续维护

### 更新代码流程
```bash
# 1. 修改代码
# 2. 提交更改
git add .
git commit -m "fix: 修复某某问题"

# 3. 推送到 GitHub
git push origin main

# 4. 创建新版本（可选）
# 在 GitHub 网页创建新的 Release
```

### 版本管理建议
- 主版本号: 重大功能更新
- 次版本号: 新功能添加
- 修订号: Bug 修复

## 🎯 推广使用

### 1. 社交媒体分享
- Twitter/X: 分享一键安装命令
- Telegram 群组: 技术分享
- 技术论坛: 如 V2EX、Reddit 等

### 2. 文档站点
可以使用 GitHub Pages 创建文档站：
1. 在仓库设置中启用 GitHub Pages
2. 选择 main 分支的 /docs 文件夹
3. 创建 `docs/index.md` 文档

### 3. 收集反馈
- 启用 GitHub Issues
- 开启 Discussions
- 收集用户使用反馈

## 🛡️ 安全注意事项

1. **代码审查**: 确保脚本不包含恶意代码
2. **权限管理**: 脚本需要 root 权限，提醒用户审查
3. **透明公开**: 所有代码开源，方便审查
4. **免责声明**: 在 README 中添加合理使用声明

## 📊 统计追踪

可以在安装脚本中添加简单的统计（可选）：
```bash
# 匿名安装统计
curl -s "https://api.github.com/repos/你的用户名/g-everywhere" | grep -o '"stargazers_count":[0-9]*'
```

## 🤝 社区建设

1. **贡献指南**: 创建 CONTRIBUTING.md
2. **行为准则**: 创建 CODE_OF_CONDUCT.md
3. **Pull Request 模板**: 创建 .github/PULL_REQUEST_TEMPLATE.md
4. **Issue 模板**: 创建 .github/ISSUE_TEMPLATE/

## 🎨 品牌标识

可以创建：
- 项目 Logo（可选）
- 社交媒体横幅
- 演示 GIF/视频

## 📈 后续开发计划

1. **Web 控制面板**（可选）
2. **多语言支持**
3. **Docker 容器化**
4. **API 接口**

---

**部署完成！** 现在你的 G-Everywhere Worker Edition 已经可以供全世界用户使用了。记得测试一键安装功能是否正常工作。