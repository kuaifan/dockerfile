FROM golang:1.20.2 AS dooso

WORKDIR /go/src/dooso
COPY ./resources/dooso ./
RUN env CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o lib/doo_cli cli/main.go


FROM alpine:latest

RUN mkdir /var/doo
COPY --from=dooso /go/src/dooso/lib /var/doo

ENTRYPOINT ["/var/doo/doo_cli", "ai"]

WORKDIR "/var/doo"
