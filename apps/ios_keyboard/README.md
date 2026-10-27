# ios_keyboard — Bàn phím Bow Go cho iOS (chưa làm)

Bộ gõ trên iOS là một **Custom Keyboard Extension** viết bằng **Swift** (target App
Extension đi kèm một app chủ). iOS không cho app chặn phím toàn hệ thống như macOS;
thay vào đó người dùng cài "bàn phím" của bạn rồi chọn dùng nó. Flutter không tạo
được keyboard extension chuẩn của iOS.

## Cách phần này dùng lại engine
- Logic gõ (Telex/VNI, đặt dấu) là **spec chung** ở [`packages/viet_engine`](../../packages/viet_engine).
- Bản native Swift ở đây có thể **tái dùng chính lớp `VietEngine`** trong
  [`apps/macos_ime/Sources/VietEngine`](../macos_ime/Sources/VietEngine) — lớp này bọc core
  Rust [`packages/viet_core`](../../packages/viet_core) (xem [ADR 0002](../../docs/adr/0002-engine-core-rust.md)).

## Việc cần làm khi bắt đầu
- [ ] App chủ (host app) + target Keyboard Extension
- [ ] UI bàn phím (layout chữ + phím dấu)
- [ ] Build `viet_core` cho iOS (`aarch64-apple-ios`, gom thành xcframework) rồi nối `VietEngine` vào extension
