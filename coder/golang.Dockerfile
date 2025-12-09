ARG BASE_IMAGE=kuaifan/coder:latest
FROM ${BASE_IMAGE}

ARG GO_VERSION=1.25
ARG GO_DIST_URL=https://go.dev/dl

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
    GOBIN=/usr/local/bin /usr/local/go/bin/go install github.com/air-verse/air@latest; \
    GOBIN=/usr/local/bin /usr/local/go/bin/go install golang.org/x/tools/gopls@latest

ENV GOROOT=/usr/local/go
ENV GOPATH=/home/coder/go
ENV PATH=/usr/local/go/bin:/home/coder/go/bin:${PATH}

USER coder
