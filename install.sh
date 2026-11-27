#!/usr/bin/env bash
# ==============================================================================
# bt-cf: aaPanel & Cloudflare DNS / Zero Trust 一键安装与配置脚本
# 支持多 VPS 节点部署，公网 IP 自动动态探测（绝不硬编码）
# Repository: https://github.com/wumingshi654/bt-cf
# ==============================================================================

set -e

# ANSI 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}"
echo "=========================================================="
echo "          bt-cf 一键快速部署与管理工具"
echo "  aaPanel & Cloudflare DNS / Zero Trust 联动管理 CLI"
echo "=========================================================="
echo -e "${NC}"

# 1. 检查 root 权限
if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}错误: 必须使用 root 权限运行此脚本！${NC}"
    exit 1
fi

# 2. 检测 Python 3 与 aaPanel 环境
echo -e "${BLUE}[1/5] 检查运行环境...${NC}"
PANEL_DIR="/www/server/panel"
PY_BIN=""

if [ -f "${PANEL_DIR}/pyenv/bin/python3" ]; then
    PY_BIN="${PANEL_DIR}/pyenv/bin/python3"
    PIP_BIN="${PANEL_DIR}/pyenv/bin/pip"
    echo -e "${GREEN}✓ 检测到 aaPanel 内置 Python 环境: ${PY_BIN}${NC}"
elif command -v python3 >/dev/null 2>&1; then
    PY_BIN="$(command -v python3)"
    PIP_BIN="$(command -v pip3 2>/dev/null || command -v pip 2>/dev/null || true)"
    echo -e "${GREEN}✓ 检测到系统 Python 环境: ${PY_BIN}${NC}"
else
    echo -e "${RED}错误: 未检测到 Python 3 环境，请先安装 Python 3 或 aaPanel！${NC}"
    exit 1
fi

# 确保 requests 依赖库可用
if ! $PY_BIN -c "import requests" >/dev/null 2>&1; then
    echo -e "${YELLOW}正在安装 Python requests 依赖...${NC}"
    if [ -n "$PIP_BIN" ] && [ -x "$PIP_BIN" ]; then
        $PIP_BIN install requests >/dev/null 2>&1 || true
    fi
fi

# 3. 安装 bt-cf 可执行文件到 /usr/local/bin
echo -e "${BLUE}[2/5] 安装 bt-cf 命令行工具...${NC}"
BIN_TARGET="/usr/local/bin/bt-cf"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"

# 清理原有旧文件或软链接
[ -e "${BIN_TARGET}" ] || [ -L "${BIN_TARGET}" ] && rm -f "${BIN_TARGET}"

if [ -f "${SCRIPT_DIR}/bt-cf" ]; then
    cp -f "${SCRIPT_DIR}/bt-cf" "${BIN_TARGET}"
else
    # 远程 curl 管道执行模式：从 GitHub 仓库拉取最新 bt-cf 脚本
    RAW_URL="https://raw.githubusercontent.com/wumingshi654/bt-cf/main/bt-cf"
    echo -e "${CYAN}正在下载最新 bt-cf 脚本 (${RAW_URL})...${NC}"

    AUTH_HEADER=()
    GH_T="${GITHUB_TOKEN:-$GH_TOKEN}"
    if [ -n "$GH_T" ]; then
        AUTH_HEADER=(-H "Authorization: token ${GH_T}")
    fi

    curl -fsSL "${AUTH_HEADER[@]}" --connect-timeout 10 -o "${BIN_TARGET}" "${RAW_URL}" || {
        echo -e "${RED}错误: 下载 bt-cf 失败！${NC}"
        echo -e "${YELLOW}排查提示:${NC}"
        echo -e "  1. 若 GitHub 仓库为 Private (私有)，请在 GitHub 仓库设置 (Settings -> Danger Zone) 中将其设为 Public。"
        echo -e "  2. 或带 GITHUB_TOKEN 安装: ${CYAN}GITHUB_TOKEN=\"你的Token\" bash install.sh${NC}"
        exit 1
    }
fi

chmod +x "${BIN_TARGET}"
echo -e "${GREEN}✓ bt-cf 已成功安装至: ${BIN_TARGET}${NC}"

# 4. 配置目录与文件初始化
echo -e "${BLUE}[3/5] 初始化配置文件...${NC}"
CONFIG_DIR="/etc/bt-cf"
CONFIG_FILE="${CONFIG_DIR}/config.json"
mkdir -p "${CONFIG_DIR}"

# 优先级: 环境变量 > 交互式输入 > 保留原有配置 > 默认模版
ENV_TOKEN="${CF_TOKEN:-$TOKEN}"
ENV_APP="${CF_APP:-$APP}"
ENV_ZONE="${CF_ZONE:-$ZONE}"

