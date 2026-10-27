#!/usr/bin/env bash
set -euxo pipefail

image="${1:?usage: smoke-test.sh <image> <amd64|arm64>}"
arch="${2:?usage: smoke-test.sh <image> <amd64|arm64>}"
container_name="nginx-ui-plus-smoke-${arch}-$$"
nginx_volume="${container_name}-nginx"
ui_volume="${container_name}-nginx-ui"
log_volume="${container_name}-logs"

cleanup() {
    local rc=$?
    trap - EXIT
    if [ "$rc" -ne 0 ]; then
        echo "smoke test failed; container logs:" >&2
        docker logs "$container_name" >&2 || true
        docker exec "$container_name" sh -c 'cat /var/log/nginx/error.log 2>/dev/null || true' >&2 || true
    fi
    docker rm -f "$container_name" >/dev/null 2>&1 || true
    docker volume rm -f "$nginx_volume" "$ui_volume" "$log_volume" >/dev/null 2>&1 || true
    exit "$rc"
}
trap cleanup EXIT

docker volume create "$nginx_volume" >/dev/null
docker volume create "$ui_volume" >/dev/null
docker volume create "$log_volume" >/dev/null

docker run -d \
    --name "$container_name" \
    --platform "linux/$arch" \
    -p 127.0.0.1::80 \
    -v "$nginx_volume:/etc/nginx" \
    -v "$ui_volume:/etc/nginx-ui" \
    -v "$log_volume:/var/log/nginx" \
    -e TZ=Asia/Shanghai \
    "$image" >/dev/null

host_port="$(docker port "$container_name" 80/tcp | awk -F: 'NR == 1 {print $NF}')"
[ -n "$host_port" ] || { echo "could not determine published port" >&2; exit 1; }

wait_http() {
    local url="$1" attempts="${2:-90}" i
    for ((i = 1; i <= attempts; i++)); do
        if curl -fsS "$url" | grep -q '"status":"ok"'; then
            return 0
        fi
        sleep 2
    done
    return 1
}

wait_http "http://127.0.0.1:${host_port}/healthz"
docker exec "$container_name" nginx -V 2>&1 | grep -qi openresty
docker exec "$container_name" nginx -t -c /etc/nginx/nginx.conf
docker exec "$container_name" test -s /etc/nginx/nginx.conf
docker exec "$container_name" test -d /etc/nginx-ui
docker exec "$container_name" test -d /etc/nginx/sites-enabled
docker exec "$container_name" ps | grep -q '[n]ginx-ui --config'
docker exec "$container_name" ps | grep -q '[n]ginx: master process'

# Customized bundled config must survive a restart.
docker exec "$container_name" sh -c \
    'printf "\n# nginx-ui-plus smoke marker\n" >> /etc/nginx/conf.d/nginx-ui.conf'
docker restart "$container_name" >/dev/null
wait_http "http://127.0.0.1:${host_port}/healthz"
docker exec "$container_name" grep -q 'nginx-ui-plus smoke marker' /etc/nginx/conf.d/nginx-ui.conf

# A broken OpenResty config must not take the Nginx UI control plane down.
docker exec "$container_name" sh -c \
    'printf "this_is_invalid_for_smoke;\n" > /etc/nginx/sites-enabled/zz-invalid-smoke.conf'
docker restart "$container_name" >/dev/null
for ((i = 1; i <= 60; i++)); do
    if docker exec "$container_name" curl -fsS http://127.0.0.1:9000/healthz 2>/dev/null | grep -q '"status":"ok"'; then
        break
    fi
    if [ "$i" -eq 60 ]; then
        echo "Nginx UI control plane did not survive a broken OpenResty config" >&2
        exit 1
    fi
    sleep 2
done
docker exec "$container_name" rm -f /etc/nginx/sites-enabled/zz-invalid-smoke.conf
docker restart "$container_name" >/dev/null
wait_http "http://127.0.0.1:${host_port}/healthz"

echo "smoke test passed for linux/$arch"
