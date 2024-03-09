FROM node:16-alpine

RUN mkdir -p /home/node/eeui

WORKDIR /home/node/eeui

RUN npm install -g eeui-cli

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["node"]
