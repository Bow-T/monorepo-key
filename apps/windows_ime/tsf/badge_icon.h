// badge_icon.h
// ------------
// Vẽ icon badge VI/EN kiểu pixel-art cho khay ngôn ngữ (language bar) trên
// Windows — bản Win32/GDI của menuBarIcon(vietnamese:) bên macOS.
//   • VI: nền xanh lá grass (#5DA130), chữ "VI" pixel trắng.
//   • EN: nền xám, chữ "EN" pixel trắng.
// Cùng lưới glyph 5 hàng như bản macOS/settings UI để đồng nhất phong cách.
//
// ⚠️ Chỉ build trên Windows (GDI). Trả HICON; caller tự DestroyIcon khi xong.

#pragma once

#if defined(_WIN32)

#include <windows.h>

namespace bowgo {

// Tạo HICON badge (side x side px). vietnamese=true -> "VI" nền xanh; ngược lại
// "EN" nền xám. Trả nullptr nếu thất bại. Caller sở hữu HICON (DestroyIcon).
HICON CreateBadgeIcon(bool vietnamese, int side = 16);

}  // namespace bowgo

#endif  // _WIN32
