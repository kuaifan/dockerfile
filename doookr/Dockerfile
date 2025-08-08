# 构建前端
FROM node:22 AS web

WORKDIR /web
RUN git clone https://github.com/hitosea/dootask-okr.git && \
    cd dootask-okr/web && \
    npm install && \
    npm run build

# 构建服务端
FROM golang:1.20.2 AS server

WORKDIR /go/src
COPY --from=web /web ./
RUN cd dootask-okr && \
    env CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o lib/doo_okr main.go

# 构建镜像
FROM alpine:latest

RUN mkdir /var/doo && apk update && apk add tzdata
COPY --from=server /go/src/dootask-okr/lib /var/doo

WORKDIR "/var/doo"
ENTRYPOINT ["/var/doo/doo_okr"]
