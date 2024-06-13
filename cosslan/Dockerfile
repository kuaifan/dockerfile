FROM golang:1.20.2 AS cosslan-client

WORKDIR /go/src
RUN git clone https://github.com/cossteam/cosslan-client.git && \
    cd cosslan-client && \
    env CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o lib/client_cli main.go

FROM golang:1.20.2 AS cosslan-tool

WORKDIR /go/src
RUN git clone https://github.com/cossteam/cosslan-tool.git && \
    cd cosslan-tool && \
    env CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o lib/tool_cli main.go

FROM alpine:latest

RUN mkdir /var/cosslan-client && mkdir /var/cosslan-tool 
COPY --from=cosslan-client /go/src/cosslan-client/lib /var/cosslan-client
COPY --from=cosslan-tool /go/src/cosslan-tool/lib /var/cosslan-tool
COPY ./start.sh /start.sh
RUN chmod +x /start.sh

ENTRYPOINT ["/start.sh"]

WORKDIR "/var/doo"