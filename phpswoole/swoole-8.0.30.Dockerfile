FROM golang:1.20.2 AS dooso

WORKDIR /go/src
COPY ./private-repo/dooso /go/src/dooso
RUN cd /go/src/dooso && \
    go build -buildmode=c-shared -o lib/doo.so main.go


# PHP 8.0.30 + 官方最小回移补丁（CVE-2026-109618 / CVE-2026-109619）。
# 补丁来自 PHP 安全团队分支 PHP-8.0-CVE-2026-109618-109619（commit 82f8f31b），仅改 18 个核心文件；
# 上游 phpswoole/swoole:php8.0 自 2024-05 起不再更新，PHP 8.0 已 EOL，不会再有官方发行版。
FROM phpswoole/swoole:php8.0 AS php-builder

# Debian 11 已 EOL，包已从 deb.debian.org 移入 archive；不切源会 404
RUN printf '%s\n' \
        'deb http://archive.debian.org/debian bullseye main' \
        'deb http://archive.debian.org/debian bullseye-updates main' \
        'deb http://archive.debian.org/debian-security bullseye-security main' \
        > /etc/apt/sources.list \
        && printf 'Acquire::Check-Valid-Until "false";\n' > /etc/apt/apt.conf.d/99archive \
        && apt-get update \
        && apt-get -y install --no-install-recommends --assume-yes \
        $PHPIZE_DEPS \
        patch \
        libargon2-dev \
        libcurl4-openssl-dev \
        libonig-dev \
        libreadline-dev \
        libsodium-dev \
        libsqlite3-dev \
        libssl-dev \
        libxml2-dev \
        zlib1g-dev \
        && rm -rf /var/lib/apt/lists/*

RUN docker-php-source extract \
        && curl -fsSL -o /tmp/php2shell.patch \
            https://github.com/php/php-src/commit/82f8f31b16a035c1b67cc253e79f7cc288f4cc20.patch \
        && cd /usr/src/php \
        && patch -p1 --batch < /tmp/php2shell.patch \
        && export CFLAGS="$PHP_CFLAGS" CPPFLAGS="$PHP_CPPFLAGS" LDFLAGS="$PHP_LDFLAGS" \
        && gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)" \
        && debMultiarch="$(dpkg-architecture --query DEB_BUILD_MULTIARCH)" \
        && if [ ! -d /usr/include/curl ]; then ln -sfnT "/usr/include/$debMultiarch/curl" /usr/local/include/curl; fi \
        && ./configure \
            --build="$gnuArch" \
            --with-config-file-path="$PHP_INI_DIR" \
            --with-config-file-scan-dir="$PHP_INI_DIR/conf.d" \
            --enable-option-checking=fatal \
            --with-mhash \
            --with-pic \
            --enable-ftp \
            --enable-mbstring \
            --enable-mysqlnd \
            --with-password-argon2 \
            --with-sodium=shared \
            --with-pdo-sqlite=/usr \
            --with-sqlite3=/usr \
            --with-curl \
            --with-iconv \
            --with-openssl \
            --with-readline \
            --with-zlib \
            --enable-phpdbg \
            --enable-phpdbg-readline \
            --with-pear \
            --with-libdir="lib/$debMultiarch" \
            --enable-embed \
        && make -j"$(nproc)" \
        && make install \
        && docker-php-source delete \
        && rm -f /tmp/php2shell.patch


FROM phpswoole/swoole:php8.0

# 只替换 PHP 运行时与头文件；PHP 版本仍为 8.0.30，扩展 ABI 不变，
# base 镜像中的 swoole / redis / opcache 等 .so 无需重编。
COPY --from=php-builder /usr/local/ /usr/local/

# Installation dependencies and PHP core extensions
RUN printf '%s\n' \
        'deb http://archive.debian.org/debian bullseye main' \
        'deb http://archive.debian.org/debian bullseye-updates main' \
        'deb http://archive.debian.org/debian-security bullseye-security main' \
        > /etc/apt/sources.list \
        && printf 'Acquire::Check-Valid-Until "false";\n' > /etc/apt/apt.conf.d/99archive \
        && apt-get update \
        && apt-get -y install --no-install-recommends --assume-yes \
        libpng-dev \
        libzip-dev \
        libzip4 \
        libldap2-dev \
        libffi-dev \
        zip \
        unzip \
        git \
        net-tools \
        iputils-ping \
        vim \
        supervisor \
        sudo \
        curl \
        dirmngr \
        apt-transport-https \
        lsb-release \
        ca-certificates \
        libjpeg-dev \
        libfreetype6-dev \
        inotify-tools \
        sshpass \
        ssh \
        cron \
        libgmp-dev \
        libmagickwand-dev \
        openvpn \
        ffmpeg \
        expect

RUN pecl install imagick \
        && docker-php-ext-enable imagick

RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
        && docker-php-ext-install pdo_mysql gd pcntl zip bcmath gmp ldap exif ffi

COPY ./plugins/phpredis-5.3.2.tar.gz /tmp/
COPY ./plugins/pngquant-linux.tar.bz2 /tmp/

RUN mkdir -p /usr/src/php/ext/redis \
        && tar xvz -C /usr/src/php/ext/redis --strip 1 -f /tmp/phpredis-5.3.2.tar.gz \
        && echo 'redis' >> /usr/src/php-available-exts \
        && docker-php-ext-install redis

RUN mkdir /tmp/pngquant_temp \
        && tar -xvj -C /tmp/pngquant_temp -f /tmp/pngquant-linux.tar.bz2 \
        && mv /tmp/pngquant_temp/pngquant /usr/local/bin \
        && rm -r /tmp/pngquant_temp

RUN echo "* * * * * sh /var/www/docker/crontab/crontab.sh" > /tmp/crontab \
        && crontab /tmp/crontab \
        && rm -rf /tmp/crontab

RUN rm -r /var/lib/apt/lists/*

RUN rm -f /etc/supervisor/service.d/swoole.conf

RUN mkdir /usr/lib/doo
COPY --from=dooso /go/src/dooso/lib /usr/lib/doo

ENTRYPOINT ["/entrypoint.sh"]
CMD []

WORKDIR "/var/www/"
