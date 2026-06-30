// VietSyllableTests.swift
// Kiểm tra bộ luật âm tiết tiếng Việt (dùng cho tự khôi phục tiếng Anh + chính tả).

import Testing
@testable import VietEngine

@Suite("Âm tiết tiếng Việt hợp lệ")
struct VietSyllableValid {

    @Test("Âm tiết tiếng Việt thật -> hợp lệ")
    func realVietnamese() {
        let valid = ["tiêng", "viêt", "nha", "ban", "đương", "phô", "nghiêng",
                     "trương", "quyên", "không", "ngươi", "tha", "anh", "em",
                     "cha", "me", "khoe", "hoa", "quy", "giưa", "nguyên",
                     "buôc", "nươc", "thương", "đep", "xinh", "yêu", "uông"]
        for s in valid {
            #expect(VietSyllable.isValidToneless(s) == true, "phải hợp lệ: \(s)")
        }
    }

    @Test("Từ tiếng Anh KHÔNG có cấu trúc tiếng Việt -> không hợp lệ")
    func englishOrGarbage() {
        // Các từ này có cấu trúc bất khả thi trong tiếng Việt (phụ âm cuối lạ,
        // cụm phụ âm không hợp lệ, nguyên âm sai...) nên chắc chắn không phải VN.
        let invalid = ["terminal", "google", "test", "user", "file", "data",
                       "code", "english", "world", "blfoo", "xyz", "strong",
                       "fast", "click", "and"]
        for s in invalid {
            #expect(VietSyllable.isValidToneless(s) == false, "phải KHÔNG hợp lệ: \(s)")
        }
    }

    // LƯU Ý quan trọng: vài từ tiếng Anh TRÙNG cấu trúc âm tiết tiếng Việt
    // (vd "the" ~ "thế", "tho" ~ "thơ"). Luật chỉ-cấu-trúc (không từ điển) coi
    // chúng là HỢP LỆ tiếng Việt -> KHÔNG khôi phục (ưu tiên tiếng Việt, an toàn
    // hơn là phá từ tiếng Việt thật). Đây là giới hạn cố hữu của heuristic.
    @Test("Từ Anh trùng cấu trúc VN vẫn coi là hợp lệ (ưu tiên tiếng Việt)")
    func ambiguousPrefersVietnamese() {
        #expect(VietSyllable.isValidToneless("the") == true)   // ~ thế/thẻ
        #expect(VietSyllable.isValidToneless("can") == true)   // ~ căn/cân
        #expect(VietSyllable.isValidToneless("ban") == true)   // ~ bàn/bạn
    }

    @Test("Chuỗi hiển thị có dấu thanh -> bỏ thanh rồi kiểm tra")
    func displayForm() {
        #expect(VietSyllable.isValidDisplay("tiếng") == true)
        #expect(VietSyllable.isValidDisplay("Việt") == true)
        #expect(VietSyllable.isValidDisplay("được") == true)
        #expect(VietSyllable.isValidDisplay("nướng") == true)
        // "terminäl" kiểu biến dạng -> không hợp lệ
        #expect(VietSyllable.isValidDisplay("terminäl") == false)
    }

    @Test("stripTone giữ mũ/móc/trăng, bỏ thanh")
    func stripTone() {
        #expect(VietSyllable.stripTone("tiếng") == "tiêng")
        #expect(VietSyllable.stripTone("được") == "đươc")
        #expect(VietSyllable.stripTone("nước") == "nươc")
        #expect(VietSyllable.stripTone("ạ") == "a")
    }

    @Test("Chỉ phụ âm, không nguyên âm -> không hợp lệ")
    func consonantOnly() {
        #expect(VietSyllable.isValidToneless("ng") == false)
        #expect(VietSyllable.isValidToneless("tr") == false)
        #expect(VietSyllable.isValidToneless("b") == false)
    }
}
