#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/chromium-legacy-probe.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
SDK_PATH="${SDKROOT:-$(xcrun --show-sdk-path)}"
COMMON_ARGS=(-std=c++17 -fobjc-arc -Wall -Wextra -Werror -isysroot "$SDK_PATH" -I "$ROOT_DIR")
# Compile the production fallback for Lion, even on Apple silicon hosts.
# This Foundation-only helper needs no C++ standard library headers. The full
# browser still needs a separately ported libc++ for Lion.
xcrun clang++ "${COMMON_ARGS[@]}" -nostdinc++ -target x86_64-apple-macosx10.7 -c     "$ROOT_DIR/base/mac/legacy_os_compat.mm" -o "$BUILD_DIR/legacy-lion.o"
# Execute the same implementation natively, without the Chromium dependency tree.
xcrun clang++ "${COMMON_ARGS[@]}" "$ROOT_DIR/base/mac/legacy_os_compat.mm"     "$ROOT_DIR/legacy/tests/os_version_probe.mm" -framework Foundation -o "$BUILD_DIR/os_version_probe"
"$BUILD_DIR/os_version_probe"
