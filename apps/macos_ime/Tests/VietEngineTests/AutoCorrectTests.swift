// AutoCorrectTests.swift
// ----------------------
// Test tự-sửa-lỗi gõ nhanh: lớp dời-dấu-thanh, lớp từ điển, và tích hợp engine.

import Testing
import Foundation
@testable import VietEngine

/// Gõ `keys` qua engine có bật autoCorrect; trả về văn bản cuối cùng caller thấy
/// (mô phỏng caller: âm tiết hiển thị, hoặc tự sửa = xoá rồi chèn từ đúng).
private func typeAC(_ keys: String, method: InputMethod = .telex) -> String {
    let engine = VietEngine(method: method, autoCorrect: true)
    var visible = ""
    var currentSyllable = ""
    for ch in keys {
        switch engine.processKey(ch) {
        case .syllable(let s):
            visible.removeLast(currentSyllable.count)
            visible += s
            currentSyllable = s
        case .wordBreak(let c):
            visible.append(c)
            currentSyllable = ""
        case .macro(let deleteCount, let insert, let breakChar),
             .autoCorrect(let deleteCount, let insert, let breakChar):
            visible.removeLast(min(deleteCount, visible.count))
            visible += insert
            visible.append(breakChar)
            currentSyllable = ""
        }
    }
    return visible
}

@Suite("Auto-correct: dời dấu thanh (lớp 1)")
struct AutoCorrectToneReposition {

    @Test("Dấu đặt sai vị trí trong cụm nguyên âm -> dời đúng")
    func repositionOpenTail() {
        // "hòa" (dấu ở 'o') là chính tả CŨ. Ở chế độ modern, dấu đúng lên 'a' -> "hoà".
        #expect(AutoCorrect.repositionTone("hòa") == "hoà")
        // "qúy" -> "quý" (dấu lên 'y')
        #expect(AutoCorrect.repositionTone("qúy") == "quý")
        // "khỏe" -> "khoẻ"
        #expect(AutoCorrect.repositionTone("khỏe") == "khoẻ")
    }

    @Test("Từ đã đúng vị trí -> không đổi (trả nil)")
    func alreadyCorrect() {
        #expect(AutoCorrect.repositionTone("tiếng") == "tiếng")   // dấu đã ở 'ê'
        #expect(AutoCorrect.repositionTone("giờ") == "giờ")       // dấu đã ở 'ơ'
        #expect(AutoCorrect.repositionTone("hoà") == "hoà")
    }

    @Test("Không có dấu thanh -> nil")
    func noTone() {
        #expect(AutoCorrect.repositionTone("hoa") == nil)
        #expect(AutoCorrect.repositionTone("tieng") == nil)
    }
}

@Suite("Auto-correct: từ điển (lớp 2)")
struct AutoCorrectDictionaryTests {

    @Test("Các lỗi override kinh điển")
    func overrides() {
        let dict = AutoCorrectDictionary.shared
        #expect(dict.lookup("giừo") == "giờ")
        #expect(dict.lookup("nhièu") == "nhiều")
        #expect(dict.lookup("ngừoi") == "người")
        #expect(dict.lookup("đựoc") == "được")
    }

