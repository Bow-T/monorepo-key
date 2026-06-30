// viet_syllable.h
// ---------------
// Kiểm tra âm tiết tiếng Việt hợp lệ — luật chính tả, KHÔNG cần từ điển.
// Bản C++ của VietSyllable.swift / viet_syllable.dart. Dùng cho tự khôi phục
// tiếng Anh + kiểm tra chính tả. Phải cho KẾT QUẢ GIỐNG bản Swift/Dart.

#pragma once

#include <optional>
#include <string>
#include <vector>

namespace bowkey {

class VietSyllable {
public:
    // Âm tiết (đã bỏ dấu thanh, giữ mũ/móc/trăng) có hợp lệ cấu trúc không?
    static bool IsValidToneless(const std::u32string& rawSyllable);

    // Bỏ dấu thanh, giữ mũ/móc/trăng: "tiếng" -> "tiêng".
    static std::u32string StripTone(const std::u32string& display);

    // Chuỗi hiển thị (có dấu) có phải âm tiết hợp lệ không?
    static bool IsValidDisplay(const std::u32string& display);

    // Một từ có sai chính tả không? (có dấu VN nhưng cấu trúc không hợp lệ)
    static bool IsMisspelled(const std::u32string& word);

    // Một từ sai chính tả tìm thấy trong văn bản: (từ, vị trí bắt đầu, kết thúc).
    struct MisspelledWord {
        std::u32string word;
        size_t start;
        size_t end;
    };
    static std::vector<MisspelledWord> MisspelledWords(const std::u32string& text);
};

// Tự khôi phục tiếng Anh (thuần, không trạng thái) — đặt cùng module âm tiết vì
// dùng chung IsValidDisplay. Trả rawKeys để khôi phục, hoặc nullopt nếu giữ.
//   rawKeys: phím thô ASCII của cả từ (vd "terminal").
//   display: chuỗi đang hiển thị (có thể đã biến dạng, vd "terminäl").
std::optional<std::u32string> EnglishRestoreKeys(const std::u32string& rawKeys,
                                                 const std::u32string& display);

}  // namespace bowkey
