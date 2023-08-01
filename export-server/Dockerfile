FROM node:lts-slim

LABEL maintainer="JGraph Ltd" \
      org.opencontainers.image.authors="JGraph Ltd" \
      org.opencontainers.image.url="https://www.drawio.com" \
      org.opencontainers.image.source="https://github.com/jgraph/docker-drawio"

ENV RUN_USER            drawio
ENV RUN_GROUP           drawio

RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
        git curl software-properties-common chromium libatk-bridge2.0-0 libgtk-3-0 wget && \
    apt-add-repository contrib && \
    apt-get update -y && \
    wget http://ftp.de.debian.org/debian/pool/contrib/m/msttcorefonts/ttf-mscorefonts-installer_3.8_all.deb && \
    apt install -y --no-install-recommends \
        ./ttf-mscorefonts-installer_3.8_all.deb && \
    mkdir /usr/local/drawio && \
    cd /usr/local/drawio && \
    git clone https://github.com/jgraph/draw-image-export2.git && \
    cd draw-image-export2 && \
    npm install && \
    apt-get remove -y --purge chromium git wget
    
# Add drawio user
RUN groupadd -r ${RUN_GROUP} && useradd -g ${RUN_GROUP} -d /usr/local/drawio -s /bin/bash ${RUN_USER} && \
    chown -R ${RUN_USER}:${RUN_GROUP} /usr/local/drawio

USER ${RUN_USER}

WORKDIR /usr/local/drawio/draw-image-export2

EXPOSE 8000

CMD ["npm", "start"]