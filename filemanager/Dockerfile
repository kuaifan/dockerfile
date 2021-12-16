FROM --platform=$TARGETPLATFORM node:14-alpine as builder

RUN apk add --update --no-cache git

RUN git clone https://github.com/kuaifan/filegator.git && \
    cd filegator && \
    git pull && \
    npm install && \
    npm run build

FROM --platform=$TARGETPLATFORM php:7-apache-buster

ENV APACHE_DOCUMENT_ROOT=/var/www/filegator/

RUN apt-get update > /dev/null && \
    # Install and enable php zip extension
    apt-get install -y git wget unzip libzip-dev && \
    docker-php-ext-install zip && \
    docker-php-ext-enable zip && \
    # Install composer
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" && \
    php -r "if (hash_file('sha384', 'composer-setup.php') === '906a84df04cea2aa72f40b5f787e49f22d4c2f19492ac310e8cba5b96ac8b64115ac402c8cd292b8a03482574915d1a8') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;" && \
    php composer-setup.php && \
    php -r "unlink('composer-setup.php');" && \
    mv composer.phar /usr/local/bin/composer && \
    # Download and extract latest build
    cd /var/www/ && \
    git clone https://github.com/kuaifan/filegator.git && \
    cd filegator && \
    composer install --ignore-platform-reqs && \
    cd ../ && \
    chown -R www-data:www-data filegator/ && \
    chmod -R 775 filegator/ && \
    # configure Apache to use the value of APACHE_DOCUMENT_ROOT as its default Document Root
    sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf && \
    sed -ri -e 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf && \
    # configure php
    mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini" && \
    # cleanup apt
    apt-get purge -y wget unzip && \
    apt-get autoclean -y && \
    rm -Rf /var/lib/apt/lists/*

COPY --from=builder /filegator/dist /var/www/filegator/dist

EXPOSE 80

VOLUME /var/www/filegator/repository
VOLUME /var/www/filegator/private

WORKDIR "/var/www/filegator/"

# docker buildx build --platform linux/arm64,linux/amd64 -t kuaifan/filemanager:latest . --push
