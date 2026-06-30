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

import AppKit
import CoreGraphics
import Foundation
import VietEngine

final class EventTapController {

    private var engine = VietEngine(method: .telex, toneStyle: .modern)
    private var tap: CFMachPort?
    var isStarted: Bool { tap != nil }
    private var runLoopSource: CFRunLoopSource?

    // Dịch keyCode -> ký tự theo layout bàn phím THẬT (Dvorak/Colemak/AZERTY...).
    private let layout = KeyboardLayout()

    // Cấu hình hiện hành (đồng bộ từ file settings do app UI ghi).
    private var method: InputMethod = .telex
    var currentMethod: InputMethod { method }
    private var toneStyle: VietEngine.ToneStyle = .modern

    // Phím tắt bật/tắt — tuỳ biến từ UI. Mặc định ⌃⇧ (Control+Shift, chỉ-modifier).
    // keyCode 0 = chỉ-modifier: bắt qua flagsChanged (nhấn-rồi-nhả), không keyDown.
    private var hotkeyKeyCode: Int64 = 0
    private var hotkeyModifiers: Set<String> = ["control", "shift"]

    // Phím tắt mở lịch sử clipboard
    private var clipboardHistoryEnabled = true
    private var clipboardHistoryHotkeyKeyCode: Int64 = 9 // V
    private var clipboardHistoryHotkeyModifiers: Set<String> = ["control"]

    // Trạng thái để theo dõi phím tắt Control+Shift (chỉ phím bổ trợ, không kèm chữ)
    private var bothDown = false
    private var cancelShortcut = false

    // Monitor AppKit cho .flagsChanged — CGEvent tap KHÔNG nhận flagsChanged
    // chỉ-modifier một cách đáng tin (macOS không feed vào .cgSessionEventTap),
    // nên ta theo dõi modifier qua NSEvent global monitor song song.
    private var flagsMonitor: Any?
    private var lastModifiers: Set<String> = []

    /// Bật/tắt bộ gõ (người dùng toggle qua menu / phím tắt).
    var enabled = true

    /// Báo cho AppDelegate khi phím tắt bật/tắt bộ gõ -> cập nhật icon menu bar.
    /// `@MainActor @Sendable` để gửi an toàn từ callback tap (ngoài isolation) về
    /// main mà không bị Swift 6 cảnh báo data race.
    var onToggle: (@MainActor @Sendable (Bool) -> Void)?

    /// "Số ký tự thô đã hiện trên màn hình cho âm tiết hiện tại" — để biết phải
    /// gửi bao nhiêu Backspace khi gõ thay. Mỗi phím chữ ta nuốt+thay sẽ +1.
    private var committedLength = 0

    /// Phím thô (ASCII) của CẢ TỪ đang gõ — để khớp macro/gõ tắt. Reset khi ngắt từ.
    private var wordRawKeys: [Character] = []

    /// Chuỗi HIỂN THỊ hiện tại của từ (kết quả render cuối) — để tự khôi phục tiếng Anh.
    private var currentDisplay = ""

    /// Bật tự khôi phục tiếng Anh (đồng bộ từ config).
    private var autoRestoreEnglish = false

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
            // Click chuột: để RESET âm tiết. Nếu không, gõ dở "tieng" rồi click chỗ
            // khác và gõ tiếp sẽ khiến engine gửi nhầm Backspace -> xoá ký tự ở vị
            // trí mới. Bắt cả 3 nút để con trỏ nhảy chỗ nào cũng chốt từ.
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
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

