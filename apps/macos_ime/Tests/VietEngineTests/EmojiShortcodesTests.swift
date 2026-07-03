// EmojiShortcodesTests.swift
// --------------------------
// Kiểm tra tính toàn vẹn của bảng emoji shortcode: keyword đúng dạng `:tên:`,
// giá trị không rỗng, và một vài shortcode phổ biến tra được đúng emoji.

import Testing
import Foundation
@testable import VietEngine

@Suite("Emoji shortcode")
struct EmojiShortcodesTests {

    @Test("Mọi keyword đúng dạng :tên: và giá trị không rỗng")
    func wellFormed() {
        for (keyword, emoji) in EmojiShortcodes.table {
            #expect(keyword.hasPrefix(":"), "keyword phải mở bằng ':' — \(keyword)")
            #expect(keyword.hasSuffix(":"), "keyword phải đóng bằng ':' — \(keyword)")
            #expect(keyword.count >= 3, "keyword phải có tên giữa hai ':' — \(keyword)")
            #expect(!emoji.isEmpty, "emoji không được rỗng — \(keyword)")
            // Phần tên giữa hai ':' chỉ gồm ký tự hợp lệ (khớp isEmojiShortcodeChar).
            let inner = keyword.dropFirst().dropLast()
            for ch in inner {
                let ok = ch.isLetter || ch.isNumber || ch == "_" || ch == "+" || ch == "-"
                #expect(ok, "ký tự '\(ch)' trong \(keyword) không hợp lệ cho shortcode")
            }
        }
    }

    @Test("Một số shortcode phổ biến tra đúng emoji")
    func lookup() {
        #expect(EmojiShortcodes.table[":cry:"] == "😢")
        #expect(EmojiShortcodes.table[":thumbsup:"] == "👍")
        #expect(EmojiShortcodes.table[":+1:"] == "👍")
        #expect(EmojiShortcodes.table[":heart:"] == "❤️")
        #expect(EmojiShortcodes.table[":fire:"] == "🔥")
        #expect(EmojiShortcodes.table[":vn:"] == "🇻🇳")
    }

    @Test("definitions() sinh MacroDefinition tĩnh khớp bảng")
    func definitionsMatchTable() {
        let defs = EmojiShortcodes.definitions()
        #expect(defs.count == EmojiShortcodes.table.count)
        for def in defs {
            #expect(def.type == .staticText)
            #expect(EmojiShortcodes.table[def.keyword] == def.content)
        }
    }
}

/// Mô phỏng CÁCH BỘ ĐIỀU KHIỂN lái matcher: mỗi ký tự ':' gọi onColon(), ký tự khác
/// gọi onCharacter(renderedSelf:). `renderedSelf` = engine gõ ra đúng ký tự thô
/// (mặc định true; đặt false để giả lập Telex biến đổi 'oo'->'ô').
@Suite("Emoji shortcode: máy trạng thái")
struct EmojiMatcherTests {

    /// Gõ chuỗi `keys`, trả về (emoji, số ký tự cần xoá) NẾU bung ở ký tự cuối.
    /// `transformed`: tập chỉ số (0-based) ký tự mà engine BIẾN ĐỔI (renderedSelf=false).
    private func type(_ keys: String, transformed: Set<Int> = []) -> (String, Int)? {
        var m = EmojiShortcodeMatcher()
        var result: (String, Int)? = nil
        for (i, ch) in keys.enumerated() {
            if ch == ":" {
                if let r = m.onColon() { result = (r.emoji, r.deleteCount) } else { result = nil }
            } else {
                m.onCharacter(ch, renderedSelf: !transformed.contains(i))
                result = nil
            }
        }
        return result
    }

    @Test("Bung đúng emoji khi gõ :cry:")
    func basic() {
        let r = type(":cry:")
        #expect(r?.0 == "😢")
        #expect(r?.1 == 4)   // xoá ':cry' (4 ký tự đã hiện), ':' đóng bị nuốt
    }

    @Test("Shortcode có dấu + và số: :+1:")
    func plusOne() {
        let r = type(":+1:")
        #expect(r?.0 == "👍")
        #expect(r?.1 == 3)   // ':+1'
    }

