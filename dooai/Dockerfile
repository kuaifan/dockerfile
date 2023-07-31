FROM golang:1.20.2 AS doocli

WORKDIR /go/src/doocli
COPY ./resources/doocli ./
RUN env CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o lib/doo_cli main.go


FROM alpine:latest

RUN mkdir /var/doo
COPY --from=doocli /go/src/doocli/lib /var/doo

ENTRYPOINT ["/var/doo/doo_cli", "ai"]

WORKDIR "/var/doo"
