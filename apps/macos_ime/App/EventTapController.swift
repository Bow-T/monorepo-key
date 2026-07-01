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
//   5. Nếu engine biến đổi chuỗi: "nuốt" phím gốc (trả nil) và gõ thay kết quả
//      ĐỒNG BỘ qua proxy của tap (KeyOutput.replace) — không dùng async.
//      Nếu không: để phím đi qua bình thường.
//
// Dùng .cgSessionEventTap + .headInsertEventTap, gắn vào main run loop,
// và CƠ CHẾ PHỤC HỒI khi macOS tự tắt tap (timeout / user input) — phần này cực
// quan trọng, thiếu nó app sẽ "đột nhiên ngừng gõ được".
//
// VÌ SAO POST ĐỒNG BỘ QUA PROXY (không DispatchQueue.async)? Post bất đồng bộ qua
// .cghidEventTap khiến sự kiện gõ-thay tới SAU phím người dùng đã được ứng dụng xử
// lý. Ở ô có autocomplete xử lý phím tức thì (thanh địa chỉ trình duyệt, Spotlight),
// phím gốc kịp lọt qua trước rồi sự kiện async gõ thêm -> nhân đôi ký tự
// ("des" -> "ddé"). tapPostEvent(proxy) đẩy sự kiện trở lại ĐÚNG vị trí trong chuỗi
// tap, đồng bộ, giữ nguyên thứ tự.

