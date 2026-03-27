#!/usr/bin/env bash
#
# setup-keys.sh — Claude Code 설치 + API 키 자동 검증 + Shannon 적용
#
# 흐름:
#   1. Claude Code 설치 (없으면)
#   2. claude-key.txt에서 Anthropic 키를 하나씩 검증
#   3. 유효한 키 발견 시 → Claude Code + Shannon + 환경변수에 적용
#   4. 나머지 키(OpenAI, GitHub)는 Shannon .env에 적용
#
# 사용법:
#   ~/setup-keys.sh                          # 기본: ~/claude-key.txt
#   ~/setup-keys.sh /path/to/claude-key.txt

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

KEY_FILE="${1:-${HOME}/claude-key.txt}"
SHANNON_ENV="${HOME}/shannon-uncontained/.env"
BASHRC="${HOME}/.bashrc"
ANTHROPIC_API="https://api.anthropic.com/v1/messages"
TOR_SOCKS="127.0.0.1:9050"
TOR_CURL="--socks5-hostname ${TOR_SOCKS}"

# ════════════════════════════════════════════
# Step 0: Tor 확인 + 키 파일 확인
# ════════════════════════════════════════════
echo -e "${CYAN}[0/4] Tor 연결 확인...${NC}"
if ! pgrep -x tor > /dev/null 2>&1; then
    echo -e "${YELLOW}  Tor not running, starting...${NC}"
    sudo service tor start 2>/dev/null || true
fi

TOR_READY=false
for i in $(seq 1 30); do
    if curl -s --max-time 5 ${TOR_CURL} https://check.torproject.org/api/ip 2>/dev/null | grep -q IsTor; then
        TOR_READY=true
        break
    fi
    sleep 2
done

