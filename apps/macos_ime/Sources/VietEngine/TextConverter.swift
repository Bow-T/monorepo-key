// TextConverter.swift
// -------------------
// CÔNG CỤ CHUYỂN MÃ / BIẾN ĐỔI VĂN BẢN tiếng Việt (đối chiếu PHTV ConvertTool).
// Thuần xử lý chuỗi Unicode -> test được bằng `swift test`, không cần AppKit.
//
// Hỗ trợ:
//   • Bỏ dấu:        "Tiếng Việt"  -> "Tieng Viet"      (giữ đ/Đ? -> tuỳ chọn)
//   • Hoa/thường:    ALL CAPS / all lower / Hoa Đầu Câu / Hoa Mỗi Từ
//   • NFC <-> NFD:   Unicode dựng sẵn <-> tổ hợp (sửa text lỗi font)
//
// Các phép trên độc lập, có thể kết hợp (vd bỏ dấu + ALL CAPS).

import Foundation

public enum TextConverter {

    // MARK: - Bỏ dấu

    /// Bản đồ nguyên âm/ký tự tiếng Việt -> ký tự Latin cơ bản (không dấu).
    /// Bao trùm mọi tổ hợp dấu thanh + dấu mũ/móc/trăng của a/e/i/o/u/y và đ.
    private static let stripMap: [Character: Character] = {
        var m: [Character: Character] = [:]
        func add(_ base: Character, _ variants: String) {
            for ch in variants { m[ch] = base }
        }
        add("a", "àáảãạăằắẳẵặâầấẩẫậ")
        add("e", "èéẻẽẹêềếểễệ")
        add("i", "ìíỉĩị")
        add("o", "òóỏõọôồốổỗộơờớởỡợ")
        add("u", "ùúủũụưừứửữự")
        add("y", "ỳýỷỹỵ")
        add("d", "đ")
        // chữ hoa
        add("A", "ÀÁẢÃẠĂẰẮẲẴẶÂẦẤẨẪẬ")
        add("E", "ÈÉẺẼẸÊỀẾỂỄỆ")
        add("I", "ÌÍỈĨỊ")
        add("O", "ÒÓỎÕỌÔỒỐỔỖỘƠỜỚỞỠỢ")
        add("U", "ÙÚỦŨỤƯỪỨỬỮỰ")
        add("Y", "ỲÝỶỸỴ")
        add("D", "Đ")
        return m
    }()

    /// Bỏ toàn bộ dấu tiếng Việt, trả chuỗi Latin cơ bản. "Tiếng Việt" -> "Tieng Viet".
    public static func removeDiacritics(_ text: String) -> String {
        // Chuẩn hoá NFC trước để mọi tổ hợp về dạng dựng sẵn rồi tra bảng.
        var out = ""
        out.reserveCapacity(text.count)
        for ch in text.precomposedStringWithCanonicalMapping {
            out.append(stripMap[ch] ?? ch)
        }
        return out
    }

    // MARK: - Hoa / thường

    public enum LetterCase {
        case allUpper        // TẤT CẢ HOA
        case allLower        // tất cả thường
        case capitalizeFirst // Hoa chữ đầu câu (sau . ? ! và xuống dòng)
        case capitalizeWords // Hoa Chữ Đầu Mỗi Từ
    }

    /// Đổi hoa/thường theo kiểu, GIỮ NGUYÊN dấu tiếng Việt (uppercased/lowercased
    /// của Swift xử lý đúng ký tự dựng sẵn: "việt" <-> "VIỆT").
    public static func changeCase(_ text: String, to mode: LetterCase) -> String {
        switch mode {
        case .allUpper: return text.uppercased()
        case .allLower: return text.lowercased()
        case .capitalizeFirst: return capitalize(text, eachWord: false)
        case .capitalizeWords: return capitalize(text, eachWord: true)
        }
    }

    private static let sentenceBreaks: Set<Character> = [".", "?", "!"]

    private static func capitalize(_ text: String, eachWord: Bool) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        var shouldUpper = true          // ký tự chữ đầu tiên luôn viết hoa
        var pendingSentenceBreak = false

