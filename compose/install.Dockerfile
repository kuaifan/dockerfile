FROM docker

RUN apk update && \
    apk add --update --no-cache bash curl wget

RUN wget --no-check-certificate https://github.com/docker/compose/releases/download/v2.2.3/docker-compose-Linux-x86_64 && \
    mv docker-compose-Linux-x86_64 /usr/local/bin/docker-compose && \
    chmod +x /usr/local/bin/docker-compose && \
    ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

ENTRYPOINT ["/install.sh"]