if [ "$TOR_READY" = true ]; then
    TOR_IP=$(curl -s --max-time 10 ${TOR_CURL} https://api.ipify.org 2>/dev/null || echo "unknown")
    echo -e "${GREEN}  Tor ready (exit IP: ${TOR_IP})${NC}"
    echo -e "${GREEN}  All API validation will go through Tor${NC}"
else
    echo -e "${RED}  Tor not available. API validation will use direct connection.${NC}"
    TOR_CURL=""
fi

if [ ! -f "${KEY_FILE}" ]; then
    echo -e "${RED}[ERROR] ${KEY_FILE} not found${NC}"
    echo "Create it with your API keys (one per line):"
    echo "  cat > ~/claude-key.txt << 'EOF'"
    echo "  sk-ant-api03-..."
    echo "  sk-..."
    echo "  EOF"
    exit 1
fi

# ════════════════════════════════════════════
# Step 1: Claude Code 설치
# ════════════════════════════════════════════
echo -e "${CYAN}[1/4] Claude Code 설치 확인...${NC}"
if command -v claude &>/dev/null; then
    echo -e "${GREEN}  Already installed: $(claude --version 2>/dev/null || echo 'unknown version')${NC}"
else
    echo -e "${YELLOW}  Installing Claude Code (via Tor)...${NC}"
    if [ -n "${TOR_CURL}" ]; then
        sudo npm config set proxy "socks5h://${TOR_SOCKS}" 2>/dev/null || true
        sudo npm config set https-proxy "socks5h://${TOR_SOCKS}" 2>/dev/null || true
    fi
    sudo npm install -g @anthropic-ai/claude-code 2>&1 | tail -3
    # npm proxy 설정 정리 (이후 npm install 깨짐 방지)
    sudo npm config delete proxy 2>/dev/null || true
    sudo npm config delete https-proxy 2>/dev/null || true
    if command -v claude &>/dev/null; then
        echo -e "${GREEN}  Installed: $(claude --version 2>/dev/null || echo 'OK')${NC}"
    else
        echo -e "${RED}  Installation failed. Continuing with env vars only.${NC}"
    fi
fi

# ════════════════════════════════════════════
# Step 2: 키 분류
# ════════════════════════════════════════════
echo -e "${CYAN}[2/4] API 키 분류 중...${NC}"

ANTHROPIC_KEYS=()
OPENAI_KEYS=()
GITHUB_KEYS=()
OTHER_KEYS=()

while IFS= read -r key || [ -n "$key" ]; do
    key=$(echo "$key" | xargs)
    [[ -z "$key" || "$key" == \#* ]] && continue

    if [[ "$key" == sk-ant-* ]]; then
        ANTHROPIC_KEYS+=("$key")
        echo -e "  ${GREEN}Anthropic${NC}: ${key:0:15}...${key: -4}"
    elif [[ "$key" == sk-* ]]; then
        OPENAI_KEYS+=("$key")
        echo -e "  ${GREEN}OpenAI${NC}:    ${key:0:7}...${key: -4}"
    elif [[ "$key" == ghp_* ]]; then
        GITHUB_KEYS+=("$key")
        echo -e "  ${GREEN}GitHub${NC}:    ${key:0:7}...${key: -4}"
    else
        OTHER_KEYS+=("$key")
        echo -e "  ${YELLOW}Unknown${NC}:   ${key:0:10}..."
    fi
done < "${KEY_FILE}"

echo "  Total: ${#ANTHROPIC_KEYS[@]} Anthropic, ${#OPENAI_KEYS[@]} OpenAI, ${#GITHUB_KEYS[@]} GitHub"

# ════════════════════════════════════════════
# Step 3: Anthropic 키 검증 (하나씩 시도)
# ════════════════════════════════════════════
echo -e "${CYAN}[3/4] Anthropic API 키 검증 중...${NC}"

validate_anthropic_key() {
    local key="$1"

    # sk-ant-oat01- = Claude Code OAuth token → claude --bare -p 로 검증
    # Note: Claude Code는 HTTPS_PROXY=socks5h 미지원, torsocks로 감싸야 함
    if [[ "$key" == sk-ant-oat01-* ]]; then
        if ! command -v claude &>/dev/null; then
            echo -e "  ${YELLOW}SKIP${NC}      ${key:0:15}...${key: -4}  (OAuth, claude not installed)"
            return 1
        fi
        echo -ne "  ${YELLOW}TESTING${NC}   ${key:0:15}...${key: -4}  (OAuth via claude)... "
        local output
        output=$(timeout 60 env ANTHROPIC_API_KEY="$key" \
            torsocks claude --bare -p "reply only: ok" --max-turns 1 --model claude-haiku-4-5-20251001 2>&1) || true
        if echo "$output" | grep -qi "ok"; then
            echo -e "${GREEN}VALID${NC}"
            return 0
        elif echo "$output" | grep -qi "invalid\|expired\|unauthorized\|Could not"; then
            echo -e "${RED}INVALID${NC}"
            echo -e "    ${YELLOW}${output:0:120}${NC}"
            return 1
        elif [ -n "$output" ] && ! echo "$output" | grep -qi "error"; then
            echo -e "${GREEN}VALID${NC}"
            return 0
        else
            echo -e "${RED}FAILED${NC}"
            echo -e "    ${YELLOW}${output:0:120}${NC}"
            return 1
        fi
    fi

    # sk-ant-api03- = API key → curl로 직접 검증
    local response http_code
    local payload='{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}'

    response=$(curl -s -w "\n%{http_code}" --max-time 30 \
        ${TOR_CURL} \
        "${ANTHROPIC_API}" \
        -H "Content-Type: application/json" \
        -H "x-api-key: ${key}" \
        -H "anthropic-version: 2023-06-01" \
        -d "$payload" 2>/dev/null)

    http_code=$(echo "$response" | tail -1)
    local body=$(echo "$response" | sed '$d')

    case "$http_code" in
        200)
            echo -e "  ${GREEN}VALID${NC}     ${key:0:15}...${key: -4}"
            return 0
            ;;
        401)
            echo -e "  ${RED}INVALID${NC}   ${key:0:15}...${key: -4}  (authentication failed)"
            return 1
            ;;
        403)
            echo -e "  ${RED}FORBIDDEN${NC} ${key:0:15}...${key: -4}  (permission denied)"
            return 1
            ;;
        429)
            echo -e "  ${GREEN}VALID${NC}     ${key:0:15}...${key: -4}  (rate limited, but key works)"
            return 0
            ;;
        529)
            echo -e "  ${GREEN}VALID${NC}     ${key:0:15}...${key: -4}  (API overloaded, but key works)"
            return 0
            ;;
        000)
            echo -e "  ${YELLOW}TIMEOUT${NC}   ${key:0:15}...${key: -4}  (network error)"
            return 1
            ;;
        *)
            if echo "$body" | grep -q "invalid_api_key\|expired"; then
                echo -e "  ${RED}EXPIRED${NC}   ${key:0:15}...${key: -4}"
                return 1
            fi
            echo -e "  ${YELLOW}HTTP ${http_code}${NC}  ${key:0:15}...${key: -4}"
            return 0
            ;;
    esac
}

VALID_ANTHROPIC_KEY=""

