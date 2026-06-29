# android_ime — Bộ gõ Bow Key cho Android (chưa làm)

Bộ gõ trên Android là một **`InputMethodService`** viết bằng **Kotlin/Java**. Đây là
API Android cho bàn phím ảo / bộ gõ; nó hiển thị bàn phím và đẩy ký tự vào ô nhập của
ứng dụng đang focus. Flutter chạy trong cửa sổ app riêng nên không đóng vai trò này.

## Cách phần này dùng lại engine
- Logic gõ (Telex/VNI, đặt dấu) là **spec chung** ở [`packages/viet_engine`](../../packages/viet_engine).
- Bản native Kotlin ở đây **bám sát spec đó** và phải vượt qua **cùng bộ ca test**
  (golden cases) trong `packages/viet_engine/test/engine_test.dart`.

## Việc cần làm khi bắt đầu
- [ ] Dựng skeleton `InputMethodService` + layout bàn phím
- [ ] Khai báo bộ gõ trong AndroidManifest (`android.view.InputMethod`)
- [ ] Port engine sang Kotlin theo spec `viet_engine` (hoặc gọi core Rust nếu tách core)
- [ ] Chạy bộ ca test chuẩn để đảm bảo khớp bản Dart/Swift
