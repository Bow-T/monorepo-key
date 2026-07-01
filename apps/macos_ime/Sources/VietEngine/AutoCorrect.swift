// AutoCorrect.swift
// -----------------
// TỰ SỬA LỖI GÕ NHANH — sửa từ vừa gõ xong (khi chốt từ bằng space/dấu câu).
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
//     về từ đúng. Muốn thêm từ mới -> chỉ cần thêm vào `AutoCorrectDictionary.words`.
//
// NGUYÊN TẮC AN TOÀN (để không phá văn bản người dùng):
//   • Chỉ sửa TỪ ĐÃ MANG DẤU TIẾNG VIỆT (có mũ/móc/trăng/thanh). Từ thuần ASCII
//     ("hello", "the", tên riêng) -> KHÔNG đụng.
//   • Chỉ sửa khi từ gốc SAI (không hợp lệ hoặc dấu đặt sai) và bản sửa HỢP LỆ.
//   • Giữ nguyên chữ HOA/thường của ký tự đầu (Giừo -> Giờ, giừo -> giờ).

import Foundation

/// Kết quả tự sửa một từ.
public struct AutoCorrectResult: Equatable {
    /// Từ sau khi sửa (đã đảm bảo khác từ gốc).
    public let corrected: String
    /// Vì sao sửa — hữu ích cho log/test.
    public enum Reason: Equatable {
        case toneReposition   // lớp 1: dời dấu thanh về đúng vị trí
        case dictionary       // lớp 2: khớp từ điển lỗi phổ biến
    }
    public let reason: Reason
}

public enum AutoCorrect {

    /// Thử tự sửa MỘT từ (chuỗi hiển thị, không chứa khoảng trắng).
    /// Trả `nil` nếu không cần/không nên sửa (giữ nguyên từ gốc).
    ///
    /// Đây là hàm THUẦN (không trạng thái) — engine gọi khi chốt từ, caller so sánh
    /// độ dài để biết cần xoá/gõ lại bao nhiêu ký tự.
    public static func correctWord(_ word: String) -> AutoCorrectResult? {
        correctWord(word, dictionary: AutoCorrectDictionary.shared)
    }

    /// Như trên nhưng dùng một `AutoCorrectDictionary` cụ thể (vd dựng từ cặp người
    /// dùng cấu hình trong settings). App gọi bản này để tôn trọng list custom.
    public static func correctWord(_ word: String,
                                   dictionary: AutoCorrectDictionary) -> AutoCorrectResult? {
        guard !word.isEmpty else { return nil }
        // An toàn: chỉ xét từ có dấu tiếng Việt. Bỏ qua ASCII thuần (Anh/tên riêng).
        guard containsVietnameseDiacritic(word) else { return nil }

        // Lớp 1: dời dấu thanh về đúng vị trí.
        if let repositioned = repositionTone(word), repositioned != word {
            return AutoCorrectResult(corrected: repositioned, reason: .toneReposition)
        }

        // Lớp 2: tra từ điển lỗi phổ biến (khớp không phân biệt hoa/thường).
        if let fixed = dictionary.lookup(word), fixed != word {
            return AutoCorrectResult(corrected: fixed, reason: .dictionary)
        }

        return nil
    }

    // MARK: - Lớp 1: dời dấu thanh về đúng vị trí

    /// Phân rã từ thành (chữ cái + mark) + (một dấu thanh), rồi dựng lại với dấu thanh
    /// đặt đúng vị trí theo quy tắc chính tả. Trả nil nếu không áp dụng được (không có
    /// dấu thanh, hoặc cấu trúc không phải âm tiết tiếng Việt hợp lệ).
    static func repositionTone(_ word: String) -> String? {
        // Chỉ xử lý một ÂM TIẾT (từ đơn). Từ ghép nhiều âm tiết hiếm khi gõ liền.
        guard let decomposed = Decomposed(word) else { return nil }
        // Không có dấu thanh -> không có gì để dời.
        guard decomposed.tone != .none else { return nil }
        // Cấu trúc phải là âm tiết tiếng Việt hợp lệ (đã bỏ thanh) — nếu không, dời
        // dấu cũng vô nghĩa, để lớp từ điển lo.
        guard VietSyllable.isValidToneless(decomposed.toneless) else { return nil }

        // Vị trí đúng theo luật chính tả.
        let target = ToneRules.targetIndex(letters: decomposed.letters)
        guard target >= 0 else { return nil }

        // Dựng lại: dấu thanh CHỈ đặt lên `target`.
        return decomposed.render(toneAt: target)
    }

