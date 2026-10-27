#!/usr/bin/env bash
set -euo pipefail

UPSTREAM_REPO="${UPSTREAM_REPO:-0xJacky/nginx-ui}"
UPSTREAM_MINISIGN_PUBLIC_KEY="${UPSTREAM_MINISIGN_PUBLIC_KEY:-RWQyULqCZhSZ4LTBwQQlPCm5HS4qjbxPv75e56lU2y3cc9kviWsNqW4v}"

version="${1:?usage: fetch-upstream.sh <version> <output-dir>}"
output_dir="${2:?usage: fetch-upstream.sh <version> <output-dir>}"

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

retry() {
    local attempt
    for attempt in 1 2 3; do
        if "$@"; then
            return 0
        fi
        if [ "$attempt" -lt 3 ]; then
            echo "command failed, retrying in $((attempt * 10))s: $*" >&2
            sleep $((attempt * 10))
        fi
    done
    return 1
}

verify_asset() {
    local arch="$1" asset_name="$2" expected_file="$3"
    local asset="$work_dir/$asset_name"

    [ -s "$asset" ] || { echo "missing release asset: $asset_name" >&2; return 1; }
    [ -s "$asset.digest" ] || { echo "missing digest: $asset_name.digest" >&2; return 1; }
    [ -s "$asset.minisig" ] || { echo "missing signature: $asset_name.minisig" >&2; return 1; }

    minisign -Vm "$asset" -P "$UPSTREAM_MINISIGN_PUBLIC_KEY" >/dev/null
    local digest
    digest="$(grep -Eo '[0-9a-fA-F]{128}' "$asset.digest" | head -n 1)"
    if [ -z "$digest" ]; then
        echo "could not parse SHA-512 digest for $asset_name" >&2
        return 1
    fi
    if command -v sha512sum >/dev/null 2>&1; then
        printf '%s  %s\n' "$digest" "$asset" | sha512sum -c - >/dev/null
    else
        printf '%s  %s\n' "$digest" "$asset" | shasum -a 512 -c - >/dev/null
    fi

    local extract_dir="$work_dir/extract-$arch"
    mkdir -p "$extract_dir"
    tar -xzf "$asset" -C "$extract_dir"
    local binary
    binary="$(find "$extract_dir" -type f -name nginx-ui -print -quit)"
    [ -n "$binary" ] || { echo "nginx-ui binary not found in $asset_name" >&2; return 1; }

    local description
    description="$(file -b "$binary")"
    case "$arch" in
        amd64)
            grep -Eq 'x86-64|x86_64' <<<"$description" || { echo "unexpected amd64 binary: $description" >&2; return 1; }
            ;;
        arm64)
            grep -Eq 'aarch64|ARM64' <<<"$description" || { echo "unexpected arm64 binary: $description" >&2; return 1; }
            ;;
        *) echo "unsupported architecture: $arch" >&2; return 1 ;;
    esac

    mkdir -p "$output_dir/$arch"
    cp "$binary" "$output_dir/$arch/nginx-ui"
    chmod 0755 "$output_dir/$arch/nginx-ui"
    printf '%s\n' "$expected_file" > "$output_dir/$arch/.source-asset"
}

command -v gh >/dev/null || { echo "gh is required" >&2; exit 1; }
command -v minisign >/dev/null || { echo "minisign is required" >&2; exit 1; }
if ! command -v sha512sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
    echo "sha512sum or shasum is required" >&2
    exit 1
fi
command -v file >/dev/null || { echo "file is required" >&2; exit 1; }

retry gh release download "$version" \
    --repo "$UPSTREAM_REPO" \
    --pattern 'nginx-ui-linux-64.tar.gz*' \
    --dir "$work_dir"
retry gh release download "$version" \
    --repo "$UPSTREAM_REPO" \
    --pattern 'nginx-ui-linux-arm64-v8a.tar.gz*' \
    --dir "$work_dir"

mkdir -p "$output_dir/amd64" "$output_dir/arm64"
verify_asset amd64 nginx-ui-linux-64.tar.gz nginx-ui-linux-64.tar.gz
verify_asset arm64 nginx-ui-linux-arm64-v8a.tar.gz nginx-ui-linux-arm64-v8a.tar.gz

echo "verified upstream release assets for $version"