    @Test("Shortcode dài có gạch dưới: :heart_eyes:")
    func underscore() {
        let r = type(":heart_eyes:")
        #expect(r?.0 == "😍")
        #expect(r?.1 == 11)  // ':heart_eyes'
    }

    @Test("Shortcode không tồn tại -> không bung, ':' đóng thành ':' mở mới")
    func unknownReopens() {
        var m = EmojiShortcodeMatcher()
        _ = m.onColon()                               // ':'
        m.onCharacter("x", renderedSelf: true)        // ':x'
        m.onCharacter("y", renderedSelf: true)        // ':xy'
        let close = m.onColon()                       // ':xy:' không có -> nil, mở lại ':'
        #expect(close == nil)
        // Giờ buffer = ':' mở. Gõ tiếp 'cry' + ':' phải bung.
        m.onCharacter("c", renderedSelf: true)
        m.onCharacter("r", renderedSelf: true)
        m.onCharacter("y", renderedSelf: true)
        let r = m.onColon()
        #expect(r?.0 == "😢")
        #expect(r?.1 == 4)
    }

    @Test("Hai shortcode liền nhau :fire::vn:")
    func backToBack() {
        var m = EmojiShortcodeMatcher()
        for ch in ":fire:" {
            if ch == ":" {
                if let r = m.onColon(), ch == ":" { // bung ở ':' đóng của :fire:
                    #expect(r.0 == "🔥")
                }
            } else {
                m.onCharacter(ch, renderedSelf: true)
            }
        }
        // Ngay sau khi bung :fire:, gõ tiếp :vn:
        var emoji2: String? = nil
        for ch in ":vn:" {
            if ch == ":" { emoji2 = m.onColon()?.emoji } else { m.onCharacter(ch, renderedSelf: true) }
        }
        #expect(emoji2 == "🇻🇳")
    }

    @Test("onColon trả shortcode gốc để undo khôi phục")
    func returnsShortcode() {
        var m = EmojiShortcodeMatcher()
        _ = m.onColon()                          // ':'
        m.onCharacter("c", renderedSelf: true)
        m.onCharacter("r", renderedSelf: true)
        m.onCharacter("y", renderedSelf: true)
        let r = m.onColon()
        #expect(r?.emoji == "😢")
        #expect(r?.shortcode == ":cry:")         // để undo gõ lại ":cry:"
    }

    @Test("Telex biến đổi giữa chừng -> huỷ buffer, KHÔNG bung sai")
    func transformationCancels() {
        // Giả lập ':oo' mà 'o' thứ hai bị Telex gộp thành 'ô' (renderedSelf=false ở i=2).
        // Buffer phải huỷ để không xoá nhầm số ký tự khi có ':' đóng.
        var m = EmojiShortcodeMatcher()
        _ = m.onColon()                          // ':'
        m.onCharacter("o", renderedSelf: true)   // ':o'
        m.onCharacter("o", renderedSelf: false)  // engine biến 'oo'->'ô' -> huỷ
        let r = m.onColon()                      // ':' -> buffer rỗng nên chỉ mở mới
        #expect(r == nil)
    }

    @Test("reset() xoá trạng thái đang gõ dở")
    func resetClears() {
        var m = EmojiShortcodeMatcher()
        _ = m.onColon()
        m.onCharacter("c", renderedSelf: true)
        m.reset()
        #expect(m.buffer.isEmpty)
        // Sau reset, ':cry:' rời rạc: ':' rồi 'cry' rồi ':' -> vẫn bung nếu đủ.
        _ = m.onColon()
        m.onCharacter("c", renderedSelf: true)
        m.onCharacter("r", renderedSelf: true)
        m.onCharacter("y", renderedSelf: true)
        #expect(m.onColon()?.0 == "😢")
    }

    @Test("Ký tự lạ giữa shortcode -> huỷ")
    func invalidCharCancels() {
        var m = EmojiShortcodeMatcher()
        _ = m.onColon()
        m.onCharacter("c", renderedSelf: true)
        m.onCharacter("!", renderedSelf: true)   // '!' không hợp lệ -> huỷ
        let r = m.onColon()
        #expect(r == nil)   // buffer đã huỷ, ':' này chỉ mở mới
    }
}
