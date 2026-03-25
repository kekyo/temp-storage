FROM docker.io/library/nginx:1.27-alpine

RUN apk add --no-cache apache2-utils

RUN mkdir -p /var/lib/webdav /var/lib/nginx/body /docker-entrypoint.d

COPY nginx.conf /etc/nginx/nginx.conf
COPY docker-entrypoint.d/10-create-htpasswd.sh /docker-entrypoint.d/10-create-htpasswd.sh
COPY docker-entrypoint.d/20-prepare-storage.sh /docker-entrypoint.d/20-prepare-storage.sh
COPY docker-entrypoint.d/30-clear-storage.sh /docker-entrypoint.d/30-clear-storage.sh

RUN chmod 0755 /docker-entrypoint.d/10-create-htpasswd.sh \
    /docker-entrypoint.d/20-prepare-storage.sh \
    /docker-entrypoint.d/30-clear-storage.sh \
    && chown -R nginx:nginx /var/lib/webdav /var/lib/nginx/body

EXPOSE 8080

VOLUME ["/var/lib/webdav"]

ENV WEBDAV_USERNAME= \
    WEBDAV_PASSWORD= \
    WEBDAV_CLEAR_STORAGE_ON_STARTUP=false