        for ch in text {
            if ch.isLetter {
                out += shouldUpper ? String(ch).uppercased() : String(ch).lowercased()
                shouldUpper = false
                pendingSentenceBreak = false
            } else {
                out.append(ch)
                if eachWord {
                    // Hoa mỗi từ: sau bất kỳ khoảng trắng nào -> hoa chữ kế.
                    if ch.isWhitespace { shouldUpper = true }
                } else {
                    // Hoa đầu câu: sau . ? ! (rồi khoảng trắng/xuống dòng) -> hoa.
                    if ch == "\n" {
                        shouldUpper = true
                        pendingSentenceBreak = false
                    } else if sentenceBreaks.contains(ch) {
                        pendingSentenceBreak = true
                    } else if ch.isWhitespace {
                        if pendingSentenceBreak { shouldUpper = true }
                        pendingSentenceBreak = false
                    } else {
                        pendingSentenceBreak = false
                    }
                }
            }
        }
        return out
    }

    // MARK: - Unicode NFC <-> NFD

    /// Unicode DỰNG SẴN (NFC): "ế" là 1 code point U+1EBF.
    public static func toPrecomposed(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
    }

    /// Unicode TỔ HỢP (NFD): "ế" = "e" + U+0302 (mũ) + U+0301 (sắc).
    public static func toDecomposed(_ text: String) -> String {
        text.decomposedStringWithCanonicalMapping
    }

    // MARK: - Bảng mã cũ: TCVN3 (ABC) & VNI-Windows

    /// Bảng mã đích/nguồn cho công cụ chuyển mã.
    public enum CodeTable {
        case unicode       // Unicode dựng sẵn (NFC)
        case tcvn3         // TCVN3 / ABC (font .VnTime)
        case vniWindows    // VNI-Windows (font VNI-Times)
    }

    /// Chuyển văn bản giữa hai bảng mã. Ký tự không thuộc bảng -> giữ nguyên.
    /// Vd: convert("Tiếng Việt", from: .unicode, to: .tcvn3).
    public static func convert(_ text: String, from: CodeTable, to: CodeTable) -> String {
        guard from != to else { return text }
        // Mọi đường đi qua "trung gian Unicode dựng sẵn" cho đơn giản & đúng.
        let unicode = toUnicode(text, from: from)
        return fromUnicode(unicode, to: to)
    }

    /// Giải mã từ bảng mã bất kỳ về Unicode dựng sẵn.
    private static func toUnicode(_ text: String, from: CodeTable) -> String {
        switch from {
        case .unicode:
            return text.precomposedStringWithCanonicalMapping
        case .tcvn3:
            var out = ""
            for ch in text { out.append(LegacyCodeTable.tcvnToUnicode[ch] ?? ch) }
            return out
        case .vniWindows:
            return decodeVNI(text)
        }
    }

    /// Mã hoá từ Unicode dựng sẵn sang bảng mã đích.
    private static func fromUnicode(_ text: String, to: CodeTable) -> String {
        let unicode = text.precomposedStringWithCanonicalMapping
        switch to {
        case .unicode:
            return unicode
        case .tcvn3:
            var out = ""
            for ch in unicode { out += LegacyCodeTable.unicodeToTCVN[ch] ?? String(ch) }
            return out
        case .vniWindows:
            var out = ""
            for ch in unicode { out += LegacyCodeTable.unicodeToVNI[ch] ?? String(ch) }
            return out
        }
    }

    /// Giải mã VNI-Windows -> Unicode. VNI dùng token 1-2 ký tự (chữ gốc + ký tự
    /// dấu rời). Quét GREEDY: thử khớp token 2 ký tự trước, rồi 1 ký tự.
    private static func decodeVNI(_ text: String) -> String {
        let chars = Array(text)
        var out = ""
        var i = 0
        while i < chars.count {
            var matched = false
            // thử token dài (2) trước
            if i + 1 < chars.count {
                let two = String(chars[i ... i + 1])
                if let uni = LegacyCodeTable.vniToUnicode[two] {
                    out.append(uni); i += 2; matched = true
                }
            }
            if !matched {
                let one = String(chars[i])
                if let uni = LegacyCodeTable.vniToUnicode[one] {
                    out.append(uni)
                } else {
                    out.append(chars[i])
                }
                i += 1
            }
        }
        return out
    }
}
