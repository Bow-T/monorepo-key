#!/bin/bash
# build-core.sh
# -------------
# Build core gõ Rust (packages/viet_core) mà VietEngine link tĩnh. Chạy trước
# `swift build` / `swift test` mỗi khi core đổi (build-app.sh tự gọi).
#
# SwiftPM link libviet_core.a qua -l nên KHÔNG theo dõi file này: đổi core mà không đổi
# Swift thì `swift build`/`swift test` không link lại và chạy core cũ. Script xoá các sản
# phẩm đã link cũ hơn thư viện để lần build kế tiếp buộc phải link lại.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE="$ROOT/../../packages/viet_core"

# rustup cài qua Homebrew là keg-only: thêm cả hai chỗ cài cargo thường gặp vào PATH.
export PATH="$PATH:$HOME/.cargo/bin:/opt/homebrew/opt/rustup/bin"
cargo build --release --manifest-path "$CORE/Cargo.toml"

LIB="$CORE/target/release/libviet_core.a"
if [ -d "$ROOT/.build" ]; then
  find "$ROOT/.build" \( -name BowGo -o -name '*.xctest' \) ! -newer "$LIB" -prune \
    -exec rm -rf {} +
fi
