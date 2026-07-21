// LongExpansionClampTests.swift
// -----------------------------
// Regression: clamp số Backspace KHÔNG được cắt các đường BUNG dài.
//
// BUG (đã sửa): `KeyOutput.maxBackspaces = 15` (đặt theo "âm tiết dài nhất ~7 ký tự")
// cắt nhầm khi bung emoji shortcode dài / macro / undo — các đường này xoá cả TỪ KHOÁ
// đã hiển thị, thường 16–40+ ký tự. Vd `:sparkling_heart:` (deleteCount 16) bị clamp
// 15 -> bung ra rác ":sparkling_heảt:". SỬA: nâng ngưỡng = 200.
//
// (KeyOutput ở target BowGoApp nên test target VietEngine không tham chiếu trực tiếp
// hằng số được; ở đây kiểm phần LOGIC thuộc VietEngine — matcher trả deleteCount đúng
// và > ngưỡng cũ — cùng mô phỏng clamp bằng hằng số cục bộ khớp giá trị đã sửa.)

import Testing
import Foundation
@testable import VietEngine

@Suite("Clamp số Backspace không cắt đường bung dài")
struct LongExpansionClamp {

    /// Khớp `KeyOutput.maxBackspaces` sau khi sửa. Nếu đổi giá trị thật, đổi cả đây.
    private static let maxBackspaces = 200

    private struct Field {
        var text = ""
        mutating func replace(backspaces: Int, with s: String, clamp: Int) {
            let safe = min(backspaces, clamp)
            if text.count >= safe { text.removeLast(safe) } else { text = "" }
            text += s
        }
    }

    @Test("Emoji shortcode dài :sparkling_heart: có deleteCount > ngưỡng cũ 15")
    func longEmojiDeleteCount() {
        var matcher = EmojiShortcodeMatcher()
        _ = matcher.onColon()   // ':' mở buffer
        for ch in "sparkling_heart" { matcher.onCharacter(ch, renderedSelf: true) }
        guard let (emoji, deleteCount, _) = matcher.onColon() else {
            Issue.record("shortcode :sparkling_heart: phải khớp"); return
        }
        #expect(emoji == "💖")
        #expect(deleteCount > 15, "ca kiểm phải > ngưỡng cũ (thực tế \(deleteCount))")
        #expect(deleteCount <= Self.maxBackspaces)
    }

    @Test("Bung emoji dài với ngưỡng 15 (cũ) RA RÁC; ngưỡng 200 (mới) SẠCH")
    func clampBehaviour() {
        var matcher = EmojiShortcodeMatcher()
        _ = matcher.onColon()   // ':' mở buffer
        for ch in "sparkling_heart" { matcher.onCharacter(ch, renderedSelf: true) }
        guard let (emoji, deleteCount, _) = matcher.onColon() else {
            Issue.record("phải khớp"); return
        }
        // Ngưỡng cũ 15 -> còn sót ký tự đầu (rác).
        var oldField = Field()
        oldField.text = ":sparkling_heart"
        oldField.replace(backspaces: deleteCount, with: emoji, clamp: 15)
        #expect(oldField.text != emoji, "bản cũ đáng lẽ để lại rác")

        // Ngưỡng mới -> sạch.
        var newField = Field()
        newField.text = ":sparkling_heart"
        newField.replace(backspaces: deleteCount, with: emoji, clamp: Self.maxBackspaces)
        #expect(newField.text == emoji, "bản mới phải sạch: '\(newField.text)'")
    }

    @Test("Undo chuỗi dài (>15) bung sạch với ngưỡng mới")
    func longUndo() {
        let shown = "Nguyễn Văn A — Kỹ sư phần mềm"   // > 15 ký tự
        var field = Field()
        field.text = shown
        field.replace(backspaces: shown.count, with: "sig", clamp: Self.maxBackspaces)
        #expect(field.text == "sig", "undo dài bị clamp: '\(field.text)'")
    }
}
