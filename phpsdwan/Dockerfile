FROM --platform=$TARGETPLATFORM phpswoole/swoole:php8.0

# Installation dependencies and PHP core extensions
RUN apt-get update \
        && apt-get -y install --no-install-recommends --assume-yes \
        libpng-dev \
        libzip-dev \
        libzip4 \
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
        dnsmasq \
        cron \
        ncat \
        libyaml-dev

RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
        && docker-php-ext-install pdo_mysql gd pcntl zip bcmath

RUN mkdir -p /usr/src/php/ext/redis \
        && curl -L https://github.com/phpredis/phpredis/archive/5.3.2.tar.gz | tar xvz -C /usr/src/php/ext/redis --strip 1 \
        && echo 'redis' >> /usr/src/php-available-exts \
        && docker-php-ext-install redis

RUN echo "deb http://deb.debian.org/debian buster-backports main" >> /etc/apt/sources.list \
        && echo "deb http://ppa.launchpad.net/ansible/ansible/ubuntu trusty main" >> /etc/apt/sources.list \
        && apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 93C4A3FD7BB9C367 \
        && apt-get update \
        && apt-get install -y wireguard openresolv ansible openssh-client

RUN echo "* * * * * sh /var/www/docker/crontab/crontab.sh" > /tmp/crontab \
        && crontab /tmp/crontab \
        && rm -rf /tmp/crontab

RUN rm -r /var/lib/apt/lists/*

RUN pecl install yaml \
        && echo "extension=yaml.so" > /usr/local/etc/php/conf.d/ext-yaml.ini

WORKDIR /var/www

# docker buildx build --platform linux/arm64,linux/amd64 -t kuaifan/phpsdwan:8.0 . --push