    // MARK: - Helpers

    /// Chuỗi có chứa ký tự MANG DẤU tiếng Việt (dấu thanh HOẶC mũ/móc/trăng/đ) không?
    /// LƯU Ý: chữ thường a/e/o/u/i/y KHÔNG tính là "có dấu" — nếu tính, mọi từ ASCII
    /// (kể cả "hello", "bay") sẽ lọt qua guard an toàn và bị auto-correct đụng nhầm.
    static func containsVietnameseDiacritic(_ word: String) -> Bool {
        for ch in word.precomposedStringWithCanonicalMapping {
            if let parts = CharDecompose.map[ch] {
                if parts.tone != .none || parts.mark != .none { return true }
            }
        }
        return false
    }
}

// MARK: - Phân rã ký tự tiếng Việt về (base, mark, tone)

/// Bảng ngược của VietTable: ký tự dựng sẵn -> (chữ gốc, dấu biến âm, dấu thanh).
/// Vd 'ế' -> ('e', .circumflex, .acute); 'ự' -> ('u', .horn, .dot); 'đ' -> ('d', .dyet, .none).
enum CharDecompose {
    struct Parts: Sendable { let base: Character; let mark: Mark; let tone: Tone }

    /// Xây dựng bảng ngược từ chính VietTable để LUÔN đồng bộ với bảng gõ.
    static let map: [Character: Parts] = {
        var m: [Character: Parts] = [:]
        let bases: [(Character, [Mark])] = [
            ("a", [.none, .circumflex, .breve]),
            ("e", [.none, .circumflex]),
            ("i", [.none]),
            ("o", [.none, .circumflex, .horn]),
            ("u", [.none, .horn]),
            ("y", [.none]),
        ]
        let tones: [Tone] = [.none, .acute, .grave, .hook, .tilde, .dot]
        for (base, marks) in bases {
            for mark in marks {
                for tone in tones {
                    if let ch = VietTable.compose(base: base, mark: mark, tone: tone) {
                        // Chỉ ghi nếu chưa có (none-mark ưu tiên cho ký tự gốc a/e/...).
                        if m[ch] == nil {
                            m[ch] = Parts(base: base, mark: mark, tone: tone)
                        }
                        let up = Character(String(ch).uppercased())
                        if up != ch, m[up] == nil {
                            m[up] = Parts(base: Character(base.uppercased()), mark: mark, tone: tone)
                        }
                    }
                }
            }
        }
        // đ (không mang dấu thanh).
        if let d = VietTable.compose(base: "d", mark: .dyet, tone: .none) {
            m[d] = Parts(base: "d", mark: .dyet, tone: .none)
            m[Character(String(d).uppercased())] = Parts(base: "D", mark: .dyet, tone: .none)
        }
        return m
    }()
}

/// Một từ đã phân rã thành các chữ cái (base + mark) và MỘT dấu thanh chung.
/// (Âm tiết tiếng Việt chỉ mang tối đa một dấu thanh, ta gom nó ra.)
struct Decomposed {
    struct Letter { var base: Character; var mark: Mark }
    var letters: [Letter]
    var tone: Tone

    /// Chuỗi toneless (giữ mũ/móc/trăng, bỏ thanh) — để kiểm tra hợp lệ.
    var toneless: String {
        var s = ""
        for l in letters {
            s.append(VietTable.compose(base: l.base, mark: l.mark, tone: .none) ?? l.base)
        }
        return s
    }

