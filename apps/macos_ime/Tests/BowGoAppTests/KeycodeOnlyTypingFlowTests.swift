// KeycodeOnlyTypingFlowTests.swift
// --------------------------------
// Lái thẳng luồng phím của EventTapController (handleLocked) bằng CGEvent thật, với
// app đang focus là máy ảo / remote: phím gõ phải đi NGUYÊN BẢN (không gõ thay bằng
// virtualKey 0 -> "a"), còn phím tắt (chụp màn hình, bật/tắt) vẫn phải chạy.
// Đối chứng: cùng chuỗi phím ở app thường thì bộ gõ có gõ thay ("as" -> "á").

import AppKit
import Testing
@testable import BowGoApp

@MainActor
@Suite("Luồng phím ở máy ảo / remote: nhả phím, phím tắt vẫn chạy")
struct KeycodeOnlyTypingFlowTests {

    /// Proxy giả: các nhánh được test không post sự kiện nào qua proxy.
    private let proxy = OpaquePointer(bitPattern: 1)!

    private func makeController(frontApp: String, config: BowConfig = BowConfig()) -> EventTapController {
        let c = EventTapController()
        c.apply(config: config)
        c.accessFlag = BackgroundFlag(ttl: .infinity, initial: true) { true }
        c.hardwareKeyDownCount = { 100 }
        c.frontAppBox.bundleID = frontApp
        return c
    }

    private func key(_ code: CGKeyCode, _ flags: CGEventFlags = []) -> CGEvent {
        let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!
        e.flags = flags
        return e
    }

    private func modifiers(_ flags: CGEventFlags) -> CGEvent {
        let e = CGEvent(keyboardEventSource: nil, virtualKey: 56, keyDown: true)!
        e.type = .flagsChanged
        e.flags = flags
        return e
    }

    /// Gõ phím, trả về (sự kiện có đi nguyên bản không, chuỗi bộ gõ định gõ thay).
    private func type(_ c: EventTapController, _ code: CGKeyCode) -> (passed: Bool, output: String?) {
        let e = key(code)
        let result = c.handleLocked(proxy: proxy, type: .keyDown, event: e)
        return (result?.takeUnretainedValue() === e, c.pendingOutput?.text)
    }

    @Test("Máy ảo / remote: gõ 'a' 's' Space đều đi nguyên bản, không gõ thay",
          arguments: ["com.parallels.desktop.console", "com.vmware.fusion",
                      "com.philandro.anydesk", "com.microsoft.rdc.macos",
                      "com.teamviewer.TeamViewer"])
    func keysPassThrough(app: String) {
        let c = makeController(frontApp: app)
        for code: CGKeyCode in [0, 1, 49] {   // a, s, Space
            let r = type(c, code)
            #expect(r.passed, "\(app) keyCode \(code)")
            #expect(r.output == nil, "\(app) keyCode \(code)")
        }
    }

    @Test("Đối chứng app thường: 'a' 's' -> bộ gõ gõ thay 'á'")
    func normalAppStillReplaces() {
        let c = makeController(frontApp: "com.apple.TextEdit")
        _ = type(c, 0)
        let r = type(c, 1)
        #expect(!r.passed)
        #expect(r.output == "á")
    }

    @Test("Máy ảo: phím tắt chụp màn hình ⌃⇧S vẫn được bắt (nuốt phím)")
    func screenshotHotkeyInVM() {
        let c = makeController(frontApp: "com.parallels.desktop.console")
        let result = c.handleLocked(proxy: proxy, type: .keyDown,
                                    event: key(1, [.maskControl, .maskShift]))
        #expect(result == nil)
    }

    @Test("Máy ảo: phím tắt bật/tắt có phím (⌃⌥Space) vẫn tắt được tiếng Việt")
    func keyedToggleInVM() {
        var cfg = BowConfig()
        cfg.hotkeyKeyCode = 49
        cfg.hotkeyModifiers = ["control", "option"]
        let c = makeController(frontApp: "com.vmware.fusion", config: cfg)
        #expect(c.enabled)
        let result = c.handleLocked(proxy: proxy, type: .keyDown,
                                    event: key(49, [.maskControl, .maskAlternate]))
        #expect(result == nil)
        #expect(!c.enabled)
    }

    @Test("Máy ảo: phím tắt chỉ-modifier ⌃⇧ (mặc định) vẫn bật/tắt")
    func modifierToggleInVM() {
        let c = makeController(frontApp: "com.philandro.anydesk")
        #expect(c.enabled)
        for f: CGEventFlags in [[.maskControl], [.maskControl, .maskShift], [.maskControl], []] {
            _ = c.handleLocked(proxy: proxy, type: .flagsChanged, event: modifiers(f))
        }
        #expect(!c.enabled)
    }
}
