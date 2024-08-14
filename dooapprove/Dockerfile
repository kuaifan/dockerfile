FROM golang:1.20.2 AS dooapprove

WORKDIR /go/src
RUN git clone https://github.com/hitosea/dootask-flow.git && \
    cd dootask-flow && \
    env CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o lib/doo_approve main.go

FROM nginx:alpine

RUN mkdir /var/doo  git 
COPY --from=dooapprove /go/src/dootask-flow/lib /var/doo
COPY --from=dooapprove /go/src/dootask-flow/config.json /var/doo
COPY --from=dooapprove /go/src/dootask-flow/workflow-vue3/dist/ /var/doo/dist
COPY --from=dooapprove /go/src/dootask-flow/workflow-engine/model/seeders /var/doo/workflow-engine/model/seeders
COPY --from=dooapprove /go/src/dootask-flow/docker/nginx/default.conf /etc/nginx/conf.d/

WORKDIR "/var/doo"

CMD nginx;./doo_approve