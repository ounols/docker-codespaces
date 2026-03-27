#!/usr/bin/env bash
#
# shannon-tor.sh — Run shannon-uncontained with all traffic routed through Tor
#
# Usage: ./shannon-tor.sh [shannon arguments...]
# Example: ./shannon-tor.sh generate https://target.com
#          ./shannon-tor.sh run https://target.com --strategy agentic

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

SHANNON_DIR="${HOME}/shannon-uncontained"
BOOTSTRAP="${SHANNON_DIR}/tor-proxy-bootstrap.mjs"
TOR_SOCKS="127.0.0.1:9050"

# ── Ensure Tor is running ──
if ! pgrep -x tor > /dev/null 2>&1; then
    echo -e "${YELLOW}[TOR] Tor is not running. Starting...${NC}"
    sudo service tor start
    sleep 3
fi

# Verify Tor connectivity
echo -ne "${YELLOW}[TOR] Verifying Tor connection... ${NC}"
TOR_IP=$(curl -s --max-time 15 --socks5-hostname "${TOR_SOCKS}" https://httpbin.org/ip 2>/dev/null | grep -oP '"origin":\s*"\K[^"]+' || true)
if [ -z "${TOR_IP}" ]; then
    echo -e "${RED}FAILED${NC}"
    echo -e "${RED}[TOR] Cannot connect through Tor. Check 'sudo service tor status'.${NC}"
    exit 1
fi
echo -e "${GREEN}OK (exit IP: ${TOR_IP})${NC}"

# ── Set proxy env vars for CLI tools spawned by child_process ──
export ALL_PROXY="socks5h://${TOR_SOCKS}"
export all_proxy="socks5h://${TOR_SOCKS}"
export HTTP_PROXY="socks5h://${TOR_SOCKS}"
export http_proxy="socks5h://${TOR_SOCKS}"
export HTTPS_PROXY="socks5h://${TOR_SOCKS}"
export https_proxy="socks5h://${TOR_SOCKS}"

# ── Set Playwright proxy ──
export PLAYWRIGHT_CHROMIUM_PROXY="socks5://${TOR_SOCKS}"

# ── Run shannon with the Tor bootstrap preload ──
cd "${SHANNON_DIR}"
echo -e "${GREEN}[TOR] Launching shannon-uncontained through Tor...${NC}"
echo ""
exec node --import ./tor-proxy-bootstrap.mjs shannon.mjs "$@"
