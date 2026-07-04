#!/bin/bash
# build-app.sh
# ------------
# Build Bow Go thành một .app bundle macOS hoàn chỉnh, rồi ký (code sign).
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
APP_NAME="Bow Go"
BUNDLE_ID="com.bowgo.keyboard"
APP_DIR="$ROOT/build/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"

echo "==> 1/4  Build (release)…"
cd "$ROOT"
swift build -c release --product "BowGo"
BIN="$ROOT/.build/release/BowGo"

echo "==> 2/4  Dựng cấu trúc .app…"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"
cp "$BIN" "$MACOS_DIR/$APP_NAME"

# Icon: sinh từ SVG nếu chưa có, rồi chép .icns + ảnh menu bar vào Resources.
if [ ! -f "$ROOT/Assets/AppIcon.icns" ]; then
  echo "    (chưa có icon — chạy build-icons.sh)"
  bash "$ROOT/scripts/build-icons.sh"
fi
cp "$ROOT/Assets/AppIcon.icns"   "$RES_DIR/AppIcon.icns"
cp "$ROOT/Assets/menubar.png"    "$RES_DIR/menubar.png"
cp "$ROOT/Assets/menubar@2x.png" "$RES_DIR/menubar@2x.png"

# Font pixel (PressStart2P + VT323) cho cửa sổ lịch sử Clipboard — khớp UI app settings.
if [ -d "$ROOT/Assets/fonts" ]; then
  cp "$ROOT/Assets/fonts/"*.ttf "$RES_DIR/" 2>/dev/null || true
fi

# Sticker (emoji ảnh) cho bảng dán sticker — nằm ở gốc monorepo (assets/emojis).
EMOJI_SRC="$ROOT/../../assets/emojis"
if [ -d "$EMOJI_SRC" ]; then
  mkdir -p "$RES_DIR/emojis"
  cp "$EMOJI_SRC/"*.png "$RES_DIR/emojis/" 2>/dev/null || true
fi

echo "==> 3/4  Viết Info.plist…"
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>     <string>Bow Go — Bộ gõ tiếng Việt</string>
    <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>         <string>1.0.7</string>
    <key>CFBundleShortVersionString</key><string>1.0.7</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleExecutable</key>      <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <!-- App accessory: ẩn khỏi Dock, chỉ có icon menu bar -->
    <key>LSUIElement</key>            <true/>
    <key>NSInputMonitoringUsageDescription</key>
    <string>Bow Go cần quyền giám sát bàn phím để nhận diện các tổ hợp phím và gõ tiếng Việt.</string>
    <key>NSAccessibilityUsageDescription</key>
    <string>Bow Go cần quyền trợ năng để thực hiện chức năng gõ thay ký tự tiếng Việt.</string>
</dict>
</plist>
PLIST
echo "==> 3.5/4 Tích hợp Settings UI (Flutter)…"
cd "$ROOT/../../apps/settings_ui"
fvm flutter build macos --release
HELPERS_DIR="$APP_DIR/Contents/Helpers"
mkdir -p "$HELPERS_DIR"
rm -rf "$HELPERS_DIR/Bow Go.app"
cp -R "build/macos/Build/Products/Release/Bow Go.app" "$HELPERS_DIR/"
cd "$ROOT"

echo "==> 4/4  Code sign (ad-hoc, từ TRONG ra NGOÀI)…"
# Ký ad-hoc (-) đủ để chạy & cấp quyền trên máy của chính bạn.
# Khi phân phối cho người khác, thay bằng Developer ID + notarize.
#
# QUAN TRỌNG — ký "inside-out" và KHÔNG dùng `--deep`:
#   TCC định danh app bằng (bundle id trong Info.plist) + (identifier trong chữ
#   ký). Hai cái này PHẢI khớp nhau. `--deep` ký đè lên MỌI bundle nhúng và áp
#   chung `--identifier` của bundle ngoài ("com.bowgo.keyboard") lên cả Helper —
#   trong khi Info.plist của Helper là "com.bowgo.app". Lệch identifier ⟺ plist
#   khiến TCC coi app là "lạ": cấp quyền xong vẫn báo chưa cấp. Vì vậy phải ký
#   TỪNG bundle với đúng identifier của nó, Helper TRƯỚC rồi mới tới app ngoài,
#   và bỏ hẳn `--deep`. (Apple cũng đã khuyến cáo ngừng dùng --deep.)
#
# CỐ Ý KHÔNG dùng `--options runtime` (Hardened Runtime):
#   Hardened Runtime khiến TCC siết chặt việc đối chiếu danh tính code. Với chữ ký
#   ad-hoc (không có Team ID ổn định), MỖI lần build lại binary đổi cdhash -> macOS
#   coi như app khác -> THU HỒI quyền Accessibility/Input Monitoring đã cấp, dù công
#   tắc trong Settings vẫn xanh. Bỏ runtime giúp quyền bám ổn định hơn giữa các lần
#   build cục bộ. (Khi phân phối thật thì bật lại runtime + Developer ID + notarize.)

# 1) Ký Helper (Settings UI) TRƯỚC. Ở ĐÂY --deep là an toàn: mọi thứ bên trong
#    Helper (Flutter framework nhúng…) đều thuộc cùng một danh tính com.bowgo.app,
#    nên áp chung identifier xuống nested không gây lệch với plist như trước.
#    Ký nested xong ở bước này để bước 2 (app ngoài) không cần đụng tới chúng.
codesign --force --deep --sign - \
    --identifier "com.bowgo.app" \
    "$HELPERS_DIR/Bow Go.app"

# 2) Ký app NGOÀI (bộ gõ) SAU, KHÔNG --deep. Helper đã tự ký hợp lệ ở bước 1 nên
#    codesign chỉ cần "seal" nó vào bundle ngoài mà KHÔNG re-sign / ghi đè
#    identifier của nó. Đây là mấu chốt để plist ⟺ chữ ký của Helper luôn khớp.
codesign --force --sign - \
    --identifier "$BUNDLE_ID" \
    "$APP_DIR"

echo ""
echo "✅ Xong: $APP_DIR"
echo ""
echo "Chạy thử:   open \"$APP_DIR\""
echo "Lần đầu sẽ cần cấp quyền Accessibility + Input Monitoring trong System Settings,"
echo "tìm mục \"$APP_NAME\", bật lên, rồi mở lại app."
echo "Nếu sau khi build lại mà gõ không được (icon hiện EN): xoá entry BowGo cũ"
echo "(dấu –) trong cả hai mục quyền rồi mở lại app để cấp lại."
