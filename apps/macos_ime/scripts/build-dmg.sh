#!/bin/bash
# build-dmg.sh
# ------------
# Đóng gói Bow Go.app thành file .dmg cài đặt — mở ra, KÉO app vào Applications.
# Giống cách phát hành chuẩn của app macOS: 1 file .dmg duy nhất.
#
# Vì sao .dmg thay vì .zip?
#   - .dmg cho trải nghiệm "cài app thật": cửa sổ có icon app + alias Applications,
#     người dùng chỉ kéo-thả. .zip thì phải tự giải nén rồi tự chép.
#   - Đặt tên theo kiến trúc (arm64/intel) như bản phát hành chuẩn.
#
# Dùng: bash scripts/build-dmg.sh        (tự build .app trước nếu chưa có)
# Yêu cầu: chỉ cần hdiutil (có sẵn trên mọi máy macOS) — KHÔNG cần brew.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Bow Go"
APP_DIR="$ROOT/build/$APP_NAME.app"

# Lấy version từ Info.plist nếu app đã build; mặc định 0.1.
VERSION="1.0.4"

# Kiến trúc máy hiện tại -> tên file (arm64 / intel) cho giống bản phát hành chuẩn.
ARCH="$(uname -m)"
case "$ARCH" in
  arm64) ARCH_LABEL="arm64" ;;
  x86_64) ARCH_LABEL="intel" ;;
  *) ARCH_LABEL="$ARCH" ;;
esac

echo "==> 1/4  Đảm bảo đã có .app…"
if [ ! -d "$APP_DIR" ]; then
  echo "    (chưa có $APP_NAME.app — chạy build-app.sh)"
  bash "$ROOT/scripts/build-app.sh"
fi
# Đọc version thật từ bundle (CFBundleShortVersionString).
if [ -f "$APP_DIR/Contents/Info.plist" ]; then
  V="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist" 2>/dev/null || true)"
  [ -n "$V" ] && VERSION="$V"
fi

DMG_OUT="$ROOT/build/$APP_NAME-$VERSION-$ARCH_LABEL.dmg"

echo "==> 2/4  Dựng cửa sổ cài đặt (staging)…"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
# Chép app + tạo alias trỏ tới /Applications để người dùng kéo-thả.
cp -R "$APP_DIR" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"

echo "==> 3/4  Tạo .dmg (nén UDZO)…"
rm -f "$DMG_OUT"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG_OUT" >/dev/null

echo "==> 4/4  Ký .dmg (ad-hoc)…"
codesign --force --sign - "$DMG_OUT" 2>/dev/null || true

SHA="$(shasum -a 256 "$DMG_OUT" | awk '{print $1}')"
SIZE="$(du -h "$DMG_OUT" | awk '{print $1}')"

echo ""
echo "✅ Xong: $DMG_OUT"
echo "   kích thước: $SIZE"
echo "   sha256:     $SHA"
echo ""
echo "Cài đặt: mở file .dmg, KÉO biểu tượng $APP_NAME vào thư mục Applications."
echo "Lần đầu mở app cần cấp quyền Accessibility + Input Monitoring (xem README)."
