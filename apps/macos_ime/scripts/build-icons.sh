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
PNG_SRC="$ASSETS/app-icon.png"
MENUBAR_SRC="$ASSETS/menubar-icon.svg"
ICONSET="$ASSETS/AppIcon.iconset"
ICNS="$ASSETS/AppIcon.icns"

if [ -f "$PNG_SRC" ]; then
  echo "    ✓ Tìm thấy app-icon.png. Sẽ dùng sips để sinh icon."
else
  command -v rsvg-convert >/dev/null || { echo "❌ Thiếu rsvg-convert (brew install librsvg) để render từ SVG"; exit 1; }
fi

echo "==> 1/4  Render app icon -> .iconset…"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
# macOS iconset cần đủ các cặp size @1x/@2x từ 16 tới 512.
for pair in "16 icon_16x16" "32 icon_16x16@2x" \
            "32 icon_32x32"  "64 icon_32x32@2x" \
            "128 icon_128x128" "256 icon_128x128@2x" \
            "256 icon_256x256" "512 icon_256x256@2x" \
            "512 icon_512x512" "1024 icon_512x512@2x"; do
  set -- $pair
  if [ -f "$PNG_SRC" ]; then
    sips -s format png -z "$1" "$1" "$PNG_SRC" --out "$ICONSET/$2.png" >/dev/null
  else
    rsvg-convert -w "$1" -h "$1" "$SRC" -o "$ICONSET/$2.png"
  fi
done

echo "==> 2/4  Đóng gói -> AppIcon.icns…"
iconutil -c icns "$ICONSET" -o "$ICNS"

echo "==> 3/4  Render menu-bar template (@1x/@2x)…"
# Template image: đen trên nền trong suốt; macOS tự tô màu theo light/dark.
if command -v rsvg-convert >/dev/null; then
  rsvg-convert -w 18 -h 18 "$MENUBAR_SRC" -o "$ASSETS/menubar.png"
  rsvg-convert -w 36 -h 36 "$MENUBAR_SRC" -o "$ASSETS/menubar@2x.png"
else
  echo "    (bỏ qua render menubar-icon từ SVG vì thiếu rsvg-convert; dùng ảnh menubar có sẵn)"
fi

echo "==> 4/4  Render icon cho app UI cài đặt (Flutter settings_ui)…"
# App Flutter dùng cùng logo BowGo (thay icon Flutter mặc định). Asset catalog
# của nó cần các PNG rời theo size; sinh thẳng từ cùng nguồn PNG/SVG để luôn đồng bộ.
FLUTTER_ICONSET="$ROOT/../settings_ui/macos/Runner/Assets.xcassets/AppIcon.appiconset"
if [ -d "$FLUTTER_ICONSET" ]; then
  for sz in 16 32 64 128 256 512 1024; do
    if [ -f "$PNG_SRC" ]; then
      sips -s format png -z "$sz" "$sz" "$PNG_SRC" --out "$FLUTTER_ICONSET/app_icon_$sz.png" >/dev/null
    else
      rsvg-convert -w "$sz" -h "$sz" "$SRC" -o "$FLUTTER_ICONSET/app_icon_$sz.png"
    fi
  done
  echo "    ✓ $FLUTTER_ICONSET/app_icon_*.png"
else
  echo "    (bỏ qua: không thấy $FLUTTER_ICONSET)"
fi

echo ""
echo "✅ Xong:"
echo "   $ICNS"
echo "   $ASSETS/menubar.png  +  menubar@2x.png"
echo "   Flutter settings_ui app_icon_*.png"
