#!/usr/bin/env bash
#
# init.sh — 컨테이너 초기화 스크립트
#
# Codespaces: postCreateCommand에서 자동 실행
# 로컬 Docker: 수동 실행 → ~/init.sh
#
# 흐름:
#   1. Tor 시작 + 부트스트랩 대기
#   2. Shannon 의존성 설치
#   3. API 키 자동 설정 (claude-key.txt 존재 시)

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── 1. Tor 시작 ──
echo -e "${CYAN}[1/3] Tor 시작...${NC}"
if pgrep -x tor > /dev/null 2>&1; then
    echo -e "${GREEN}  Already running${NC}"
else
    sudo service tor start
fi

echo -ne "${YELLOW}  Waiting for bootstrap... ${NC}"
TOR_OK=false
for i in $(seq 1 60); do
    if curl -s --max-time 5 --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip | grep -q IsTor; then
        TOR_OK=true
        break
    fi
    sleep 2
done

if [ "$TOR_OK" = true ]; then
    TOR_IP=$(curl -s --max-time 10 --socks5-hostname 127.0.0.1:9050 https://api.ipify.org 2>/dev/null || echo "unknown")
    echo -e "${GREEN}Ready (exit IP: ${TOR_IP})${NC}"
else
    echo -e "${RED}Timeout (continuing without Tor verification)${NC}"
fi

# ── 2. Shannon 의존성 ──
echo -e "${CYAN}[2/3] Shannon 의존성 확인...${NC}"
cd ~/shannon-uncontained
if [ -d node_modules ] && [ -f node_modules/.package-lock.json ]; then
    echo -e "${GREEN}  Already installed${NC}"
else
    npm install 2>&1 | tail -3
fi

# ── 3. API 키 설정 ──
echo -e "${CYAN}[3/3] API 키 설정...${NC}"
if [ -f ~/claude-key.txt ]; then
    ~/setup-keys.sh
else
    echo -e "${YELLOW}  ~/claude-key.txt not found, skipping${NC}"
    echo -e "${YELLOW}  Create it and run ~/setup-keys.sh manually${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN} Environment Ready${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "  ${CYAN}Shannon:${NC}  ~/shannon-tor.sh run https://target.com"
echo -e "  ${CYAN}Claude:${NC}   claude (Tor alias auto-applied)"
echo -e "  ${CYAN}Keys:${NC}     ~/setup-keys.sh"
