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
