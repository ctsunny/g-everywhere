# G-Everywhere Worker Edition v5.2

基于 wk= 命令快速切换地区的 Google 解锁方案。专为需要频繁切换地区的用户设计。

> 🚀 最后更新：2026-03-16 | 版本：v5.2
> 
> 🔄 重构优化：wk=命令快速切换 | 智能地区获取 | 简化管理

## 🚀 快速开始

### 一键安装
```bash
curl -fsSL https://raw.githubusercontent.com/yourusername/g-everywhere/main/g-everywhere-wk-final.sh | bash
```

### 或下载后安装
```bash
wget https://raw.githubusercontent.com/yourusername/g-everywhere/main/g-everywhere-wk-final.sh
bash g-everywhere-wk-final.sh --install
```

## ✨ 特性

### 1. wk= 快速切换
- `wk=us` - 切换到美国 🇺🇸
- `wk=sg` - 切换到新加坡 🇸🇬  
- `wk=jp` - 切换到日本 🇯🇵
- `wk=auto` - 自动模式 🌐

### 2. 智能地区获取
- 8次智能重试机制
- 动态等待时间优化
- 评分系统选择最佳出口
- 失败自动回退

### 3. 简化管理
- `ge-wk status` - 查看状态
- `ge-wk test` - 完整测试
- `ge-wk fix` - 一键修复
- `ge-wk stop/start` - 停止/启动

## 📁 文件说明

| 文件 | 说明 |
|------|------|
| `g-everywhere-wk-final.sh` | 主安装脚本，完整功能版 |
| `ge-wk.sh` | 集成管理命令 |
| `warp-simple.sh` | 极简版，核心功能 |
| `warp-worker.sh` | 详细配置版 |
| `warp-setup.sh` | 原版 v5.0 脚本 |

## 🛠️ 安装流程

### 交互式安装
```bash
bash g-everywhere-wk-final.sh
```
然后选择选项 `1` 进行安装。

### 命令行安装
```bash
bash g-everywhere-wk-final.sh --install
```

### 选择地区
安装时会显示地区选择菜单，选择目标地区（如美国、新加坡、日本等）。

## 🎯 使用示例

### 切换到美国
```bash
wk=us
```

### 查看状态
```bash
ge-wk status
```

### 运行完整测试
```bash
ge-wk test
```

### 修复问题
```bash
ge-wk fix
```

### 查看出口IP
```bash
curl -x socks5://127.0.0.1:40000 ip.sb
```

## 🔧 支持的系统

- Ubuntu 18.04+
- Debian 10+
- CentOS 7+
- Rocky Linux 8+
- AlmaLinux 8+
- Fedora 32+

## 📊 地区支持

| 代码 | 地区 | 图标 |
|------|------|------|
| `auto` | 自动 | 🌐 |
| `us` | 美国 | 🇺🇸 |
| `jp` | 日本 | 🇯🇵 |
| `sg` | 新加坡 | 🇸🇬 |
| `de` | 德国 | 🇩🇪 |
| `uk` | 英国 | 🇬🇧 |
| `nl` | 荷兰 | 🇳🇱 |
| `au` | 澳大利亚 | 🇦🇺 |
| `kr` | 韩国 | 🇰🇷 |
| `hk` | 香港 | 🇭🇰 |
| `ca` | 加拿大 | 🇨🇦 |
| `in` | 印度 | 🇮🇳 |
| `br` | 巴西 | 🇧🇷 |

## 🐛 故障排除

### 常见问题

1. **warp-cli 连接失败**
   ```bash
   ge-wk fix
   systemctl restart warp-svc
   ```

2. **Google 无法访问**
   ```bash
   ge-wk test
   # 检查iptables规则
   iptables -t nat -L WARP_GOOGLE -n
   ```

3. **wk=命令不生效**
   ```bash
   source /etc/profile.d/wk-alias.sh
   # 或重新登录
   ```

### 日志查看
```bash
# warp-cli 日志
journalctl -u warp-svc -f

# redsocks 日志
journalctl -u redsocks-warp -f
```

## 🗑️ 卸载

### 完全卸载
```bash
bash g-everywhere-wk-final.sh --uninstall
```

### 或使用命令
```bash
ge-wk uninstall
```

## 🔄 升级

1. 先卸载旧版
2. 下载最新版安装
3. 或直接运行更新脚本

## 📈 性能特点

- **仅 Google IP 走代理**，其他流量直连
- **系统资源占用低**，仅需 warp-cli + redsocks
- **启动速度快**，systemd 服务管理
- **稳定性高**，自动重启和恢复

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

1. Fork 本仓库
2. 创建功能分支 (`git checkout -b feature/awesome`)
3. 提交更改 (`git commit -m 'Add awesome feature'`)
4. 推送到分支 (`git push origin feature/awesome`)
5. 创建 Pull Request

## 📄 许可证

MIT License

## 🙏 致谢

- 原项目: [ctsunny/g-everywhere](https://github.com/ctsunny/g-everywhere)
- Cloudflare WARP 团队
- 所有贡献者和用户

## 📞 支持

- GitHub Issues: [问题反馈](https://github.com/yourusername/g-everywhere/issues)
- 讨论区: [Discussions](https://github.com/yourusername/g-everywhere/discussions)

---

**提示**: 安装完成后建议重新登录，以使 `wk=` 命令别名生效。