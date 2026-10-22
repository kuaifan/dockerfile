FROM golang:1.20.2 AS dooso

WORKDIR /go/src
COPY ./private-repo/dooso /go/src/dooso
RUN cd /go/src/dooso && \
    go build -buildmode=c-shared -o lib/doo.so main.go


# 镜像 tag 取自本文件名（config.ini: variantTagMode=raw），即 kuaifan/php:swoole-8.4.27
# 基础镜像 6.2-php8.4 为浮动 tag，构建时（2026-10-22）为 PHP 8.4.27 + Swoole 6.2.3，
# 已修复 CVE-2026-109618 / CVE-2026-109619（PHP2Shell RCE）；旧 tag swoole-8.4 为 PHP 8.4.21，存在上述漏洞
# 升级 PHP 补丁版本时：重命名本文件为新版本号，并同步 config.ini 的 latestTag 与 dootask 的 docker-compose.yml
FROM phpswoole/swoole:6.2-php8.4

# Installation dependencies and PHP core extensions
RUN apt-get update \
        && apt-get -y install --no-install-recommends --assume-yes \
        libpng-dev \
        libzip-dev \
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

# imagick >= 3.8 才支持 PHP 8.4；redis 扩展 base 镜像已自带 6.3.0（旧版 phpredis-5.3.2 tarball 无法在 8.4 编译）
RUN pecl install imagick \
        && docker-php-ext-enable imagick

RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
        && docker-php-ext-install pdo_mysql gd pcntl zip bcmath gmp ldap exif ffi

COPY ./plugins/pngquant-linux.tar.bz2 /tmp/

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
