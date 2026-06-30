// text_converter.h
// ----------------
// Công cụ chuyển mã / biến đổi văn bản tiếng Việt — bản C++ của TextConverter.swift.
// Bỏ dấu, hoa/thường, TCVN3/VNI-Windows. (NFC↔NFD bỏ qua ở C++ — cần lib normalize;
// vẫn có ở bản Swift.) Phải khớp kết quả với bản Swift/Dart trên cùng ca test.

#pragma once

#include <string>

namespace bowkey {

enum class CodeTable { Unicode, Tcvn3, VniWindows };
enum class LetterCase { AllUpper, AllLower, CapitalizeFirst, CapitalizeWords };

class TextConverter {
public:
    // Bỏ toàn bộ dấu tiếng Việt: "Tiếng Việt" -> "Tieng Viet".
    static std::u32string RemoveDiacritics(const std::u32string& text);

    // Đổi hoa/thường, giữ dấu tiếng Việt.
    static std::u32string ChangeCase(const std::u32string& text, LetterCase mode);

    // Chuyển giữa hai bảng mã (đi qua trung gian Unicode dựng sẵn).
    static std::u32string Convert(const std::u32string& text, CodeTable from, CodeTable to);
};

}  // namespace bowkey
