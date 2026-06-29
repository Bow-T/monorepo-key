#!/bin/bash
# build-icons.sh
# --------------
# Sinh icon cho Bow Key từ nguồn SVG (vector) -> PNG -> AppIcon.icns.
#
# Vì sao tách riêng khỏi build-app.sh?
#   - Icon hiếm khi đổi; render lại mỗi lần build app là phí.
#   - Nguồn duy nhất là Assets/*.svg (dễ sửa, version-control gọn).
#
# Yêu cầu: rsvg-convert (brew install librsvg), iconutil, sips (có sẵn trên macOS).
# Dùng: bash scripts/build-icons.sh   (chạy từ thư mục gốc app macos_ime)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASSETS="$ROOT/Assets"
SRC="$ASSETS/app-icon.svg"
MENUBAR_SRC="$ASSETS/menubar-icon.svg"
ICONSET="$ASSETS/AppIcon.iconset"
ICNS="$ASSETS/AppIcon.icns"

command -v rsvg-convert >/dev/null || { echo "❌ Thiếu rsvg-convert (brew install librsvg)"; exit 1; }

echo "==> 1/3  Render app icon -> .iconset…"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
# macOS iconset cần đủ các cặp size @1x/@2x từ 16 tới 512.
for pair in "16 icon_16x16" "32 icon_16x16@2x" \
            "32 icon_32x32"  "64 icon_32x32@2x" \
            "128 icon_128x128" "256 icon_128x128@2x" \
            "256 icon_256x256" "512 icon_256x256@2x" \
            "512 icon_512x512" "1024 icon_512x512@2x"; do
  set -- $pair
  rsvg-convert -w "$1" -h "$1" "$SRC" -o "$ICONSET/$2.png"
done

echo "==> 2/3  Đóng gói -> AppIcon.icns…"
iconutil -c icns "$ICONSET" -o "$ICNS"

echo "==> 3/3  Render menu-bar template (@1x/@2x)…"
# Template image: đen trên nền trong suốt; macOS tự tô màu theo light/dark.
rsvg-convert -w 18 -h 18 "$MENUBAR_SRC" -o "$ASSETS/menubar.png"
rsvg-convert -w 36 -h 36 "$MENUBAR_SRC" -o "$ASSETS/menubar@2x.png"

echo ""
echo "✅ Xong:"
echo "   $ICNS"
echo "   $ASSETS/menubar.png  +  menubar@2x.png"
