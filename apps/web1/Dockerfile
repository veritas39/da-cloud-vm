FROM nginx:1.27-alpine

COPY src/ /usr/share/nginx/html/

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3   CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:80/ || exit 1
