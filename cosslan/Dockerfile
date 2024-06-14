FROM golang:1.22 AS cosslan-client

WORKDIR /go/src
COPY ./private-repo/cosslan-client /go/src/cosslan-client
RUN cd cosslan-client && \
    env CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o lib/client_cli main.go

FROM golang:1.22 AS cosslan-tool

WORKDIR /go/src
COPY ./private-repo/cosslan-tool /go/src/cosslan-tool
RUN cd cosslan-tool && \
    env CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o lib/tool_cli main.go


FROM alpine:latest

RUN mkdir /var/cosslan-client && mkdir /var/cosslan-tool 
COPY --from=cosslan-client /go/src/cosslan-client/lib /var/cosslan-client
COPY --from=cosslan-tool /go/src/cosslan-tool/lib /var/cosslan-tool
COPY ./start.sh /start.sh
RUN chmod +x /start.sh

WORKDIR "/var"