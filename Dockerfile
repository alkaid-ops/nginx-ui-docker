# syntax=docker/dockerfile:1.7

ARG OPENRESTY_IMAGE=openresty/openresty:1.31.1.1-5-alpine
FROM ${OPENRESTY_IMAGE}

ARG TARGETARCH
ARG S6_OVERLAY_VERSION=3.2.3.2
ARG UPSTREAM_VERSION=unknown
ARG UPSTREAM_REVISION=unknown
ARG BUILD_MODE=unknown

LABEL org.opencontainers.image.title="nginx-ui-plus" \
      org.opencontainers.image.description="Nginx UI on OpenResty, CI-built from upstream artifacts" \
      org.opencontainers.image.source="https://github.com/alkaid-ops/nginx-ui-docker" \
      org.opencontainers.image.version="${UPSTREAM_VERSION}" \
      org.opencontainers.image.revision="${UPSTREAM_REVISION}" \
      org.opencontainers.image.base.name="openresty/openresty:1.31.1.1-5-alpine" \
      org.opencontainers.image.licenses="AGPL-3.0-only" \
      com.alkaid.nginx-ui.build-mode="${BUILD_MODE}"

ENV PATH="/usr/local/openresty/luajit/bin:/usr/local/openresty/nginx/sbin:/usr/local/openresty/bin:${PATH}" \
    NGINX_UI_OFFICIAL_DOCKER=true \
    NGINX_UI_SERVER_RUN_MODE=release \
    NGINX_UI_WORKING_DIR=/var/run/ \
    NGINX_UI_NGINX_SBIN_PATH=/usr/local/openresty/nginx/sbin/nginx \
    NGINX_UI_NGINX_CONFIG_DIR=/etc/nginx \
    NGINX_UI_NGINX_CONFIG_PATH=/etc/nginx/nginx.conf \
    NGINX_UI_NGINX_PID_PATH=/var/run/nginx.pid \
    NGINX_UI_NGINX_ACCESS_LOG_PATH=/var/log/nginx/access.log \
    NGINX_UI_NGINX_ERROR_LOG_PATH=/var/log/nginx/error.log \
    NGINX_UI_NGINX_TEST_CONFIG_CMD="nginx -c /etc/nginx/nginx.conf -t" \
    NGINX_UI_NGINX_RELOAD_CMD="nginx -c /etc/nginx/nginx.conf -s reload" \
    NGINX_UI_NGINX_RESTART_CMD="nginx -c /etc/nginx/nginx.conf -s stop"

RUN apk add --no-cache bash ca-certificates curl logrotate tzdata xz \
    && case "${TARGETARCH}" in \
         amd64) S6_ARCH=x86_64 ;; \
         arm64) S6_ARCH=aarch64 ;; \
         *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
       esac \
    && curl --fail --silent --show-error --location --retry 5 --retry-delay 3 \
         -o /tmp/s6-overlay-noarch.tar.xz \
         "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz" \
    && curl --fail --silent --show-error --location --retry 5 --retry-delay 3 \
         -o "/tmp/s6-overlay-${S6_ARCH}.tar.xz" \
         "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz" \
    && tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz \
    && tar -C / -Jxpf "/tmp/s6-overlay-${S6_ARCH}.tar.xz" \
    && rm -f /tmp/s6-overlay-*.tar.xz \
    && mkdir -p /etc/nginx/conf.d \
       /etc/nginx/sites-available \
       /etc/nginx/sites-enabled \
       /etc/nginx/streams-available \
       /etc/nginx/streams-enabled \
       /etc/nginx/maintenance \
       /etc/nginx-ui \
       /usr/local/etc/nginx \
       /usr/local/share/nginx-ui \
       /var/log/nginx \
       /var/run/openresty \
    && cp /usr/local/openresty/nginx/conf/mime.types /usr/local/etc/nginx/mime.types \
    && touch /var/log/nginx/access.log /var/log/nginx/error.log

COPY rootfs/ /

RUN chmod 0755 \
        /etc/s6-overlay/s6-rc.d/init-config/up \
        /etc/s6-overlay/s6-rc.d/init-config/init-config.sh \
        /etc/s6-overlay/s6-rc.d/nginx/run \
        /etc/s6-overlay/s6-rc.d/nginx-ui/run \
    && cp -a /usr/local/etc/nginx/. /etc/nginx/

COPY artifacts/${TARGETARCH}/nginx-ui /usr/local/bin/nginx-ui

RUN chmod 0755 /usr/local/bin/nginx-ui \
    && rm -f /etc/nginx/conf.d/default.conf /usr/local/etc/nginx/conf.d/default.conf

EXPOSE 80 443
STOPSIGNAL SIGTERM
ENTRYPOINT ["/init"]
