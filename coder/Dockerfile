FROM ubuntu:noble

SHELL ["/bin/bash", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

# Install the Docker apt repository
RUN apt-get update \
    && apt-get upgrade --yes --no-install-recommends --no-install-suggests \
    && apt-get install --yes --no-install-recommends --no-install-suggests \
    software-properties-common \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Add the Docker apt repository
COPY ./resources/docker-archive-keyring.gpg /usr/share/keyrings/docker-archive-keyring.gpg
COPY ./resources/docker.list /etc/apt/sources.list.d/docker.list

# Install baseline packages
RUN add-apt-repository -y ppa:fish-shell/release-4 \
    && add-apt-repository -y ppa:git-core/ppa \
    && apt-get update \
    && apt-get install --yes --no-install-recommends --no-install-suggests \
    bash \
    bash-completion \
    build-essential \
    containerd.io \
    curl \
    docker-ce \
    docker-ce-cli \
    docker-buildx-plugin \
    docker-compose-plugin \
    fish \
    git \
    git-lfs \
    htop \
    jq \
    locales \
    man \
    pipx \
    python3 \
    python3-pip \
    software-properties-common \
    sudo \
    systemd \
    systemd-sysv \
    unzip \
    vim \
    wget \
    rsync \
    lsof \
    socat \
    iputils-ping \
    net-tools \
    openssh-client \
    traceroute \
    dnsutils \
    tcpdump \
    && rm -rf /var/lib/apt/lists/*

# Enables Docker starting with systemd
RUN systemctl enable docker

# Create a symlink for standalone docker-compose usage
RUN ln -s /usr/libexec/docker/cli-plugins/docker-compose /usr/bin/docker-compose

# Generate the desired locale (en_US.UTF-8)
RUN locale-gen en_US.UTF-8

# Make typing unicode characters in the terminal work.
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Install Node.js (LTS) and Yarn
RUN set -eux; \
    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -; \
    mkdir -p /etc/apt/keyrings; \
    apt-get update; \
    apt-get install -y --no-install-recommends gnupg; \
    curl -fsSL https://dl.yarnpkg.com/debian/pubkey.gpg | gpg --dearmor -o /etc/apt/keyrings/yarn.gpg; \
    echo "deb [signed-by=/etc/apt/keyrings/yarn.gpg] https://dl.yarnpkg.com/debian stable main" > /etc/apt/sources.list.d/yarn.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends nodejs yarn; \
    corepack enable || true; \
    # Install/activate pnpm via corepack (fallback to npm global install if needed)
    corepack prepare pnpm@latest --activate || npm install -g pnpm; \
    apt-get purge -y --auto-remove gnupg; \
    rm -rf /var/lib/apt/lists/*

# Install Easytier
RUN curl -fsSL https://raw.githubusercontent.com/EasyTier/EasyTier/main/script/install.sh | bash -s install

# Remove the `ubuntu` user and add a user `coder` so that you're not developing as the `root` user
RUN userdel -r ubuntu && \
    useradd coder \
    --create-home \
    --shell=/bin/bash \
    --groups=docker \
    --uid=1000 \
    --user-group && \
    echo "coder ALL=(ALL) NOPASSWD:ALL" >>/etc/sudoers.d/nopasswd

# Switch to the `coder` user and set up their environment
USER coder

# adds user's bin directory to PATH
RUN pipx ensurepath
