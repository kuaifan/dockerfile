ARG BASE_IMAGE=kuaifan/coder:latest
FROM ${BASE_IMAGE}

ARG PHP_VERSION=8.4

USER root

RUN set -eux; \
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
        composer; \
    update-alternatives --set php /usr/bin/php${PHP_VERSION}; \
    update-alternatives --set phar /usr/bin/phar${PHP_VERSION}; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# USER coder
