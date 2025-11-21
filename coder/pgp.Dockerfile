ARG BASE_IMAGE=kuaifan/coder:latest
FROM ${BASE_IMAGE}

ARG GO_VERSION=1.25
ARG GO_DIST_URL=https://go.dev/dl
ARG PHP_VERSION=8.4
ARG PYTHON_VERSION=3.14.0

USER root

RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "${arch}" in \
        amd64) go_arch=amd64 ;; \
        arm64) go_arch=arm64 ;; \
        armhf) go_arch=armv6l ;; \
        ppc64el) go_arch=ppc64le ;; \
        s390x) go_arch=s390x ;; \
        *) echo "unsupported architecture: ${arch}" >&2; exit 1 ;; \
    esac; \
    tmp_tar="/tmp/go.tgz"; \
    rm -f "${tmp_tar}"; \
    for candidate in "${GO_VERSION}" "${GO_VERSION}.0" "${GO_VERSION}.0rc1" "${GO_VERSION}.0beta1" "${GO_VERSION}rc1" "${GO_VERSION}beta1"; do \
        artifact="go${candidate}.linux-${go_arch}.tar.gz"; \
        url="${GO_DIST_URL%/}/${artifact}"; \
        if curl -fsSL "${url}" -o "${tmp_tar}"; then \
            echo "Downloaded Go archive: ${artifact}"; \
            break; \
        fi; \
    done; \
    if [ ! -s "${tmp_tar}" ]; then \
        echo "Could not locate Go ${GO_VERSION} artifacts at ${GO_DIST_URL}" >&2; \
        exit 1; \
    fi; \
    rm -rf /usr/local/go; \
    tar -C /usr/local -xzf "${tmp_tar}"; \
    rm -f "${tmp_tar}"; \
    install -d -o coder -g coder /home/coder/go; \
    add-apt-repository -y ppa:ondrej/php; \
    apt-get update; \
    apt-get install --yes --no-install-recommends --no-install-suggests \
        php${PHP_VERSION} \
        php${PHP_VERSION}-cli \
        php${PHP_VERSION}-common \
        php${PHP_VERSION}-curl \
        php${PHP_VERSION}-mbstring \
        php${PHP_VERSION}-mysql \
        php${PHP_VERSION}-pgsql \
        php${PHP_VERSION}-sqlite3 \
        php${PHP_VERSION}-xml \
        php${PHP_VERSION}-zip \
        php${PHP_VERSION}-opcache \
        composer \
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
    update-alternatives --set php /usr/bin/php${PHP_VERSION}; \
    update-alternatives --set phar /usr/bin/phar${PHP_VERSION}; \
    python_short="$(printf '%s' "${PYTHON_VERSION}" | cut -d. -f1,2)"; \
    curl -fsSL "https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tgz" -o /tmp/Python.tgz; \
    tar -xf /tmp/Python.tgz -C /tmp; \
    cd "/tmp/Python-${PYTHON_VERSION}"; \
    ./configure --enable-optimizations --with-ensurepip=install --prefix=/usr/local; \
    make -j "$(nproc)"; \
    make altinstall; \
    python_bin="/usr/local/bin/python${python_short}"; \
    pip_bin="/usr/local/bin/pip${python_short}"; \
    update-alternatives --install /usr/bin/python3 python3 "${python_bin}" 1; \
    update-alternatives --set python3 "${python_bin}"; \
    update-alternatives --install /usr/bin/pip3 pip3 "${pip_bin}" 1; \
    update-alternatives --set pip3 "${pip_bin}"; \
    "${python_bin}" -m pip install --upgrade pip; \
    cd /; \
    rm -rf "/tmp/Python-${PYTHON_VERSION}" /tmp/Python.tgz; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

ENV GOROOT=/usr/local/go
ENV GOPATH=/home/coder/go
ENV PATH=/usr/local/go/bin:/home/coder/go/bin:${PATH}

USER coder
