#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/chromium-legacy-platform-build.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
SDK_PATH="${SDKROOT:-$(xcrun --show-sdk-path)}"
CXX_PATH="${CXX:-$(xcrun --find clang++)}"
LINK_ARGS=(-Wl,-fatal_warnings)
if [[ -x "$(dirname "$CXX_PATH")/ld64.lld" ]]; then
    LINK_ARGS+=(-fuse-ld=lld)
fi
"$CXX_PATH" -std=c++17 -Wall -Wextra -Werror -fno-exceptions -fno-rtti \
    -nostdinc++ -nostdlib++ -target x86_64-apple-macosx10.7 \
    -isysroot "$SDK_PATH" -I "$ROOT_DIR" \
    "$ROOT_DIR/legacy/tests/platform_probe.cc" -framework CoreServices \
    "${LINK_ARGS[@]}" -o "$BUILD_DIR/platform_probe"
"$BUILD_DIR/platform_probe"
