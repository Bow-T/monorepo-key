// text_codec.h
// ------------
// Chuyển mã UTF-8 / UTF-16 / UTF-32 dùng chung cho tầng Windows:
//   - settings.json là UTF-8 -> engine làm việc bằng char32_t (UTF-32).
//   - TSF/Win32 nhận chuỗi UTF-16 (wchar_t trên Windows).
// Thuần C++17, không phụ thuộc nền tảng — test được trên macOS/Linux.

#pragma once

#include <cstdint>
#include <string>

namespace bowgo {

// UTF-8 -> UTF-32. Byte hỏng được thay bằng U+FFFD (không throw).
std::u32string Utf8ToU32(const std::string& utf8);

// UTF-32 -> UTF-8. Code point ngoài phạm vi Unicode -> U+FFFD.
std::string U32ToUtf8(const std::u32string& text);

// UTF-32 -> UTF-16 (có surrogate pair cho code point ngoài BMP).
std::u16string U32ToUtf16(const std::u32string& text);

}  // namespace bowgo