        startFlagsMonitor()
        return true
    }

    /// NSEvent global monitor cho .flagsChanged — xử lý phím tắt chỉ-modifier
    /// (vd ⌃⇧) mà CGEvent tap không nhận được.
    private func startFlagsMonitor() {
        guard flagsMonitor == nil else { return }
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event.modifierFlags)
        }
    }

    /// Xử lý đổi modifier: phát hiện NHẤN ĐÚNG tập yêu cầu rồi NHẢ ra để toggle.
    /// Chỉ áp dụng khi phím tắt là chỉ-modifier (hotkeyKeyCode == 0).
    private func handleFlagsChanged(_ flags: NSEvent.ModifierFlags) {
        guard hotkeyKeyCode == 0, !hotkeyModifiers.isEmpty else { return }

        let active: Set<String> = [
            flags.contains(.control) ? "control" : nil,
            flags.contains(.option)  ? "option"  : nil,
            flags.contains(.shift)   ? "shift"   : nil,
            flags.contains(.command) ? "command" : nil,
        ].compactMap { $0 }.reduce(into: Set()) { $0.insert($1) }

        // Khử trùng lặp: cùng một thay đổi có thể đến từ CẢ tap LẪN monitor.
        // Nếu tập modifier y hệt lần xử lý trước -> bỏ qua (tránh toggle 2 lần).
        if active == lastModifiers { return }
        lastModifiers = active

        if !active.isSubset(of: hotkeyModifiers) {
            // Có modifier thừa -> huỷ.
            cancelShortcut = true
            bothDown = false
        } else if active == hotkeyModifiers {
            // Nhấn đúng tập -> lên đạn (nếu chưa bị huỷ trong session).
            if !cancelShortcut { bothDown = true }
        } else if bothDown {
            // Nhả bớt modifier khi đang lên đạn -> kích hoạt.
            if !cancelShortcut { toggleEnabledState() }
            bothDown = false
        }

        // Nhả hết -> reset cờ huỷ.
        if active.isEmpty { cancelShortcut = false }
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        runLoopSource = nil

        if let m = flagsMonitor {
            NSEvent.removeMonitor(m)
            flagsMonitor = nil
        }
        bothDown = false
        cancelShortcut = false
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

    // MARK: - Trạng thái cho menu (đọc + bật/tắt nhanh)

    /// Tự khôi phục tiếng Anh có đang bật không.
    var autoRestoreEnglishOn: Bool { autoRestoreEnglish }

    /// Gõ tắt (macro) có đang bật không.
    var macroOn: Bool { macroEnabled }

    /// Bật/tắt tự khôi phục tiếng Anh (gọi từ menu). Tái tạo engine.
    func setAutoRestoreEnglish(_ on: Bool) {
        autoRestoreEnglish = on
        rebuildEngine()
    }

    /// Bật/tắt gõ tắt (gọi từ menu). Tái tạo engine từ định nghĩa macro đã lưu.
    func setMacroEnabled(_ on: Bool) {
        macroEnabled = on
        rebuildMacroStore()
        rebuildEngine()
    }

    /// Áp toàn bộ cấu hình đọc từ file (gọi lúc khởi động & mỗi khi UI lưu).
    func apply(config: BowConfig) {
        enabled = config.enabled
        method = config.method
        toneStyle = config.toneStyle
        hotkeyKeyCode = config.hotkeyKeyCode
        hotkeyModifiers = config.hotkeyModifiers
        macroDefs = config.macros
        macroEnabled = config.macroEnabled
        rebuildMacroStore()
        autoRestoreEnglish = config.autoRestoreEnglish
        clipboardHistoryEnabled = config.clipboardHistoryEnabled
        clipboardHistoryHotkeyKeyCode = config.clipboardHistoryHotkeyKeyCode
        clipboardHistoryHotkeyModifiers = config.clipboardHistoryHotkeyModifiers
        rebuildEngine()
    }

    /// Kho macro hiện hành (nil = tắt gõ tắt). Tái tạo engine khi đổi.
    private var macroStore: MacroStore?

    /// Định nghĩa macro đã lưu (để bật lại sau khi tắt qua menu).
    private var macroDefs: [MacroDefinition] = []

    /// Cờ bật gõ tắt (tách khỏi việc có định nghĩa hay không).
    private var macroEnabled = true

    private func rebuildMacroStore() {
        macroStore = (macroEnabled && !macroDefs.isEmpty) ? MacroStore(macroDefs) : nil
    }

    private func rebuildEngine() {
        engine = VietEngine(method: method, toneStyle: toneStyle,
                            macros: macroStore, autoRestoreEnglish: autoRestoreEnglish)
        resetSyllable()
    }

    private func resetSyllable() {
        engine.clear()
        committedLength = 0
        wordRawKeys.removeAll()
        currentDisplay = ""
    }

    /// Sự kiện này có khớp phím tắt bật/tắt do người dùng đặt không?
    /// So khớp CHÍNH XÁC: đúng keyCode VÀ đúng tập modifier (không thừa, không
    /// thiếu) — để ⌃⌥ không kích hoạt nhầm khi đang giữ thêm ⌘.
    private func isToggleHotkey(_ event: CGEvent) -> Bool {
        // Phím tắt chỉ-modifier (keyCode 0) KHÔNG khớp qua keyDown — nó được xử lý
        // riêng ở nhánh flagsChanged. Tránh nhầm với phím 'A' (keyCode thật = 0).
        guard hotkeyKeyCode != 0 else { return false }
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

    private func isClipboardHistoryHotkey(_ event: CGEvent) -> Bool {
        guard clipboardHistoryHotkeyKeyCode != 0 else { return false }
        guard event.getIntegerValueField(.keyboardEventKeycode) == clipboardHistoryHotkeyKeyCode else {
            return false
        }
        guard !clipboardHistoryHotkeyModifiers.isEmpty else { return false }

        let flags = event.flags
        let active: Set<String> = [
            flags.contains(.maskControl)   ? "control" : nil,
            flags.contains(.maskAlternate) ? "option"  : nil,
            flags.contains(.maskShift)     ? "shift"   : nil,
            flags.contains(.maskCommand)   ? "command" : nil,
        ].compactMap { $0 }.reduce(into: Set()) { $0.insert($1) }

        return active == clipboardHistoryHotkeyModifiers
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

        // CLICK CHUỘT -> con trỏ nhảy chỗ khác -> chốt âm tiết đang gõ dở. Không
        // reset thì lần gõ kế tiếp sẽ gửi Backspace dựa trên committedLength cũ và
        // xoá nhầm ký tự ở vị trí mới. Cho event đi qua nguyên vẹn.
        if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
            cancelShortcut = true
            resetSyllable()
            return Unmanaged.passUnretained(event)
        }

        // PHÍM TẮT CHỈ-MODIFIER (vd ⌃⇧): xử lý cả ở đây (CGEvent tap) LẪN ở NSEvent
        // global monitor (`startFlagsMonitor`) — vì tuỳ macOS/ngữ cảnh, có khi tap
        // nhận flagsChanged, có khi chỉ monitor nhận. `handleFlagsChanged` tự
        // chống lặp qua so sánh `lastModifiers` nên gọi 2 đường không bị toggle 2 lần.
        if type == .flagsChanged {
            handleFlagsChanged(event.modifierFlagsAsNSEvent)
            return Unmanaged.passUnretained(event)
        }

        // PHÍM TẮT bật/tắt: ⌃⌥ Space (Control+Option+Space). Kiểm tra TRƯỚC cổng
        // `enabled` để vẫn bật lại được khi bộ gõ đang tắt. Nuốt phím (trả nil) để
        // Space không lọt vào ứng dụng.
        if type == .keyDown {
            cancelShortcut = true
            if clipboardHistoryEnabled && isClipboardHistoryHotkey(event) {
                // Kích hoạt hiển thị lịch sử clipboard trên main thread
                DispatchQueue.main.async {
                    AppDelegate.shared?.showClipboardHistory()
                }
                return nil
            }
            if isToggleHotkey(event) {
                toggleEnabledState()
                return nil
            }
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
            if !wordRawKeys.isEmpty { wordRawKeys.removeLast() }
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
            // GÕ TẮT: trước khi chốt, thử khớp macro theo phím thô của cả từ.
            // Chỉ bung với phím ngắt thực sự chèn ký tự (space/return/tab), không esc.
            let macroBreak = keyCode == KeyCodeMap.space
                || keyCode == KeyCodeMap.return || keyCode == KeyCodeMap.tab
            if macroBreak, let store = macroStore, !wordRawKeys.isEmpty,
               let content = store.expand(keyword: String(wordRawKeys)) {
                let backspaces = committedLength      // xoá từ khoá đã hiển thị
                let breakChar = KeyCodeMap.wordBreakCharacter(for: keyCode)
                resetSyllable()
                wordRawKeys.removeAll()
                DispatchQueue.main.async {
                    // Xoá từ khoá, gõ nội dung macro, rồi gõ chính phím ngắt từ.
                    KeyOutput.replace(backspaces: backspaces,
                                      with: content + String(breakChar))
                }
                return nil  // nuốt phím ngắt gốc (ta đã tự gõ nó)
            }

            // TỰ KHÔI PHỤC TIẾNG ANH: nếu từ bị biến dạng và không phải âm tiết
            // tiếng Việt hợp lệ -> gõ lại phím thô (vd "terminäl" -> "terminal").
            if autoRestoreEnglish, !wordRawKeys.isEmpty,
               let raw = VietEngine.englishRestoreKeys(
                   rawKeys: String(wordRawKeys), display: currentDisplay) {
                let backspaces = committedLength
                let breakChar = KeyCodeMap.wordBreakCharacter(for: keyCode)
                resetSyllable()
                DispatchQueue.main.async {
                    KeyOutput.replace(backspaces: backspaces, with: raw + String(breakChar))
                }
                return nil  // nuốt phím ngắt gốc (ta đã tự gõ nó kèm từ khôi phục)
            }

            resetSyllable()
            return Unmanaged.passUnretained(event)
        }

        // Dịch keyCode -> Character theo layout thật; lùi về bảng tĩnh QWERTY nếu
        // UCKeyTranslate không cho kết quả dùng được.
        //
        // CHỮ HOA = Shift HOẶC CapsLock. CapsLock chỉ đảo hoa/thường với CHỮ CÁI
        // (không tác động số/ký hiệu), và Shift+CapsLock thì triệt tiêu -> ra
        // thường. Với phím không phải chữ cái, chỉ Shift quyết định.
        // Thiếu xét CapsLock thì gõ khi bật Caps sẽ ra chữ thường ("VIỆT" -> "việt").
        let shiftDown = flags.contains(.maskShift)
        let capsOn = flags.contains(.maskAlphaShift)
        let isLetterKey = KeyCodeMap.character(for: keyCode, shift: false)?.isLetter ?? false
        let shift = isLetterKey ? (shiftDown != capsOn) : shiftDown
        guard let ch = layout.character(for: keyCode, shift: shift)
                ?? KeyCodeMap.character(for: keyCode, shift: shift) else {
            // Phím ta không xử lý -> chốt từ, cho đi qua.
            resetSyllable()
            return Unmanaged.passUnretained(event)
        }

        // Ghi phím thô của từ (cho macro + tự khôi phục tiếng Anh). Chỉ chữ/số ASCII.
        if (macroStore != nil || autoRestoreEnglish), ch.isLetter || ch.isNumber {
            wordRawKeys.append(ch)
        }

        // Đưa vào engine.
        guard let rendered = engine.process(ch) else {
            // Engine bảo đây là ngắt từ -> cho đi qua.
            committedLength = 0
            wordRawKeys.removeAll()
            currentDisplay = ""
            return Unmanaged.passUnretained(event)
        }

        // Engine trả chuỗi âm tiết mới. Ta NUỐT phím gốc và gõ thay:
        //   - xoá committedLength ký tự cũ đã hiện
        //   - gõ chuỗi rendered mới
        let backspaces = committedLength
        committedLength = rendered.count
        currentDisplay = rendered

        DispatchQueue.main.async {
            KeyOutput.replace(backspaces: backspaces, with: rendered)
        }
        // Trả nil = "nuốt" phím gốc, không cho hệ thống nhận ký tự thô.
        return nil
    }

    private func toggleEnabledState() {
        enabled.toggle()
        resetSyllable()
        let now = enabled
        if let notify = onToggle {
            Task { @MainActor in notify(now) }
        }
    }
}

private extension CGEvent {
    /// Quy đổi cờ modifier của CGEvent sang NSEvent.ModifierFlags để dùng chung
    /// một hàm xử lý phím tắt cho cả CGEvent tap lẫn NSEvent monitor.
    var modifierFlagsAsNSEvent: NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if flags.contains(.maskControl)   { result.insert(.control) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskShift)     { result.insert(.shift) }
        if flags.contains(.maskCommand)   { result.insert(.command) }
        return result
    }
}
