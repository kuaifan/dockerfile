FROM debian:buster

COPY ./bakdb/start.sh /start.sh
RUN chmod +x /start.sh

ENTRYPOINT ["/start.sh"]
