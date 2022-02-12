FROM nginx:1.21.4-alpine

RUN apk add --update --no-cache bash

COPY ./bakdb/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
