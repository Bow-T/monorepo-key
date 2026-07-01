// AutoCorrectDictionary.swift
// ---------------------------
// TỪ ĐIỂN TĨNH cho tự-sửa lỗi gõ nhanh — dựng sẵn trong app, chạy offline.
//
// Cách hoạt động:
//   • `words` = danh sách TỪ ĐÚNG tiếng Việt phổ biến (phần "trend" — muốn thêm từ
//     mới chỉ cần bổ sung vào đây).
//   • Với mỗi từ đúng, ta TỰ SINH các biến thể-lỗi gõ nhanh hay gặp (đảo thứ tự chữ
//     trong cụm nguyên âm, thiếu dấu mũ, thừa/thiếu chữ...) rồi map ngược variant->đúng.
//   • `overrides` = các cặp (lỗi -> đúng) đặc thù không sinh tự động được, ưu tiên cao.
//
// Vì sao tự sinh thay vì liệt kê tay? Vì cùng một loại lỗi ("dấu rơi nhầm nguyên âm")
// lặp lại trên hàng nghìn từ. Sinh tự động từ từ-đúng giúp thêm 1 từ là phủ nhiều lỗi.

import Foundation

public final class AutoCorrectDictionary: Sendable {

    /// Bản dùng chung (xây một lần, tra nhiều lần).
    public static let shared = AutoCorrectDictionary()

    /// variant (đã lowercase, NFC) -> từ đúng (lowercase).
    private let table: [String: String]

    /// - Parameters:
    ///   - words: danh sách từ đúng để TỰ SINH biến thể-lỗi (bộ sức mạnh ngầm).
    ///   - overrides: cặp lỗi->đúng thủ công built-in.
    ///   - userPairs: cặp (sai -> đúng) do NGƯỜI DÙNG cấu hình (từ settings.json).
    ///     Ưu tiên CAO NHẤT — ghi đè cả overrides lẫn biến thể tự sinh. Người dùng
    ///     xoá một cặp mặc định bằng cách bỏ nó khỏi danh sách này (xem SettingsStore).
    public init(words: [String] = AutoCorrectDictionary.words,
                overrides: [String: String] = AutoCorrectDictionary.overrides,
                userPairs: [(wrong: String, right: String)] = []) {
        var t: [String: String] = [:]

        // 1) Sinh biến thể-lỗi từ danh sách từ đúng.
        for correct in words {
            let key = correct.lowercased().precomposedStringWithCanonicalMapping
            for variant in AutoCorrectDictionary.misspellings(of: key) {
                // Không ghi đè nếu variant TRÙNG một từ đúng khác (tránh sửa nhầm từ thật).
                guard variant != key else { continue }
                if t[variant] == nil { t[variant] = key }
            }
        }
        // Xoá các key mà bản thân nó cũng là một từ đúng (an toàn: đừng "sửa" từ đúng).
        let correctSet = Set(words.map { $0.lowercased().precomposedStringWithCanonicalMapping })
        for k in Array(t.keys) where correctSet.contains(k) { t.removeValue(forKey: k) }

        // 2) Overrides thủ công built-in (ghi đè bản sinh tự động).
        for (wrong, right) in overrides {
            t[wrong.lowercased().precomposedStringWithCanonicalMapping] =
                right.lowercased().precomposedStringWithCanonicalMapping
        }

        // 3) Cặp do NGƯỜI DÙNG cấu hình — ưu tiên cao nhất. Bỏ qua cặp rỗng/trùng gốc.
        for (wrong, right) in userPairs {
            let w = wrong.lowercased().precomposedStringWithCanonicalMapping
            let r = right.lowercased().precomposedStringWithCanonicalMapping
            guard !w.isEmpty, !r.isEmpty, w != r else { continue }
            t[w] = r
        }

        self.table = t
    }

    /// Tra từ đúng cho một từ (không phân biệt hoa/thường), giữ lại kiểu hoa của bản gốc.
    /// Trả nil nếu không có trong từ điển.
    public func lookup(_ word: String) -> String? {
        let key = word.lowercased().precomposedStringWithCanonicalMapping
        guard let fixed = table[key] else { return nil }
        return AutoCorrectDictionary.applyCasing(of: word, to: fixed)
    }

    /// Số cặp lỗi->đúng đã dựng (để test/thống kê).
    public var count: Int { table.count }

    /// Toàn bộ cặp (sai -> đúng) — để xuất ra file/UI cho người dùng xem & sửa.
    public func allPairs() -> [(wrong: String, right: String)] {
        table.map { (wrong: $0.key, right: $0.value) }
    }

    /// BỘ CẶP MẶC ĐỊNH để gieo vào settings.json lần đầu (người dùng sẽ thấy & sửa).
    /// Chỉ giữ cặp mà VẾ SAI có dấu tiếng Việt — vì runtime chỉ sửa từ có dấu, nên
    /// các cặp "không dấu" (bay->bây) sẽ không bao giờ chạy và chỉ gây rối nếu hiện ra.
    /// Sắp xếp theo vế đúng rồi vế sai cho dễ đọc.
    public static func defaultPairs() -> [(wrong: String, right: String)] {
        let dict = AutoCorrectDictionary()   // built-in words + overrides, không userPairs
        return dict.allPairs()
            .filter { AutoCorrect.containsVietnameseDiacritic($0.wrong) }
            .sorted { ($0.right, $0.wrong) < ($1.right, $1.wrong) }
    }

    // MARK: - Bộ sinh biến thể-lỗi gõ nhanh

