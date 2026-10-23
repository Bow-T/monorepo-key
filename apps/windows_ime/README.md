# windows_ime — Bộ gõ Bow Go cho Windows (C++/TSF)

Bộ gõ trên Windows là một **Text Services Framework (TSF)** text service viết bằng
**C++/Win32**. Đây là tầng Windows cho phép chen vào luồng nhập liệu của **mọi ứng
dụng** — Flutter/Dart không với tới được tầng này.

```
apps/windows_ime/
├── engine/                  # ENGINE C++ thuần — ĐÃ KIỂM CHỨNG (đa nền)
│   ├── viet_model.h         # Tone / Mark / InputMethod / ToneStyle
│   ├── viet_table.h/.cpp    # bảng tra (gốc+mark+tone) -> char32_t Unicode
│   ├── viet_syllable.h/.cpp # luật âm tiết + tự khôi phục tiếng Anh
│   ├── engine.h/.cpp        # bộ não: nhận phím -> trả chuỗi tiếng Việt
│   ├── macro.h/.cpp         # gõ tắt (vn -> Việt Nam), tĩnh + động
│   ├── auto_correct.h/.cpp  # tự sửa lỗi gõ nhanh (giừo -> giờ)
│   ├── text_converter.h/.cpp# bỏ dấu / đổi hoa-thường / TCVN3 / VNI
│   └── test_engine.cpp      # 218 ca test chuẩn (khớp Dart/Swift)
├── common/                  # TẦNG DÙNG CHUNG — ĐÃ KIỂM CHỨNG (đa nền)
│   ├── text_codec.h/.cpp    # UTF-8 <-> UTF-16 <-> UTF-32
│   ├── bow_config.h/.cpp    # đọc settings.json (dùng chung với app Flutter)
│   ├── ime_controller.h/.cpp# controller: mirror EventTapController.swift
│   └── test_common.cpp      # 66 ca test (codec + config + controller)
├── tsf/                     # TEXT SERVICE TSF — chỉ build trên Windows
│   ├── BowGoTextService.h/.cpp # ITfTextInputProcessor + key sink -> controller
│   ├── lang_bar.h/.cpp      # nút VI/EN trên khay ngôn ngữ (ITfLangBarItemButton)
│   ├── badge_icon.h/.cpp    # vẽ icon badge VI/EN pixel (GDI), khớp phong cách macOS
│   ├── dll_main.cpp         # COM in-proc server + đăng ký TSF/registry
│   └── BowGoTSF.def         # export hàm COM (DllGetClassObject...)
└── CMakeLists.txt           # build engine+common+test (đa nền) & DLL TSF (Windows)
```

## Trạng thái

| Phần | Trạng thái |
|---|---|
| Engine C++ (Telex/VNI, đặt dấu, backspace, macro, tự sửa lỗi, chuyển mã) | ✅ **218/218 ca test xanh** (khớp Dart/Swift) |
| Tầng common (controller + đọc settings.json + chuyển mã) | ✅ **66/66 ca test xanh** (đa nền) |
| Cầu nối phím → controller (`ImeController`) | ✅ Bám sát `EventTapController.swift`, test đa nền |
| Ghi văn bản qua `ITfEditSession` (`ReplaceText`) | ✅ Viết xong (xoá N ký tự + chèn chuỗi mới) |
| Gắn/gỡ sink (`AdviseKeyEventSink`, `AdviseSink`) | ✅ Viết xong trong `Activate`/`Deactivate` |
| Đăng ký TSF (`ITfInputProcessorProfiles`, registry) | ✅ Viết xong trong `DllRegisterServer` |
| CLSID/GUID thật | ✅ Đã sinh (uuidgen) |
| Dịch phím theo layout thật (`ToUnicodeEx`) | ✅ Viết xong (thay bản ASCII tối giản) |
| Nạp/theo dõi `%APPDATA%\BowGo\settings.json` | ✅ Viết xong (nạp lại khi đổi focus) |
| Icon VI/EN trên khay ngôn ngữ (langbar button + GDI) | ✅ Viết xong (bấm để bật/tắt) |
| Phím tắt bật/tắt Ctrl+Shift+Space (`PreserveKey`) | ✅ Viết xong |
| **Thử trên máy Windows thật** | ⬜ **CHƯA** — cần build bằng Visual Studio + cài thử |

