FROM golang:1.20.2 AS dooapprove

WORKDIR /go/src
RUN git clone https://github.com/innet8/task-flow.git && \
    cd task-flow && \
    env CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o lib/doo_approve main.go

FROM nginx:alpine

RUN mkdir /var/doo  git 
COPY --from=dooapprove /go/src/task-flow/lib /var/doo
COPY --from=dooapprove /go/src/task-flow/config.json /var/doo
COPY --from=dooapprove /go/src/task-flow/workflow-vue3/dist/ /var/doo/dist
COPY --from=dooapprove /go/src/task-flow/workflow-engine/model/seeders /var/doo/workflow-engine/model/seeders
COPY --from=dooapprove /go/src/task-flow/docker/nginx/default.conf /etc/nginx/conf.d/

WORKDIR "/var/doo"

CMD nginx;./doo_approve