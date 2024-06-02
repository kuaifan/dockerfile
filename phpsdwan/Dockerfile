FROM golang:1.20.2 AS dooso

WORKDIR /go/src
COPY ./private-repo/dooso /go/src/dooso
RUN cd /go/src/dooso && \
    go build -buildmode=c-shared -o lib/doo.so main.go


FROM phpswoole/swoole:php8.0

# Installation dependencies and PHP core extensions
RUN apt-get update \
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
        dnsmasq \
        cron \
        ncat \
        libyaml-dev \
        libmagickwand-dev \
        wireguard \
        openresolv \
        openssh-client \
        openvpn \
        ffmpeg \
        expect

RUN pecl install imagick \
        && docker-php-ext-enable imagick

RUN docker-php-ext-configure gd --with-freetype --with-jpeg \
        && docker-php-ext-install pdo_mysql gd pcntl zip bcmath ldap exif ffi

RUN mkdir -p /usr/src/php/ext/redis \
        && curl -L https://github.com/phpredis/phpredis/archive/5.3.2.tar.gz | tar xvz -C /usr/src/php/ext/redis --strip 1 \
        && echo 'redis' >> /usr/src/php-available-exts \
        && docker-php-ext-install redis

RUN echo "* * * * * sh /var/www/docker/crontab/crontab.sh" > /tmp/crontab \
        && crontab /tmp/crontab \
        && rm -rf /tmp/crontab

RUN pecl install yaml \
        && echo "extension=yaml.so" > /usr/local/etc/php/conf.d/ext-yaml.ini

RUN rm -r /var/lib/apt/lists/*

RUN rm -f /etc/supervisor/service.d/swoole.conf

RUN mkdir /usr/lib/doo
COPY --from=dooso /go/src/dooso/lib /usr/lib/doo

COPY ./start.sh /start.sh
RUN chmod +x /start.sh

ENTRYPOINT ["/start.sh"]
CMD []

WORKDIR /var/www
