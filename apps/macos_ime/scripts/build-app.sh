#!/bin/bash
# build-app.sh
# ------------
# Build Bow Key thành một .app bundle macOS hoàn chỉnh, rồi ký (code sign).
#
# Vì sao cần đóng gói thành .app thay vì chạy binary trần?
#   - macOS gắn quyền Accessibility/Input Monitoring theo "bundle identifier".
#     Binary trần không có bundle id ổn định -> cấp quyền xong vẫn không nhận.
#   - LSUIElement (app accessory, ẩn Dock) chỉ khai báo được trong Info.plist của bundle.
#   - Code signing ổn định giúp macOS không thu hồi quyền mỗi lần build lại.
#
# Dùng: bash scripts/build-app.sh   (chạy từ thư mục gốc repo)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="BowKey"
BUNDLE_ID="tech.local.bowkey"
APP_DIR="$ROOT/build/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"

echo "==> 1/4  Build (release)…"
cd "$ROOT"
swift build -c release --product "$APP_NAME"
BIN="$ROOT/.build/release/$APP_NAME"

echo "==> 2/4  Dựng cấu trúc .app…"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"
cp "$BIN" "$MACOS_DIR/$APP_NAME"

echo "==> 3/4  Viết Info.plist…"
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>     <string>Bow Key — Bộ gõ tiếng Việt</string>
    <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleExecutable</key>      <string>$APP_NAME</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <!-- App accessory: ẩn khỏi Dock, chỉ có icon menu bar -->
    <key>LSUIElement</key>            <true/>
</dict>
</plist>
PLIST

echo "==> 4/4  Code sign (ad-hoc)…"
# Ký ad-hoc (-) đủ để chạy & cấp quyền trên máy của chính bạn.
# Khi phân phối cho người khác, thay bằng Developer ID + notarize.
codesign --force --deep --sign - \
    --options runtime \
    --identifier "$BUNDLE_ID" \
    "$APP_DIR"

echo ""
echo "✅ Xong: $APP_DIR"
echo ""
echo "Chạy thử:   open \"$APP_DIR\""
echo "Lần đầu sẽ cần cấp quyền Accessibility + Input Monitoring trong System Settings,"
echo "tìm mục \"$APP_NAME\", bật lên, rồi mở lại app."
