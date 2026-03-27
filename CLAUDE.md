# docker-codespaces

## 프로젝트 목표

GitHub Codespaces에서 **Kali Linux 기반 보안 테스팅 환경**을 원클릭으로 생성하는 것.
핵심 도구는 [shannon-uncontained](https://github.com/Steake/shannon-uncontained) (블랙박스 AI 펜테스터)이며,
모든 네트워크 트래픽은 **Tor**를 경유해야 한다.

## 아키텍처

```
GitHub Codespaces
└── Kali Linux (kalilinux/kali-rolling) ← 메인 컨테이너 (Docker-in-Docker 아님)
    ├── Tor (SOCKS5 :9050, Control :9051) ← 컨테이너 시작 시 자동 실행
    ├── shannon-uncontained (~/shannon-uncontained)
    │   ├── tor-proxy-bootstrap.mjs  ← Node.js fetch/http/https 전부 Tor 경유
    │   └── tool-runner.js (patched) ← CLI 도구에 Tor 프록시 플래그 자동 주입
    └── ~/shannon-tor.sh ← 래퍼 스크립트 (Tor 확인 → bootstrap 로드 → shannon 실행)
```

## 파일 구조

```
.devcontainer/
├── Dockerfile                 # Kali Linux + 보안 도구 + Node.js + Go + Tor
├── devcontainer.json          # Codespaces 설정 (Tor 자동 시작)
├── .env.example               # LLM 프로바이더 API 키 템플릿
├── tor-proxy-bootstrap.mjs    # Node.js 레벨 Tor 프록시 (undici dispatcher + http/https 패치)
├── tor-tool-runner-patch.mjs  # tool-runner.js에 CLI 도구별 프록시 플래그 주입 패치
└── shannon-tor.sh             # shannon 실행 래퍼 (Tor 검증 + 환경변수 + bootstrap)
```

## Tor 프록시 커버리지

shannon-uncontained은 5가지 네트워크 채널을 사용하며, 모두 Tor를 경유하도록 구성됨:

| 채널 | 처리 방식 |
|------|----------|
| Native `fetch()` | undici `setGlobalDispatcher()` SOCKS5 |
| `node-fetch` | `http.request`/`https.request` monkey-patch |
| `axios` | `HTTP_PROXY`/`HTTPS_PROXY` 환경변수 |
| OpenAI SDK (LLM) | 환경변수 + http agent 패치 |
| CLI 도구 (nmap, nuclei 등) | tool-runner.js 패치로 도구별 `--proxy` 플래그 자동 주입 |
| Playwright | `PLAYWRIGHT_CHROMIUM_PROXY` 환경변수 |

## 설치된 도구

- **보안**: nmap, sqlmap, feroxbuster, wafw00f, sslyze, nikto, dirb, whatweb
- **Go 정찰**: subfinder, httpx, katana, nuclei, gau
- **Tor**: tor, torsocks, netcat-openbsd
- **런타임**: Node.js, npm, Python 3, Go

## 사용법

```bash
# 1. LLM API 키 설정
cp .env.example .env && vim .env

# 2. Tor 경유로 shannon 실행
~/shannon-tor.sh generate https://target.com
~/shannon-tor.sh run https://target.com --strategy agentic
```

## 주의사항

- Metasploit은 빌드 시간 문제로 제외됨 (필요시 `sudo apt install metasploit-framework`)
- `kali-linux-headless` 메타패키지 대신 개별 패키지 설치로 이미지 경량화
- Docker Desktop이 로컬에 필요함 (로컬 테스트 시 `docker build -t shannon-kali .devcontainer/`)
- GUI/VNC 환경 미포함 (터미널 전용)
