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
    # install -d -o coder -g coder /home/coder/go; \
    /usr/local/go/bin/go install github.com/air-verse/air@latest; \
    /usr/local/go/bin/go install golang.org/x/tools/gopls@latest; \
    /usr/local/go/bin/go install google.golang.org/protobuf/cmd/protoc-gen-go@latest; \
    /usr/local/go/bin/go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest; \
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
        curl; \
    curl -fsSL https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/usr/local/bin sh; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# USER coder
