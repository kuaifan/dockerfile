FROM nestybox/ubuntu-noble-docker:latest

SHELL ["/bin/bash", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

# Install baseline packages
RUN add-apt-repository -y ppa:fish-shell/release-4 \
    && add-apt-repository -y ppa:git-core/ppa \
    && apt-get update \
    && apt-get install --yes --no-install-recommends --no-install-suggests \
    bash \
    ca-certificates \
    bash-completion \
    build-essential \
    curl \
    fish \
    git \
    git-lfs \
    htop \
    jq \
    locales \
    man \
    nano \
    pipx \
    python3 \
    python3-pip \
    software-properties-common \
    sudo \
    systemd \
    systemd-sysv \
    tree \
    unzip \
    vim \
    wget \
    rsync \
    lsof \
    socat \
    iputils-ping \
    iproute2 \
    ncat \
    less \
    net-tools \
    nload \
    openssh-client \
    openssl \
    sshpass \
    traceroute \
    dnsutils \
    tcpdump \
    gettext \
    protobuf-compiler \
    ripgrep \
    cron \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /usr/local/lib/docker/cli-plugins && \
    curl -SL https://github.com/docker/compose/releases/download/v2.40.3/docker-compose-linux-x86_64 \
      -o /usr/local/lib/docker/cli-plugins/docker-compose && \
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# Generate the desired locale (en_US.UTF-8)
RUN locale-gen en_US.UTF-8

# Install Playwright browser dependencies
RUN apt-get update -qq \
    && apt-get install -y -qq --no-install-recommends \
      libglib2.0-0 libnspr4 libnss3 libatk1.0-0 libatk-bridge2.0-0 \
      libcups2 libxcb1 libxkbcommon0 libatspi2.0-0 libx11-6 \
      libxcomposite1 libxdamage1 libxext6 libxfixes3 libxrandr2 \
      libgbm1 libcairo2 libpango-1.0-0 ca-certificates gnupg \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 24
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y -qq nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code CLI, Playwright browser, and GitHub CLI
RUN npm install -g @anthropic-ai/claude-code \
    && npx -y playwright install chromium \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update -qq && apt-get install -y -qq gh \
    && rm -rf /var/lib/apt/lists/*

# Make typing unicode characters in the terminal work.
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Switch to the `coder` user and set up their environment
# USER coder
