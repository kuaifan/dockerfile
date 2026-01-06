ARG BASE_IMAGE=kuaifan/coder:latest
FROM ${BASE_IMAGE}

ARG PYTHON_VERSION=3.14.0

USER root

# 仅安装基础运行环境所需的极简依赖
RUN set -eux; \
    apt-get update; \
    apt-get install --yes --no-install-recommends \
        curl \
        ca-certificates; \
    # 安装 uv
    curl -fsSL https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/usr/local/bin sh; \
    # 清理缓存
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# 切换到非 root 用户
# USER coder
