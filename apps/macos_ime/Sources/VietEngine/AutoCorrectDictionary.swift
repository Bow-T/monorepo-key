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
        // (a) Trùng một từ trong danh sách `words`.
        let correctSet = Set(words.map { $0.lowercased().precomposedStringWithCanonicalMapping })
        for k in Array(t.keys) where correctSet.contains(k) { t.removeValue(forKey: k) }
        // (b) Bản thân biến thể đã là một TỪ ĐÚNG (dù không nằm trong `words`). Ví dụ
        //     "dậy" sinh biến thể "dạy" — nhưng "dạy" cũng là từ đúng (dạy học), không
        //     phải lỗi gõ; sửa "dạy"→"dậy" là phá từ đúng. Phân biệt với typo dấu-sai-chỗ
        //     (nhiêù, giừo) bằng: biến thể có VẦN hợp lệ VÀ dấu thanh đặt ĐÚNG vị trí
        //     chuẩn → là từ thật, loại bỏ. (nhiêù có vần "iêu" hợp lệ nhưng dấu ở 'u'
        //     sai vị trí -> KHÔNG bị loại, vẫn sửa được về "nhiều".)
        for k in Array(t.keys) where AutoCorrectDictionary.isRealWord(k) {
            t.removeValue(forKey: k)
        }

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
    /// Một chuỗi có phải TỪ ĐÚNG thật không (để không "sửa" nhầm nó)?
    /// = vần hợp lệ VÀ dấu thanh nằm ĐÚNG vị trí chuẩn chính tả. Chỉ true cho từ
    /// gõ chuẩn (dạy, tay, mây), false cho typo dấu-sai-chỗ (nhiêù, cuời) dù vần
    /// của chúng có thể hợp lệ.
    static func isRealWord(_ word: String) -> Bool {
        guard VietSyllable.isValidDisplay(word) else { return false }
        guard let dec = Decomposed(word) else { return false }
        // Không mang dấu thanh -> coi là "đúng" (không phải lỗi dấu-sai-chỗ).
        guard dec.tone != .none else { return true }
        // Vị trí dấu thanh THỰC TẾ trong chuỗi.
        var realIdx = -1
        for (i, ch) in word.precomposedStringWithCanonicalMapping.enumerated() {
            if let parts = CharDecompose.map[ch], parts.tone != .none { realIdx = i }
        }
        // Đúng từ khi dấu đặt ĐÚNG vị trí chuẩn.
        return realIdx == ToneRules.targetIndex(letters: dec.letters)
    }

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

        // (c) TÁCH ĐÔI NGUYÊN ÂM MŨ RA HAI BÊN NGUYÊN ÂM KẾ (lỗi gõ nhanh đảo phím):
        //     mũ â/ê/ô gõ bằng chữ đôi (aa/ee/oo). Khi gõ vội "rooif" (=rồi), một chữ
        //     'o' nhảy sang bên kia 'i' -> "roiof" -> engine dựng "roìo". Sinh biến thể
        //     đó để tự phủ lỗi này cho mọi từ dạng ô/ê/â + nguyên âm (rồi, mồi, tồi...).
        out.formUnion(splitCircumflexVariants(dec))

        return out
    }

    /// Biến thể "tách đôi nguyên âm mũ ra hai bên nguyên âm kế": mô phỏng lỗi gõ nhanh
    /// khi mũ được gõ bằng chữ đôi (aa→â, ee→ê, oo→ô). Điều kiện: một nguyên âm mang
    /// MŨ (circumflex) đứng NGAY TRƯỚC một nguyên âm khác. Ta "tách" nó: bỏ mũ, và chèn
    /// một bản sao (không mũ, không thanh) NGAY SAU nguyên âm kế; dấu thanh giữ ở chữ
    /// gốc (giờ là nguyên âm giữa của cụm 3). Ví dụ: "rồi" (r-ô-i) -> "roìo".
    private static func splitCircumflexVariants(_ dec: Decomposed) -> Set<String> {
        var out: Set<String> = []
        for i in dec.letters.indices {
            guard dec.letters[i].mark == .circumflex else { continue }
            // Phải có nguyên âm KHÁC đứng ngay sau (ô+i, ô+a, ê+u...).
            let j = i + 1
            guard j < dec.letters.count, isVowelLetter(dec.letters[j].base),
                  Character(dec.letters[j].base.lowercased()) != Character(dec.letters[i].base.lowercased())
            else { continue }
            var copy = dec
            copy.letters[i].mark = .none                       // gỡ mũ ở chữ gốc
            // Chèn bản sao thô của chữ gốc ngay sau nguyên âm kế (j).
            copy.letters.insert(Decomposed.Letter(base: dec.letters[i].base, mark: .none),
                                at: j + 1)
            // Dấu thanh vẫn thuộc chữ gốc (chỉ số i không đổi vì chèn ở sau).
            let variant = copy.render(toneAt: i)
            out.insert(variant.lowercased().precomposedStringWithCanonicalMapping)
        }
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
        // ── MỞ RỘNG: âm tiết phổ biến hay gõ sai dấu / thiếu mũ ──────────────
        // đại từ / hư từ thêm
        "này", "kia", "ấy", "đó", "sao", "vậy", "thôi", "mà", "rằng", "vì",
        "hay", "hoặc", "cũng", "chỉ", "mỗi", "vài", "dăm", "bấy", "bao",
        // động từ hay dùng (mũ/móc/dấu hay lệch)
        "nghĩ", "biểu", "hiện", "thiện", "liền", "chiếm", "khiến", "kiếm",
        "tiếc", "việt", "kiệt", "thiệt", "quyết", "khuyết", "chuyển", "truyền",
        "nguyện", "chuyện", "quyền", "luyện", "duyệt", "khuyên", "tuyên",
        "chương", "nương", "sương", "gương", "hưởng", "vướng", "cưỡng", "ngưỡng",
        "hưởng", "sưởng", "bưởng", "lưỡng", "trưởng", "dưỡng", "tưởng",
        // đuôi -uôi / -ươi / - uơ hay bị lệch
        "buổi", "chuồi", "ruổi", "xuôi", "đuôi", "cuối", "muội", "tuổi",
        "tươi", "lưới", "dưới", "khưới", "bưởi", "gửi", "chửi", "mửa",
        // đuôi mở oa/oe/uê/uy thêm
        "loè", "khoè", "xoè", "hoè", "quờ", "thuê", "huê", "quê", "quen",
        "quỳnh", "huỳnh", "quẩn", "quần", "khuỷu", "quậy", "quãng", "hoàng",
        "khoảng", "thoáng", "choáng", "ngoáy", "xoáy", "hoặc", "ngoặc",
        // âm tiết mang dấu ngã hay bị gõ thành hỏi (và ngược lại)
        "cũng", "những", "mãi", "vẫn", "dẫn", "mẫu", "kẽ", "rõ", "vẽ", "sẽ",
        "bão", "não", "hão", "lão", "cão", "chão", "gãy", "nãy", "hãy",
        // âm tiết mang mũ hay quên
        "công", "trông", "sông", "đông", "vông", "thông", "phông", "không",
        "lâu", "sâu", "câu", "đâu", "mâu", "châu", "trâu", "hầu", "dầu",
        "tầng", "vầng", "mầm", "nầm", "cầm", "nhầm", "chậm", "gậm", "ngậm",
        // ── MỞ RỘNG 2: từ cực phổ biến hay gõ sai vị trí dấu / thiếu mũ ──
        // (mỗi từ tự sinh biến thể-lỗi an toàn — đã lọc qua isRealWord)
        "hiện", "hiểu", "khiển", "triển", "biển", "kiểm", "điểm", "chiếm",
        "tiếng", "riêng", "thiêng", "liêng", "chiếc", "tiếc", "biếc",
        "muộn", "chuộng", "ruộng", "xuống", "luống", "guồng",
        "hưởng", "sưởi", "cưới", "mười", "lưới", "tưới", "bưởi", "gửi",
        "chuyện", "khuyến", "chuyến", "quyển", "tuyển", "nguyễn", "huyện",
        "phường", "giường", "nhường", "vượng", "tượng", "lượng",
        "thuyền", "quyền", "chuyền", "truyện", "huyền", "duyên", "yên",
        "muốn", "buộc", "thuộc", "chuộc", "nuốt", "buột", "suốt",
    ]

    /// OVERRIDES thủ công — cặp (lỗi -> đúng) đặc thù, ưu tiên cao hơn bản sinh tự động.
    /// Dùng cho lỗi không suy ra được từ từ-đúng (đảo phụ âm, viết tắt phổ biến...).
    static let overrides: [String: String] = [
        "giừo": "giờ",     // 'ư' + dời chữ -> 'ờ'
        "nhièu": "nhiều",  // dấu ở 'e' -> ở 'ê'
        "ngừoi": "người",
        "đựoc": "được",
        "cuộcj": "cuộc",
        // ── MỞ RỘNG: lỗi gõ nhanh phổ biến không suy ra được từ từ-đúng ──────
        // (chỉ TỪ ĐƠN; vế trái là lỗi rõ ràng, vế phải là từ đúng duy nhất hợp lý)
        // dấu đặt trên 'ư' của cụm ươ thay vì 'ơ' + thiếu móc (lỗi gõ nhanh kinh điển)
        "đừơng": "đường", "trừơng": "trường", "hừơng": "hương", "thừơng": "thương",
        "nứơc": "nước", "trứơc": "trước", "bứơc": "bước", "vứơt": "vượt",
        "lừơi": "lười", "cừơi": "cười", "tứơi": "tươi", "dứơi": "dưới",
        // cụm iê/yê: dấu ở nguyên âm trước thay vì sau (vế sai KHÔNG phải từ hợp lệ)
        "tièn": "tiền", "bièt": "biết", "vièc": "việc", "hièu": "hiểu",

        // ══════════════════════════════════════════════════════════════════════
        // BỘ 100 CẶP LỖI GÕ NHANH HAY GẶP NHẤT (bổ sung)
        // Nguyên tắc: vế SAI luôn có dấu tiếng Việt (nếu không, tính năng bỏ qua —
        // xem defaultPairs()), và vế SAI KHÔNG được là từ đúng chính tả (nếu không
        // test expandedDictSafety/DefaultPairsCheck sẽ fail). Vế ĐÚNG là từ đơn duy
        // nhất hợp lý. Đã lọc qua isRealWord() nên an toàn khi gõ đúng.
        // ══════════════════════════════════════════════════════════════════════

        // ── A. Cụm ươ: dấu/móc rơi nhầm 'ư' thay vì 'ơ' (lỗi Telex kinh điển) ──
        "gừơm": "gươm", "sừơng": "sương", "vừơng": "vương", "phừơng": "phường",
        "chừơng": "chương", "nhừơng": "nhường", "lừơng": "lương", "mừơn": "mượn",
        "khừơng": "khương", "dừơng": "dưỡng", "tứơng": "tướng", "gứơng": "gương",
        "sứơng": "sướng", "nứơng": "nướng", "xứơng": "xưởng", "hứơng": "hướng",
        "vứơn": "vườn", "rứơu": "rượu", "hứơu": "hươu", "bứơi": "bưởi",
        "tửơng": "tưởng", "thửơng": "thưởng", "ngửơng": "ngưỡng",

        // ── C. Cụm iê / yê: dấu rơi nhầm nguyên âm đầu thay vì giữa ──
        "chièu": "chiều", "nghièn": "nghiền", "thièn": "thiền", "kièn": "kiên",
        "mièng": "miệng", "sièng": "siêng", "chièn": "chiến", "lièn": "liền",
        "hièn": "hiền", "phièn": "phiền", "tièng": "tiếng", "chuyèn": "chuyện",
        "truyèn": "truyền", "nguyèn": "nguyện", "quyèn": "quyền", "luyèn": "luyện",
        "khuyèn": "khuyên", "tuyèn": "tuyên", "duyèt": "duyệt", "yèu": "yêu",

        // ── D. Cụm oa / oe / uy: dấu đặt sai vị trí (chính tả cũ → mới) ──
        "khòe": "khoẻ", "tòan": "toàn", "hòan": "hoàn", "ngòai": "ngoài",
        "lòai": "loài", "xòay": "xoay", "tòa": "toà", "hòa": "hoà",
        "qúy": "quý", "qùa": "quà", "qủa": "quả", "qùy": "quỳ",
        "thùy": "thuỳ", "qủy": "quỷ", "tùy": "tuỳ", "hùy": "huỷ",

        // ── E. Đảo / dính chữ khi gõ nhanh (thừa phụ âm cuối, kẹt phím —
        //      vế sai bất khả về chính tả nên luôn an toàn) ──
        "đượcc": "được", "nhiềuu": "nhiều", "ngườii": "người",
        "vớii": "với", "khỏee": "khoẻ", "cũngg": "cũng", "nhưngg": "nhưng",
        "muốnn": "muốn", "biếtt": "biết", "việcc": "việc", "chuyệnn": "chuyện",
        "buồnn": "buồn", "cuộcc": "cuộc", "tiềnn": "tiền", "trườngg": "trường",

        // ── F. TÁCH ĐÔI MŨ RA HAI BÊN (gõ nhanh "rooif"→"roiof"→"roìo"): mũ ô/ê/â
        //      gõ bằng chữ đôi, một nửa nhảy sang bên kia nguyên âm kế. Bộ sinh biến
        //      thể (splitCircumflexVariants) đã phủ phần lớn; thêm tay các từ hay gặp
        //      để chắc chắn kể cả khi từ gốc không nằm trong `words`.
        "roìo": "rồi", "moìo": "mồi", "toìo": "tồi", "coìo": "côi",
        "boìo": "bồi", "doìo": "dồi", "noìo": "nồi", "hoìo": "hồi",
        "goìo": "gồi", "loìo": "lồi", "xoìo": "xồi",
    ]
}
