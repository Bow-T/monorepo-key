# ADR 0001 — Engine gõ dùng chung: chưa tách core Rust, khoá hành vi bằng bộ ca chuẩn

- **Trạng thái:** Bị thay thế bởi [ADR 0002](0002-engine-core-rust.md) — 2026-10-27
  (giữ phần bộ ca chuẩn + CI; bỏ quyết định hoãn core Rust)
- **Phạm vi:** logic gõ (Telex/VNI, đặt dấu, gõ lại bỏ dấu, backspace). Các tiện ích
  chỉ có ở Swift (Calculator, EmojiShortcodes, AIProvider…) không thuộc ADR này.

## Bối cảnh

Logic gõ hiện có **ba bản viết tay**, không sinh từ nhau:

| Bản | Vị trí | Vai trò |
|---|---|---|
| Dart | `packages/viet_engine` | spec + `TextConverter` cho UI Flutter |
| Swift | `apps/macos_ime/Sources/VietEngine` | bộ gõ macOS đang phát hành |
| C++ | `apps/windows_ime/engine` | bộ gõ Windows (TSF mới ở skeleton) |

Android và iOS chưa có code.

Chi phí thật đang phải trả là **lệch giữa các bản**. PR #35, #36, #37/#38 đều là việc
"port cho khớp" (`8b03243`, `242be65`, `be5a556`). Trước ADR này không có gì so ba bản
với nhau. Ví dụ: corpus 249 từ × 4 cách gõ của `CorpusRegressionTests` chỉ engine
Swift chạy.

Đề xuất được xét: tách engine thành **một core Rust** gọi qua FFI cho mọi nền tảng.

## Các phương án

1. **Core Rust + C ABI** (cbindgen / uniffi cho Swift–Kotlin, `dart:ffi` cho Flutter).
   Chỉ còn một bản. Đổi lại phải viết lại ~1.000 dòng lõi gõ, thêm toolchain cargo
   cho mọi nền, và thay engine của bản macOS đang phát hành.
2. **Nâng engine C++ sẵn có thành core dùng chung** qua C ABI. Không phải viết lại,
   nhưng C++ là bản non nhất (vừa đuổi kịp ở #36) và vẫn thiếu an toàn bộ nhớ.
3. **Giữ các bản native, khoá hành vi bằng một bộ ca chuẩn dùng chung + CI.** ← chọn

## Quyết định

Làm **phương án 3 ngay**. Phương án 1 **hoãn có điều kiện** (xem dưới).

- Bộ ca chuẩn: `packages/viet_engine/spec/typing_cases.tsv` (844 ca, gom từ test của
  cả ba bản). Dart (`golden_cases_test.dart`), Swift (`GoldenCasesTests.swift`) và
  C++ (`CheckSharedCases` trong `test_engine.cpp`) cùng nạp file này.
- CI: `engine-parity.yml` chạy Dart + Swift; `windows-ime.yml` chạy C++ khi file
  spec đổi.
- Bốn nền tảng vẫn chỉ cần ba bản: **iOS dùng lại `VietEngine` Swift** (không import
  AppKit), **Android dùng lại engine C++ qua NDK/JNI**. Không viết bản Kotlin.

## Lý do

- Bộ ca chuẩn là điều kiện cần cho **mọi** hướng. Muốn thay bằng Rust thì cũng phải có
  oracle chứng minh bản Rust gõ giống hệt bản cũ. Làm nó trước không phí công.
- Rust kéo theo các việc sau, đều chưa có:
  - toolchain + target cho từng nền: universal macOS qua `lipo`, MSVC, Android NDK,
    iOS xcframework;
  - sửa `build-app.sh` và CI;
  - một ngôn ngữ mới cho team đang viết Dart/Swift/C++.
- Hồi quy khi thay engine của bản macOS đang phát hành là rủi ro lớn nhất. Lợi ích
  (bớt hai bản) chưa đủ bù khi lệch đã bị CI chặn.
- Phần tiện ích chỉ có ở Swift vẫn ở lại native dù có core Rust. Core Rust không xoá
  được app native nào.

## Điều kiện mở lại phương án 1 (Rust)

Chỉ cần một trong ba điều sau:

- Vẫn phải làm ≥ 3 PR "port cho khớp" trong một quý dù đã có cổng CI. Khi đó chi phí
  giữ ba bản đã vượt chi phí chuyển.
- Cần một nền tảng không dùng lại được Swift/C++ (vd web/WASM).
- DLL TSF (C++ chạy trong tiến trình của app khác) gặp lỗi bộ nhớ làm sập app chủ.

Nếu mở lại, chuyển theo thứ tự:

1. Crate `packages/viet_core` qua toàn bộ `typing_cases.tsv`.
2. Android (chưa có code, không phải thay gì).
3. Windows (thay engine C++).
4. iOS.
5. macOS sau cùng.

Bản Dart giữ vai spec tới khi macOS chuyển xong.

## Hệ quả

- Thêm hoặc sửa một luật gõ:
  1. Thêm ca vào `typing_cases.tsv`.
  2. Port code sang cả ba bản.
  
  CI đỏ nếu sót bản nào.
- Ca cũ trong ba bộ test riêng vẫn giữ (trùng với file chung). Dọn dần khi đụng tới,
  không bắt buộc.
- File spec chỉ chứa ca **một âm tiết, không phím ngắt từ** (`<` = Backspace). Hành vi
  nhiều từ / macro / auto-correct vẫn test riêng ở từng bản.
