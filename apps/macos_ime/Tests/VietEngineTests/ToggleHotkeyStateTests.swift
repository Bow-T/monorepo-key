// ToggleHotkeyStateTests.swift
// ----------------------------
// Regression: phím tắt bật/tắt CHỈ-MODIFIER (mặc định ⌃⇧) không được "chết" sau khi
// người dùng gõ chữ.
//
// BUG (đã sửa): `cancelShortcut = true` chạy VÔ ĐIỀU KIỆN ở mỗi keyDown và chỉ reset
// khi nhả HẾT modifier. Sau khi gõ bất kỳ chữ nào, cờ treo `true` -> lần nhấn ⌃⇧ kế
// tiếp không "lên đạn" -> KHÔNG toggle được cho tới khi nhả sạch tay.
//
// SỬA: chỉ set `cancelShortcut` khi keyDown xảy ra lúc `bothDown` đang lên đạn (gõ
// phím GIỮA tổ hợp ⌃⇧), không phải mọi keyDown.
//
// Test mô phỏng CHÍNH XÁC máy trạng thái `handleFlagsChanged` + điểm set cancel ở
// keyDown, chạy cả bản CŨ và MỚI để chứng minh.

import Testing
import Foundation

/// Máy trạng thái toggle chỉ-modifier, tách khỏi EventTapController để test thuần.
/// `legacyCancel`: true = tái hiện bug cũ (cancel vô điều kiện mỗi keyDown).
private struct ToggleMachine {
    let hotkey: Set<String>
    let legacyCancel: Bool

    private var bothDown = false
    private var cancelShortcut = false
    private var lastModifiers: Set<String> = []
    private(set) var toggleCount = 0

    init(hotkey: Set<String> = ["control", "shift"], legacyCancel: Bool) {
        self.hotkey = hotkey
        self.legacyCancel = legacyCancel
    }

    /// Một keyDown phím THẬT (chữ/số). Điểm set `cancelShortcut`.
    mutating func keyDown() {
        if legacyCancel {
            cancelShortcut = true                 // BUG cũ: vô điều kiện
        } else {
            if bothDown { cancelShortcut = true } // SỬA: chỉ khi đang lên đạn
        }
    }

    /// flagsChanged với tập modifier `active` (khớp handleFlagsChanged).
    mutating func flags(_ active: Set<String>) {
        if active == lastModifiers { return }
        lastModifiers = active
        if !active.isSubset(of: hotkey) {
            cancelShortcut = true
            bothDown = false
        } else if active == hotkey {
            if !cancelShortcut { bothDown = true }
        } else if bothDown {
            if !cancelShortcut { toggleCount += 1 }
            bothDown = false
        }
        if active.isEmpty { cancelShortcut = false }
    }

    /// Nhấn ⌃ rồi ⇧ rồi nhả ⇧ rồi nhả ⌃ — một cử chỉ toggle ⌃⇧ đầy đủ.
    mutating func pressAndReleaseCtrlShift() {
        flags(["control"])
        flags(["control", "shift"])
        flags(["control"])          // nhả ⇧ khi đang lên đạn -> toggle
        flags([])                   // nhả ⌃
    }
}

@Suite("Phím tắt toggle chỉ-modifier không chết sau khi gõ chữ")
struct ToggleHotkeyState {

    @Test("Toggle ăn ngay khi chưa gõ gì")
    func freshToggle() {
        var m = ToggleMachine(legacyCancel: false)
        m.pressAndReleaseCtrlShift()
        #expect(m.toggleCount == 1)
    }

    @Test("BẢN CŨ: toggle CHẾT sau khi gõ chữ (tái hiện bug)")
    func legacyDeadAfterTyping() {
        var m = ToggleMachine(legacyCancel: true)
        m.keyDown()                      // gõ một chữ (không có flagsChanged về rỗng sau đó)
        m.pressAndReleaseCtrlShift()     // cancelShortcut treo true -> không lên đạn
        #expect(m.toggleCount == 0, "bug cũ: đáng lẽ không toggle")
    }

    @Test("BẢN MỚI: toggle vẫn ăn sau khi gõ chữ")
    func fixedWorksAfterTyping() {
        var m = ToggleMachine(legacyCancel: false)
        m.keyDown()                      // gõ chữ (bothDown=false -> KHÔNG set cancel)
        m.pressAndReleaseCtrlShift()
        #expect(m.toggleCount == 1, "sau sửa: toggle phải ăn")
    }

    @Test("Gõ phím GIỮA tổ hợp ⌃⇧ vẫn HUỶ toggle (không kích hoạt nhầm)")
    func typingMidComboCancels() {
        var m = ToggleMachine(legacyCancel: false)
        m.flags(["control"])
        m.flags(["control", "shift"])    // lên đạn
        m.keyDown()                      // gõ ⌃⇧+phím -> huỷ
        m.flags(["control"])             // nhả ⇧ -> KHÔNG toggle
        m.flags([])
        #expect(m.toggleCount == 0)
    }

    @Test("Nhiều lần toggle liên tiếp xen gõ chữ đều ăn")
    func repeatedToggles() {
        var m = ToggleMachine(legacyCancel: false)
        m.keyDown(); m.keyDown()
        m.pressAndReleaseCtrlShift()     // 1
        m.keyDown()
        m.pressAndReleaseCtrlShift()     // 2
        #expect(m.toggleCount == 2)
    }
}