    /// Phân rã một chuỗi hiển thị. Trả nil nếu có ký tự lạ (không phải chữ tiếng Việt).
    /// Nếu từ mang >1 dấu thanh (bất thường) -> lấy dấu thanh cuối cùng gặp được.
    init?(_ word: String) {
        var letters: [Letter] = []
        var tone: Tone = .none
        for ch in word.precomposedStringWithCanonicalMapping {
            if let parts = CharDecompose.map[ch] {
                letters.append(Letter(base: parts.base, mark: parts.mark))
                if parts.tone != .none { tone = parts.tone }
            } else if ch.isLetter, ch.isASCII {
                letters.append(Letter(base: ch, mark: .none))
            } else {
                return nil   // ký tự lạ -> không phân rã được
            }
        }
        guard !letters.isEmpty else { return nil }
        self.letters = letters
        self.tone = tone
    }

    /// Dựng lại chuỗi, đặt dấu thanh CHỈ lên chữ cái ở `toneAt`.
    func render(toneAt: Int) -> String {
        var out = ""
        for (i, l) in letters.enumerated() {
            let t: Tone = (i == toneAt) ? tone : .none
            out.append(VietTable.compose(base: l.base, mark: l.mark, tone: t) ?? l.base)
        }
        return out
    }
}

// MARK: - Quy tắc đặt dấu thanh (dùng chung, tách khỏi Engine để test độc lập)

/// Chọn vị trí đặt dấu thanh cho một dãy chữ cái — theo quy tắc chính tả "modern".
/// Đây là bản rút gọn, ĐỒNG NHẤT với `VietEngine.toneTargetIndex()`:
///   1. Nguyên âm mang dấu biến âm (â ê ô ơ ư ă) -> dấu lên đó.
///   2. Có phụ âm cuối -> nguyên âm cuối của cụm.
///   3. Cụm hở: 2 nguyên âm -> đầu, trừ "oa/oe/uy" -> sau; 3 nguyên âm -> giữa.
///   4. 1 nguyên âm -> chính nó.
enum ToneRules {
    static func targetIndex(letters: [Decomposed.Letter]) -> Int {
        // Luật 1: nguyên âm có dấu biến âm.
        if let marked = letters.lastIndex(where: {
            $0.mark == .circumflex || $0.mark == .breve || $0.mark == .horn
        }) {
            return marked
        }

        var vowelIdx = letters.indices.filter { isVowel(letters[$0].base) }

        // Gộp nguyên âm trùng liên tiếp (kéo dài) về một đại diện đầu.
        if vowelIdx.count >= 2 {
            var collapsed: [Int] = []
            for idx in vowelIdx {
                if let prev = collapsed.last,
                   lower(letters[prev].base) == lower(letters[idx].base) {
                    continue
                }
                collapsed.append(idx)
            }
            vowelIdx = collapsed
        }

        // "gi"/"qu": 'i'/'u' là bán phụ âm đầu, loại khỏi cụm nếu còn nguyên âm khác.
        if vowelIdx.count >= 2, let first = vowelIdx.first {
            let firstBase = lower(letters[first].base)
            let prevBase = first > 0 ? lower(letters[first - 1].base) : " "
            if (firstBase == "i" && prevBase == "g") || (firstBase == "u" && prevBase == "q") {
                vowelIdx.removeFirst()
            }
        }

        guard let start = vowelIdx.first, let end = vowelIdx.last else { return -1 }
        let count = vowelIdx.count

        let hasFinalConsonant = (end + 1 < letters.count) && !isVowel(letters[end + 1].base)
        if hasFinalConsonant { return end }

        switch count {
        case 1:
            return start
        case 2:
            let a = lower(letters[start].base)
            let b = lower(letters[end].base)
            let openTail = (a == "o" && (b == "a" || b == "e")) || (a == "u" && b == "y")
            return openTail ? end : start
        default:
            return vowelIdx[1]
        }
    }

    private static func isVowel(_ ch: Character) -> Bool {
        "aeiouy".contains(lower(ch))
    }
    private static func lower(_ ch: Character) -> Character {
        Character(ch.lowercased())
    }
}