if [ ! -f "${CONFIG_FILE}" ]; then
    TOKEN_VAL=""
    APP_VAL="APP"
    ZONE_VAL=""

    if [ -n "$ENV_TOKEN" ]; then
        TOKEN_VAL="$ENV_TOKEN"
        [ -n "$ENV_APP" ] && APP_VAL="$ENV_APP"
        [ -n "$ENV_ZONE" ] && ZONE_VAL="$ENV_ZONE"
    elif [ -r /dev/tty ]; then
        echo -e "${CYAN}首次部署，请输入 Cloudflare 配置信息 (直接回车可跳过后续通过命令配置):${NC}"
        read -r -p "Cloudflare API Token: " input_token < /dev/tty || true
        TOKEN_VAL="$(echo "$input_token" | tr -d ' ')"
        if [ -n "$TOKEN_VAL" ]; then
            read -r -p "Zero Trust APP 名称 [默认 APP]: " input_app < /dev/tty || true
            [ -n "$input_app" ] && APP_VAL="$(echo "$input_app" | tr -d ' ')"
            read -r -p "托管主域名 Zone [留空自动匹配]: " input_zone < /dev/tty || true
            [ -n "$input_zone" ] && ZONE_VAL="$(echo "$input_zone" | tr -d ' ')"
        fi
    fi

    cat > "${CONFIG_FILE}" <<EOF
{
  "api_token": "${TOKEN_VAL}",
  "app_name": "${APP_VAL}",
  "zone_name": "${ZONE_VAL}",
  "server_ip": "",
  "dns_proxied": true
}
EOF
    chmod 600 "${CONFIG_FILE}"
    echo -e "${GREEN}✓ 已创建配置文件: ${CONFIG_FILE}${NC}"
else
    echo -e "${GREEN}✓ 保留已有配置文件: ${CONFIG_FILE}${NC}"
    # 如果指定了环境变量，则更新配置
    if [ -n "$ENV_TOKEN" ] || [ -n "$ENV_APP" ] || [ -n "$ENV_ZONE" ]; then
        ${BIN_TARGET} config ${ENV_TOKEN:+--token "$ENV_TOKEN"} ${ENV_APP:+--app "$ENV_APP"} ${ENV_ZONE:+--zone "$ENV_ZONE"} >/dev/null 2>&1 || true
    fi
fi

# 5. 动态检测本节点 VPS 公网 IP
echo -e "${BLUE}[4/5] 动态探测当前 VPS 公网 IP...${NC}"
DETECTED_IP="$($PY_BIN -c "import subprocess, re; out = subprocess.check_output(['${BIN_TARGET}', 'config']).decode('utf-8'); m = re.search(r'当前 VPS 公网 IP:\s+.*?([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})', out); print(m.group(1) if m else '')" 2>/dev/null || true)"
if [ -z "$DETECTED_IP" ] || [ "$DETECTED_IP" = "127.0.0.1" ]; then
    DETECTED_IP="$(curl --noproxy "*" -4 -s --connect-timeout 3 https://api.ipify.org 2>/dev/null || curl --noproxy "*" -4 -s --connect-timeout 3 https://ifconfig.me/ip 2>/dev/null || echo "动态获取")"
fi
echo -e "${GREEN}✓ 当前节点 IP: ${BOLD}${DETECTED_IP}${NC} (动态自动识别，无需手动修改)"

# 6. 测试连接状态
echo -e "${BLUE}[5/5] 测试 Cloudflare 与 aaPanel 联动...${NC}"
if ${BIN_TARGET} status >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Cloudflare API 通信验证成功！${NC}"
else
    echo -e "${YELLOW}提示: 尚未配置有效的 Cloudflare API Token 或网络连接受限。${NC}"
    echo -e "可稍后运行以下命令完成配置:"
    echo -e "  ${BOLD}bt-cf config --token <你的Cloudflare_Token> --app APP${NC}"
fi

echo -e "\n${GREEN}${BOLD}=========================================================="
echo "          bt-cf 已成功部署并就绪！"
echo -e "==========================================================${NC}"
echo -e "常用命令速查:"
echo -e "  ${CYAN}bt-cf list${NC}                        # 查看所有域名及 Zero Trust 状态"
echo -e "  ${CYAN}bt-cf proxy <ID/域名> <端口>${NC}       # 一键修改反代目标端口"
echo -e "  ${CYAN}bt-cf add <域名>${NC}                   # 添加域名 (建站 + CF解析 + 进ZT)"
echo -e "  ${CYAN}bt-cf add <域名> --no-zt${NC}           # 仅建站并加 DNS，不加入 Zero Trust"
echo -e "  ${CYAN}bt-cf add <域名> --no-proxy${NC}        # 不开启小橙云 (仅 DNS 直连)"
echo -e "  ${CYAN}bt-cf check${NC}                       # 检查 CF 解析到本机但未建站的域名"
echo -e "  ${CYAN}bt-cf toggle-zt <域名> [on|off]${NC}   # 随时开启/关闭 Zero Trust 保护"
echo -e "  ${CYAN}bt-cf del <域名>${NC}                   # 彻底删除 (面板 + DNS + ZT)"
echo -e "  ${CYAN}bt-cf update${NC}                     # 从 GitHub 检查并一键更新到最新版本"
echo -e "  ${CYAN}bt-cf status${NC}                     # 查看通信状态与诊断信息"
echo -e "  ${CYAN}bt-cf config${NC}                     # 查看或修改配置"
echo -e "==========================================================\n"
