# GitHub 网页上传指南

如果 Git 推送一直失败，可以通过 GitHub 网页直接上传文件。

## 📋 需要上传的文件

复制以下文件到 GitHub：

```
1. g-everywhere-wk-final.sh      # 主安装脚本 v5.2.1
2. warp-worker.sh                # Worker Edition 版本
3. warp-simple.sh                # 简化版本
4. ge-wk.sh                      # 管理命令
5. warp-setup.sh                 # 原版脚本（参考）
6. install.sh                    # 一键安装脚本
7. push_to_github.sh             # 部署脚本
8. README_WORKER.md              # 详细文档 v5.2
9. DEPLOY_GUIDE.md               # 部署指南
10. README.md                    # 项目说明
11. .gitignore                   # 忽略规则
```

## 🌐 网页上传步骤

### 方法 1：批量上传（推荐）

1. **访问仓库**：https://github.com/ctsunny/g-everywhere
2. **点击** "Add file" → "Upload files"
3. **拖拽** 上面列出的 11 个文件到上传区域
4. **填写** 提交信息：
   ```
   发布: G-Everywhere Worker Edition v5.2.1 优化版
   ```
5. **选择** 提交到 `main` 分支
6. **点击** "Commit changes"

### 方法 2：单个文件上传

如果批量上传失败，可以逐个上传：

1. 对每个 `.sh` 和 `.md` 文件重复：
   - 点击 "Add file" → "Create new file"
   - 文件名：输入完整文件名
   - 内容：复制文件内容粘贴
   - 提交

## 🔧 文件内容验证

上传后检查：

### g-everywhere-wk-final.sh
- 第一行：`#!/bin/bash`
- 第二行：`# G-Everywhere Worker Final v5.2.1`
- 应该有完整的 wk= 功能

### README_WORKER.md
- 标题：`# G-Everywhere Worker Edition v5.2`
- 包含快速开始指南
- 有 wk= 使用说明

## 📊 验证上传成功

上传后检查：
1. **文件数量**：应该有 11 个文件
2. **文件内容**：点击文件查看内容是否正确
3. **一键安装**：测试安装命令

## 🚀 一键安装命令

上传成功后，用户可以这样安装：

```bash
# 方法 1：使用 install.sh
bash <(curl -fsSL https://raw.githubusercontent.com/ctsunny/g-everywhere/main/install.sh)

# 方法 2：直接运行主脚本
bash <(curl -fsSL https://raw.githubusercontent.com/ctsunny/g-everywhere/main/g-everywhere-wk-final.sh) --install
```

## ⏱️ 上传时间预估

- **批量上传**：2-3 分钟
- **单个上传**：10-15 分钟
- **验证时间**：5 分钟

## ❓ 常见问题

### Q: 上传时提示文件已存在？
A: 选择 "Replace file" 覆盖

### Q: 如何知道上传成功？
A: 刷新页面，看到文件列表

### Q: 上传后如何更新？
A: 可以继续用网页上传，或者配置好 Git 后使用命令行

### Q: 文件太大上传失败？
A: 每个脚本文件都很小，应该没问题

## ✅ 完成检查清单

- [ ] 11 个文件全部上传
- [ ] 文件内容正确
- [ ] README 显示正常
- [ ] 一键安装命令可执行
- [ ] 仓库页面整洁

## 📞 帮助

如果上传仍有问题：
1. 截图错误信息
2. 检查网络连接
3. 尝试更换浏览器
4. 稍后再试