# 构建前端
FROM node:16 AS web

WORKDIR /web
RUN git clone https://github.com/hitosea/dootask-flow.git && \
    cd dootask-flow/workflow-vue3 && \
    npm install && \
    npm run build


# 构建服务端
FROM golang:1.20.2 AS server

WORKDIR /go/src
COPY --from=web /web ./
RUN cd dootask-flow && \
    env CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o lib/doo_approve main.go

# 构建镜像
FROM nginx:alpine

RUN mkdir /var/doo
COPY --from=server /go/src/dootask-flow/lib /var/doo
COPY --from=server /go/src/dootask-flow/config.json /var/doo
COPY --from=server /go/src/dootask-flow/workflow-vue3/dist/ /var/doo/dist
COPY --from=server /go/src/dootask-flow/workflow-engine/model/seeders /var/doo/workflow-engine/model/seeders
COPY --from=server /go/src/dootask-flow/docker/nginx/default.conf /etc/nginx/conf.d/

WORKDIR "/var/doo"

RUN echo '#!/bin/sh' > /start.sh && \
    echo 'nginx' >> /start.sh && \
    echo 'exec /var/doo/doo_approve' >> /start.sh && \
    chmod +x /start.sh

CMD ["/start.sh"]