> ⚠️ Phần `tsf/` **chưa build/chạy trên macOS** (cần Windows SDK + `msctf.h` +
> Visual Studio). Phần đã kiểm chứng đa nền là `engine/` + `common/` — chứa TOÀN BỘ
> logic bộ gõ (đặt dấu, backspace đồng bộ, gõ tắt, khôi phục tiếng Anh, tự sửa lỗi,
> đọc settings). `tsf/` chỉ còn là lớp "keo dán" Win32/TSF gọi vào `common/`.

## Engine + common — chạy & test (mọi nền, gồm macOS)

Không cần Windows. Đây là spec chung, phải vượt **cùng bộ ca test** với bản Dart
(`packages/viet_engine`) và Swift (`apps/macos_ime`).

```bash
cd apps/windows_ime
cmake -S . -B build && cmake --build build
./build/bowgo_engine_tests    # in "218 pass, 0 fail."
./build/bowgo_common_tests    # in "66 pass, 0 fail."
# hoặc: cd build && ctest
```

## Build TSF DLL (chỉ trên Windows)

Cần Visual Studio 2022 (hoặc Build Tools) + Windows 10/11 SDK.

```powershell
cd apps\windows_ime
cmake -S . -B build -G "Visual Studio 17 2022" -A x64
cmake --build build --config Release
# -> build\Release\BowGoTSF.dll
```

## Cài đặt & thử trên Windows

```powershell
# Chạy PowerShell/CMD bằng quyền Administrator (đăng ký ghi vào HKCR + TSF).
regsvr32 build\Release\BowGoTSF.dll        # đăng ký
#   -> DllRegisterServer thành công.

# Gỡ:
regsvr32 /u build\Release\BowGoTSF.dll
```

Sau khi đăng ký:
1. Vào **Settings ▸ Time & language ▸ Language & region** — thêm ngôn ngữ **Tiếng
   Việt** nếu chưa có.
2. Chọn bộ gõ **Bow Go** qua thanh ngôn ngữ hoặc **Win + Space**.
3. Cấu hình (Telex/VNI, gõ tắt, tự sửa lỗi...) qua app cài đặt Flutter — nó ghi
   `%APPDATA%\BowGo\settings.json`, DLL đọc & nạp lại khi đổi ô nhập.
4. Gõ thử: `tieengs → tiếng`, `vn → Việt Nam` (nếu bật gõ tắt).

## Cách tầng TSF nối vào logic dùng chung

```
Phím Windows (WPARAM/VK)
      │  ToUnicodeEx theo layout thật
      ▼
BowGoTextService::OnKeyDown ──► ImeController::HandleChar/HandleBackspace/HandleWordBreak
      │                               │  (logic đã test đa nền: đặt dấu, gõ tắt,
      │                               │   khôi phục tiếng Anh, tự sửa lỗi)
      │        KeyAction (Pass / Replace{backspaces, text, resend})
      ▼
BowGoTextService::ApplyReplace ──► ITfEditSession: lùi N ký tự + SetText(chuỗi mới)
```

Cấu hình đọc từ `%APPDATA%\BowGo\settings.json` — **dùng chung** với bản macOS
(`~/Library/Application Support/BowGo/settings.json`) qua cùng schema JSON.

## Phím tắt & khay ngôn ngữ
- **Bật/tắt VI-EN**: `Ctrl + Shift + Space`, hoặc bấm nút **VI/EN** trên khay
  ngôn ngữ. (TSF `PreserveKey` cần một phím THẬT nên không dùng được tổ hợp
  chỉ-modifier ⌃⇧ như macOS.)
- **Icon khay**: badge pixel VI (xanh lá) / EN (xám), khớp phong cách menu bar
  macOS, tự đổi khi bật/tắt.

## Việc còn lại
- [ ] **Build & thử trên máy Windows thật** (mục quan trọng nhất): cài DLL, chọn
      bộ gõ, gõ thử; kiểm hành vi ở ô autocomplete (thanh địa chỉ trình duyệt) —
      đã dùng edit session ĐỒNG BỘ để chống gõ đôi, cần xác nhận thực tế.
- [ ] Clipboard history / chụp màn hình: tính năng tầng app đồng hành (không thuộc
      text service). Đang làm trong app Flutter `settings_ui` bằng plugin
      tray/hotkey/clipboard — xem README của `apps/settings_ui`.
