// auto_correct.h
// --------------
// TỰ SỬA LỖI GÕ NHANH — bản C++ của AutoCorrect.swift / AutoCorrectDictionary.swift.
// Sửa từ vừa gõ xong (khi chốt từ bằng space/dấu câu).
//
// Ví dụ người gõ nhanh hay sai:
//   "giừo"  -> "giờ"    (dấu huyền rơi nhầm vào 'ư' thay vì 'ơ' + sai chữ)
//   "nhièu" -> "nhiều"  (dấu huyền rơi vào 'e' thay vì 'ê')
//   "hoÀ"   -> "hoà"    (dấu đặt sai vị trí trong cụm nguyên âm)
//
// CHIẾN LƯỢC 2 LỚP (chạy theo thứ tự, dừng ở lớp đầu tiên sửa được):
//
//   Lớp 1 — SỬA VỊ TRÍ DẤU THANH (không cần từ điển).
//     Phân rã từ về (các chữ cái + dấu biến âm) + (1 dấu thanh) rồi ĐẶT LẠI dấu
//     thanh đúng vị trí theo quy tắc chính tả. Nếu từ gốc hợp lệ nhưng đặt dấu sai
//     chỗ, lớp này sửa ngay mà không cần biết "từ đúng" là gì.
//
//   Lớp 2 — TỪ ĐIỂN TĨNH (lỗi phổ biến -> từ đúng).
//     Bảng ánh xạ các lỗi gõ nhanh hay gặp (thiếu/thừa/sai ký tự) sang từ đúng.
//     Bảng này TỰ SINH: cho một danh sách từ tiếng Việt phổ biến ("trend"), ta sinh
//     các biến thể-lỗi thường gặp (đảo dấu-nguyên-âm, thiếu dấu mũ...) rồi map ngược
//     về từ đúng. Muốn thêm từ mới -> chỉ cần thêm vào `AutoCorrectDictionary::Words`.
//
// NGUYÊN TẮC AN TOÀN (để không phá văn bản người dùng):
//   • Chỉ sửa TỪ ĐÃ MANG DẤU TIẾNG VIỆT (có mũ/móc/trăng/thanh). Từ thuần ASCII
//     ("hello", "the", tên riêng) -> KHÔNG đụng.
//   • Chỉ sửa khi từ gốc SAI (không hợp lệ hoặc dấu đặt sai) và bản sửa HỢP LỆ.
//   • Giữ nguyên chữ HOA/thường của ký tự đầu (Giừo -> Giờ, giừo -> giờ).
//
// Kiểu chuỗi Việt dùng std::u32string (UTF-32) để mỗi nguyên âm có dấu là MỘT
// code point (khớp với phần còn lại của engine C++).

#pragma once

#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

#include "viet_model.h"

namespace bowgo {

// Kết quả tự sửa một từ.
struct AutoCorrectResult {
    // Vì sao sửa — hữu ích cho log/test.
    enum class Reason {
        ToneReposition,  // lớp 1: dời dấu thanh về đúng vị trí
        Dictionary,      // lớp 2: khớp từ điển lỗi phổ biến
    };

    // Từ sau khi sửa (đã đảm bảo khác từ gốc).
    std::u32string corrected;
    Reason reason;

    bool operator==(const AutoCorrectResult& o) const {
        return corrected == o.corrected && reason == o.reason;
    }
};

// Một từ đã phân rã thành các chữ cái (base + mark) và MỘT dấu thanh chung.
// (Âm tiết tiếng Việt chỉ mang tối đa một dấu thanh, ta gom nó ra.)
struct Decomposed {
    struct Letter {
        char32_t base;
        Mark mark;
    };
    std::vector<Letter> letters;
    Tone tone;

    // Chuỗi toneless (giữ mũ/móc/trăng, bỏ thanh) — để kiểm tra hợp lệ.
    std::u32string Toneless() const;

    // Dựng lại chuỗi, đặt dấu thanh CHỈ lên chữ cái ở `tone_at`.
    std::u32string Render(int tone_at) const;

    // Phân rã một chuỗi hiển thị. Trả nullopt nếu có ký tự lạ (không phải chữ
    // tiếng Việt). Nếu từ mang >1 dấu thanh (bất thường) -> lấy dấu thanh cuối cùng.
    static std::optional<Decomposed> Parse(const std::u32string& word);
};

// Quy tắc đặt dấu thanh (dùng chung, tách khỏi Engine để test độc lập).
// Chọn vị trí đặt dấu thanh cho một dãy chữ cái — theo quy tắc chính tả "modern",
// ĐỒNG NHẤT với VietEngine::ToneTargetIndex() (nhánh Modern).
struct ToneRules {
    static int TargetIndex(const std::vector<Decomposed::Letter>& letters);
};

// TỪ ĐIỂN TĨNH cho tự-sửa lỗi gõ nhanh — dựng sẵn, chạy offline.
class AutoCorrectDictionary {
public:
    // Bản dùng chung (xây một lần, tra nhiều lần).
    static const AutoCorrectDictionary& Shared();

    // DANH SÁCH TỪ ĐÚNG phổ biến ("trend"). Mỗi từ tự sinh biến thể-lỗi.
    static const std::vector<std::u32string>& Words();

    // OVERRIDES thủ công — cặp (lỗi -> đúng) đặc thù, ưu tiên cao hơn bản sinh tự động.
    static const std::vector<std::pair<std::u32string, std::u32string>>& Overrides();

    AutoCorrectDictionary(
        const std::vector<std::u32string>& words,
        const std::vector<std::pair<std::u32string, std::u32string>>& overrides);

    // Tra từ đúng cho một từ (không phân biệt hoa/thường), giữ kiểu hoa của bản gốc.
    // Trả nullopt nếu không có trong từ điển.
    std::optional<std::u32string> Lookup(const std::u32string& word) const;

    // Số cặp lỗi->đúng đã dựng (để test/thống kê).
    size_t Count() const { return table_.size(); }

private:
    // variant (đã lowercase) -> từ đúng (lowercase).
    std::unordered_map<std::u32string, std::u32string> table_;
};

// Hàm public chính — thử tự sửa MỘT từ (chuỗi hiển thị, không chứa khoảng trắng).
// Trả nullopt nếu không cần/không nên sửa (giữ nguyên từ gốc).
class AutoCorrect {
public:
    static std::optional<AutoCorrectResult> CorrectWord(const std::u32string& word);

    // Lớp 1: dời dấu thanh về đúng vị trí. Trả nullopt nếu không áp dụng được.
    // (Trả về CHÍNH từ gốc nếu dấu đã đúng — caller so sánh để biết có đổi không.)
    static std::optional<std::u32string> RepositionTone(const std::u32string& word);

    // Từ có mang dấu tiếng Việt không? (mũ/móc/trăng/thanh precomposed)
    static bool ContainsVietnameseDiacritic(const std::u32string& word);
};

}  // namespace bowgo
