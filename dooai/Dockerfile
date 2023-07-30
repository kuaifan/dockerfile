FROM golang:1.20.2 AS dooso

WORKDIR /go/src/dooso
COPY ./resources/dooso ./
RUN go build -trimpath -ldflags "-s -w" -o lib/doo_cli cli/main.go


FROM alpine:latest

RUN mkdir /var/doo
COPY --from=dooso /go/src/dooso/lib /var/doo

COPY ./dooai/start.sh /start.sh
RUN chmod +x /start.sh

ENTRYPOINT ["/start.sh"]
CMD []

WORKDIR "/var/doo"
