# macos_ime — Bộ gõ Bow Key cho macOS (Swift)

Bộ gõ macOS dùng **CGEvent tap** để chặn phím toàn hệ thống, đưa qua engine tiếng Việt,
rồi "gõ thay" kết quả vào ứng dụng đang focus. Viết bằng **Swift + AppKit**, chạy dạng
app menu-bar (accessory, ẩn Dock).

```
apps/macos_ime/
├── Package.swift            # build & test bằng terminal (Swift Package Manager)
├── Sources/
│   └── VietEngine/          # ENGINE Swift — logic gõ tiếng Việt, KHÔNG đụng macOS
│       ├── VietModel.swift  # mô hình: Tone (thanh), Mark (mũ/móc/trăng), InputMethod
│       ├── VietTable.swift  # bảng tra (chữ gốc + mark + tone) -> ký tự Unicode
│       └── Engine.swift     # bộ não: nhận phím -> trả chữ tiếng Việt
├── App/                     # APP macOS — CGEvent tap + menu bar
│   ├── main.swift           # điểm vào (app accessory, ẩn Dock)
│   ├── AppDelegate.swift    # vòng đời + menu bar + health check
│   ├── EventTapController.swift # CGEvent tap: bắt phím -> engine -> gõ thay
│   ├── KeyOutput.swift      # gõ thay ký tự (backspace + post Unicode)
│   ├── KeyCodeMap.swift     # keyCode macOS -> Character
│   └── Permissions.swift    # xin/kiểm tra quyền Accessibility + Input Monitoring
├── Tests/VietEngineTests/   # test: gõ "tieengs" có ra "tiếng" không?
├── Assets/                  # NGUỒN ICON (vector) — sửa ở đây rồi render lại
│   ├── app-icon.svg         # logo app (cung + chìa khoá) -> AppIcon.icns
│   └── menubar-icon.svg     # icon menu bar (template đen/trong suốt)
└── scripts/
    ├── build-app.sh         # đóng gói .app + code sign
    └── build-icons.sh       # SVG -> PNG -> AppIcon.icns + menubar.png
```

> **Engine Swift ở đây và engine Dart ở [`packages/viet_engine`](../../packages/viet_engine)
> phải cho ra kết quả GIỐNG HỆT** — cùng một bộ ca test chuẩn (golden cases).

## Chạy thử engine (không cần quyền gì)

```bash
cd apps/macos_ime
swift test          # 25 test — KHÔNG cần Xcode, KHÔNG cần quyền macOS
```

## Chạy app thật trên máy

```bash
cd apps/macos_ime
bash scripts/build-app.sh        # build + ký -> build/BowKey.app
open build/BowKey.app
```

Lần đầu chạy, app sẽ xin **2 quyền** (bắt buộc của mọi bộ gõ macOS):

1. **Accessibility** (Trợ năng) — để gõ thay ký tự vào app khác.
2. **Input Monitoring** (Giám sát đầu vào) — để đọc phím bạn gõ.

→ Mở **System Settings → Privacy & Security**, tìm mục **Bow Key** ở cả hai phần trên,
bật lên, rồi **mở lại app**. Khi icon menu bar hiện **VN** là đã gõ được.
Bấm icon để bật/tắt, đổi Telex/VNI, hoặc thoát.

> Mỗi lần `build-app.sh` chạy lại, nếu macOS quên quyền thì bật lại trong System Settings.
> Ký Developer ID + notarize (giai đoạn sau) sẽ khắc phục việc này khi phân phối.

## Lộ trình macOS

- [x] App menu-bar (NSStatusItem), accessory (ẩn Dock)
- [x] CGEvent tap: bắt phím, gọi engine, "gõ thay" ký tự
- [x] Xin & kiểm tra quyền Accessibility + Input Monitoring
- [x] Cơ chế phục hồi tap khi macOS tự tắt (health check 5s)
- [x] Đóng gói .app + code sign (ad-hoc)
- [x] Bật/tắt + đổi Telex/VNI qua menu
- [ ] Dịch keyCode theo layout thật (UCKeyTranslate) — đúng cả Dvorak/Colemak
- [ ] Smart Switch: nhớ bật/tắt theo từng app
- [ ] Developer ID + notarize để phân phối
