# ADR 0002 — Engine gõ của bộ gõ native là một core Rust gọi qua C ABI

- **Trạng thái:** Chấp nhận — 2026-10-27. Thay thế quyết định "hoãn core Rust" của
  [ADR 0001](0001-engine-core-dung-chung.md); giữ nguyên bộ ca chuẩn + CI của ADR đó.
- **Phạm vi:** máy trạng thái gõ âm tiết: Telex/VNI, đặt dấu, gõ lại bỏ dấu, backspace.
  - Macro, tự sửa lỗi gõ nhanh, tự khôi phục tiếng Anh, chuyển mã và mọi tiện ích khác
    vẫn ở native: Swift trên macOS, C++ trên Windows.
  - Engine Dart (`packages/viet_engine`) vẫn là spec và phục vụ UI Flutter.

## Quyết định

- **Core:** `packages/viet_core`, Rust. Đây là bản port của `Engine.swift`, kèm crate
  `staticlib` và C ABI ở `include/viet_core.h` gồm `bow_engine_new` / `process` /
  `backspace` / `clear` / `text` / `is_word_char` / `free`.
- **macOS:** `VietEngine` (Swift) giữ nguyên API công khai và gọi core qua module
  `CVietCore`, link tĩnh `libviet_core.a`.
  - Phần cấp từ (macro, auto-correct, khôi phục tiếng Anh) ở lại trong lớp bọc.
  - Phải chạy `scripts/build-core.sh` trước `swift build` / `swift test`. `build-app.sh`
    và CI tự làm bước này.
- **Windows:** `bowgo::VietEngine` (C++) giữ API cũ và bọc core. CMake gọi `cargo`, rồi link
  thêm thư viện hệ thống mà std của Rust cần.
- **Android / iOS:** gọi cùng core. Android qua NDK/JNI; iOS dùng lại `VietEngine` Swift,
  với core build thành xcframework.
- **Spec:** bộ ca `packages/viet_engine/spec/typing_cases.tsv` chạy trên core
  (`cargo test`), trên engine Dart, và qua hai lớp bọc Swift/C++.

## Lý do

- Bỏ được hai bản viết tay (Swift ~840 dòng, C++ ~600 dòng). Luật gõ mới chỉ viết một
  lần cho bộ gõ native.
- Android và iOS chưa có code. Chọn core trước khi viết chúng thì không phải port thêm bản
  thứ 4.
- Rust an toàn bộ nhớ, quan trọng với DLL TSF chạy trong tiến trình của app khác.
  `panic = "abort"`, và không có panic nào được unwind qua FFI.
- Bề mặt FFI nhỏ: app macOS chỉ gọi engine qua `process`, `backspace`, `clear`.

## Đánh đổi đã chấp nhận

- **Toolchain:** mọi build native cần `cargo`. Image GitHub Actions (macOS 26, Windows 2025,
  Ubuntu 24.04) có sẵn Rust.
- **`swift test` không còn chạy trần:** phải chạy `scripts/build-core.sh` trước.
  - SwiftPM link `libviet_core.a` qua `-l` nên không theo dõi file này. Nếu chỉ core đổi,
    SwiftPM sẽ không tự link lại.
  - Script xoá các sản phẩm đã link mà cũ hơn thư viện. CMake thì tự link lại vì
    theo dõi thư viện IMPORTED.
- **Hai bản luật gõ:** vẫn còn Dart (spec + UI) và Rust. Bộ ca chung chặn lệch giữa hai bản.
- **Phân loại phím:** core dùng `char::is_alphabetic` / `is_numeric` của Unicode, gần với
  `Character.isLetter` / `isNumber` của Swift cũ. Phía Windows trước đây chỉ nhận chữ ASCII.
  Từ nay hai nền tảng phân loại phím như nhau.
- **Ký tự nhiều scalar:** lớp bọc Swift dựng sẵn NFC trước khi gửi xuống core. Nếu vẫn
  còn nhiều scalar thì coi là phím ngắt từ.