import AppKit
import CoreGraphics
import Foundation
import ApplicationServices
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

    /// Bật tự sửa lỗi gõ nhanh (đồng bộ từ config). Xem `AutoCorrect`.
    private var autoCorrect = false

    /// Cặp (sai -> đúng) người dùng cấu hình (đồng bộ từ config).
    private var autoCorrectPairs: [AutoCorrectPair] = []

    /// Từ điển tự-sửa dựng từ `autoCorrectPairs` (dựng lại khi đổi cấu hình).
    private var autoCorrectDict = AutoCorrectDictionary(userPairs: [])

    // MARK: - Sửa lỗi gõ đôi trên ô autocomplete (trình duyệt Chromium / Spotlight)

    /// Bật mẹo "phá highlight autocomplete" (gửi ký tự rỗng trước khi Backspace).
    /// Mặc định bật — áp cho MỌI app trừ `browserFixExcludedApps`.
    private var fixBrowserDoubleType = true

    /// Bundle id các app KHÔNG áp mẹo (người dùng cấu hình nếu app hiếm chèn nhầm).
    private var browserFixExcludedApps: Set<String> = []

    // Cache cho check address bar để tránh AX tree query liên tục tốn CPU
    private var cachedAddressBarResult = false
    private var lastAddressBarCheckTime: CFTimeInterval = 0
    private let addressBarCacheTTL: CFTimeInterval = 0.5
    private var eventCounter: UInt = 0

    /// Hộp chứa bundle id app đang focus — CACHE, cập nhật qua NSWorkspace
    /// notification trên main (KHÔNG query trong callback tap vì tốn kém, chạy mỗi
    /// phím). Đọc từ callback (ngoài main) chỉ là đọc một String Optional -> chấp nhận
    /// được, cùng lắm trễ một lần đổi app (không ảnh hưởng đúng/sai gõ, chỉ ảnh hưởng
    /// có-phá-highlight-hay-không). Dùng CLASS BOX `@unchecked Sendable` để observer
    /// `@Sendable` capture được box (Sendable) thay vì `self` (non-Sendable).
    private final class FrontAppBox: @unchecked Sendable {
        var bundleID: String?
    }
    private let frontAppBox = FrontAppBox()
    private var frontAppBundleID: String? { frontAppBox.bundleID }

    /// Observer theo dõi app focus để cập nhật `frontAppBundleID`.
    private var frontAppObserver: NSObjectProtocol?

    /// CACHE "Spotlight có đang hiện không" — `CGWindowListCopyWindowInfo` liệt kê mọi
    /// cửa sổ nên KHÔNG gọi mỗi phím. Kiểm lại sau mỗi `spotlightTTL`. Spotlight không
    /// đổi `frontmostApplication` (nó là overlay) nên phải dò qua danh sách cửa sổ.
    private var spotlightVisible = false
    private var spotlightCheckedAt: CFTimeInterval = 0
    private let spotlightTTL: CFTimeInterval = 0.5

    private func isSpotlightVisible() -> Bool {
        let now = CACurrentMediaTime()
        if now - spotlightCheckedAt >= spotlightTTL {
            spotlightVisible = Self.querySpotlightVisible()
            spotlightCheckedAt = now
        }
        return spotlightVisible
    }

    /// Dò danh sách cửa sổ trên màn tìm cửa sổ do "Spotlight" sở hữu.
    private static func querySpotlightVisible() -> Bool {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]]
        else { return false }
        for w in windows {
            if let owner = w[kCGWindowOwnerName as String] as? String, owner == "Spotlight" {
                return true
            }
        }
        return false
    }

    private func isBrowserApp(_ bundleID: String) -> Bool {
        let browsers: Set<String> = [
            "com.apple.Safari",
            "com.apple.SafariTechnologyPreview",
            "com.apple.Safari.WebApp",
            "com.google.Chrome",
            "com.brave.Browser",
            "com.microsoft.edgemac",
            "com.microsoft.edgemac.Dev",
            "com.microsoft.edgemac.Beta",
            "com.microsoft.Edge",
            "com.microsoft.Edge.Dev",
            "org.chromium.Chromium",
            "com.vivaldi.Vivaldi",
            "com.operasoftware.Opera",
            "com.operasoftware.OperaGX",
            "com.coccoc.browser",
            "com.duckduckgo.macos.browser",
            "org.mozilla.firefox",
            "org.mozilla.firefoxdeveloperedition",
            "org.mozilla.nightly",
            "company.thebrowser.Browser",
            "com.kagi.orion",
            "com.kagi.orion.RC"
        ]
        if browsers.contains(bundleID) { return true }
        if bundleID.hasPrefix("com.google.Chrome.app.") || bundleID.hasPrefix("com.brave.Browser.app.") {
            return true
        }
        return false
    }

    private func isFocusedElementAddressBar() -> Bool {
        let now = CACurrentMediaTime()
        if now - lastAddressBarCheckTime < addressBarCacheTTL {
            return cachedAddressBarResult
        }

        var isAddressBar = false
        defer {
            cachedAddressBarResult = isAddressBar
            lastAddressBarCheckTime = now
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef else {
            return false
        }
        let element = focused as! AXUIElement

        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
              let role = roleRef as? String else {
            return false
        }

        // Dò ngược lên tối đa 12 cấp để tìm AXWebArea (vùng trang web)
        var current: AXUIElement? = element
        var foundWebArea = false
        for _ in 0..<12 {
            guard let curr = current else { break }
            var parentRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(curr, kAXParentAttribute as CFString, &parentRef) == .success,
               let parent = parentRef {
                let parentElement = parent as! AXUIElement
                var pRoleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(parentElement, kAXRoleAttribute as CFString, &pRoleRef) == .success,
                   let pRole = pRoleRef as? String,
                   pRole == "AXWebArea" {
                    foundWebArea = true
                    break
                }
                current = parentElement
            } else {
                break
            }
        }

        if foundWebArea {
            isAddressBar = false
        } else {
            isAddressBar = (role == "AXComboBox" || role == "AXTextField" || role == "AXSearchField")
        }

        return isAddressBar
    }

    private func checkAndRecover() {
        eventCounter &+= 1
        if eventCounter % 25 == 0 {
            ensureAlive()
        }
    }

    /// Chọn CÁCH XOÁ ký tự cũ khi gõ thay, theo ô nhập liệu đang focus:
    ///   • Spotlight đang hiện -> bôi đen bằng Shift+Mũi-tên-trái (ký tự rỗng không
    ///     phá được highlight Spotlight, dễ để lại vệt).
    ///   • App khác + bật fix + không bị loại trừ -> phá highlight bằng ký tự rỗng
    ///     (chống gõ đôi "ddo" ở address/search bar Chromium).
    ///   • Còn lại -> Backspace thường.
    /// Mẹo này vô hại ở ô THƯỜNG vì chỉ kích hoạt khi CÓ ký tự cần xoá (backspaces>0).
    private func eraseStrategy() -> KeyOutput.EraseStrategy {
        guard fixBrowserDoubleType else { return .backspace }
        if isSpotlightVisible() { return .selectionReplacement }
        if let app = frontAppBundleID {
            if app == "com.raycast.macos" || app == "com.runningwithcrayons.Alfred" {
                return .selectionReplacement
            }
            if browserFixExcludedApps.contains(app) { return .backspace }
            if isBrowserApp(app) {
                // Chỉ áp dụng mẹo phá highlight cho Address Bar.
                // Ở vùng nội dung trang web (AXWebArea), dùng Backspace thường để tránh lỗi mất chữ/kẹt ký tự.
                if isFocusedElementAddressBar() {
                    return .breakAutocompleteHighlight
                } else {
                    return .backspace
                }
            }
        }
        return .backspace
    }

    /// CACHE quyền Accessibility — để guard "mất quyền giữa chừng" mà KHÔNG gọi
    /// AXIsProcessTrusted() mỗi phím (tốn CPU). Kiểm tra lại sau mỗi `accessTTL`.
    private var accessOK = true
    private var accessCheckedAt: CFTimeInterval = 0
    private let accessTTL: CFTimeInterval = 2.0

    /// Còn quyền "gõ thay" (Accessibility) không? Có cache theo thời gian.
    /// Mất quyền giữa chừng -> ta KHÔNG được nuốt phím (sẽ gõ thay thất bại, người
    /// dùng mất phím hoàn toàn). Khi đó để mọi phím đi qua nguyên bản.
    private func accessibilityReady() -> Bool {
        let now = CACurrentMediaTime()
        if now - accessCheckedAt >= accessTTL {
            accessOK = Permissions.hasAccessibility()
            accessCheckedAt = now
        }
        return accessOK
    }

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
        startFrontAppTracking()
        return true
    }

    /// Theo dõi app đang focus để cache `frontAppBundleID` (dùng quyết định có phá
    /// highlight autocomplete hay không). Cập nhật trên main qua NSWorkspace — KHÔNG
    /// query trong callback tap.
    private func startFrontAppTracking() {
        guard frontAppObserver == nil else { return }
        frontAppBox.bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let box = frontAppBox   // capture box (Sendable), KHÔNG capture self.
        frontAppObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { note in
            let app = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
            box.bundleID = app?.bundleIdentifier
        }
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
        if let o = frontAppObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
            frontAppObserver = nil
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

    /// Tự sửa lỗi gõ nhanh có đang bật không.
    var autoCorrectOn: Bool { autoCorrect }

    /// Gõ tắt (macro) có đang bật không.
    var macroOn: Bool { macroEnabled }

    /// Bật/tắt tự khôi phục tiếng Anh (gọi từ menu). Tái tạo engine.
    func setAutoRestoreEnglish(_ on: Bool) {
        autoRestoreEnglish = on
        rebuildEngine()
    }

    /// Bật/tắt tự sửa lỗi gõ nhanh (gọi từ menu). Tái tạo engine.
    func setAutoCorrect(_ on: Bool) {
        autoCorrect = on
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
        autoCorrect = config.autoCorrect
        autoCorrectPairs = config.autoCorrectPairs
        rebuildAutoCorrectDict()
        fixBrowserDoubleType = config.fixBrowserDoubleType
        browserFixExcludedApps = config.browserFixExcludedApps
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

    /// Dựng lại từ điển tự-sửa từ cặp người dùng cấu hình.
    private func rebuildAutoCorrectDict() {
        let pairs = autoCorrectPairs.map { (wrong: $0.wrong, right: $0.right) }
        autoCorrectDict = AutoCorrectDictionary(userPairs: pairs)
    }

    private func rebuildEngine() {
        engine = VietEngine(method: method, toneStyle: toneStyle,
                            macros: macroStore, autoRestoreEnglish: autoRestoreEnglish,
                            autoCorrect: autoCorrect)
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

    private static let callback: CGEventTapCallBack = { proxy, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let controller = Unmanaged<EventTapController>.fromOpaque(refcon).takeUnretainedValue()
        return controller.handle(proxy: proxy, type: type, event: event)
    }

    // MARK: - Xử lý sự kiện

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .keyDown {
            checkAndRecover()
        }

        // PHỤC HỒI: macOS tự tắt tap -> bật lại ngay.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        // Bỏ qua sự kiện do CHÍNH TA tạo (chống vòng lặp vô tận).
        if event.getIntegerValueField(.eventSourceUserData) == KeyOutput.marker {
            return Unmanaged.passUnretained(event)
        }

        // GUARD MẤT QUYỀN: nếu Accessibility bị thu hồi giữa chừng, ta KHÔNG gõ thay
        // được nữa. Lúc này tuyệt đối không nuốt phím (return nil) — sẽ khiến người
        // dùng mất hẳn ký tự. Reset trạng thái dở dang và cho MỌI phím đi qua nguyên
        // bản, để gõ tiếng Anh/thao tác vẫn dùng được bình thường cho tới khi cấp lại
        // quyền.
        if (type == .keyDown || type == .keyUp) && !accessibilityReady() {
            if committedLength != 0 || !wordRawKeys.isEmpty { resetSyllable() }
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

        // Backspace: lùi trong engine, ĐỒNG BỘ màn hình = engine.
        if keyCode == KeyCodeMap.delete {
            if let rebuilt = engine.backspace() {
                // Engine đã dựng lại âm tiết (lùi tới khi hiển thị bớt 1 ký tự).
                // KHÔNG để phím Backspace gốc đi qua rồi giả định nó xoá đúng 1 ký tự:
                // engine có thể vừa nhảy nhiều hơn 1 ký tự hiển thị (ư=u+w, â=a+a...),
                // nên ta NUỐT phím gốc và TỰ đồng bộ — xoá `committedLength` ký tự cũ,
                // gõ lại `rebuilt`. Nhờ vậy màn hình luôn khớp engine -> hết nuốt chữ
                // khi gõ sai, xoá đi rồi gõ lại. `wordRawKeys` không còn khớp phần đã
                // xoá nên bỏ luôn (macro/khôi-phục-tiếng-Anh tính lại từ phím kế tiếp).
                let backspaces = committedLength
                committedLength = rebuilt.count
                currentDisplay = rebuilt
                wordRawKeys.removeAll()
                KeyOutput.replace(backspaces: backspaces, with: rebuilt, proxy: proxy,
                                  erase: eraseStrategy())
                return nil  // nuốt phím Backspace gốc (ta đã tự đồng bộ màn hình)
            }
            // Engine rỗng -> Backspace bình thường (để phím gốc xoá 1 ký tự).
            committedLength = 0
            currentDisplay = ""
            wordRawKeys.removeAll()
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
                // Xoá từ khoá, gõ nội dung macro, rồi gõ chính phím ngắt từ.
                KeyOutput.replace(backspaces: backspaces,
                                  with: content + String(breakChar), proxy: proxy,
                                  erase: eraseStrategy())
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
                KeyOutput.replace(backspaces: backspaces, with: raw + String(breakChar), proxy: proxy,
                                  erase: eraseStrategy())
                return nil  // nuốt phím ngắt gốc (ta đã tự gõ nó kèm từ khôi phục)
            }

            // TỰ SỬA LỖI GÕ NHANH: từ vừa gõ khớp một lỗi phổ biến hoặc dấu thanh đặt
            // sai vị trí -> thay bằng từ đúng (vd "giừo" -> "giờ", "nhièu" -> "nhiều").
            // Chạy SAU khôi-phục-tiếng-Anh để không tranh chỗ với từ tiếng Anh.
            if autoCorrect, !currentDisplay.isEmpty,
               let result = AutoCorrect.correctWord(currentDisplay, dictionary: autoCorrectDict) {
                let backspaces = committedLength
                let breakChar = KeyCodeMap.wordBreakCharacter(for: keyCode)
                resetSyllable()
                KeyOutput.replace(backspaces: backspaces,
                                  with: result.corrected + String(breakChar), proxy: proxy,
                                  erase: eraseStrategy())
                return nil  // nuốt phím ngắt gốc (ta đã tự gõ từ đúng kèm ký tự ngắt)
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

        // LUÔN NUỐT PHÍM GỐC RỒI GÕ THAY (đồng bộ qua proxy) — KỂ CẢ khi engine chỉ
        // nối thêm đúng ký tự gốc.
        //
        // VÌ SAO KHÔNG "cho phím đi qua tự nhiên khi không biến đổi"? Đó là một tối ưu
        // TỪNG có ở 1.0.1 và GÂY MẤT CHỮ: nếu ký tự trước (vd "a") đi qua TỰ NHIÊN,
        // thì phím kế ("s" -> "á") lại cần backspace CHÍNH ký tự tự nhiên đó bằng sự
        // kiện TỔNG HỢP. Ở nhiều app, ký tự tự nhiên chưa được commit vào buffer kịp
        // lúc backspace tổng hợp tới -> backspace xoá nhầm/không xoá, "á" chèn sai ->
        // cả cụm "as" biến mất ("em chịu á" -> "em chịu "). Trộn hai nguồn sự kiện
        // (tự nhiên + tổng hợp) trong cùng một từ phá vỡ bất biến "mọi ký tự đã hiện
        // đều do ta post, đúng thứ tự". Luôn gõ thay giữ bất biến đó -> hết mất chữ.
        //
        // (Việc chống GÕ ĐÔI ở URL bar/Spotlight đã do POST ĐỒNG BỘ QUA PROXY xử lý —
        // xem KeyOutput.replace — chứ KHÔNG phải nhờ nhánh "đi qua tự nhiên".)
        let backspaces = committedLength
        committedLength = rendered.count
        currentDisplay = rendered

        KeyOutput.replace(backspaces: backspaces, with: rendered, proxy: proxy,
                          erase: eraseStrategy())
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
