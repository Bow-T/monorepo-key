// EventTapController.swift
// ------------------------
// Trái tim của app: tạo CGEvent tap để chặn phím TOÀN HỆ THỐNG, đưa qua engine
// tiếng Việt, rồi gõ thay kết quả vào ứng dụng đang focus.
//
// Luồng cho mỗi phím người dùng gõ:
//   1. Sự kiện keyDown tới callback.
//   2. Bỏ qua nếu là sự kiện do CHÍNH TA tạo (đánh dấu marker) -> tránh vòng lặp.
//   3. Bỏ qua nếu bộ gõ đang tắt, hoặc có phím điều khiển (Cmd/Ctrl/Option).
//   4. Dịch keyCode -> Character, đưa vào engine.
//   5. Nếu engine biến đổi chuỗi: "nuốt" phím gốc (trả nil) và gõ thay kết quả.
//      Nếu không: để phím đi qua bình thường.
//
// Dùng .cgSessionEventTap + .headInsertEventTap, gắn vào main run loop,
// và CƠ CHẾ PHỤC HỒI khi macOS tự tắt tap (timeout / user input) — phần này cực
// quan trọng, thiếu nó app sẽ "đột nhiên ngừng gõ được".

import CoreGraphics
import Foundation
import VietEngine

final class EventTapController {

    private var engine = VietEngine(method: .telex, toneStyle: .modern)
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Dịch keyCode -> ký tự theo layout bàn phím THẬT (Dvorak/Colemak/AZERTY...).
    private let layout = KeyboardLayout()

    // Cấu hình hiện hành (đồng bộ từ file settings do app UI ghi).
    private var method: InputMethod = .telex
    private var toneStyle: VietEngine.ToneStyle = .modern

    // Phím tắt bật/tắt — tuỳ biến từ UI. Mặc định ⌃⌥ Space.
    private var hotkeyKeyCode: Int64 = 49
    private var hotkeyModifiers: Set<String> = ["control", "option"]

    /// Bật/tắt bộ gõ (người dùng toggle qua menu / phím tắt).
    var enabled = true

    /// Báo cho AppDelegate khi phím tắt bật/tắt bộ gõ -> cập nhật icon menu bar.
    /// `@MainActor @Sendable` để gửi an toàn từ callback tap (ngoài isolation) về
    /// main mà không bị Swift 6 cảnh báo data race.
    var onToggle: (@MainActor @Sendable (Bool) -> Void)?

    /// "Số ký tự thô đã hiện trên màn hình cho âm tiết hiện tại" — để biết phải
    /// gửi bao nhiêu Backspace khi gõ thay. Mỗi phím chữ ta nuốt+thay sẽ +1.
    private var committedLength = 0

    // MARK: - Vòng đời tap

    /// Tạo và bật event tap. Trả false nếu thất bại (thường do thiếu quyền).
    @discardableResult
    func start() -> Bool {
        guard Permissions.ready() else {
            NSLog("[Tap] Chưa đủ quyền (Accessibility/Input Monitoring).")
            return false
        }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.tapDisabledByTimeout.rawValue) |
            (1 << CGEventType.tapDisabledByUserInput.rawValue)

