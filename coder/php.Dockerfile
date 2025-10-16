ARG BASE_IMAGE=coder:latest
FROM ${BASE_IMAGE}

USER root

ENV PHP_DEFAULT_VERSION=8.4
ENV PHP_INI_DIR=/etc/php/${PHP_DEFAULT_VERSION}
ENV PHPIZE_DEPS="autoconf dpkg-dev file g++ gcc libc6-dev make pkg-config re2c"
ENV COMPOSER_ALLOW_SUPERUSER=1
ENV PATH=/home/coder/.composer/vendor/bin:${PATH}

RUN set -eux; \
    add-apt-repository -y ppa:ondrej/php; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        $PHPIZE_DEPS \
        php${PHP_DEFAULT_VERSION}-cli \
        php${PHP_DEFAULT_VERSION}-common \
        php${PHP_DEFAULT_VERSION}-dev \
        php${PHP_DEFAULT_VERSION}-opcache \
        php${PHP_DEFAULT_VERSION}-mbstring \
        php${PHP_DEFAULT_VERSION}-xml \
        php${PHP_DEFAULT_VERSION}-zip \
        php${PHP_DEFAULT_VERSION}-bcmath \
        php${PHP_DEFAULT_VERSION}-intl \
        php${PHP_DEFAULT_VERSION}-curl \
        php${PHP_DEFAULT_VERSION}-gd \
        php${PHP_DEFAULT_VERSION}-mysql \
        php${PHP_DEFAULT_VERSION}-pgsql \
        php${PHP_DEFAULT_VERSION}-sqlite3 \
        php${PHP_DEFAULT_VERSION}-redis \
        php${PHP_DEFAULT_VERSION}-xdebug \
        unzip \
    ; \
    if update-alternatives --list php >/dev/null 2>&1; then \
        update-alternatives --set php /usr/bin/php${PHP_DEFAULT_VERSION}; \
    fi; \
    if update-alternatives --list phar >/dev/null 2>&1; then \
        update-alternatives --set phar /usr/bin/phar${PHP_DEFAULT_VERSION}; \
    fi; \
    if update-alternatives --list phar.phar >/dev/null 2>&1; then \
        update-alternatives --set phar.phar /usr/bin/phar.phar${PHP_DEFAULT_VERSION}; \
    fi; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    curl -fsSL https://getcomposer.org/installer -o /tmp/composer-setup.php; \
    php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer; \
    rm -f /tmp/composer-setup.php; \
    composer --version

RUN set -eux; \
    mkdir -p /home/coder/.composer; \
    chown -R coder:coder /home/coder/.composer

USER coder

WORKDIR /home/coder
