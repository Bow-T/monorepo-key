// TextStats.swift
// ---------------
// ĐẾM từ / ký tự / dòng của một đoạn văn bản (cho tính năng "Đếm vùng bôi đen").
// Thuần logic -> test được; tầng App lo đọc vùng chọn qua AX + hiện toast.
//
// Định nghĩa (theo cách đếm quen thuộc, phù hợp tiếng Việt lẫn Anh):
//   • words:      số "từ" — cụm ký tự không-khoảng-trắng, phân tách bởi khoảng trắng.
//   • characters: tổng ký tự (tính grapheme, kể cả khoảng trắng & xuống dòng).
//   • charactersNoSpaces: ký tự KHÔNG tính mọi loại khoảng trắng.
//   • lines:      số dòng (đếm theo ngắt dòng; đoạn không rỗng luôn >= 1 dòng).

import Foundation

public struct TextStats: Equatable {
    public let words: Int
    public let characters: Int
    public let charactersNoSpaces: Int
    public let lines: Int

    public init(words: Int, characters: Int, charactersNoSpaces: Int, lines: Int) {
        self.words = words
        self.characters = characters
        self.charactersNoSpaces = charactersNoSpaces
        self.lines = lines
    }

    /// Đếm thống kê của `text`.
    public static func of(_ text: String) -> TextStats {
        // Ký tự: đếm grapheme (Character) — "é", cờ 🇻🇳, emoji đều tính 1.
        let characters = text.count
        let charactersNoSpaces = text.reduce(0) { $0 + ($1.isWhitespace ? 0 : 1) }

        // Từ: tách theo khoảng trắng (mọi loại), bỏ cụm rỗng.
        let words = text
            .split(whereSeparator: { $0.isWhitespace })
            .count

        // Dòng: đếm theo \n (đã quy \r\n, \r về \n). Chuỗi rỗng -> 0 dòng.
        let lines: Int
        if text.isEmpty {
            lines = 0
        } else {
            let unified = text
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
            lines = unified.split(separator: "\n", omittingEmptySubsequences: false).count
        }

        return TextStats(words: words, characters: characters,
                         charactersNoSpaces: charactersNoSpaces, lines: lines)
    }

    /// Chuỗi tóm tắt tiếng Việt để hiện toast. Vd "12 từ · 58 ký tự · 2 dòng".
    public var summary: String {
        var parts = ["\(words) từ", "\(characters) ký tự"]
        if lines > 1 { parts.append("\(lines) dòng") }
        return parts.joined(separator: " · ")
    }
}