if [ ${#ANTHROPIC_KEYS[@]} -eq 0 ]; then
    echo -e "  ${YELLOW}No Anthropic keys found in ${KEY_FILE}${NC}"
else
    for key in "${ANTHROPIC_KEYS[@]}"; do
        if validate_anthropic_key "$key"; then
            VALID_ANTHROPIC_KEY="$key"
            break
        fi
    done

    if [ -z "$VALID_ANTHROPIC_KEY" ]; then
        echo -e "  ${RED}All ${#ANTHROPIC_KEYS[@]} Anthropic keys failed validation${NC}"
    fi
fi

# ════════════════════════════════════════════
# Step 4: 유효한 키 적용
# ════════════════════════════════════════════
echo -e "${CYAN}[4/4] 키 적용 중...${NC}"

# Shannon .env 초기화
if [ -f "${HOME}/shannon-uncontained/.env.example" ] && [ ! -f "${SHANNON_ENV}" ]; then
    cp "${HOME}/shannon-uncontained/.env.example" "${SHANNON_ENV}"
fi
touch "${SHANNON_ENV}"

apply_key() {
    local var="$1"
    local val="$2"

    # 현재 세션
    export "${var}=${val}"

    # .bashrc (중복 방지)
    if grep -q "^export ${var}=" "${BASHRC}" 2>/dev/null; then
        sed -i "s|^export ${var}=.*|export ${var}=${val}|" "${BASHRC}"
    else
        echo "export ${var}=${val}" >> "${BASHRC}"
    fi

    # Shannon .env (중복 방지, 주석도 활성화)
    sed -i "s|^# *${var}=.*|${var}=${val}|" "${SHANNON_ENV}"
    if grep -q "^${var}=" "${SHANNON_ENV}" 2>/dev/null; then
        sed -i "s|^${var}=.*|${var}=${val}|" "${SHANNON_ENV}"
    else
        echo "${var}=${val}" >> "${SHANNON_ENV}"
    fi
}

# Anthropic 키 적용
if [ -n "$VALID_ANTHROPIC_KEY" ]; then
    echo -e "  ${GREEN}Anthropic → Claude Code + Shannon + env${NC}"
    apply_key "ANTHROPIC_API_KEY" "$VALID_ANTHROPIC_KEY"

    # Shannon이 Anthropic을 LLM 프로바이더로 사용하도록 설정
    apply_key "LLM_PROVIDER" "anthropic"
    apply_key "LLM_MODEL" "claude-sonnet-4-20250514"
    echo -e "  ${GREEN}Shannon LLM → anthropic / claude-sonnet-4-20250514${NC}"

    # Claude Code는 ANTHROPIC_API_KEY 환경변수로 키를 인식함 (.bashrc에 이미 등록됨)
    echo -e "  ${GREEN}Claude Code will use ANTHROPIC_API_KEY from env${NC}"

    # Claude Code가 항상 Tor 경유하도록 alias 등록 (torsocks 사용)
    CLAUDE_ALIAS='alias claude="torsocks claude"'
    if ! grep -q "alias claude=" "${BASHRC}" 2>/dev/null; then
        echo "$CLAUDE_ALIAS" >> "${BASHRC}"
        echo -e "  ${GREEN}Claude Code Tor alias added to .bashrc${NC}"
    fi
fi

# OpenAI 키 적용 (첫 번째 키)
if [ ${#OPENAI_KEYS[@]} -gt 0 ]; then
    echo -e "  ${GREEN}OpenAI → Shannon + env${NC}"
    apply_key "OPENAI_API_KEY" "${OPENAI_KEYS[0]}"
fi

# GitHub 키 적용 (첫 번째 키)
if [ ${#GITHUB_KEYS[@]} -gt 0 ]; then
    echo -e "  ${GREEN}GitHub → Shannon + env${NC}"
    apply_key "GITHUB_TOKEN" "${GITHUB_KEYS[0]}"
fi

# ── 보안 ──
chmod 600 "${KEY_FILE}" "${SHANNON_ENV}"

# ════════════════════════════════════════════
# 결과 요약
# ════════════════════════════════════════════
echo ""
echo -e "${CYAN}════════════════════════════════════════${NC}"
echo -e "${CYAN} Setup Complete${NC}"
echo -e "${CYAN}════════════════════════════════════════${NC}"

if [ -n "$VALID_ANTHROPIC_KEY" ]; then
    echo -e "  Anthropic: ${GREEN}OK${NC} → Claude Code + Shannon"
else
    echo -e "  Anthropic: ${RED}NONE${NC}"
fi

[ ${#OPENAI_KEYS[@]} -gt 0 ] \
    && echo -e "  OpenAI:    ${GREEN}OK${NC} → Shannon" \
    || echo -e "  OpenAI:    ${YELLOW}not provided${NC}"

[ ${#GITHUB_KEYS[@]} -gt 0 ] \
    && echo -e "  GitHub:    ${GREEN}OK${NC} → Shannon" \
    || echo -e "  GitHub:    ${YELLOW}not provided${NC}"

echo ""
echo -e "  Run ${GREEN}source ~/.bashrc${NC} or open a new terminal."
echo -e "  Then: ${GREEN}~/shannon-tor.sh run https://target.com${NC}"
[ -n "$VALID_ANTHROPIC_KEY" ] && echo -e "  Or:   ${GREEN}claude${NC}"
