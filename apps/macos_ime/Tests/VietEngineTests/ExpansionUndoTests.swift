// ExpansionUndoTests.swift
// ------------------------
// Test máy trạng thái undo-sau-bung: chỉ khôi phục ở Backspace NGAY sau bung, và
// chỉ đúng một nhịp.

import Testing
import Foundation
@testable import VietEngine

@Suite("Undo bung gõ tắt")
struct ExpansionUndoTests {

    @Test("Backspace ngay sau bung -> khôi phục chuỗi gốc")
    func undoOnBackspace() {
        var u = ExpansionUndo()
        u.arm(shown: "Việt Nam ", original: "vn ")
        #expect(u.isArmed)
        let action = u.consumeBackspace()
        #expect(action == ExpansionUndo.Action(deleteCount: 9, restore: "vn "))
        #expect(!u.isArmed)   // đã tiêu thụ -> không còn vũ trang
    }

    @Test("Chỉ đúng MỘT nhịp: Backspace lần hai không undo nữa")
    func onlyOnce() {
        var u = ExpansionUndo()
        u.arm(shown: "😢", original: ":cry:")
        _ = u.consumeBackspace()
        #expect(u.consumeBackspace() == nil)
    }

    @Test("Phím khác (disarm) rồi Backspace -> không undo")
    func disarmCancels() {
        var u = ExpansionUndo()
        u.arm(shown: "Việt Nam ", original: "vn ")
        u.disarm()   // người dùng gõ phím khác
        #expect(!u.isArmed)
        #expect(u.consumeBackspace() == nil)
    }

    @Test("Không vũ trang khi shown == original (không có gì để undo)")
    func noopWhenSame() {
        var u = ExpansionUndo()
        u.arm(shown: "abc", original: "abc")
        #expect(!u.isArmed)
    }

    @Test("Không vũ trang khi shown rỗng")
    func noopWhenEmpty() {
        var u = ExpansionUndo()
        u.arm(shown: "", original: "x")
        #expect(!u.isArmed)
    }

    @Test("arm mới ghi đè arm cũ")
    func rearm() {
        var u = ExpansionUndo()
        u.arm(shown: "😢", original: ":cry:")
        u.arm(shown: "🔥", original: ":fire:")
        let action = u.consumeBackspace()
        #expect(action?.restore == ":fire:")
    }

    @Test("deleteCount đếm theo ký tự (emoji 1 ký tự)")
    func deleteCountByCharacter() {
        var u = ExpansionUndo()
        u.arm(shown: "🇻🇳", original: ":vn:")   // cờ VN là 1 grapheme
        let action = u.consumeBackspace()
        #expect(action?.deleteCount == "🇻🇳".count)
    }
}
