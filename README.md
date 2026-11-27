# bt-cf: aaPanel & Cloudflare DNS / Zero Trust CLI

![aaPanel](https://img.shields.io/badge/aaPanel-7.x%20%7C%208.x%20%7C%209.x-blue.svg)
![Cloudflare](https://img.shields.io/badge/Cloudflare-DNS%20%7C%20Zero%20Trust-orange.svg)
![Python](https://img.shields.io/badge/Python-3.6+-green.svg)
![Multi-VPS](https://img.shields.io/badge/Multi--VPS-Dynamic%20IP-success.svg)

`bt-cf` 是一个专为 **aaPanel (宝塔海外版)** 与 **Cloudflare** 打造的自动化管理命令行工具。无需修改面板源码或受限于脆弱的前端页面注入，通过纯命令行实现建站、DNS 解析同步与 Cloudflare Zero Trust (Access) 受保护域名的全自动化联动。

---

## 🌟 核心特性

- **多 VPS 原生支持**：自动动态探测各 VPS 节点的公网 IP，配置文件绝不硬编码 IP，同一份配置可在多台服务器快速部署。
- **一键建站 + DNS + Zero Trust**：一条命令同时创建 aaPanel 站点目录、自动在 Cloudflare 添加 A 记录，并动态将其加入指定的 Zero Trust Application 保护名单。
- **细粒度开关**：
  - 支持 `--no-proxy`（关闭 Cloudflare CDN 小橙云，仅 DNS 解析）。
  - 支持 `--no-zt`（仅建站并解析，不纳入 Zero Trust 保护）。
- **随时切换 Zero Trust**：`bt-cf toggle-zt <domain> [on|off]` 毫秒级增删 Access 保护，无需登录 Cloudflare 控制台反复点选。
- **快速修改反代端口 (`proxy`)**：支持通过站点 ID 或域名一键更改反代端口或目标地址，自动保留自定义规则、校验 Nginx 语法并重载生效。
- **一键自更新 (`update`)**：直接在终端执行 `bt-cf update` 即可毫秒级从 GitHub 拉取最新脚本并热替换，无需重新运行安装流程。
- **域名一致性核查 (`check`)**：自动扫描 Cloudflare 中已解析到当前 VPS 但 aaPanel 尚未建站的“孤儿域名”，并提供一键建站建议。
- **直观列表展示 (`list`)**：紧凑型终端全彩表格对齐输出，直接从 Web 服务器真实配置文件解析反代端口，并实时探测监听进程（支持 Docker 容器名、Python/Node 脚本及未监听告警）与 Zero Trust / 小橙云状态。
- **纯净稳健**：独立运行，完全不修改 aaPanel 系统文件，杜绝 502 Bad Gateway 隐患，面板升级无感知。

---

## 🚀 快速部署 (多 VPS 通用)

### 方法一：一键脚本快速安装 (推荐)

在任意已安装 aaPanel 的 VPS 终端以 root 权限执行：

```bash
# 方式 1: 直接安装 (随后按提示输入 API Token)
curl -fsSL https://raw.githubusercontent.com/wumingshi654/bt-cf/main/install.sh | bash

# 方式 2: 带环境变量静默安装 (推荐用于多 VPS 快速部署)
CF_TOKEN="你的Cloudflare_API_Token" CF_APP="APP" bash <(curl -fsSL https://raw.githubusercontent.com/wumingshi654/bt-cf/main/install.sh)
```

### 方法二：Git 源码部署

```bash
git clone https://github.com/wumingshi654/bt-cf.git /root/bt-cf
cd /root/bt-cf
bash install.sh
```

---

## ⚙️ 配置说明

配置文件存放于 `/etc/bt-cf/config.json`（权限 600）：

```json
{
  "api_token": "YOUR_CLOUDFLARE_API_TOKEN",
  "app_name": "APP",
  "zone_name": "",
  "server_ip": "",
  "dns_proxied": true
}
```

> **注意**：
> - `server_ip` 保持留空 `""`，`bt-cf` 会在每次运行时动态获取本机的公网 IP，完美适配单节点与多节点部署。
> - `zone_name` 留空时会自动根据域名后缀匹配 Cloudflare 对应的托管 Zone。

### 命令行快速配置

```bash
# 设置 API Token 与 Zero Trust 应用程序名称
bt-cf config --token "你的_Cloudflare_API_Token" --app "APP"

# 查看当前配置与探测到的 VPS IP
bt-cf config

# 测试 Cloudflare API 连接通信
bt-cf status
```

---

## 📖 命令使用指南

### 1. 查看所有站点状态 (`list`)
输出当前 VPS 上 aaPanel 站点清单、真实反代目标、端口运行进程（支持 Docker 容器与原生进程识别）以及 Cloudflare Zero Trust / 小橙云状态：
```bash
bt-cf list
```

### 2. 添加站点 (`add`)
创建 aaPanel 站点，自动配置反向代理与默认 SSL，并在 Cloudflare 配置 DNS 和 Zero Trust：
```bash
# 推荐全自动：建站 + 反代到本机 8123 + 自动配置 SSL + CF解析 (开启小橙云) + 加入 Zero Trust APP
bt-cf add test.example.com -p 8123

# 支持 --port 或 --proxy-port 传参
bt-cf add test.example.com --proxy-port 8123
bt-cf add test.example.com --port 8123

# 自定义完整反代地址 (支持跨主机或特定路径)
bt-cf add test.example.com --proxy-site http://10.0.0.5:8080

# 不加入 Zero Trust (对外公开站点)
bt-cf add blog.example.com -p 3000 --no-zt

# 仅 DNS 解析 (关闭小橙云直连)
bt-cf add api.example.com -p 8080 --no-proxy

# 临时指定解析 IP (覆盖自动探测)
bt-cf add custom.example.com -p 8080 --ip 1.2.3.4
```

### 3. 修改反代端口 (`proxy`)
支持通过 `bt-cf list` 中的站点 **ID** 或 **域名** 一键修改反向代理目标，自动保留自定义配置、校验语法并重载 Web 服务：
```bash
# 通过站点 ID 修改反代端口
bt-cf proxy 26 8123

# 通过域名修改反代端口
bt-cf proxy app.example.com 8123

# 修改为完整目标 URL
bt-cf proxy 26 http://127.0.0.1:8123
```

### 4. 核查孤儿域名 (`check`)
扫描 Cloudflare 中解析到当前 VPS 公网 IP，但在 aaPanel 中未建站的域名：
```bash
bt-cf check
```

### 5. 切换 Zero Trust 保护 (`toggle-zt`)
无需登录 Cloudflare 控制台，随时开启或关闭域名的 Access 保护：
```bash
# 开启 Zero Trust 保护
bt-cf toggle-zt test.example.com on

# 解除 Zero Trust 保护
bt-cf toggle-zt test.example.com off

# 状态自动取反切换
bt-cf toggle-zt test.example.com
```

### 6. 彻底删除站点 (`del`)
同时从 aaPanel 面板、Cloudflare DNS A 记录以及 Zero Trust 保护名单中移除：
```bash
bt-cf del test.example.com
```

### 7. 通信诊断 (`status`)
检查 Token 有效性、账户信息、Zone 域名及 Zero Trust 保护规则状态：
```bash
bt-cf status
```

### 8. 一键自更新 (`update`)
从 GitHub 远程仓库检查并热更新 `bt-cf` 到最新版本（支持单机 curl 部署与 git 部署自动同步）：
```bash
bt-cf update
```

---

## 🌐 多 VPS 部署最佳实践

1. **统一 API Token**：在 Cloudflare 创建一个具有 `Zone.DNS` 和 `Account.Access: Apps and Policies` 读写权限的 API Token。
2. **多节点一键分发**：在每台 VPS 上直接运行：
   ```bash
   CF_TOKEN="你的_Token" CF_APP="APP" bash <(curl -fsSL https://raw.githubusercontent.com/wumingshi654/bt-cf/main/install.sh)
   ```
3. 每台 VPS 运行 `bt-cf add` 时，会自动将域名 A 记录指向该 VPS 自身的公网 IP，多机之间互不干扰。

---

## 🗑️ 卸载

```bash
bash /root/bt-cf/uninstall.sh
# 或直接清理:
rm -f /usr/local/bin/bt-cf
rm -rf /etc/bt-cf
```

---

## 📄 开源许可证

MIT License.
