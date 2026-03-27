FROM kalilinux/kali-rolling

ENV DEBIAN_FRONTEND=noninteractive

# ── Layer 0: Fix broken HTTPS mirrors in Kali CDN rotation ──
RUN echo 'Acquire::https::Verify-Peer "false";' > /etc/apt/apt.conf.d/99no-ssl-verify && \
    echo "deb http://http.kali.org/kali kali-rolling main non-free non-free-firmware contrib" > /etc/apt/sources.list

# ── Layer 1: System packages + security tools ──
RUN apt-get update && \
    apt-get install -y --fix-missing \
    # Base utilities
    sudo ca-certificates curl wget git vim nano \
    net-tools iputils-ping openssh-client dnsutils whois \
    unzip jq build-essential procps locales \
    # Node.js 20.x
    nodejs npm \
    # Python 3
    python3 python3-pip python3-venv \
    # Go
    golang \
    # Security tools (available in Kali repos)
    nmap \
    sqlmap \
    feroxbuster \
    wafw00f \
    sslyze \
    nikto \
    dirb \
    whatweb \
    # Tor
    tor torsocks netcat-openbsd \
    # Playwright dependencies
    libnss3 libatk1.0-0 libatk-bridge2.0-0 libcups2 \
    libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 \
    libxrandr2 libgbm1 libpango-1.0-0 libcairo2 libasound2t64 \
    libxshmfence1 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ── Layer 2: Tor configuration ──
RUN echo "\n## Auto-configured for Codespaces\nSocksPort 9050\nControlPort 9051\nCookieAuthentication 1" >> /etc/tor/torrc

# ── Layer 3: Locale setup ──
RUN sed -i 's/# en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8

# ── Layer 4: Create kali user ──
RUN useradd -m -s /bin/bash kali && \
    echo "kali:kali" | chpasswd && \
    echo "kali ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# ── Layer 5: Go-based recon tools (as kali user) ──
USER kali
ENV GOPATH=/home/kali/go
ENV PATH="${GOPATH}/bin:/home/kali/.local/bin:${PATH}"

RUN go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest && \
    go install github.com/projectdiscovery/httpx/cmd/httpx@latest && \
    go install github.com/projectdiscovery/katana/cmd/katana@latest && \
    go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest && \
    go install github.com/lc/gau/v2/cmd/gau@latest && \
    chmod -R u+w ${GOPATH}/pkg ${GOPATH}/src 2>/dev/null; rm -rf ${GOPATH}/pkg ${GOPATH}/src

# ── Layer 6: Clone and setup shannon-uncontained ──
WORKDIR /home/kali
RUN git clone https://github.com/Steake/shannon-uncontained.git && \
    cd shannon-uncontained && \
    npm install && \
    npm install undici socks-proxy-agent

# ── Layer 7: Install Tor proxy integration ──
COPY --chown=kali:kali tor-proxy-bootstrap.mjs /home/kali/shannon-uncontained/tor-proxy-bootstrap.mjs
COPY --chown=kali:kali tor-tool-runner-patch.mjs /home/kali/shannon-uncontained/tor-tool-runner-patch.mjs
COPY --chown=kali:kali shannon-tor.sh /home/kali/shannon-tor.sh
RUN chmod +x /home/kali/shannon-tor.sh

# Patch tool-runner.js to inject Tor proxy flags into CLI tools
RUN cd /home/kali/shannon-uncontained && node tor-tool-runner-patch.mjs

WORKDIR /home/kali/shannon-uncontained
