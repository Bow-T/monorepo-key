// WhitespaceNormalizer.swift
// --------------------------
// CHUẨN HOÁ KHOẢNG TRẮNG cho văn bản dán lộn xộn (từ PDF/web/email):
//   • Gộp nhiều dấu cách/tab liên tiếp thành MỘT dấu cách.
//   • Cắt khoảng trắng đầu & cuối MỖI dòng.
//   • Gộp nhiều dòng trống liên tiếp thành MỘT dòng trống (giữ ngắt đoạn).
//   • Bỏ dòng trống ở đầu & cuối toàn văn bản.
//
// Chuẩn hoá ký tự khoảng trắng "lạ" (non-breaking space U+00A0, các loại space
// Unicode, tab) về dấu cách thường trước khi gộp. Thuần logic -> test được.

import Foundation

public enum WhitespaceNormalizer {

    /// Tập ký tự khoảng-trắng-trong-dòng (không tính xuống dòng) cần quy về ' '.
    /// Gồm space thường, tab, NBSP (U+00A0), NARROW NBSP (U+202F), các space Unicode.
    private static let inlineSpaces: Set<Character> = [
        " ", "\t", "\u{00A0}", "\u{202F}", "\u{2007}", "\u{2009}", "\u{200A}",
        "\u{2002}", "\u{2003}", "\u{2004}", "\u{2005}", "\u{2006}", "\u{2008}",
        "\u{3000}", "\u{feff}",  // ideographic space, zero-width no-break
    ]

    /// Chuẩn hoá toàn bộ khoảng trắng của `text`. Luôn trả chuỗi (rỗng nếu vào rỗng).
    public static func normalize(_ text: String) -> String {
        // 1) Tách theo mọi kiểu xuống dòng (\r\n, \r, \n) thành các dòng.
        let unifiedNewlines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let rawLines = unifiedNewlines.split(separator: "\n", omittingEmptySubsequences: false)

        // 2) Với mỗi dòng: quy space lạ -> ' ', gộp space liên tiếp, trim hai đầu.
        let cleanedLines = rawLines.map { collapseLine(String($0)) }

        // 3) Gộp nhiều dòng trống liên tiếp thành một; bỏ trống ở đầu/cuối.
        var result: [String] = []
        var lastWasEmpty = false
        for line in cleanedLines {
            let isEmpty = line.isEmpty
            if isEmpty {
                if lastWasEmpty { continue }        // đã có 1 dòng trống -> bỏ dòng này
                if result.isEmpty { continue }      // dòng trống ở đầu -> bỏ
            }
            result.append(line)
            lastWasEmpty = isEmpty
        }
        // Bỏ dòng trống ở cuối.
        while let last = result.last, last.isEmpty { result.removeLast() }

        return result.joined(separator: "\n")
    }

    /// Chuẩn hoá MỘT dòng: quy mọi space lạ về ' ', gộp liên tiếp, trim hai đầu.
    private static func collapseLine(_ line: String) -> String {
        var out = ""
        out.reserveCapacity(line.count)
        var pendingSpace = false
        var started = false

        for ch in line {
            if inlineSpaces.contains(ch) {
                pendingSpace = true
            } else {
                if pendingSpace && started {
                    out.append(" ")
                }
                out.append(ch)
                started = true
                pendingSpace = false
            }
        }
        // pendingSpace ở cuối -> bỏ (trim phải). Đầu dòng không thêm space nhờ `started`.
        return out
    }
}
