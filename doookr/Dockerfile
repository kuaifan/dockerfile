FROM golang:1.20.2 AS doookr

WORKDIR /go/src
RUN git clone https://github.com/hitosea/dootask-okr.git && \
    cd dootask-okr && \
    env CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o lib/doo_okr main.go

FROM debian:latest

RUN mkdir /var/doo
COPY --from=doookr /go/src/dootask-okr/lib /var/doo

ENTRYPOINT ["/var/doo/doo_okr"]

WORKDIR "/var/doo"
