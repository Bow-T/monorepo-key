# 🏹 Bow Key — Bộ gõ tiếng Việt đa nền tảng

Một monorepo cho bộ gõ tiếng Việt (Telex/VNI) chạy trên **macOS, Windows, Android, iOS**.

Triết lý cốt lõi: **một engine, nhiều bộ gõ native.**

Logic gõ (bỏ dấu, đặt dấu đúng chính tả, gõ lại bỏ dấu, backspace) là phần khó &
giá trị nhất — nó được viết **một lần** và dùng làm **spec chuẩn**. Phần "chặn phím
toàn hệ thống" thì mỗi OS bắt buộc một công nghệ native riêng (xem bảng bên dưới),
nên mỗi nền tảng có một app native bám theo cùng spec đó.

---

## 📁 Cấu trúc dự án

Tổ chức theo Monorepo (giống `monorepo-remote`), Dart workspace cho phần Dart:

```
monorepo-key/
├── packages/
│   └── viet_engine/        # Engine gõ tiếng Việt thuần Dart + BỘ CA TEST CHUẨN
├── apps/
│   ├── macos_ime/          # macOS — CGEvent tap (Swift) — ✅ chạy được
│   ├── windows_ime/        # Windows — TSF text service (C++) — ⬜ chưa làm
│   ├── android_ime/        # Android — InputMethodService (Kotlin) — ⬜ chưa làm
│   ├── ios_keyboard/       # iOS — Keyboard Extension (Swift) — ⬜ chưa làm
│   └── settings_ui/        # Flutter — UI cài đặt (chọn Telex/VNI…) — ⬜ chưa làm
├── pubspec.yaml            # Dart workspace (resolution dùng chung)
└── README.md               # tài liệu này
```

> **Vì sao bộ gõ không viết toàn bộ bằng Flutter/Dart?**
> Một bộ gõ phải chen vào tầng nhập liệu của HĐH để bắt phím cho **mọi ứng dụng khác**.
> Flutter chỉ render trong cửa sổ app của nó nên không làm được việc này. Mỗi OS bắt
> buộc một công nghệ native:
>
> | Nền tảng | Công nghệ bắt buộc | Ngôn ngữ |
> |---|---|---|
> | macOS | CGEvent tap | Swift |
> | Windows | TSF / IMM32 | C++ |
> | Android | `InputMethodService` | Kotlin |
> | iOS | Keyboard Extension | Swift |
>
> Vì vậy Flutter ở đây làm **UI cài đặt** (`apps/settings_ui`), không phải bản thân bộ gõ.

---

## ⚡ Bắt đầu nhanh

Dự án Dart dùng **fvm** (Flutter version đã pin trong `.fvmrc`).

### 1. Engine (Dart) — chạy được mọi nền

```bash
fvm dart pub get                     # resolve workspace (từ thư mục gốc)
fvm dart test packages/viet_engine   # 25 ca test chuẩn
```

### 2. App macOS (Swift) — bộ gõ thật trên máy

```bash
cd apps/macos_ime
swift test                       # 25 test engine Swift (khớp bản Dart)
bash scripts/build-app.sh        # build + ký -> build/BowKey.app
open build/BowKey.app
```

Lần đầu cần cấp **Accessibility** + **Input Monitoring** trong System Settings cho
mục **Bow Key**, rồi mở lại app. Chi tiết: [apps/macos_ime/README.md](apps/macos_ime/README.md).

---

## 🧠 Engine chung & "bộ ca test chuẩn"

`packages/viet_engine` là nguồn chân lý cho logic gõ. Mỗi bộ gõ native (Swift/C++/Kotlin)
**phải vượt qua cùng một bộ ca test** (vd `tieengs → tiếng`, `hoaf → hoà`, `quys → quý`)
để đảm bảo gõ giống hệt nhau trên mọi nền tảng. Hiện engine Dart và engine Swift (macOS)
đều xanh 25/25 trên cùng bộ ca này.

Tính năng engine đã có:
- Telex + VNI: dấu thanh, mũ, móc, trăng, đ
- Đặt dấu chuẩn chính tả: modern (hoà, quý) + old (hòa, qúy)
- Cụm "ươ" (nướng, được)
- Gõ lại để bỏ/đổi dấu (hoaff→hoaf, hoafs→hoá)
- Backspace bằng cách dựng lại (replay) từ buffer phím thô

---

## 🗺️ Lộ trình

| Phần | Công nghệ | Trạng thái |
|---|---|---|
| Engine gõ | Dart (`viet_engine`) | ✅ 25 test xanh |
| macOS IME | Swift + CGEvent tap | ✅ Chạy được |
| Windows IME | C++ + TSF | ⬜ Chưa làm |
| Android IME | Kotlin + InputMethodService | ⬜ Chưa làm |
| iOS keyboard | Swift + Keyboard Extension | ⬜ Chưa làm |
| UI cài đặt | Flutter (`settings_ui`) | ⬜ Chưa làm |

Hướng mở rộng engine: kiểm tra âm tiết hợp lệ (auto-restore tiếng Anh), bảng mã ngoài
Unicode (TCVN3/VNI-Windows), Smart Switch nhớ bật/tắt theo app.

> **Cân nhắc kỹ thuật:** để 4 nền tảng dùng *chung một* engine biên dịch (thay vì port
> lại logic sang C++/Kotlin), một hướng là tách engine thành **core Rust** gọi qua FFI.
> Hiện tại engine Dart đóng vai spec + phục vụ UI Flutter; native mỗi OS bám theo spec đó.

---

> **Bản quyền:** code trong repo này được viết lại từ đầu (clean-room) dựa trên *ý tưởng*
> chung về cách một bộ gõ tiếng Việt hoạt động, KHÔNG sao chép mã nguồn của bất kỳ dự án nào.