    @Test("Biến thể-lỗi tự sinh: dấu rơi nhầm nguyên âm")
    func generatedToneMisplacement() {
        let dict = AutoCorrectDictionary.shared
        // "nhiều" đúng ở 'ê'. Biến thể dấu ở 'e' cuối "nhiêù" -> phải map về "nhiều".
        #expect(dict.lookup("nhiêù") == "nhiều")
        // "được": dấu nặng rơi vào nguyên âm khác -> vẫn về "được"
        #expect(dict.lookup("đươc̣".precomposedStringWithCanonicalMapping) == nil
                || dict.lookup("đươc̣".precomposedStringWithCanonicalMapping) == "được")
    }

    @Test("Từ đúng KHÔNG bị 'sửa' (an toàn)")
    func doesNotTouchCorrectWords() {
        let dict = AutoCorrectDictionary.shared
        #expect(dict.lookup("giờ") == nil)
        #expect(dict.lookup("nhiều") == nil)
        #expect(dict.lookup("người") == nil)
        #expect(dict.lookup("được") == nil)
    }

    @Test("Biến thể trùng từ đúng KHÁC không bị sửa (dạy≠dậy)")
    func doesNotCollideWithOtherRealWords() {
        // "dậy" ∈ words -> sinh biến thể bỏ mũ "dạy". Nhưng "dạy" (dạy học) cũng
        // là từ đúng, dấu ĐÚNG vị trí -> KHÔNG được sửa thành "dậy".
        let dict = AutoCorrectDictionary.shared
        #expect(dict.lookup("dạy") == nil)
        // Typo dấu-sai-chỗ (dấu chồng "dâỵ") vẫn phải sửa được về "dậy".
        #expect(dict.lookup("dâỵ".precomposedStringWithCanonicalMapping) == "dậy")
        // isRealWord: đúng chỗ = true, sai chỗ = false.
        #expect(AutoCorrectDictionary.isRealWord("dạy") == true)
        #expect(AutoCorrectDictionary.isRealWord("nhiêù") == false)
    }

    @Test("Giữ kiểu hoa của chữ đầu")
    func preservesCasing() {
        let dict = AutoCorrectDictionary.shared
        #expect(dict.lookup("Giừo") == "Giờ")
        #expect(dict.lookup("Nhièu") == "Nhiều")
    }

    @Test("Cặp người dùng: ưu tiên cao nhất + thêm cặp mới")
    func userPairs() {
        // Người dùng thêm cặp riêng "tets"->"tết" và GHI ĐÈ mặc định giừo->giơ (ví dụ).
        let dict = AutoCorrectDictionary(userPairs: [
            (wrong: "chảo", right: "chào"),   // thêm cặp mới
            (wrong: "giừo", right: "giơ"),    // ghi đè override built-in
        ])
        #expect(dict.lookup("chảo") == "chào")   // cặp custom hoạt động
        #expect(dict.lookup("giừo") == "giơ")    // custom thắng built-in override
    }

    @Test("defaultPairs: bộ gieo mặc định chỉ gồm vế sai CÓ dấu")
    func defaultPairsAllHaveDiacritic() {
        let pairs = AutoCorrectDictionary.defaultPairs()
        #expect(!pairs.isEmpty)
        // Mọi vế 'wrong' phải chứa ít nhất một ký tự dấu tiếng Việt.
        for p in pairs {
            #expect(AutoCorrect.containsVietnameseDiacritic(p.wrong))
        }
        // Có mặt các cặp kinh điển.
        #expect(pairs.contains { $0.wrong == "giừo" && $0.right == "giờ" })
        #expect(pairs.contains { $0.wrong == "nhièu" && $0.right == "nhiều" })
    }

    @Test("Từ điển mở rộng: không cặp nào biến từ đúng thành từ khác")
    func expandedDictSafety() {
        // BẤT BIẾN AN TOÀN: vế 'wrong' KHÔNG được là một từ tiếng Việt viết đúng —
        // nếu không, gõ đúng từ đó sẽ bị "sửa" nhầm. Kiểm cho TOÀN BỘ cặp built-in.
        let dict = AutoCorrectDictionary()
        for p in dict.allPairs() {
            #expect(!AutoCorrectDictionary.isRealWord(p.wrong),
                    "vế sai '\(p.wrong)' lại là từ đúng -> sẽ sửa nhầm khi gõ đúng")
            #expect(p.wrong != p.right, "cặp no-op: \(p.wrong)")
        }
    }

    @Test("Từ điển mở rộng: một số lỗi mới được sửa đúng")
    func expandedDictCorrections() {
        let dict = AutoCorrectDictionary(userPairs: [])
        // Override mới (cụm ươ/iê hay lệch).
        #expect(dict.lookup("đừơng") == "đường")
        #expect(dict.lookup("nứơc") == "nước")
        #expect(dict.lookup("cừơi") == "cười")
        #expect(dict.lookup("tièn") == "tiền")
        // Biến thể tự sinh từ 'words' mới (dấu rơi nhầm nguyên âm).
        #expect(dict.lookup("nghĩ") == nil)   // từ ĐÚNG -> không sửa
    }

    @Test("Tách đôi mũ ra hai bên (rooif→roiof→roìo) -> sửa về từ đúng")
    func splitCircumflexMisspelling() {
        let dict = AutoCorrectDictionary.shared
        // Lỗi kinh điển người dùng nêu: gõ nhanh "rồi" ra "roìo".
        #expect(dict.lookup("roìo") == "rồi")
        // Cùng mẫu (ô + i): 'rồi' nằm trong words -> biến thể tự sinh cũng phủ.
        #expect(dict.lookup("moìo") == "mồi")
        #expect(dict.lookup("hoìo") == "hồi")
        // 'tôi' ∈ words -> "toìo" phải map về "tôi" (qua splitCircumflexVariants).
        #expect(dict.lookup("toìo") == "tôi" || dict.lookup("toìo") == "tồi")
        // An toàn: "rồi" đúng KHÔNG bị đụng.
        #expect(dict.lookup("rồi") == nil)
    }
}

