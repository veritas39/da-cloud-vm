FROM alpine:3.20

WORKDIR /app
COPY src/worker.sh /app/worker.sh
RUN chmod +x /app/worker.sh

CMD ["/app/worker.sh"]
