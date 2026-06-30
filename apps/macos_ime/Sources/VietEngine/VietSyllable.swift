// VietSyllable.swift
// ------------------
// KIỂM TRA ÂM TIẾT TIẾNG VIỆT HỢP LỆ — luật chính tả, KHÔNG cần từ điển.
//
// Dùng cho 2 việc:
//   • Tự khôi phục tiếng Anh: nếu chuỗi đã gõ KHÔNG phải âm tiết tiếng Việt hợp lệ
//     thì nhiều khả năng là từ tiếng Anh/vô nghĩa -> khôi phục phím thô.
//   • Kiểm tra chính tả: cảnh báo/không áp dấu cho tổ hợp sai.
//
// Cấu trúc âm tiết: [phụ âm đầu]? + [vần: (đệm) + nguyên-âm-chính + (kết)].
// Bảng phụ âm đầu/cuối lấy theo chuẩn (đối chiếu vnConsonantTable/vnEndConsonantTable
// của PHTV/OpenKey).

import Foundation

public enum VietSyllable {

    /// Phụ âm đầu hợp lệ (đã sắp dài trước ngắn để khớp tham lam).
    /// Gồm cả 'gi', 'qu' xử lý riêng vì kéo theo bán nguyên âm.
    private static let initials: [String] = [
        "ngh", "ng", "nh", "ch", "gh", "gi", "kh", "ph", "th", "tr", "qu",
        "b", "c", "d", "đ", "g", "h", "k", "l", "m", "n", "p", "q", "r",
        "s", "t", "v", "x",
    ]

    /// Phụ âm cuối hợp lệ.
    private static let finals: [String] = [
        "ch", "nh", "ng", "c", "m", "n", "p", "t",
    ]

    /// Tập nguyên âm (đã bỏ dấu thanh, GIỮ dấu mũ/móc/trăng) hợp lệ làm "vần"
    /// (phần nguyên âm + có thể gồm bán nguyên âm đệm/cuối i/o/u/y).
    /// Đây là danh sách vần tiếng Việt phổ biến (không tính phụ âm cuối).
    private static let nuclei: Set<String> = [
        // 1 nguyên âm
        "a", "ă", "â", "e", "ê", "i", "o", "ô", "ơ", "u", "ư", "y",
        // 2 nguyên âm (nguyên âm đôi + bán nguyên âm)
        "ai", "ao", "au", "ay", "âu", "ây",
        "eo", "êu",
        "ia", "iê", "iu", "yê", "yêu", "iêu",
        "oa", "oă", "oe", "oo", "oi", "ôi", "ơi",
        "ua", "uâ", "uê", "uô", "uơ", "ui", "ưi", "uy", "ưa", "ươ", "ưu", "ôô",
        "oai", "oay", "oao", "uây", "uôi", "ươi", " uya",
        "uya", "uyê", "uyu", "yêu",
        "uê", "uơ",
    ]

    /// Một âm tiết (đã bỏ dấu thanh) có HỢP LỆ về cấu trúc tiếng Việt không?
    /// Đầu vào nên là dạng base + dấu mũ/móc/trăng (vd "tiếng" -> dùng "tiêng").
    public static func isValidToneless(_ rawSyllable: String) -> Bool {
        let s = rawSyllable.lowercased()
        guard !s.isEmpty else { return false }
        // Phải toàn chữ cái tiếng Việt (a-z + nguyên âm có mũ/móc/trăng + đ).
        guard s.allSatisfy({ isVietLetter($0) }) else { return false }

        // Tách phụ âm đầu (khớp tham lam dài nhất).
        var rest = Substring(s)
        if let initial = matchPrefix(rest, in: initials) {
            rest = rest.dropFirst(initial.count)
        }
        // 'gi'/'qu' có thể đã ăn 'i'/'u' — nếu sau khi cắt mà rỗng thì coi như chỉ
        // có phụ âm (không hợp lệ — âm tiết cần nguyên âm). Bỏ qua, xử lý bên dưới.

        guard !rest.isEmpty else { return false }  // chỉ có phụ âm -> không phải âm tiết

        // Tách phụ âm cuối (khớp tham lam dài nhất) ở cuối.
        var nucleus = String(rest)
        if let fin = matchSuffix(rest, in: finals) {
            nucleus = String(rest.dropLast(fin.count))
        }
        guard !nucleus.isEmpty else { return false }  // chỉ có phụ âm cuối, không nguyên âm

        // Phần còn lại phải là một "vần nguyên âm" hợp lệ.
        return nuclei.contains(nucleus)
    }

