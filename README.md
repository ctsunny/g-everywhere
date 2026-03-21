# G-Everywhere Worker Edition

> 基于 Cloudflare WARP 的 Google 解锁方案，使用 `wk=` 命令快速切换出口地区。

---

## 📦 安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ctsunny/g-everywhere/main/install.sh)
```

> 需要 root 权限运行。安装完成后建议重新登录，使 `wk=` 命令别名生效，或手动执行：
>
> ```bash
> source /etc/profile.d/wk-alias.sh
> ```

---

## 🔄 升级

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ctsunny/g-everywhere/main/install.sh) --update
```

---

## 🗑️ 卸载

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ctsunny/g-everywhere/main/install.sh) --uninstall
```

---

## 🌍 常用命令

| 命令 | 说明 |
|------|------|
| `wk=us` | 切换到美国 🇺🇸 |
| `wk=sg` | 切换到新加坡 🇸🇬 |
| `wk=jp` | 切换到日本 🇯🇵 |
| `wk=auto` | 自动选择最佳出口 🌐 |
| `ge-wk status` | 查看当前状态 |
| `ge-wk test` | 完整连通性测试 |
| `ge-wk fix` | 一键修复常见问题 |

---

## 🖥️ 支持的系统

- Ubuntu 18.04+
- Debian 10+
- CentOS 7+
- Rocky Linux 8+
- AlmaLinux 8+
- Fedora 32+

---

## 📄 许可证

MIT License
