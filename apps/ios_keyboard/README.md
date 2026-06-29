# ios_keyboard — Bàn phím Bow Key cho iOS (chưa làm)

Bộ gõ trên iOS là một **Custom Keyboard Extension** viết bằng **Swift** (target App
Extension đi kèm một app chủ). iOS không cho app chặn phím toàn hệ thống như macOS;
thay vào đó người dùng cài "bàn phím" của bạn rồi chọn dùng nó. Flutter không tạo
được keyboard extension chuẩn của iOS.

## Cách phần này dùng lại engine
- Logic gõ (Telex/VNI, đặt dấu) là **spec chung** ở [`packages/viet_engine`](../../packages/viet_engine).
- Bản native Swift ở đây có thể **tái dùng chính engine Swift** trong
  [`apps/macos_ime/Sources/VietEngine`](../macos_ime/Sources/VietEngine) (cùng ngôn ngữ),
  và phải vượt qua **cùng bộ ca test** chuẩn.

## Việc cần làm khi bắt đầu
- [ ] App chủ (host app) + target Keyboard Extension
- [ ] UI bàn phím (layout chữ + phím dấu)
- [ ] Nối engine Swift `VietEngine` vào extension
- [ ] Chạy bộ ca test chuẩn để đảm bảo khớp bản Dart/macOS
