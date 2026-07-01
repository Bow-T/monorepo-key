# 🏹 Bow Go — Bộ gõ tiếng Việt đa nền tảng

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
│   ├── windows_ime/        # Windows — TSF (C++) — 🟨 engine xong (81 test), TSF skeleton
│   ├── android_ime/        # Android — InputMethodService (Kotlin) — ⬜ chưa làm
│   ├── ios_keyboard/       # iOS — Keyboard Extension (Swift) — ⬜ chưa làm
│   └── settings_ui/        # Flutter — UI cài đặt pixel (Telex/VNI…) — ✅ chạy được (macOS)
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
swift test                       # 84 test engine Swift (khớp bản Dart)
bash scripts/build-app.sh        # build + ký -> "build/Bow Go.app"
open "build/Bow Go.app"
```

Lần đầu cần cấp **Accessibility** + **Input Monitoring** trong System Settings cho
mục **Bow Go**, rồi mở lại app. Phím tắt **⌃⌥ Space** bật/tắt nhanh.
Chi tiết: [apps/macos_ime/README.md](apps/macos_ime/README.md).

### 3. UI cài đặt (Flutter) — giao diện pixel

```bash
cd apps/settings_ui
fvm flutter run -d macos          # mở app cài đặt phong cách pixel
```

Chọn Telex/VNI, kiểu đặt dấu (hiện đại/cũ), bật/tắt, gõ thử ngay trong app. Mọi
thay đổi **auto-save** ra file JSON dùng chung; bộ gõ Swift đọc & áp **ngay lập tức**
(không cần khởi động lại). Xem mục "Đường dây UI ↔ bộ gõ" bên dưới.

---

## 🧠 Engine chung & "bộ ca test chuẩn"

`packages/viet_engine` là nguồn chân lý cho logic gõ. Mỗi bộ gõ native (Swift/C++/Kotlin)
**phải vượt qua cùng một bộ ca test** (vd `tieengs → tiếng`, `hoaf → hoà`, `quys → quý`)
để đảm bảo gõ giống hệt nhau trên mọi nền tảng. Hiện engine Dart (74 test), engine
Swift macOS (84 test) và engine C++ Windows (114 test) đều xanh trên cùng bộ ca này.

Tính năng engine đã có:
- Telex + VNI: dấu thanh, mũ, móc, trăng, đ
- Đặt dấu chuẩn chính tả: modern (hoà, quý) + old (hòa, qúy)
- Cụm "ươ" (nướng, được)
- Gõ lại để bỏ/đổi dấu (hoaff→hoaf, hoafs→hoá)
- Kéo dài nguyên âm đúng chu kỳ mũ (aaaa→aaa, chòiiii)
- Backspace bằng cách dựng lại (replay) từ buffer phím thô
- **Gõ tắt / Macro**: `vn`→Việt Nam; nội dung tĩnh + động (ngày/giờ/đếm/ngẫu nhiên)
- **Công cụ chuyển mã**: bỏ dấu, hoa/thường (4 kiểu), NFC↔NFD, TCVN3/VNI-Windows
- **Tự khôi phục tiếng Anh** (heuristic, không từ điển): từ biến dạng & không hợp
  lệ tiếng Việt → trả phím thô (vd "terminäl"→"terminal")
- **Tự sửa lỗi gõ nhanh**: khi chốt từ, dời dấu thanh đặt sai vị trí + tra từ điển
  tĩnh lỗi phổ biến (vd "giừo"→"giờ", "nhièu"→"nhiều"). Tắt mặc định.
- **Kiểm tra chính tả** tiếng Việt theo luật âm tiết (gạch chân từ sai)

---

## 🗺️ Lộ trình

| Phần | Công nghệ | Trạng thái |
|---|---|---|
| Engine gõ | Dart (`viet_engine`) | ✅ 74 test xanh (gõ + macro + chuyển mã + chính tả) |
| macOS IME | Swift + CGEvent tap | ✅ Chạy được (84 test engine) |
| Windows IME | C++ + TSF | 🟨 Engine C++ xong (114 test xanh); TSF text service mới ở skeleton |
| Android IME | Kotlin + InputMethodService | ⬜ Chưa làm |
| iOS keyboard | Swift + Keyboard Extension | ⬜ Chưa làm |
| UI cài đặt | Flutter (`settings_ui`) | ✅ Chạy được (macOS), pixel UI |

Hướng mở rộng engine: kiểm tra âm tiết hợp lệ (auto-restore tiếng Anh), bảng mã ngoài
Unicode (TCVN3/VNI-Windows), Smart Switch nhớ bật/tắt theo app.

### 🔌 Đường dây UI ↔ bộ gõ

App UI Flutter và bộ gõ Swift **không gọi nhau trực tiếp** — chúng dùng chung một
file JSON làm "hợp đồng":

```
~/Library/Application Support/BowGo/settings.json
{
  "enabled": true, "method": "telex", "toneStyle": "modern",
  "hotkeyKeyCode": 49, "hotkeyModifiers": ["control","option"],
  "toggleHotkey": "⌃⌥ Space",
  "smartSwitch": false, "perApp": { "com.apple.Terminal": false },

  "autoRestoreEnglish": false,
  "autoCorrect": false,
  "macroEnabled": true,
  "macros": [
    { "keyword": "vn", "content": "Việt Nam" },
    { "keyword": "email", "content": "ban@example.com" },
    { "keyword": "td", "content": "dd/MM/yyyy", "type": "date" }
  ]
}
```

- **`macros`** — gõ tắt: gõ `keyword` (phím thô ASCII) + space/return/tab → thay bằng
  `content`. `type`: `staticText` (mặc định) · `date` · `time` · `dateTime` · `random`
  (content = "a, b, c") · `counter` (content = tiền tố). Tắt toàn bộ bằng `macroEnabled:false`.
- **`autoRestoreEnglish`** — bật để từ bị biến dạng & không hợp lệ tiếng Việt tự trả về
  phím thô khi chốt từ (heuristic theo luật âm tiết, không cần từ điển).
- **`autoCorrect`** — bật để tự sửa lỗi gõ nhanh khi chốt từ: dời dấu thanh đặt sai vị
  trí + tra từ điển tĩnh các lỗi phổ biến ("giừo"→"giờ"). Thêm từ vào danh sách trong
  `AutoCorrectDictionary.words` để mở rộng. Mặc định tắt.

- **Flutter GHI** (auto-save mỗi khi đổi cài đặt) — `settings_ui/lib/src/models/settings.dart`.
- **Swift ĐỌC + watch file** (`DispatchSource`) → áp ngay không cần restart — `macos_ime/App/SettingsStore.swift`.
- **Phím tắt tuỳ biến**: UI "thu" tổ hợp phím → ghi `hotkeyKeyCode` (mã phím macOS) +
  `hotkeyModifiers`; Swift so khớp CHÍNH XÁC tập modifier. `toggleHotkey` chỉ là chuỗi hiển thị.
- **Smart Switch**: bật `smartSwitch` để bộ gõ tự nhớ bật/tắt theo từng app vào `perApp`
  (bundleId → enabled). Swift theo dõi app focus (`NSWorkspace`) và tự khôi phục. UI giữ
  nguyên `perApp` khi ghi để không xoá bộ nhớ.
- Phím tắt (hoặc menu bar) bật/tắt cũng **ghi ngược** `enabled` vào file để UI đồng bộ.
- Các khoá JSON phải KHỚP hai bên; đổi tên một bên phải đổi bên kia.

> **Cân nhắc kỹ thuật:** để 4 nền tảng dùng *chung một* engine biên dịch (thay vì port
> lại logic sang C++/Kotlin), một hướng là tách engine thành **core Rust** gọi qua FFI.
> Hiện tại engine Dart đóng vai spec + phục vụ UI Flutter; native mỗi OS bám theo spec đó.