        // refcon = con trỏ tới self, để callback C lấy lại được instance.
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.callback,
            userInfo: refcon
        ) else {
            NSLog("[Tap] tapCreate thất bại.")
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("[Tap] Đã bật event tap.")
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    /// Re-enable tap nếu macOS đã tắt nó. Gọi định kỳ từ health check.
    func ensureAlive() {
        guard let tap else { return }
        if !CGEvent.tapIsEnabled(tap: tap) {
            NSLog("[Tap] Tap bị tắt — bật lại.")
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    func setMethod(_ method: InputMethod) {
        self.method = method
        rebuildEngine()
    }

    /// Áp toàn bộ cấu hình đọc từ file (gọi lúc khởi động & mỗi khi UI lưu).
    func apply(config: BowConfig) {
        enabled = config.enabled
        method = config.method
        toneStyle = config.toneStyle
        hotkeyKeyCode = config.hotkeyKeyCode
        hotkeyModifiers = config.hotkeyModifiers
        rebuildEngine()
    }

    private func rebuildEngine() {
        engine = VietEngine(method: method, toneStyle: toneStyle)
        resetSyllable()
    }

    private func resetSyllable() {
        engine.clear()
        committedLength = 0
    }

    /// Sự kiện này có khớp phím tắt bật/tắt do người dùng đặt không?
    /// So khớp CHÍNH XÁC: đúng keyCode VÀ đúng tập modifier (không thừa, không
    /// thiếu) — để ⌃⌥ không kích hoạt nhầm khi đang giữ thêm ⌘.
    private func isToggleHotkey(_ event: CGEvent) -> Bool {
        guard event.getIntegerValueField(.keyboardEventKeycode) == hotkeyKeyCode else {
            return false
        }
        // Phím tắt phải có ít nhất 1 modifier (tránh nuốt nhầm phím thường).
        guard !hotkeyModifiers.isEmpty else { return false }

        let flags = event.flags
        let active: Set<String> = [
            flags.contains(.maskControl)   ? "control" : nil,
            flags.contains(.maskAlternate) ? "option"  : nil,
            flags.contains(.maskShift)     ? "shift"   : nil,
            flags.contains(.maskCommand)   ? "command" : nil,
        ].compactMap { $0 }.reduce(into: Set()) { $0.insert($1) }

        return active == hotkeyModifiers
    }

    // MARK: - Callback C (static, không bắt được self -> lấy qua refcon)

    private static let callback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let controller = Unmanaged<EventTapController>.fromOpaque(refcon).takeUnretainedValue()
        return controller.handle(type: type, event: event)
    }

    // MARK: - Xử lý sự kiện

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // PHỤC HỒI: macOS tự tắt tap -> bật lại ngay.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        // Bỏ qua sự kiện do CHÍNH TA tạo (chống vòng lặp vô tận).
        if event.getIntegerValueField(.eventSourceUserData) == KeyOutput.marker {
            return Unmanaged.passUnretained(event)
        }

        // PHÍM TẮT bật/tắt: ⌃⌥ Space (Control+Option+Space). Kiểm tra TRƯỚC cổng
        // `enabled` để vẫn bật lại được khi bộ gõ đang tắt. Nuốt phím (trả nil) để
        // Space không lọt vào ứng dụng.
        if type == .keyDown, isToggleHotkey(event) {
            enabled.toggle()
            resetSyllable()
            let now = enabled
            // Báo lên main mà KHÔNG bắt `self` (callback tap chạy ngoài isolation).
            // `onToggle` là @MainActor @Sendable -> gửi qua Task an toàn.
            if let notify = onToggle {
                Task { @MainActor in notify(now) }
            }
            return nil
        }

        guard enabled, type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        // Có Cmd/Ctrl/Option -> phím tắt, không phải gõ chữ. Reset & cho đi qua.
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            resetSyllable()
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // Backspace: lùi trong engine, đồng bộ committedLength.
        if keyCode == KeyCodeMap.delete {
            if let rebuilt = engine.backspace() {
                // Engine đã dựng lại âm tiết. Cho phím Backspace gốc đi qua (xoá 1 ký
                // tự trên màn), rồi để committedLength khớp độ dài mới.
                committedLength = rebuilt.count
                return Unmanaged.passUnretained(event)
            }
            // Engine rỗng -> Backspace bình thường.
            committedLength = 0
            return Unmanaged.passUnretained(event)
        }

        // Phím ngắt âm tiết (space, return, tab, esc) -> chốt từ.
        if KeyCodeMap.isWordBreak(keyCode) {
            resetSyllable()
            return Unmanaged.passUnretained(event)
        }

        // Dịch keyCode -> Character theo layout thật; lùi về bảng tĩnh QWERTY nếu
        // UCKeyTranslate không cho kết quả dùng được.
        let shift = flags.contains(.maskShift)
        guard let ch = layout.character(for: keyCode, shift: shift)
                ?? KeyCodeMap.character(for: keyCode, shift: shift) else {
            // Phím ta không xử lý -> chốt từ, cho đi qua.
            resetSyllable()
            return Unmanaged.passUnretained(event)
        }

        // Đưa vào engine.
        guard let rendered = engine.process(ch) else {
            // Engine bảo đây là ngắt từ -> cho đi qua.
            committedLength = 0
            return Unmanaged.passUnretained(event)
        }

        // Engine trả chuỗi âm tiết mới. Ta NUỐT phím gốc và gõ thay:
        //   - xoá committedLength ký tự cũ đã hiện
        //   - gõ chuỗi rendered mới
        let backspaces = committedLength
        committedLength = rendered.count

        DispatchQueue.main.async {
            KeyOutput.replace(backspaces: backspaces, with: rendered)
        }
        // Trả nil = "nuốt" phím gốc, không cho hệ thống nhận ký tự thô.
        return nil
    }
}
