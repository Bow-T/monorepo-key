# windows_ime — Bộ gõ Bow Go cho Windows (C++/TSF)

Bộ gõ trên Windows là một **Text Services Framework (TSF)** text service viết bằng
**C++/Win32**. Đây là tầng Windows cho phép chen vào luồng nhập liệu của **mọi ứng
dụng** — Flutter/Dart không với tới được tầng này.

```
apps/windows_ime/
├── engine/                  # ENGINE C++ thuần — ĐÃ KIỂM CHỨNG (đa nền)
│   ├── viet_model.h         # Tone / Mark / InputMethod / ToneStyle
│   ├── viet_table.h/.cpp    # bảng tra (gốc+mark+tone) -> char32_t Unicode
│   ├── engine.h/.cpp        # bộ não: nhận phím -> trả chuỗi tiếng Việt
│   └── test_engine.cpp      # 81 ca test chuẩn (port từ VietEngineTests.swift)
├── tsf/                     # TEXT SERVICE TSF — ⚠️ SKELETON, chỉ build trên Windows
│   ├── BowGoTextService.h/.cpp # ITfTextInputProcessor + key sink -> engine
│   └── dll_main.cpp         # COM in-proc server (DllGetClassObject, đăng ký)
└── CMakeLists.txt           # build engine+test (đa nền) và DLL TSF (Windows)
```

## Trạng thái

| Phần | Trạng thái |
|---|---|
| Engine C++ (Telex/VNI, đặt dấu, backspace) | ✅ **81/81 ca test xanh** (khớp Dart/Swift) |
| Cầu nối phím → engine (`HandleKey`) | ✅ Viết xong (bám `EventTapController.swift`) |
| TSF text service (COM/DLL skeleton) | 🟨 Khung có, **chưa hoàn thiện & chưa thử** |
| Ghi văn bản qua `ITfEditSession` (`ReplaceText`) | ⬜ TODO (cần Windows) |
| Đăng ký với TSF (profiles/registry) | ⬜ TODO (cần Windows) |
| Dịch phím theo layout thật (`ToUnicodeEx`) | ⬜ TODO (hiện tối giản ASCII) |

> ⚠️ **Phần TSF CHƯA build/chạy được trên macOS** (cần Windows SDK + `msctf.h` +
> Visual Studio). Mọi code trong `tsf/` mới chỉ là khung cấu trúc, **chưa kiểm chứng**.
> Phần **đã kiểm chứng** là `engine/` — chạy được mọi nền (xem dưới).

## Engine — chạy & test (mọi nền, gồm macOS)

Không cần Windows. Engine là spec chung, phải vượt **cùng bộ ca test** với bản
Dart (`packages/viet_engine`) và Swift (`apps/macos_ime`).

```bash
cd apps/windows_ime
cmake -S . -B build && cmake --build build
./build/bowgo_engine_tests          # in "81 pass, 0 fail."
# hoặc: cd build && ctest
```

Hoặc biên dịch trực tiếp bằng clang/g++:

```bash
c++ -std=c++17 engine/engine.cpp engine/viet_table.cpp engine/test_engine.cpp -o test_engine
./test_engine
```

## Build TSF DLL (chỉ trên Windows)

```powershell
cmake -S . -B build
cmake --build build --config Release     # tạo BowGoTSF.dll (khi đã hoàn thiện)
```

## Việc còn lại để bộ gõ chạy thật trên Windows
- [ ] Hiện thực `ReplaceText` qua `ITfEditSession` (xoá N ký tự + ghi chuỗi mới, u32→UTF-16)
- [ ] Gắn sink trong `Activate` (`AdviseKeyEventSink`, `AdviseSink`) và gỡ ở `Deactivate`
- [ ] Đăng ký text service (`ITfInputProcessorProfiles`, `ITfCategoryMgr`) + registry trong `DllRegisterServer`
- [ ] Sinh CLSID/GUID thật (guidgen) thay các GUID giữ chỗ trong `BowGoTextService.cpp`
- [ ] Dịch phím theo layout thật bằng `ToUnicodeEx` (tương tự UCKeyTranslate bên macOS)
- [ ] Thử trên máy Windows: cài DLL, chọn bộ gõ, gõ thử `tieengs → tiếng`
