# windows_ime — Bộ gõ Bow Key cho Windows (chưa làm)

Bộ gõ trên Windows phải là một **Text Services Framework (TSF)** text service viết bằng
**C++/Win32** (hoặc IMM32 cho bản tối giản). Đây là tầng Windows cho phép chen vào
luồng nhập liệu của **mọi ứng dụng** — Flutter/Dart không với tới được tầng này.

## Cách phần này dùng lại engine
- Logic gõ (Telex/VNI, đặt dấu) là **spec chung** ở [`packages/viet_engine`](../../packages/viet_engine).
- Bản native C++ ở đây sẽ **bám sát spec đó** và phải vượt qua **cùng bộ ca test**
  (golden cases) trong `packages/viet_engine/test/engine_test.dart`.

## Việc cần làm khi bắt đầu
- [ ] Dựng skeleton TSF text service (DLL, COM in-proc server)
- [ ] Đăng ký input method với Windows (CLSID + profile)
- [ ] Port engine sang C++ theo spec `viet_engine` (hoặc gọi core Rust nếu sau này tách core)
- [ ] Chạy bộ ca test chuẩn để đảm bảo khớp bản Dart/Swift
