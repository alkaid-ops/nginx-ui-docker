#!/usr/bin/env bash
set -euo pipefail

source_dir="${1:?usage: build-from-source.sh <source-dir> <output-dir> <amd64-toolchain> <arm64-toolchain>}"
output_dir="${2:?usage: build-from-source.sh <source-dir> <output-dir> <amd64-toolchain> <arm64-toolchain>}"
amd64_toolchain="${3:?usage: build-from-source.sh <source-dir> <output-dir> <amd64-toolchain> <arm64-toolchain>}"
arm64_toolchain="${4:?usage: build-from-source.sh <source-dir> <output-dir> <amd64-toolchain> <arm64-toolchain>}"

[ -f "$source_dir/go.mod" ] || { echo "source directory is not an Nginx UI checkout: $source_dir" >&2; exit 1; }
[ -x "$amd64_toolchain/x86_64-linux-musl-gcc" ] || { echo "missing amd64 musl compiler in $amd64_toolchain" >&2; exit 1; }
[ -x "$arm64_toolchain/aarch64-linux-musl-gcc" ] || { echo "missing arm64 musl compiler in $arm64_toolchain" >&2; exit 1; }

(
    cd "$source_dir"
    bun ci
    bun run lint
    bun run typecheck
    (cd app && bun run test)
    bun run build
    go generate cmd/version/generate.go
)

build_time="$(date +%s)"
ldflags="-w --extldflags '-static' -X 'github.com/0xJacky/Nginx-UI/settings.buildTime=${build_time}'"

build_one() {
    local arch="$1" goarch="$2" toolchain="$3" cc_name="$4" cxx_name="$5"
    mkdir -p "$output_dir/$arch"

    (
        cd "$source_dir"
        PATH="$toolchain:$PATH" \
        CGO_ENABLED=1 \
        GOOS=linux \
        GOARCH="$goarch" \
        CC="$toolchain/$cc_name" \
        CXX="$toolchain/$cxx_name" \
        go build -trimpath -tags=jsoniter -ldflags "$ldflags" -o "$output_dir/$arch/nginx-ui" -v main.go
    )

    local description
    description="$(file -b "$output_dir/$arch/nginx-ui")"
    case "$arch" in
        amd64) grep -Eq 'x86-64|x86_64' <<<"$description" || { echo "unexpected amd64 binary: $description" >&2; exit 1; } ;;
        arm64) grep -Eq 'aarch64|ARM64' <<<"$description" || { echo "unexpected arm64 binary: $description" >&2; exit 1; } ;;
    esac
    printf 'source\n' > "$output_dir/$arch/.source-asset"
}

build_one amd64 amd64 "$amd64_toolchain" x86_64-linux-musl-gcc x86_64-linux-musl-g++
build_one arm64 arm64 "$arm64_toolchain" aarch64-linux-musl-gcc aarch64-linux-musl-g++

echo "built and validated source binaries"