    /// Chuẩn hoá một chuỗi HIỂN THỊ tiếng Việt (có dấu thanh) về dạng toneless để
    /// kiểm tra: bỏ dấu thanh nhưng GIỮ dấu mũ/móc/trăng. Vd "tiếng" -> "tiêng".
    public static func stripTone(_ display: String) -> String {
        var out = ""
        for ch in display.precomposedStringWithCanonicalMapping {
            out.append(toneStripMap[ch] ?? ch)
        }
        return out
    }

    /// Một chuỗi HIỂN THỊ (có dấu) có phải âm tiết tiếng Việt hợp lệ không?
    public static func isValidDisplay(_ display: String) -> Bool {
        isValidToneless(stripTone(display))
    }

    // MARK: - Kiểm tra chính tả (spell-check)

    /// Một TỪ (chuỗi hiển thị) có sai chính tả tiếng Việt không?
    /// "Sai" = có dấu tiếng Việt nhưng cấu trúc âm tiết không hợp lệ.
    /// Từ thuần ASCII (không dấu) -> coi là KHÔNG sai (có thể là tiếng Anh/tên riêng).
    ///
    /// Dùng cho: gạch chân lỗi trong UI, hoặc chế độ "khôi phục từ sai" (Unikey).
    public static func isMisspelled(_ word: String) -> Bool {
        guard hasVietnameseDiacritic(word) else { return false }
        return !isValidDisplay(word)
    }

    /// Một chuỗi NHIỀU TỪ: trả về danh sách các từ sai chính tả (kèm vị trí range
    /// trong chuỗi gốc) — để UI gạch chân. Tách từ theo khoảng trắng.
    public static func misspelledWords(in text: String) -> [(word: String, range: Range<String.Index>)] {
        var result: [(String, Range<String.Index>)] = []
        var i = text.startIndex
        while i < text.endIndex {
            // bỏ qua khoảng trắng / dấu câu (không phải chữ)
            if !text[i].isLetter {
                i = text.index(after: i)
                continue
            }
            // gom 1 từ (chuỗi chữ liên tiếp)
            var j = i
            while j < text.endIndex && text[j].isLetter {
                j = text.index(after: j)
            }
            let word = String(text[i..<j])
            if isMisspelled(word) { result.append((word, i..<j)) }
            i = j
        }
        return result
    }

    /// Chuỗi có chứa ký tự mang dấu tiếng Việt (mũ/móc/trăng/thanh hoặc đ) không?
    private static func hasVietnameseDiacritic(_ word: String) -> Bool {
        for ch in word.precomposedStringWithCanonicalMapping {
            if toneStripMap[ch] != nil { return true }   // nguyên âm có thanh
            if "ăâđêôơưĂÂĐÊÔƠƯ".contains(ch) { return true }  // có mũ/móc/trăng/đ
            // nguyên âm có thanh dạng hoa
            if "ÁÀẢÃẠẮẰẲẴẶẤẦẨẪẬÉÈẺẼẸẾỀỂỄỆÍÌỈĨỊÓÒỎÕỌỐỒỔỖỘỚỜỞỠỢÚÙỦŨỤỨỪỬỮỰÝỲỶỸỴ".contains(ch) {
                return true
            }
        }
        return false
    }

    // MARK: - Helpers

    private static func matchPrefix(_ s: Substring, in list: [String]) -> String? {
        for cand in list where s.hasPrefix(cand) { return cand }
        return nil
    }

    private static func matchSuffix(_ s: Substring, in list: [String]) -> String? {
        for cand in list where s.hasSuffix(cand) { return cand }
        return nil
    }

    private static func isVietLetter(_ ch: Character) -> Bool {
        if ch >= "a" && ch <= "z" { return true }
        return "ăâđêôơư".contains(ch)
    }

    /// Bỏ DẤU THANH nhưng giữ mũ/móc/trăng: á->a, ấ->â, ế->ê, ự->ư, ọ->o...
    private static let toneStripMap: [Character: Character] = {
        var m: [Character: Character] = [:]
        func add(_ keep: Character, _ toned: String) {
            for ch in toned { m[ch] = keep }
        }
        add("a", "áàảãạ");  add("ă", "ắằẳẵặ");  add("â", "ấầẩẫậ")
        add("e", "éèẻẽẹ");  add("ê", "ếềểễệ")
        add("i", "íìỉĩị")
        add("o", "óòỏõọ");  add("ô", "ốồổỗộ");  add("ơ", "ớờởỡợ")
        add("u", "úùủũụ");  add("ư", "ứừửữự")
        add("y", "ýỳỷỹỵ")
        return m
    }()
}