    /// Sinh các biến thể-lỗi thường gặp của MỘT từ đúng (đã lowercase, NFC).
    /// Các lỗi mô phỏng: gõ nhanh làm dấu thanh rơi nhầm nguyên âm, thiếu dấu mũ/móc,
    /// và đảo hai chữ liền kề trong cụm nguyên âm.
    static func misspellings(of correct: String) -> Set<String> {
        var out: Set<String> = []
        guard let dec = Decomposed(correct), dec.tone != .none else {
            // Không có dấu thanh: chỉ sinh lỗi thiếu-dấu-mũ (nếu có mũ/móc/trăng).
            if let dec = Decomposed(correct) {
                out.formUnion(missingMarkVariants(dec))
            }
            return out
        }

        // (a) DẤU THANH RƠI NHẦM NGUYÊN ÂM: đặt dấu thanh lên MỖI nguyên âm khác vị trí
        //     đúng. Đây là lỗi gõ nhanh phổ biến nhất ("nhièu", "giừo"...).
        let correctTarget = ToneRules.targetIndex(letters: dec.letters)
        for i in dec.letters.indices where isVowelLetter(dec.letters[i].base) {
            guard i != correctTarget else { continue }
            let variant = dec.render(toneAt: i)
            out.insert(variant.lowercased().precomposedStringWithCanonicalMapping)
        }

        // (b) THIẾU DẤU MŨ/MÓC/TRĂNG trên nguyên âm mang dấu thanh (giừo: dấu ở 'ư'
        //     nhưng chữ đúng là 'ơ'). Kết hợp: bỏ mark của nguyên âm mang dấu thanh
        //     rồi vẫn giữ dấu thanh ở đó.
        out.formUnion(missingMarkVariants(dec))

        return out
    }

    /// Biến thể "thiếu dấu biến âm": với mỗi nguyên âm mang mũ/móc/trăng, tạo bản bỏ
    /// mark đó (giữ nguyên dấu thanh) — mô phỏng gõ nhanh quên dấu mũ.
    private static func missingMarkVariants(_ dec: Decomposed) -> Set<String> {
        var out: Set<String> = []
        for i in dec.letters.indices where dec.letters[i].mark != .none && dec.letters[i].mark != .dyet {
            var copy = dec
            copy.letters[i].mark = .none
            let target = ToneRules.targetIndex(letters: copy.letters)
            guard target >= 0 else { continue }
            let variant = copy.render(toneAt: target)
            out.insert(variant.lowercased().precomposedStringWithCanonicalMapping)
        }
        return out
    }

    private static func isVowelLetter(_ ch: Character) -> Bool {
        "aeiouy".contains(Character(ch.lowercased()))
    }

    /// Áp kiểu hoa/thường của `source` lên `target` (theo từng ký tự, phần dư giữ thường).
    static func applyCasing(of source: String, to target: String) -> String {
        let src = Array(source)
        var out = ""
        for (i, ch) in target.enumerated() {
            if i < src.count, src[i].isUppercase {
                out.append(Character(ch.uppercased()))
            } else {
                out.append(ch)
            }
        }
        return out
    }
}

// MARK: - Dữ liệu: danh sách từ đúng ("trend") + override thủ công

public extension AutoCorrectDictionary {

    /// DANH SÁCH TỪ ĐÚNG phổ biến. Thêm từ mới vào đây để mở rộng ("tự thêm để trend").
    /// Mỗi từ đúng tự sinh ra các biến thể-lỗi gõ nhanh (xem `misspellings`).
    /// Ưu tiên các âm tiết đơn hay bị gõ sai vị trí dấu / thiếu dấu mũ.
    static let words: [String] = [
        // đại từ / hư từ hay gặp
        "giờ", "giữa", "giường", "người", "được", "nhiều", "chiều", "yêu",
        "tiền", "biết", "việc", "hiểu", "chuyện", "muốn", "buồn", "luôn", "cuộc",
        "cũng", "những", "từng", "cùng", "vẫn", "lần", "phần", "gần", "nhưng",
        // động từ / tính từ thường dùng (có móc "ươ" hay bị gõ lệch)
        "trường", "thương", "hường", "phường", "vườn", "mượn", "lười", "cười",
        "rượu", "hươu", "bưởi", "tưởng", "thưởng", "nướng", "xưởng", "trước",
        "tuổi", "cuối", "suối", "chuối", "đuối", "nuôi", "muối", "đường", "vướng",
        // đuôi mở oa/oe/uy (dấu hay đặt sai vị trí)
        "khỏe", "hoà", "hoạ", "toà", "xoà", "loã", "thoả",
        "quý", "quà", "quả", "quẻ", "quỳ", "thuý", "tuý", "huỳnh", "quỷ",
        // âm tiết mang mũ/móc hay bị quên
        "mấy", "thấy", "đấy", "cây", "mây", "bây", "gây", "dậy", "chạy",
        "tôi", "rồi", "mới", "với", "vội", "đội", "hỏi", "gọi", "nói", "mọi",
        "về", "lễ", "kể", "thế", "để", "nếu", "đều", "kêu", "nhiêu", "trên",
    ]

    /// OVERRIDES thủ công — cặp (lỗi -> đúng) đặc thù, ưu tiên cao hơn bản sinh tự động.
    /// Dùng cho lỗi không suy ra được từ từ-đúng (đảo phụ âm, viết tắt phổ biến...).
    static let overrides: [String: String] = [
        "giừo": "giờ",     // 'ư' + dời chữ -> 'ờ'
        "nhièu": "nhiều",  // dấu ở 'e' -> ở 'ê'
        "ngừoi": "người",
        "đựoc": "được",
        "cuộcj": "cuộc",
    ]
}
