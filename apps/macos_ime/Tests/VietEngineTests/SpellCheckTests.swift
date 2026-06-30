// SpellCheckTests.swift
// Kiểm tra chính tả tiếng Việt (dựa trên luật âm tiết, không từ điển).

import Testing
@testable import VietEngine

@Suite("Kiểm tra chính tả tiếng Việt")
struct SpellCheck {

    @Test("Từ tiếng Việt đúng -> không sai")
    func correctWords() {
        for w in ["tiếng", "Việt", "được", "nướng", "đường", "phở", "nghiêng",
                  "thương", "quyển", "không", "người"] {
            #expect(VietSyllable.isMisspelled(w) == false, "đúng: \(w)")
        }
    }

    @Test("Từ có dấu nhưng cấu trúc sai -> sai chính tả")
    func wrongSpelling() {
        // các tổ hợp có dấu nhưng không phải âm tiết VN hợp lệ
        #expect(VietSyllable.isMisspelled("tểrn") == true)
        #expect(VietSyllable.isMisspelled("xyữz") == true)
        #expect(VietSyllable.isMisspelled("ăăă") == true)
    }

    @Test("Từ thuần ASCII -> KHÔNG đánh dấu sai (có thể tiếng Anh/tên riêng)")
    func asciiNotFlagged() {
        for w in ["terminal", "google", "Hello", "test123", "the", "abc"] {
            #expect(VietSyllable.isMisspelled(w) == false, "ascii bỏ qua: \(w)")
        }
    }

    @Test("Tìm các từ sai trong câu (cho UI gạch chân)")
    func findInSentence() {
        let text = "Tôi viết tểrn rồi"
        let bad = VietSyllable.misspelledWords(in: text)
        #expect(bad.count == 1)
        #expect(bad.first?.word == "tểrn")
    }

    @Test("Câu toàn từ đúng -> không có từ sai")
    func cleanSentence() {
        let bad = VietSyllable.misspelledWords(in: "Tôi yêu tiếng Việt")
        #expect(bad.isEmpty)
    }
}
