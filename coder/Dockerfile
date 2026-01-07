FROM nestybox/ubuntu-jammy-docker:latest

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
    iproute2 \
    ncat \
    less \
    net-tools \
    openssh-client \
    traceroute \
    dnsutils \
    tcpdump \
    ripgrep \
    cron \
    && rm -rf /var/lib/apt/lists/*

# Generate the desired locale (en_US.UTF-8)
RUN locale-gen en_US.UTF-8

# Make typing unicode characters in the terminal work.
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Switch to the `coder` user and set up their environment
# USER coder
