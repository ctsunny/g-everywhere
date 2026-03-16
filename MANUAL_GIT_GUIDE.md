# 手动 Git 部署指南

如果你在执行 `push_to_github.sh` 时遇到问题，请按照以下步骤手动操作：

## 准备工作

1. **确认 Git 已安装**：
   ```
   git --version
   ```

2. **确认你的 GitHub 仓库地址**：
   - 例如：`https://github.com/YOUR_USERNAME/g-everywhere.git`

## 手动 Git 操作步骤

### 步骤 1：完成当前的提交

如果你卡在 `git commit` 界面，先按以下操作：

1. **按 `i` 键** 进入编辑模式
2. **输入提交信息**：`feat: 发布 G-Everywhere Worker Edition v5.2`
3. **按 `Esc` 键** 退出编辑模式
4. **输入 `:wq` 并按 Enter** 保存并退出

或者，如果你要取消当前的提交：
- 按 `Esc` 键
- 输入 `:q!` 并按 Enter（强制退出不保存）

### 步骤 2：手动完成整个流程

打开命令行，按顺序执行以下命令：

```bash
# 1. 检查当前状态
git status

# 2. 添加所有文件
git add .

# 3. 提交更改
git commit -m "feat: 发布 G-Everywhere Worker Edition v5.2"

# 4. 设置远程仓库（将 YOUR_USERNAME 替换为你的用户名）
git remote add origin https://github.com/YOUR_USERNAME/g-everywhere.git

# 如果已经设置过，先删除再添加
git remote remove origin
git remote add origin https://github.com/YOUR_USERNAME/g-everywhere.git

# 5. 设置分支
git branch -M main

# 6. 推送到 GitHub（这里可能需要认证）
git push -u origin main
```

## 关于 GitHub 认证

第一次推送时，GitHub 会要求认证。以下是几种认证方式：

### 方式 1：使用 Personal Access Token（推荐）

1. 访问：https://github.com/settings/tokens
2. 点击 "Generate new token" → "Generate new token (classic)"
3. 选择权限：
   - `repo`（完整仓库权限）
4. 生成 Token 并复制
5. 推送时，在密码位置粘贴 Token

### 方式 2：使用 Git Credential Manager（Windows）

如果安装了 Git for Windows，它会自动弹出认证窗口。

### 方式 3：手动配置用户名和密码

```bash
# 设置用户名
git config --global user.name "YOUR_GITHUB_USERNAME"

# 设置邮箱
git config --global user.email "YOUR_EMAIL@example.com"
```

## 如果推送失败

如果 `git push` 失败，尝试以下解决方案：

### 方案 1：使用 HTTPS 代替 SSH

确保你使用的是 HTTPS URL：
```bash
https://github.com/YOUR_USERNAME/g-everywhere.git
```
而不是 SSH URL：
```bash
git@github.com:YOUR_USERNAME/g-everywhere.git
```

### 方案 2：清除缓存并重试

```bash
# 清除 Git 缓存
git config --global --unset credential.helper

# Windows 凭据管理器
cmdkey /delete:git:https://github.com

# 重新尝试推送
git push -u origin main
```

### 方案 3：使用 cURL 测试

测试 GitHub 连接是否正常：
```bash
curl -I https://github.com/YOUR_USERNAME/g-everywhere.git
```

## 验证部署

推送成功后，验证文件是否正确上传：

1. **访问你的仓库**：
   ```
   https://github.com/YOUR_USERNAME/g-everywhere
   ```

2. **检查文件列表**，确保所有 `.sh` 和 `.md` 文件都在

3. **测试安装脚本**：
   ```bash
   curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/g-everywhere/main/install.sh | head -5
   ```

## 更新 install.sh 文件

手动更新 `install.sh` 中的用户名：
1. 打开 `install.sh` 文件
2. 找到第 13 行：
   ```bash
   REPO_OWNER="yourusername"
   ```
3. 修改为你的用户名：
   ```bash
   REPO_OWNER="YOUR_USERNAME"
   ```

## 一键安装链接

部署成功后，用户可以使用以下命令安装：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/g-everywhere/main/install.sh)
```

## 常见问题解答

### Q: 为什么需要认证？
A: GitHub 需要验证你有权推送代码到仓库。

### Q: 如何创建 GitHub Personal Access Token？
A: 访问 https://github.com/settings/tokens → Generate new token → 选择 `repo` 权限。

### Q: 推送时提示 "permission denied"？
A: 检查：1) 仓库URL是否正确 2) 是否有推送权限 3) Token是否过期。

### Q: 如何查看当前的远程仓库设置？
A: 运行 `git remote -v`

### Q: 如何修改已经提交的信息？
A: 运行 `git commit --amend -m "新的提交信息"`