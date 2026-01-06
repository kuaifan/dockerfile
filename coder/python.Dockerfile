ARG BASE_IMAGE=kuaifan/coder:latest
FROM nestybox/ubuntu-jammy-docker:latest

ARG PYTHON_VERSION=3.14.0

USER root

RUN set -eux; \
    apt-get update; \
    apt-get install --yes --no-install-recommends --no-install-suggests \
        build-essential \
        curl \
        libbz2-dev \
        libffi-dev \
        libgdbm-compat-dev \
        libgdbm-dev \
        liblzma-dev \
        libncurses5-dev \
        libncursesw5-dev \
        libreadline-dev \
        libsqlite3-dev \
        libssl-dev \
        tk-dev \
        uuid-dev \
        wget \
        xz-utils \
        zlib1g-dev; \
    curl -fsSL "https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz" -o /tmp/Python.tgz; \
    tar -xf /tmp/Python.tgz -C /tmp; \
    cd /tmp/Python-${PYTHON_VERSION}; \
    ./configure --enable-optimizations --with-ensurepip=install --prefix=/usr/local; \
    make -j "$(nproc)"; \
    make altinstall; \
    update-alternatives --install /usr/bin/python3 python3 /usr/local/bin/python3.14 1; \
    update-alternatives --set python3 /usr/local/bin/python3.14; \
    update-alternatives --install /usr/bin/pip3 pip3 /usr/local/bin/pip3.14 1; \
    update-alternatives --set pip3 /usr/local/bin/pip3.14; \
    /usr/local/bin/python3.14 -m pip install --upgrade pip; \
    cd /; \
    rm -rf /tmp/Python-${PYTHON_VERSION} /tmp/Python.tgz; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

USER coder
