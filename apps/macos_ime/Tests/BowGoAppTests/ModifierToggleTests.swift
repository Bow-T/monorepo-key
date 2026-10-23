// ModifierToggleTests.swift
// -------------------------
// Phím tắt bật/tắt CHỈ-MODIFIER (vd ⇧⌘) trùng modifier với phím tắt HỆ THỐNG: chụp
// màn hình macOS ⇧⌘3/4/5 bị WindowServer ăn trước, phím 3/4/5 không tới event tap.
// Tap chỉ thấy "nhấn ⇧⌘ rồi nhả" -> tưởng người dùng bật/tắt -> mỗi lần chụp màn
// hình là tiếng Việt tắt. Bộ đếm keyDown phần cứng vẫn đếm phím đó -> huỷ toggle.

import AppKit
import Testing
@testable import BowGoApp

/// `@MainActor`: EventTapController dựng KeyboardLayout (API TIS chỉ chạy trên main).
@MainActor
@Suite("Phím tắt chỉ-modifier không bật/tắt nhầm khi chụp màn hình macOS")
struct ModifierToggleTests {

    /// Bộ đếm keyDown phần cứng giả.
    private final class Counter: @unchecked Sendable { var value: UInt32 = 100 }

    /// Bộ gõ đang BẬT, phím tắt ⇧⌘ chỉ-modifier.
    private func makeController(_ counter: Counter) -> EventTapController {
        let c = EventTapController()
        var cfg = BowConfig()
        cfg.hotkeyModifiers = ["command", "shift"]
        c.apply(config: cfg)
        c.hardwareKeyDownCount = { counter.value }
        return c
    }

    /// Nhấn ⌘, nhấn ⇧, (`between`), nhả ⇧, nhả ⌘.
    private func pressCommandShift(_ c: EventTapController, between: () -> Void = {}) {
        c.handleFlagsChanged([.command])
        c.handleFlagsChanged([.command, .shift])
        between()
        c.handleFlagsChanged([.command])
        c.handleFlagsChanged([])
    }

    @Test("Nhấn rồi nhả ⇧⌘ không kèm phím -> bật/tắt")
    func plainToggle() {
        let counter = Counter()
        let c = makeController(counter)
        pressCommandShift(c)
        #expect(c.enabled == false)
        pressCommandShift(c)
        #expect(c.enabled == true)
    }

    @Test("⇧⌘4 chụp màn hình (phím 4 không tới tap) -> KHÔNG tắt tiếng Việt")
    func systemScreenshotDoesNotToggle() {
        let counter = Counter()
        let c = makeController(counter)
        pressCommandShift(c) { counter.value += 1 }
        #expect(c.enabled == true)
    }

    @Test("Chụp màn hình xong, ⇧⌘ lần sau vẫn bật/tắt được")
    func toggleStillWorksAfterScreenshot() {
        let counter = Counter()
        let c = makeController(counter)
        pressCommandShift(c) { counter.value += 1 }
        pressCommandShift(c)
        #expect(c.enabled == false)
    }
}
