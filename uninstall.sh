#!/usr/bin/env bash
# ==============================================================================
# bt-cf 卸载脚本
# ==============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}错误: 必须使用 root 权限运行此脚本！${NC}"
    exit 1
fi

echo -e "${YELLOW}正在卸载 bt-cf...${NC}"

# 删除可执行文件
if [ -f "/usr/local/bin/bt-cf" ]; then
    rm -f /usr/local/bin/bt-cf
    echo -e "${GREEN}✓ 已移除 /usr/local/bin/bt-cf${NC}"
fi

# 询问是否保留配置
if [ -d "/etc/bt-cf" ]; then
    read -r -p "是否删除配置文件 (/etc/bt-cf)? (y/N): " confirm
    if [[ "$confirm" =~ ^[yY]$ ]]; then
        rm -rf /etc/bt-cf
        echo -e "${GREEN}✓ 已删除 /etc/bt-cf${NC}"
    else
        echo -e "${GREEN}✓ 已保留 /etc/bt-cf 配置文件${NC}"
    fi
fi

echo -e "${GREEN}${BOLD}bt-cf 卸载完成！${NC}"
