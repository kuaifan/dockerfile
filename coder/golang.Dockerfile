ARG BASE_IMAGE=kuaifan/coder:latest
FROM ${BASE_IMAGE}

USER root

ENV GOLANG_VERSION=1.25.3
ENV GOROOT=/usr/local/go
ENV GOPATH=/home/coder/go
ENV GOTOOLCHAIN=local
ENV PATH=${GOROOT}/bin:${GOPATH}/bin:${PATH}

RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
        amd64) go_url="https://dl.google.com/go/go${GOLANG_VERSION}.linux-amd64.tar.gz"; go_sha256="0335f314b6e7bfe08c3d0cfaa7c19db961b7b99fb20be62b0a826c992ad14e0f" ;; \
        arm64) go_url="https://dl.google.com/go/go${GOLANG_VERSION}.linux-arm64.tar.gz"; go_sha256="1d42ebc84999b5e2069f5e31b67d6fc5d67308adad3e178d5a2ee2c9ff2001f5" ;; \
        armhf) go_url="https://dl.google.com/go/go${GOLANG_VERSION}.linux-armv6l.tar.gz"; go_sha256="3992bd28316484be0af36494124588581aa27e0659a436d607b11d534045bc1f" ;; \
        i386) go_url="https://dl.google.com/go/go${GOLANG_VERSION}.linux-386.tar.gz"; go_sha256="acb585c13e7acb10e3b53743c39a7996640c745dffd7d828758786bde92f44ca" ;; \
        mips64el) go_url="https://dl.google.com/go/go${GOLANG_VERSION}.linux-mips64le.tar.gz"; go_sha256="2ff582bbacb1e2600cbd6a4bdc23265ce98bd891e25a821a0286a2ba9664ed21" ;; \
        ppc64el) go_url="https://dl.google.com/go/go${GOLANG_VERSION}.linux-ppc64le.tar.gz"; go_sha256="68d1a08bf3567f330717d821b266a0be1c5080bd05dc238b5a43a24ca0c47d7c" ;; \
        riscv64) go_url="https://dl.google.com/go/go${GOLANG_VERSION}.linux-riscv64.tar.gz"; go_sha256="998f5ed86156d865bff69b9fa0e616ea392eaf32123f03da79f1e6a101d8e8ce" ;; \
        s390x) go_url="https://dl.google.com/go/go${GOLANG_VERSION}.linux-s390x.tar.gz"; go_sha256="a0b5ccd631743f01230030412fdc9252b18d96b4e63d44ba1c4e9469e79cfcb1" ;; \
        *) echo >&2 "Unsupported architecture: $arch"; exit 1 ;; \
    esac; \
    if [ "$arch" = "arm64" ]; then \
        apt-get update; \
        apt-get install -y --no-install-recommends binutils-gold; \
        rm -rf /var/lib/apt/lists/*; \
    fi; \
    tmpdir="$(mktemp -d)"; \
    cd "$tmpdir"; \
    curl -fsSL "$go_url" -o go.tgz; \
    echo "$go_sha256  go.tgz" | sha256sum -c -; \
    rm -rf "${GOROOT}"; \
    tar -C /usr/local -xzf go.tgz; \
    rm -rf "$tmpdir"; \
    go version

RUN set -eux; \
    mkdir -p "${GOPATH}/bin" "${GOPATH}/pkg" "${GOPATH}/src"; \
    chown -R coder:coder "${GOPATH}"

USER coder

WORKDIR /home/coder
