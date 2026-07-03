// SymbolCatalog.swift
// -------------------
// DANH MỤC KÝ TỰ ĐẶC BIỆT + EMOJI cho bảng gõ nhanh (picker). Dữ liệu thuần, test
// được. Bảng picker chia theo nhóm; mỗi mục là một chuỗi để chèn thẳng vào ô gõ.
//
// Emoji lấy chung nguồn với gõ tắt (EmojiShortcodes) để nhất quán; ký tự đặc biệt
// là các glyph hay dùng khi soạn tiếng Việt (mũi tên, dấu, gạch, tiền tệ…).

import Foundation

public enum SymbolCatalog {

    /// Một nhóm trong bảng picker.
    public struct Group {
        public let title: String        // nhãn nhóm (tiếng Việt)
        public let items: [String]      // các ký tự/emoji để chèn
        public init(title: String, items: [String]) {
            self.title = title
            self.items = items
        }
    }

    /// Ký tự đặc biệt hay dùng — mũi tên, gạch, dấu, toán học, tiền tệ.
    public static let specials: [String] = [
        "→", "←", "↑", "↓", "↔", "⇒", "⇐", "⇔",
        "•", "·", "–", "—", "…", "«", "»", "“", "”", "‘", "’",
        "×", "÷", "±", "≈", "≠", "≤", "≥", "∞", "√", "°", "%", "‰",
        "★", "☆", "♥", "♦", "♣", "♠", "✓", "✔", "✗", "✘", "☑", "☐",
        "©", "®", "™", "§", "¶", "№",
        "₫", "$", "€", "£", "¥", "₩",
        "①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⑩",
    ]

    /// Emoji hay dùng (một tập gọn, ưu tiên mặt cười + cử chỉ + biểu tượng).
    /// Lấy trực tiếp từ EmojiShortcodes để một nguồn sự thật.
    public static let emojis: [String] = {
        // Thứ tự cố định (bảng table không có thứ tự) — chọn danh sách keyword ưu tiên.
        let order = [
            ":grin:", ":joy:", ":sweat_smile:", ":wink:", ":blush:", ":sunglasses:",
            ":heart_eyes:", ":thinking:", ":unamused:", ":pensive:", ":cry:", ":sob:",
            ":rage:", ":scream:", ":sleeping:", ":smirk:", ":nerd:", ":star_struck:",
            ":partying:", ":pleading:", ":skull:",
            ":thumbsup:", ":thumbsdown:", ":ok_hand:", ":clap:", ":wave:", ":pray:",
            ":muscle:", ":point_right:", ":v:", ":handshake:", ":writing:",
            ":heart:", ":broken_heart:", ":sparkling_heart:", ":fire:", ":sparkles:",
            ":star:", ":boom:", ":zap:", ":100:", ":tada:", ":gift:",
            ":check:", ":x:", ":warning:", ":question:", ":bulb:", ":bell:",
            ":rocket:", ":coffee:", ":pizza:", ":cake:", ":eyes:", ":brain:",
            ":computer:", ":phone:", ":email:", ":calendar:", ":memo:", ":books:",
            ":bug:", ":lock:", ":key:", ":link:", ":mag:", ":wrench:",
            ":sun:", ":moon:", ":rainbow:", ":dog:", ":cat:", ":unicorn:",
            ":rose:", ":sunflower:", ":vn:",
        ]
        return order.compactMap { EmojiShortcodes.table[$0] }
    }()

    /// Các nhóm hiển thị trên picker, đúng thứ tự.
    public static func groups() -> [Group] {
        [
            Group(title: "Ký tự đặc biệt", items: specials),
            Group(title: "Emoji", items: emojis),
        ]
    }
}
