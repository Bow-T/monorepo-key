// text_codec.cpp — xem text_codec.h.

#include "text_codec.h"

namespace bowgo {

namespace {
constexpr char32_t kReplacement = 0xFFFD;
constexpr char32_t kMaxCodePoint = 0x10FFFF;

bool IsContinuation(unsigned char b) { return (b & 0xC0) == 0x80; }
}  // namespace

std::u32string Utf8ToU32(const std::string& utf8) {
    std::u32string out;
    out.reserve(utf8.size());
    size_t i = 0;
    const size_t n = utf8.size();
    while (i < n) {
        unsigned char b0 = static_cast<unsigned char>(utf8[i]);
        if (b0 < 0x80) {
            out.push_back(b0);
            i += 1;
        } else if ((b0 & 0xE0) == 0xC0 && i + 1 < n && IsContinuation(utf8[i + 1])) {
            char32_t cp = ((b0 & 0x1Fu) << 6) |
                          (static_cast<unsigned char>(utf8[i + 1]) & 0x3Fu);
            out.push_back(cp < 0x80 ? kReplacement : cp);  // chặn dạng overlong
            i += 2;
        } else if ((b0 & 0xF0) == 0xE0 && i + 2 < n && IsContinuation(utf8[i + 1]) &&
                   IsContinuation(utf8[i + 2])) {
            char32_t cp = ((b0 & 0x0Fu) << 12) |
                          ((static_cast<unsigned char>(utf8[i + 1]) & 0x3Fu) << 6) |
                          (static_cast<unsigned char>(utf8[i + 2]) & 0x3Fu);
            bool surrogate = cp >= 0xD800 && cp <= 0xDFFF;
            out.push_back((cp < 0x800 || surrogate) ? kReplacement : cp);
            i += 3;
        } else if ((b0 & 0xF8) == 0xF0 && i + 3 < n && IsContinuation(utf8[i + 1]) &&
                   IsContinuation(utf8[i + 2]) && IsContinuation(utf8[i + 3])) {
            char32_t cp = ((b0 & 0x07u) << 18) |
                          ((static_cast<unsigned char>(utf8[i + 1]) & 0x3Fu) << 12) |
                          ((static_cast<unsigned char>(utf8[i + 2]) & 0x3Fu) << 6) |
                          (static_cast<unsigned char>(utf8[i + 3]) & 0x3Fu);
            out.push_back((cp < 0x10000 || cp > kMaxCodePoint) ? kReplacement : cp);
            i += 4;
        } else {
            out.push_back(kReplacement);
            i += 1;
        }
    }
    return out;
}

std::string U32ToUtf8(const std::u32string& text) {
    std::string out;
    out.reserve(text.size() * 3);
    for (char32_t cp : text) {
        if (cp > kMaxCodePoint || (cp >= 0xD800 && cp <= 0xDFFF)) cp = kReplacement;
        if (cp < 0x80) {
            out.push_back(static_cast<char>(cp));
        } else if (cp < 0x800) {
            out.push_back(static_cast<char>(0xC0 | (cp >> 6)));
            out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
        } else if (cp < 0x10000) {
            out.push_back(static_cast<char>(0xE0 | (cp >> 12)));
            out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
            out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
        } else {
            out.push_back(static_cast<char>(0xF0 | (cp >> 18)));
            out.push_back(static_cast<char>(0x80 | ((cp >> 12) & 0x3F)));
            out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
            out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
        }
    }
    return out;
}

std::u16string U32ToUtf16(const std::u32string& text) {
    std::u16string out;
    out.reserve(text.size());
    for (char32_t cp : text) {
        if (cp > kMaxCodePoint || (cp >= 0xD800 && cp <= 0xDFFF)) cp = kReplacement;
        if (cp < 0x10000) {
            out.push_back(static_cast<char16_t>(cp));
        } else {
            cp -= 0x10000;
            out.push_back(static_cast<char16_t>(0xD800 | (cp >> 10)));
            out.push_back(static_cast<char16_t>(0xDC00 | (cp & 0x3FF)));
        }
    }
    return out;
}

}  // namespace bowgo
