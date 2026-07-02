# Icon khay hệ thống (Windows)

**`bowgo.ico`** đã có sẵn: badge pixel "VI" trắng trên nền xanh grass (#5DA130),
bo góc — khớp phong cách badge menu bar macOS (`apps/windows_ime/tsf/badge_icon.cpp`).
Gồm 7 kích thước (16/24/32/48/64/128/256 px).

Dùng bởi `tray_manager.setIcon('assets/tray/bowgo.ico')` trong
`lib/src/services/windows_runtime.dart`. Nếu file bị xoá, app vẫn chạy — chỉ là
mục khay không có icon (`_setupTray` bọc trong try/catch).

Muốn đổi icon: thay `bowgo.ico` (giữ nguyên tên). Có thể tạo lại bằng ImageMagick
từ lưới glyph trong `badge_icon.cpp` để đồng nhất.