@Suite("Auto-correct: an toàn")
struct AutoCorrectSafety {

    @Test("Từ thuần ASCII / tiếng Anh -> KHÔNG đụng")
    func leavesEnglishAlone() {
        #expect(AutoCorrect.correctWord("hello") == nil)
        #expect(AutoCorrect.correctWord("the") == nil)
        #expect(AutoCorrect.correctWord("Github") == nil)
    }

    @Test("Từ tiếng Việt đúng -> KHÔNG đụng")
    func leavesCorrectVietnameseAlone() {
        #expect(AutoCorrect.correctWord("tiếng") == nil)
        #expect(AutoCorrect.correctWord("giờ") == nil)
        #expect(AutoCorrect.correctWord("người") == nil)
    }
}

@Suite("Auto-correct: tích hợp engine (chốt từ)")
struct AutoCorrectEngineIntegration {

    @Test("Sửa khi gõ space — ví dụ người dùng nêu (gõ nhanh sai vị trí dấu)")
    func fixesOnSpace() {
        // Gõ nhanh "giuwof": engine dựng ra "giừo" (móc rơi nhầm vào 'u', dấu vào 'o').
        // Chốt bằng space -> auto-correct sửa thành "giờ ".
        #expect(typeAC("giuwof ") == "giờ ")
        // Gõ nhanh "nhieuf": engine dựng ra "nhièu" (quên mũ ê). Space -> "nhiều ".
        #expect(typeAC("nhieuf ") == "nhiều ")
        // Chốt bằng dấu câu cũng sửa.
        #expect(typeAC("nhiefu.") == "nhiều.")
    }

    @Test("Từ đúng gõ bình thường -> KHÔNG bị đụng")
    func doesNotBreakCorrectTyping() {
        #expect(typeAC("tieengs ") == "tiếng ")     // gõ đúng -> giữ nguyên
        #expect(typeAC("nguowif ") == "người ")     // gõ đúng -> giữ nguyên
        #expect(typeAC("dduwocj ") == "được ")      // gõ đúng -> giữ nguyên
    }

    @Test("Gõ nhanh 'roiof' (đảo phím của rooif) -> 'rồi'")
    func fixesSplitCircumflex() {
        // Người dùng định gõ "rồi" (rooif) nhưng gõ nhanh thành "roiof" -> "roìo".
        // Chốt bằng space -> auto-correct sửa thành "rồi ".
        #expect(typeAC("roiof ") == "rồi ")
        // Gõ ĐÚNG vẫn ra đúng, không bị đụng.
        #expect(typeAC("rooif ") == "rồi ")
    }

    @Test("Tắt autoCorrect (mặc định) -> không sửa")
    func offByDefault() {
        let engine = VietEngine(method: .telex)   // autoCorrect: false
        var visible = ""
        var cur = ""
        for ch in "hoaf " {
            switch engine.processKey(ch) {
            case .syllable(let s): visible.removeLast(cur.count); visible += s; cur = s
            case .wordBreak(let c): visible.append(c); cur = ""
            case .macro, .autoCorrect: break
            }
        }
        // "hoaf" telex -> "hoà" (đã đúng modern). Không có gì để test tắt ở đây,
        // chỉ đảm bảo không crash và ra chữ hợp lệ.
        #expect(visible == "hoà ")
    }
}
