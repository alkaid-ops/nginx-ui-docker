#!/bin/bash
# Initialize /etc/nginx on first boot and safely upgrade unchanged bundled files.
set -u

: "${ETC_NGINX:=/etc/nginx}"
: "${TEMPLATE_DIR:=/usr/local/etc/nginx}"
: "${HASH_FILE:=/usr/local/share/nginx-ui/nginx-ui.conf.known-hashes}"

log() { echo "[$1] init-config: $2"; }

sync_bundled_file() {
    local template="$1" target="$2" hashes="$3"

    [ -f "$template" ] || { log WARN "template missing: $template"; return 0; }
    [ -f "$hashes" ] || { log WARN "hash list missing: $hashes"; return 0; }
    if [ ! -f "$target" ]; then
        log INFO "target absent; leaving it absent"
        return 0
    fi
    if ! command -v sha256sum >/dev/null 2>&1; then
        log WARN "sha256sum unavailable; skipping sync of $target"
        return 0
    fi

    local cur_hash tpl_hash
    cur_hash="$(sha256sum "$target" | awk '{print $1}')"
    tpl_hash="$(sha256sum "$template" | awk '{print $1}')"

    if [ "$cur_hash" = "$tpl_hash" ]; then
        return 0
    fi

    if grep -vE '^[[:space:]]*(#|$)' "$hashes" | awk '{print $1}' | grep -Fxq "$cur_hash"; then
        local bak
        bak="${target}.bak.$(date +%Y%m%d%H%M%S)"
        if ! cp -p "$target" "$bak"; then
            log ERROR "backup failed ($target -> $bak); leaving file untouched"
            return 1
        fi
        local tmp="${target}.tmp.$$"
        if ! cp -p "$template" "$tmp" || ! mv -f "$tmp" "$target"; then
            log ERROR "write failed; restoring from $bak"
            cp -p "$bak" "$target" 2>/dev/null
            rm -f "$tmp" 2>/dev/null
            return 1
        fi
        log INFO "Synced $target from bundled template (old saved as $bak)"
    else
        log INFO "Skipping $target: customized (hash $cur_hash). See UI self-check."
    fi
}

init_config_main() {
    if [ -n "${TZ:-}" ] && [ -f "/usr/share/zoneinfo/$TZ" ]; then
        ln -sf "/usr/share/zoneinfo/$TZ" /etc/localtime
        printf '%s\n' "$TZ" > /etc/timezone
        log INFO "timezone set to $TZ"
    fi

    if [ "${NGINX_UI_DISABLE_BUNDLED_NGINX:-}" = "true" ]; then
        log INFO "host mode: skipping bundled nginx config initialization"
        return 0
    fi

    # A container restart keeps /run by default; never trust a stale master PID.
    rm -f /var/run/nginx.pid

    if [ -z "$(ls -A "$ETC_NGINX" 2>/dev/null)" ]; then
        cp -a "$TEMPLATE_DIR/." "$ETC_NGINX/"
        log INFO "Nginx configurations directory initialized"
        return 0
    fi

    mkdir -p \
        "$ETC_NGINX/conf.d" \
        "$ETC_NGINX/sites-available" \
        "$ETC_NGINX/sites-enabled" \
        "$ETC_NGINX/streams-available" \
        "$ETC_NGINX/streams-enabled" \
        "$ETC_NGINX/maintenance" \
        /etc/nginx-ui \
        /var/log/nginx

    if [ "${NGINX_UI_PRESERVE_BUNDLED_CONF:-}" = "true" ]; then
        log INFO "NGINX_UI_PRESERVE_BUNDLED_CONF=true; skipping bundled-conf sync"
        return 0
    fi

    if ! sync_bundled_file \
        "$TEMPLATE_DIR/conf.d/nginx-ui.conf" \
        "$ETC_NGINX/conf.d/nginx-ui.conf" \
        "$HASH_FILE"; then
        log WARN "bundled-conf sync failed; continuing without blocking bundled nginx startup"
    fi
}

case "${1:-}" in
    --testing) return 0 ;;
    *) init_config_main ;;
esac
