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
// Dùng .cgSessionEventTap + .headInsertEventTap, gắn vào runloop của MỘT THREAD
// RIÊNG (KHÔNG phải main), và CƠ CHẾ PHỤC HỒI khi macOS tự tắt tap (timeout / user
// input) — phần này cực quan trọng, thiếu nó app sẽ "đột nhiên ngừng gõ được".
//
// VÌ SAO THREAD RIÊNG? macOS đo thời gian callback trả lời: quá ngưỡng là nó TẮT
// TAP. Khi tap nằm trên main runloop, mọi việc UI (mở menu, overlay chụp màn hình,
// gọi AI, timer ghi file, poll clipboard) đều chen vào giữa đường nhận phím -> phím
// và phím tắt "lag, bấm không ăn". Hệ quả kéo theo: mọi thứ chậm/không đoán trước
// được (AX query, CGWindowList, AXIsProcessTrusted) đều bị đẩy ra khỏi callback,
// chạy ngầm và chỉ để lại một phép ĐỌC BIẾN trên đường phím (xem `BackgroundFlag`).
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

/// `@unchecked Sendable`: callback tap chạy trên THREAD RIÊNG còn cấu hình/menu đến
/// từ main, nên trạng thái được bảo vệ thủ công bằng `stateLock` (xem bên dưới).
final class EventTapController: @unchecked Sendable {

    private var engine = VietEngine(method: .telex, toneStyle: .modern)
    private var tap: CFMachPort?
    var isStarted: Bool { locked { tap != nil } }
    private var runLoopSource: CFRunLoopSource?

    /// THREAD RIÊNG chạy event tap — KHÔNG dùng main runloop nữa.
    ///
    /// VÌ SAO? Trước đây tap gắn vào `CFRunLoopGetMain()`, nên MỌI việc trên main
    /// (mở menu/overlay chụp màn hình, gọi AI, timer ghi status.json, poll clipboard)
    /// đều xen vào giữa đường nhận phím. Callback trễ quá ngưỡng là macOS TỰ TẮT TAP
    /// -> phím tắt bấm không ăn cho tới lần phục hồi kế tiếp. Thread này chỉ làm đúng
    /// một việc: nhận phím và trả lời ngay, nên UI có bận cũng không bóp cổ bộ gõ.
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?

    /// Khoá bảo vệ TOÀN BỘ trạng thái. Trước đây tap chạy trên main nên mọi thứ tuần
    /// tự tự nhiên; giờ callback ở thread riêng còn cấu hình/menu tới từ main -> phải
    /// khoá. RECURSIVE vì `handle()` (đã giữ khoá) còn gọi tiếp các hàm tự khoá.
    private let stateLock = NSRecursiveLock()

    /// Chạy một khối dưới `stateLock`.
    private func locked<T>(_ body: () -> T) -> T {
        stateLock.lock(); defer { stateLock.unlock() }
        return body()
    }

    // Dịch keyCode -> ký tự theo layout bàn phím THẬT (Dvorak/Colemak/AZERTY...).
    private let layout = KeyboardLayout()

    // Cấu hình hiện hành (đồng bộ từ file settings do app UI ghi).
    private var method: InputMethod = .telex
    var currentMethod: InputMethod { locked { method } }
    private var toneStyle: VietEngine.ToneStyle = .modern

    // Phím tắt bật/tắt — tuỳ biến từ UI. Mặc định ⌃⇧ (Control+Shift, chỉ-modifier).
    // keyCode 0 = chỉ-modifier: bắt qua flagsChanged (nhấn-rồi-nhả), không keyDown.
    private var hotkeyKeyCode: Int64 = 0
    private var hotkeyModifiers: Set<String> = ["control", "shift"]

    // Phím tắt mở lịch sử clipboard
    private var clipboardHistoryEnabled = true
    private var clipboardHistoryHotkeyKeyCode: Int64 = 9 // V
    private var clipboardHistoryHotkeyModifiers: Set<String> = ["control"]

    // Phím tắt chụp màn hình (chọn vùng)
    private var screenshotEnabled = true
    private var screenshotHotkeyKeyCode: Int64 = 1 // S
    private var screenshotHotkeyModifiers: Set<String> = ["control", "shift"]

    // Phím tắt biến đổi văn bản đã bôi đen (popup chọn thao tác)
    private var textTransformEnabled = true
    private var textTransformHotkeyKeyCode: Int64 = 17 // T
    private var textTransformHotkeyModifiers: Set<String> = ["control", "shift"]

    // Phím tắt bảng gõ nhanh ký tự & emoji (picker)
    private var symbolPickerEnabled = true
    private var symbolPickerHotkeyKeyCode: Int64 = 40 // K
    private var symbolPickerHotkeyModifiers: Set<String> = ["control", "shift"]

    // Phím tắt bảng dán sticker (emoji ảnh)
    private var stickerPickerEnabled = true
    private var stickerPickerHotkeyKeyCode: Int64 = 38 // J
    private var stickerPickerHotkeyModifiers: Set<String> = ["control", "shift"]

    // Phím tắt đếm từ/ký tự vùng bôi đen
    private var countSelectionEnabled = true
    private var countSelectionHotkeyKeyCode: Int64 = 8 // C
    private var countSelectionHotkeyModifiers: Set<String> = ["control", "shift"]

    // Phím tắt trợ lý AI (mở popup chọn thao tác trên vùng bôi đen)
    private var aiEnabled = false
    private var aiHotkeyKeyCode: Int64 = 5 // G
    private var aiHotkeyModifiers: Set<String> = ["control", "shift"]

    // Gõ tắt emoji theo shortcode (:cry: -> 😢). Bung khi gõ dấu ':' đóng.
    private var emojiShortcutsEnabled = false
    /// Máy trạng thái theo dõi shortcode đang gõ dở (logic thuần, test được ở
    /// EmojiShortcodesTests). Bộ điều khiển chỉ lo đồng bộ màn hình.
    private var emojiMatcher = EmojiShortcodeMatcher()

    // Undo ngay sau khi bung (Backspace lập tức -> khôi phục chuỗi gốc).
    private var undoExpansionEnabled = true
    private var expansionUndo = ExpansionUndo()

    // Trạng thái để theo dõi phím tắt Control+Shift (chỉ phím bổ trợ, không kèm chữ)
    private var bothDown = false
    private var cancelShortcut = false

    // Monitor AppKit cho .flagsChanged — CGEvent tap KHÔNG nhận flagsChanged
    // chỉ-modifier một cách đáng tin (macOS không feed vào .cgSessionEventTap),
    // nên ta theo dõi modifier qua NSEvent global monitor song song.
    private var flagsMonitor: Any?
    private var lastModifiers: Set<String> = []

    /// Tap có THẬT SỰ nhận được flagsChanged trên máy này không?
    ///
    /// Nếu CÓ thì bỏ hẳn NSEvent monitor: nó đi qua main runloop nên LUÔN tới trễ
    /// hơn tap, và khi main bận nó phát lại nguyên chuỗi modifier mà tap đã xử lý
    /// xong -> toggle lần thứ hai -> bật rồi tắt ngay, người dùng thấy "ấn không ăn".
    /// Monitor chỉ còn là đường dự phòng cho máy mà tap không được feed flagsChanged.
    private var tapDeliversFlags = false

    /// Bật/tắt bộ gõ (người dùng toggle qua menu / phím tắt). Đọc/ghi từ main lẫn
    /// thread tap nên đi qua khoá.
    private var _enabled = true
    var enabled: Bool {
        get { locked { _enabled } }
        set { locked { _enabled = newValue } }
    }

    /// Báo cho AppDelegate khi phím tắt bật/tắt bộ gõ -> cập nhật icon menu bar.
    /// `@MainActor @Sendable` để gửi an toàn từ callback tap (ngoài isolation) về
    /// main mà không bị Swift 6 cảnh báo data race.
    /// Gán từ main, đọc từ thread tap -> đi qua khoá như mọi trạng thái khác.
    private var _onToggle: (@MainActor @Sendable (Bool) -> Void)?
    var onToggle: (@MainActor @Sendable (Bool) -> Void)? {
        get { locked { _onToggle } }
        set { locked { _onToggle = newValue } }
    }

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

    /// "Ô đang focus có phải address bar không" — LÀM MỚI NGẦM (xem `BackgroundFlag`).
    /// AX query xuyên tiến trình có thể mất hàng chục ms khi app đích bận
    /// (Chrome/Electron), tuyệt đối không được chạy trong callback tap.
    private let addressBarFlag = BackgroundFlag(ttl: 0.5) {
        EventTapController.queryFocusedElementIsAddressBar()
    }

    /// Chờ app đích xử lý xong click/⌘L (đổi focus) rồi mới dò lại ô focus.
    private static let focusSettleDelay: TimeInterval = 0.08

    /// Lần cuối kiểm tra tap còn sống (xem `checkAndRecover`).
    private var lastAliveCheckAt: CFTimeInterval = 0

    /// Hộp chứa bundle id app đang focus — CACHE, cập nhật qua NSWorkspace
    /// notification trên main (KHÔNG query trong callback tap vì tốn kém, chạy mỗi
    /// phím). Cùng lắm trễ một lần đổi app (không ảnh hưởng đúng/sai gõ, chỉ ảnh
    /// hưởng có-phá-highlight-hay-không). Dùng CLASS BOX `@unchecked Sendable` để observer
    /// `@Sendable` capture được box (Sendable) thay vì `self` (non-Sendable).
    private final class FrontAppBox: @unchecked Sendable {
        // Ghi trên main, đọc trên thread tap: String không đọc/ghi nguyên tử được
        // (đọc trúng lúc đang ghi = crash hiếm), nên phải qua khoá.
        private let lock = NSLock()
        private var _bundleID: String?
        var bundleID: String? {
            get { lock.lock(); defer { lock.unlock() }; return _bundleID }
            set { lock.lock(); _bundleID = newValue; lock.unlock() }
        }
    }
    private let frontAppBox = FrontAppBox()
    private var frontAppBundleID: String? { frontAppBox.bundleID }

    /// Observer theo dõi app focus để cập nhật `frontAppBundleID`.
    private var frontAppObserver: NSObjectProtocol?

    /// CACHE "Spotlight có đang hiện không" — `CGWindowListCopyWindowInfo` liệt kê mọi
    /// cửa sổ nên KHÔNG gọi trong callback tap; làm mới NGẦM mỗi 0.5s. Spotlight không
    /// đổi `frontmostApplication` (nó là overlay) nên phải dò qua danh sách cửa sổ.
    private let spotlightFlag = BackgroundFlag(ttl: 0.5) {
        EventTapController.querySpotlightVisible()
    }

    private func isSpotlightVisible() -> Bool { spotlightFlag.get() }

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

    /// Cửa sổ này có phải MÁY ẢO / SIMULATOR không (Parallels/VMware/UTM/VirtualBox/
    /// iOS Simulator)? Các app này xử lý sự kiện phím khác app native: gõ cả cụm Unicode
    /// một lần quá nhanh -> guest OS rớt ký tự (mất chữ). Với chúng ta gõ TỪNG KÝ TỰ +
    /// delay + precomposed (xem `eraseStrategy` -> `.stepByStep`). Khớp theo TIỀN TỐ
    /// bundle id để bắt mọi biến thể phiên bản.
    private func isVirtualMachineApp(_ bundleID: String) -> Bool {
        let prefixes = [
            "com.parallels.",              // Parallels Desktop
            "com.vmware.fusion",           // VMware Fusion
            "com.utmapp.",                 // UTM (App Store)
            "com.osy.UTM",                 // UTM (bản ngoài App Store)
            "org.virtualbox.",             // VirtualBox
        ]
        return prefixes.contains { bundleID.hasPrefix($0) }
    }

    /// App chỉ đọc MÃ PHÍM của sự kiện, bỏ qua chuỗi Unicode kèm theo — mọi ký tự ta
    /// gõ thay (gửi với keyCode 0 = phím A) đều thành "a". Ký tự có dấu cũng không có
    /// mã phím nào để gửi, nên ở đây bộ gõ NHẢ TAY: phím đi nguyên bản, tiếng Việt
    /// gõ bằng bàn phím Tiếng Việt của chính thiết bị ảo.
    static func passesKeysThrough(_ bundleID: String) -> Bool {
        bundleID == "com.apple.iphonesimulator"   // iOS Simulator (Xcode)
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

    private func isFocusedElementAddressBar() -> Bool { addressBarFlag.get() }

    /// Dò cây AX xem ô đang focus có phải thanh địa chỉ / ô tìm kiếm không.
    /// CHẠY TRÊN QUEUE NỀN (qua `BackgroundFlag`) — KHÔNG gọi từ callback tap.
    private static func queryFocusedElementIsAddressBar() -> Bool {
        var isAddressBar = false

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

    /// Kiểm tra tap còn sống theo THỜI GIAN, không theo số phím.
    ///
    /// Bản cũ chỉ gọi `ensureAlive()` mỗi 25 keyDown — nhưng khi tap đã bị macOS tắt
    /// thì KHÔNG còn keyDown nào tới nữa, nhánh này chết hẳn và người dùng phải chờ
    /// health check ở AppDelegate. Theo thời gian thì mỗi phím đầu tiên sau một giây
    /// im lặng đều là một lần tự kiểm.
    private func checkAndRecover() {
        let now = CACurrentMediaTime()
        guard now - lastAliveCheckAt >= 1.0 else { return }
        lastAliveCheckAt = now
        ensureAlive()
    }

    /// Chọn CÁCH XOÁ ký tự cũ khi gõ thay, theo ô nhập liệu đang focus:
    ///   • MÁY ẢO / SIMULATOR -> gõ lại TỪNG KÝ TỰ + delay (chống rớt ký tự khi gõ cả
    ///     cụm quá nhanh). Ưu tiên tuyệt đối.
    ///   • Spotlight đang hiện -> bôi đen bằng Shift+Mũi-tên-trái (ký tự rỗng không
    ///     phá được highlight Spotlight, dễ để lại vệt).
    ///   • App khác + bật fix + không bị loại trừ -> phá highlight bằng ký tự rỗng
    ///     (chống gõ đôi "ddo" ở address/search bar Chromium).
    ///   • Còn lại -> Backspace thường.
    /// Mẹo này vô hại ở ô THƯỜNG vì chỉ kích hoạt khi CÓ ký tự cần xoá (backspaces>0).
    private func eraseStrategy() -> KeyOutput.EraseStrategy {
        // MÁY ẢO: kiểm TRƯỚC mọi thứ (kể cả `fixBrowserDoubleType`, không liên quan) —
        // đây là điều kiện gõ được-hay-không, không phải một mẹo tuỳ chọn.
        if let app = frontAppBundleID, isVirtualMachineApp(app) {
            return .stepByStep
        }
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

    /// CACHE quyền Accessibility — `AXIsProcessTrusted()` là một chuyến IPC sang
    /// tccd, không được nằm trên đường phím. Làm mới NGẦM mỗi 2 giây; khởi đầu là
    /// `true` vì tap chỉ được bật khi đã đủ quyền.
    private let accessFlag = BackgroundFlag(ttl: 2.0, initial: true) {
        Permissions.hasAccessibility()
    }

    /// Còn quyền "gõ thay" (Accessibility) không? Có cache theo thời gian.
    /// Mất quyền giữa chừng -> ta KHÔNG được nuốt phím (sẽ gõ thay thất bại, người
    /// dùng mất phím hoàn toàn). Khi đó để mọi phím đi qua nguyên bản.
    private func accessibilityReady() -> Bool { accessFlag.get() }

    // MARK: - Vòng đời tap

    /// Tạo và bật event tap. Trả false nếu thất bại (thường do thiếu quyền).
    @discardableResult
    func start() -> Bool {
        guard Permissions.ready() else {
            NSLog("[Tap] Chưa đủ quyền (Accessibility/Input Monitoring).")
            return false
        }

        guard tapThread == nil else { return isStarted }

        // Dựng tap NGAY TRÊN thread riêng: CFMachPort phải gắn vào runloop của chính
        // thread sẽ chạy nó. Đợi thread báo kết quả (rất nhanh) để `start()` vẫn trả
        // đúng true/false cho caller như trước.
        let ready = DispatchSemaphore(value: 0)
        let result = BoolBox()
        let thread = Thread { [weak self] in
            guard let self else { ready.signal(); return }
            self.runTapThread(result: result, ready: ready)
        }
        thread.name = "BowGo.EventTap"
        thread.qualityOfService = .userInteractive
        tapThread = thread
        thread.start()
        _ = ready.wait(timeout: .now() + 5)

        guard result.value else {
            tapThread = nil
            return false
        }

        // Nạp sẵn hai cờ dò nền để phím đầu tiên đã có giá trị đúng.
        addressBarFlag.refresh()
        spotlightFlag.refresh()
        startFlagsMonitor()
        startFrontAppTracking()
        return true
    }

    /// Thân của thread tap: tạo tap, gắn vào runloop CỦA THREAD NÀY, rồi chạy vòng
    /// lặp cho tới khi `stop()` gọi `CFRunLoopStop`.
    private func runTapThread(result: BoolBox, ready: DispatchSemaphore) {
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
            ready.signal()
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let runLoop = CFRunLoopGetCurrent()
        locked {
            self.tap = tap
            self.runLoopSource = source
            self.tapRunLoop = runLoop
        }
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("[Tap] Đã bật event tap trên thread riêng.")
        result.value = true
        ready.signal()

        CFRunLoopRun()   // chạy tới khi `stop()` gọi CFRunLoopStop

        // Runloop đã dừng -> dọn tài nguyên cục bộ. Các property đã được `stop()` xoá.
        CGEvent.tapEnable(tap: tap, enable: false)
        CFRunLoopRemoveSource(runLoop, source, .commonModes)
        CFMachPortInvalidate(tap)
        NSLog("[Tap] Thread event tap đã dừng.")
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
        ) { [weak self] note in
            let app = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
            box.bundleID = app?.bundleIdentifier
            // Đổi app -> ô focus chắc chắn khác: làm mới ngay cho kịp phím đầu tiên.
            self?.addressBarFlag.refresh()
        }
    }

    /// NSEvent global monitor cho .flagsChanged — đường DỰ PHÒNG cho phím tắt
    /// chỉ-modifier (vd ⌃⇧) trên máy/ngữ cảnh mà CGEvent tap không được feed
    /// flagsChanged. Hễ tap nhận được thì monitor tự im (xem `tapDeliversFlags`).
    private func startFlagsMonitor() {
        guard flagsMonitor == nil else { return }
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return }
            // Tap đã nhận được flagsChanged -> monitor là thừa và còn CÓ HẠI: nó tới
            // trễ hơn tap (qua main runloop), khi main bận sẽ phát lại cả chuỗi
            // modifier đã xử lý -> toggle lần hai -> "ấn phím tắt không ăn".
            if self.locked({ self.tapDeliversFlags }) { return }
            self.handleFlagsChanged(event.modifierFlags)
        }
    }

    /// Xử lý đổi modifier: phát hiện NHẤN ĐÚNG tập yêu cầu rồi NHẢ ra để toggle.
    /// Chỉ áp dụng khi phím tắt là chỉ-modifier (hotkeyKeyCode == 0).
    private func handleFlagsChanged(_ flags: NSEvent.ModifierFlags) {
        stateLock.lock(); defer { stateLock.unlock() }
        // Đang thu phím tắt trong app Cài đặt -> đừng toggle, để ô thu bắt được ⌃⇧.
        if isHotkeyRecording() {
            bothDown = false
            cancelShortcut = false
            lastModifiers = []
            return
        }
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
        // Nhả property TRƯỚC (isStarted về false ngay), rồi mới ra lệnh cho thread tap
        // dừng runloop — chính nó sẽ gỡ source và invalidate port.
        let (port, runLoop): (CFMachPort?, CFRunLoop?) = locked {
            let p = tap
            let r = tapRunLoop
            tap = nil
            runLoopSource = nil
            tapRunLoop = nil
            return (p, r)
        }
        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        if let runLoop { CFRunLoopStop(runLoop) }   // an toàn khi gọi từ thread khác
        tapThread = nil

        if let m = flagsMonitor {
            NSEvent.removeMonitor(m)
            flagsMonitor = nil
        }
        if let o = frontAppObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
            frontAppObserver = nil
        }
        locked {
            bothDown = false
            cancelShortcut = false
        }
    }

    /// Re-enable tap nếu macOS đã tắt nó. Gọi định kỳ từ health check.
    func ensureAlive() {
        guard let tap = locked({ self.tap }) else { return }
        if !CGEvent.tapIsEnabled(tap: tap) {
            NSLog("[Tap] Tap bị tắt — bật lại.")
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    func setMethod(_ method: InputMethod) {
        stateLock.lock(); defer { stateLock.unlock() }
        self.method = method
        rebuildEngine()
    }

    // MARK: - Trạng thái cho menu (đọc + bật/tắt nhanh)

    /// Tự khôi phục tiếng Anh có đang bật không.
    var autoRestoreEnglishOn: Bool { locked { autoRestoreEnglish } }

    /// Tự sửa lỗi gõ nhanh có đang bật không.
    var autoCorrectOn: Bool { locked { autoCorrect } }

    /// Gõ tắt (macro) có đang bật không.
    var macroOn: Bool { locked { macroEnabled } }

    /// Gõ tắt emoji có đang bật không.
    var emojiShortcutsOn: Bool { locked { emojiShortcutsEnabled } }

    /// Bật/tắt tự khôi phục tiếng Anh (gọi từ menu). Tái tạo engine.
    func setAutoRestoreEnglish(_ on: Bool) {
        stateLock.lock(); defer { stateLock.unlock() }
        autoRestoreEnglish = on
        rebuildEngine()
    }

    /// Bật/tắt tự sửa lỗi gõ nhanh (gọi từ menu). Tái tạo engine.
    func setAutoCorrect(_ on: Bool) {
        stateLock.lock(); defer { stateLock.unlock() }
        autoCorrect = on
        rebuildEngine()
    }

    /// Bật/tắt gõ tắt (gọi từ menu). Tái tạo engine từ định nghĩa macro đã lưu.
    func setMacroEnabled(_ on: Bool) {
        stateLock.lock(); defer { stateLock.unlock() }
        macroEnabled = on
        rebuildMacroStore()
        rebuildEngine()
    }

    /// Bật/tắt gõ tắt emoji (gọi từ menu).
    func setEmojiShortcuts(_ on: Bool) {
        stateLock.lock(); defer { stateLock.unlock() }
        emojiShortcutsEnabled = on
        if !on { emojiMatcher.reset() }
    }

    /// Undo-sau-bung có đang bật không.
    var undoExpansionOn: Bool { locked { undoExpansionEnabled } }

    /// Bật/tắt undo-sau-bung (gọi từ menu).
    func setUndoExpansion(_ on: Bool) {
        stateLock.lock(); defer { stateLock.unlock() }
        undoExpansionEnabled = on
        if !on { expansionUndo.disarm() }
    }

    /// Áp toàn bộ cấu hình đọc từ file (gọi lúc khởi động & mỗi khi UI lưu).
    func apply(config: BowConfig) {
        stateLock.lock(); defer { stateLock.unlock() }
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
        screenshotEnabled = config.screenshotEnabled
        screenshotHotkeyKeyCode = config.screenshotHotkeyKeyCode
        screenshotHotkeyModifiers = config.screenshotHotkeyModifiers
        textTransformEnabled = config.textTransformEnabled
        textTransformHotkeyKeyCode = config.textTransformHotkeyKeyCode
        textTransformHotkeyModifiers = config.textTransformHotkeyModifiers
        symbolPickerEnabled = config.symbolPickerEnabled
        symbolPickerHotkeyKeyCode = config.symbolPickerHotkeyKeyCode
        symbolPickerHotkeyModifiers = config.symbolPickerHotkeyModifiers
        stickerPickerEnabled = config.stickerPickerEnabled
        stickerPickerHotkeyKeyCode = config.stickerPickerHotkeyKeyCode
        stickerPickerHotkeyModifiers = config.stickerPickerHotkeyModifiers
        countSelectionEnabled = config.countSelectionEnabled
        countSelectionHotkeyKeyCode = config.countSelectionHotkeyKeyCode
        countSelectionHotkeyModifiers = config.countSelectionHotkeyModifiers
        aiEnabled = config.aiEnabled
        aiHotkeyKeyCode = config.aiHotkeyKeyCode
        aiHotkeyModifiers = config.aiHotkeyModifiers
        emojiShortcutsEnabled = config.emojiShortcutsEnabled
        if !emojiShortcutsEnabled { emojiMatcher.reset() }
        undoExpansionEnabled = config.undoExpansionEnabled
        if !undoExpansionEnabled { expansionUndo.disarm() }
        rebuildEngine()
    }

    /// Kho macro hiện hành (nil = tắt gõ tắt). Tái tạo engine khi đổi.
    private var macroStore: MacroStore?

    /// Định nghĩa macro đã lưu (để bật lại sau khi tắt qua menu).
    private var macroDefs: [MacroDefinition] = []

    /// Cờ bật gõ tắt (tách khỏi việc có định nghĩa hay không).
    private var macroEnabled = true

    private func rebuildMacroStore() {
        guard macroEnabled && !macroDefs.isEmpty else { macroStore = nil; return }
        // Tiêm hàm đọc clipboard cho macro loại `clipboard` (đọc pasteboard hệ thống).
        let env = MacroStore.Environment(clipboard: {
            NSPasteboard.general.string(forType: .string) ?? ""
        })
        macroStore = MacroStore(macroDefs, environment: env)
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

    // MARK: - Thu phím tắt trong app Cài đặt

    /// Bundle id app Cài đặt (Flutter) — tiến trình RIÊNG với bộ gõ.
    private static let settingsBundleID = "com.bowgo.app"

    /// File cờ app Cài đặt tạo trong lúc ô "thu phím tắt" đang mở, rồi xoá khi
    /// thu xong. Nằm cùng thư mục với settings.json (đường dây IPC sẵn có).
    private static let hotkeyRecordingLockPath: String = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("BowGo", isDirectory: true)
            .appendingPathComponent("hotkey_recording.lock")
            .path
    }()

    /// Cờ quá hạn sau ngần này giây — phòng khi app Cài đặt tắt đột ngột và để lại
    /// file, bộ gõ không bị "câm" phím tắt vĩnh viễn.
    private static let hotkeyRecordingMaxAge: TimeInterval = 120

    /// App Cài đặt có đang THU phím tắt không? Khi đang thu, tap phải NHẢ TAY: không
    /// nuốt, không kích hoạt hotkey nào — nếu không thì mọi tổ hợp đã gán (⌃⇧K mở
    /// bảng ký hiệu, ⌃⇧ bật/tắt bộ gõ…) bị tap ăn trước, ô thu không bao giờ thấy
    /// chúng, nên chỉ đặt được những tổ hợp còn TRỐNG (vd ⌥⇧).
    ///
    /// Chỉ đụng đĩa khi app đang focus CHÍNH LÀ cửa sổ Cài đặt (hiếm) -> không ảnh
    /// hưởng đường gõ thường ngày.
    private func isHotkeyRecording() -> Bool {
        guard frontAppBundleID == Self.settingsBundleID else { return false }
        guard let attrs = try? FileManager.default.attributesOfItem(
            atPath: Self.hotkeyRecordingLockPath
        ), let mtime = attrs[.modificationDate] as? Date else { return false }
        return Date().timeIntervalSince(mtime) < Self.hotkeyRecordingMaxAge
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

    private func isScreenshotHotkey(_ event: CGEvent) -> Bool {
        guard screenshotHotkeyKeyCode != 0 else { return false }
        guard event.getIntegerValueField(.keyboardEventKeycode) == screenshotHotkeyKeyCode else {
            return false
        }
        guard !screenshotHotkeyModifiers.isEmpty else { return false }

        let flags = event.flags
        let active: Set<String> = [
            flags.contains(.maskControl)   ? "control" : nil,
            flags.contains(.maskAlternate) ? "option"  : nil,
            flags.contains(.maskShift)     ? "shift"   : nil,
            flags.contains(.maskCommand)   ? "command" : nil,
        ].compactMap { $0 }.reduce(into: Set()) { $0.insert($1) }

        return active == screenshotHotkeyModifiers
    }

    private func isTextTransformHotkey(_ event: CGEvent) -> Bool {
        guard textTransformHotkeyKeyCode != 0 else { return false }
        guard event.getIntegerValueField(.keyboardEventKeycode) == textTransformHotkeyKeyCode else {
            return false
        }
        guard !textTransformHotkeyModifiers.isEmpty else { return false }

        let flags = event.flags
        let active: Set<String> = [
            flags.contains(.maskControl)   ? "control" : nil,
            flags.contains(.maskAlternate) ? "option"  : nil,
            flags.contains(.maskShift)     ? "shift"   : nil,
            flags.contains(.maskCommand)   ? "command" : nil,
        ].compactMap { $0 }.reduce(into: Set()) { $0.insert($1) }

        return active == textTransformHotkeyModifiers
    }

    private func isSymbolPickerHotkey(_ event: CGEvent) -> Bool {
        guard symbolPickerHotkeyKeyCode != 0 else { return false }
        guard event.getIntegerValueField(.keyboardEventKeycode) == symbolPickerHotkeyKeyCode else {
            return false
        }
        guard !symbolPickerHotkeyModifiers.isEmpty else { return false }

        let flags = event.flags
        let active: Set<String> = [
            flags.contains(.maskControl)   ? "control" : nil,
            flags.contains(.maskAlternate) ? "option"  : nil,
            flags.contains(.maskShift)     ? "shift"   : nil,
            flags.contains(.maskCommand)   ? "command" : nil,
        ].compactMap { $0 }.reduce(into: Set()) { $0.insert($1) }

        return active == symbolPickerHotkeyModifiers
    }

    private func isStickerPickerHotkey(_ event: CGEvent) -> Bool {
        guard stickerPickerHotkeyKeyCode != 0 else { return false }
        guard event.getIntegerValueField(.keyboardEventKeycode) == stickerPickerHotkeyKeyCode else {
            return false
        }
        guard !stickerPickerHotkeyModifiers.isEmpty else { return false }

        let flags = event.flags
        let active: Set<String> = [
            flags.contains(.maskControl)   ? "control" : nil,
            flags.contains(.maskAlternate) ? "option"  : nil,
            flags.contains(.maskShift)     ? "shift"   : nil,
            flags.contains(.maskCommand)   ? "command" : nil,
        ].compactMap { $0 }.reduce(into: Set()) { $0.insert($1) }

        return active == stickerPickerHotkeyModifiers
    }

    private func isCountSelectionHotkey(_ event: CGEvent) -> Bool {
        guard countSelectionHotkeyKeyCode != 0 else { return false }
        guard event.getIntegerValueField(.keyboardEventKeycode) == countSelectionHotkeyKeyCode else {
            return false
        }
        guard !countSelectionHotkeyModifiers.isEmpty else { return false }

        let flags = event.flags
        let active: Set<String> = [
            flags.contains(.maskControl)   ? "control" : nil,
            flags.contains(.maskAlternate) ? "option"  : nil,
            flags.contains(.maskShift)     ? "shift"   : nil,
            flags.contains(.maskCommand)   ? "command" : nil,
        ].compactMap { $0 }.reduce(into: Set()) { $0.insert($1) }

        return active == countSelectionHotkeyModifiers
    }

    private func isAIHotkey(_ event: CGEvent) -> Bool {
        guard aiHotkeyKeyCode != 0 else { return false }
        guard event.getIntegerValueField(.keyboardEventKeycode) == aiHotkeyKeyCode else {
            return false
        }
        guard !aiHotkeyModifiers.isEmpty else { return false }

        let flags = event.flags
        let active: Set<String> = [
            flags.contains(.maskControl)   ? "control" : nil,
            flags.contains(.maskAlternate) ? "option"  : nil,
            flags.contains(.maskShift)     ? "shift"   : nil,
            flags.contains(.maskCommand)   ? "command" : nil,
        ].compactMap { $0 }.reduce(into: Set()) { $0.insert($1) }

        return active == aiHotkeyModifiers
    }

    // MARK: - Callback C (static, không bắt được self -> lấy qua refcon)

    private static let callback: CGEventTapCallBack = { proxy, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let controller = Unmanaged<EventTapController>.fromOpaque(refcon).takeUnretainedValue()
        return controller.handle(proxy: proxy, type: type, event: event)
    }

    // MARK: - Xử lý sự kiện

    /// Lượt gõ-thay chờ post SAU khi nhả `stateLock` (xem `handle`).
    private var pendingOutput: (backspaces: Int, text: String, erase: KeyOutput.EraseStrategy)?

    private func queueOutput(backspaces: Int, text: String) {
        pendingOutput = (backspaces, text, eraseStrategy())
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Callback chạy trên THREAD TAP; cấu hình/menu tới từ main -> khoá trạng thái.
        // Nhưng POST nằm NGOÀI khoá: đường AX (Spotlight/Raycast) có thể chặn tới vài
        // giây, máy ảo thì usleep giữa từng ký tự — giữ khoá lúc đó là chặn luôn main
        // (health check, menu, apply config) -> beachball.
        stateLock.lock()
        let result = handleLocked(proxy: proxy, type: type, event: event)
        let output = pendingOutput
        pendingOutput = nil
        stateLock.unlock()
        if let output {
            KeyOutput.replace(backspaces: output.backspaces, with: output.text,
                              proxy: proxy, erase: output.erase)
        }
        return result
    }

    private func handleLocked(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
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

        // ĐANG THU PHÍM TẮT (ô thu trong app Cài đặt đang mở): cho MỌI phím đi qua
        // nguyên bản. Không nuốt, không kích hoạt hotkey, không gõ thay — nếu không
        // thì tổ hợp nào đã gán sẽ bị ta ăn trước và người dùng không đặt lại được nó.
        if (type == .keyDown || type == .keyUp) && isHotkeyRecording() {
            if committedLength != 0 || !wordRawKeys.isEmpty { resetSyllable() }
            return Unmanaged.passUnretained(event)
        }

        // CLICK CHUỘT -> con trỏ nhảy chỗ khác -> chốt âm tiết đang gõ dở. Không
        // reset thì lần gõ kế tiếp sẽ gửi Backspace dựa trên committedLength cũ và
        // xoá nhầm ký tự ở vị trí mới. Cho event đi qua nguyên vẹn.
        if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
            // Chỉ huỷ toggle khi đang "lên đạn" (xem lý do ở nhánh keyDown bên dưới).
            if bothDown { cancelShortcut = true }
            // Con trỏ vừa nhảy chỗ khác -> ô focus có thể đổi (vào/ra thanh địa chỉ).
            // Kick làm mới NGẦM để phím gõ kế tiếp đã có giá trị đúng.
            addressBarFlag.refresh(after: Self.focusSettleDelay)
            resetSyllable()
            emojiMatcher.reset()
            return Unmanaged.passUnretained(event)
        }

        // PHÍM TẮT CHỈ-MODIFIER (vd ⌃⇧): tap là nguồn CHÍNH. NSEvent global monitor
        // (`startFlagsMonitor`) chỉ là dự phòng cho máy/ngữ cảnh mà tap không được
        // feed flagsChanged — và nó tự im ngay khi thấy tap làm được việc, vì hai
        // nguồn chạy song song sẽ xử lý cùng một chuỗi modifier hai lần khi main bận.
        if type == .flagsChanged {
            // Máy này có feed flagsChanged vào tap -> tắt đường NSEvent monitor.
            tapDeliversFlags = true
            handleFlagsChanged(event.modifierFlagsAsNSEvent)
            return Unmanaged.passUnretained(event)
        }

        // PHÍM TẮT chỉ-modifier (mặc định ⌃⇧): kiểm TRƯỚC cổng `enabled` để vẫn bật lại
        // được khi bộ gõ đang tắt. Nuốt phím (trả nil) khi khớp.
        if type == .keyDown {
            // HUỶ toggle chỉ-modifier CHỈ KHI đang "lên đạn" (đã giữ đúng ⌃⇧) mà user gõ
            // thêm một phím THẬT — đó là tổ hợp ⌃⇧+phím, không phải ý định toggle.
            // KHÔNG huỷ vô điều kiện: trước đây `cancelShortcut = true` chạy mọi keyDown
            // và chỉ reset khi nhả HẾT modifier -> sau khi gõ chữ thường, ⌃⇧ toggle chết
            // cho tới khi nhả sạch tay (bug "không bật/tắt được sau khi gõ").
            if bothDown { cancelShortcut = true }
            // GIỮ PHÍM -> macOS bắn keyDown lặp lại. Với các phím tắt MỞ CỬA SỔ, mỗi
            // lần lặp là một phiên mới (overlay chụp màn hình chồng nhau, cửa sổ mở
            // đi mở lại). Vẫn NUỐT phím ở nhánh lặp, chỉ bỏ qua hành động.
            let autorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if clipboardHistoryEnabled && isClipboardHistoryHotkey(event) {
                // Kích hoạt hiển thị lịch sử clipboard trên main thread
                if !autorepeat {
                    DispatchQueue.main.async {
                        AppDelegate.shared?.showClipboardHistory()
                    }
                }
                return nil
            }
            if screenshotEnabled && isScreenshotHotkey(event) {
                if !autorepeat {
                    DispatchQueue.main.async {
                        AppDelegate.shared?.startScreenshotCapture()
                    }
                }
                return nil
            }
            if textTransformEnabled && isTextTransformHotkey(event) {
                if !autorepeat {
                    DispatchQueue.main.async {
                        AppDelegate.shared?.showTextTransformMenu()
                    }
                }
                return nil
            }
            if symbolPickerEnabled && isSymbolPickerHotkey(event) {
                if !autorepeat {
                    DispatchQueue.main.async {
                        AppDelegate.shared?.showSymbolPicker()
                    }
                }
                return nil
            }
            if stickerPickerEnabled && isStickerPickerHotkey(event) {
                if !autorepeat {
                    DispatchQueue.main.async {
                        AppDelegate.shared?.showStickerPicker()
                    }
                }
                return nil
            }
            if countSelectionEnabled && isCountSelectionHotkey(event) {
                if !autorepeat {
                    DispatchQueue.main.async {
                        AppDelegate.shared?.countSelection()
                    }
                }
                return nil
            }
            if aiEnabled && isAIHotkey(event) {
                if !autorepeat {
                    DispatchQueue.main.async {
                        AppDelegate.shared?.showAIMenu()
                    }
                }
                return nil
            }
            if isToggleHotkey(event) {
                // Giữ phím -> autorepeat bật/tắt liên tục, trạng thái cuối ngẫu nhiên.
                if !autorepeat { toggleEnabledState() }
                return nil
            }
        }

        // THỐNG KÊ (bộ gõ TẮT): đếm phím chữ/số gõ khi đang ở chế độ tiếng Anh, để
        // tính tỉ lệ Việt/Anh. Chỉ xét keyDown không kèm modifier (phím gõ thật).
        if !enabled, type == .keyDown {
            let f = event.flags
            if !f.contains(.maskCommand), !f.contains(.maskControl), !f.contains(.maskAlternate) {
                let kc = event.getIntegerValueField(.keyboardEventKeycode)
                if let c = KeyCodeMap.character(for: kc, shift: false), c.isLetter || c.isNumber {
                    StatsTracker.shared.recordKeystroke(vietnamese: false)
                }
            }
        }

        guard enabled, type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        // iOS SIMULATOR: đặt SAU các phím tắt (⌃⇧, chụp màn hình… vẫn chạy) nhưng
        // TRƯỚC mọi xử lý gõ — xem `passesKeysThrough`.
        if let app = frontAppBundleID, Self.passesKeysThrough(app) {
            if committedLength != 0 || !wordRawKeys.isEmpty { resetSyllable() }
            emojiMatcher.reset()
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        // Có Cmd/Ctrl/Option -> phím tắt, không phải gõ chữ. Reset & cho đi qua.
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            // ⌘L / ⌘F… có thể vừa đưa focus vào thanh địa chỉ -> làm mới cache ngầm.
            addressBarFlag.refresh(after: Self.focusSettleDelay)
            resetSyllable()
            emojiMatcher.reset()
            expansionUndo.disarm()   // phím tắt -> huỷ cửa sổ undo
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // UNDO BUNG: nếu vừa bung gõ tắt/emoji/tự-sửa và phím này là Backspace -> khôi
        // phục chuỗi gốc thay vì xoá 1 ký tự. Chỉ đúng MỘT nhịp ngay sau bung.
        if undoExpansionEnabled, keyCode == KeyCodeMap.delete,
           let undo = expansionUndo.consumeBackspace() {
            emojiMatcher.reset()
            resetSyllable()
            // Xoá chuỗi đã hiện (deleteCount), gõ lại chuỗi gốc.
            queueOutput(backspaces: undo.deleteCount, text: undo.restore)
            return nil  // nuốt Backspace gốc (ta đã tự khôi phục)
        }
        // Phím KHÁC ngay sau bung -> huỷ trạng thái undo (chỉ 1 nhịp).
        if undoExpansionEnabled, expansionUndo.isArmed { expansionUndo.disarm() }

        // Backspace: lùi trong engine, ĐỒNG BỘ màn hình = engine.
        if keyCode == KeyCodeMap.delete {
            emojiMatcher.reset()   // sửa chữ giữa chừng -> huỷ shortcode đang gõ dở
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
                queueOutput(backspaces: backspaces, text: rebuilt)
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
            emojiMatcher.reset()   // ngắt từ -> shortcode dở dang (nếu có) bị huỷ
            // THỐNG KÊ: một từ tiếng Việt được chốt khi có âm tiết đã hiển thị.
            if !currentDisplay.isEmpty { StatsTracker.shared.recordVietWord() }
            // GÕ TẮT: trước khi chốt, thử khớp macro theo phím thô của cả từ.
            // Chỉ bung với phím ngắt thực sự chèn ký tự (space/return/tab), không esc.
            let macroBreak = keyCode == KeyCodeMap.space
                || keyCode == KeyCodeMap.return || keyCode == KeyCodeMap.tab
            if macroBreak, let store = macroStore, !wordRawKeys.isEmpty,
               let content = store.expand(keyword: String(wordRawKeys)) {
                let backspaces = committedLength      // xoá từ khoá đã hiển thị
                let breakChar = KeyCodeMap.wordBreakCharacter(for: keyCode)
                // THỐNG KÊ: ký tự tiết kiệm = độ dài nội dung - độ dài từ khoá.
                StatsTracker.shared.recordCharsSaved(content.count - wordRawKeys.count)
                let rawKeys = String(wordRawKeys)
                resetSyllable()
                wordRawKeys.removeAll()
                // UNDO: shown = "content+break", gốc = "từ khoá thô + break".
                armUndo(shown: content + String(breakChar),
                        original: rawKeys + String(breakChar))
                // Xoá từ khoá, gõ nội dung macro, rồi gõ chính phím ngắt từ.
                queueOutput(backspaces: backspaces, text: content + String(breakChar))
                return nil  // nuốt phím ngắt gốc (ta đã tự gõ nó)
            }

            // TỰ KHÔI PHỤC TIẾNG ANH: nếu từ bị biến dạng và không phải âm tiết
            // tiếng Việt hợp lệ -> gõ lại phím thô (vd "terminäl" -> "terminal").
            if autoRestoreEnglish, !wordRawKeys.isEmpty,
               let raw = VietEngine.englishRestoreKeys(
                   rawKeys: String(wordRawKeys), display: currentDisplay) {
                let backspaces = committedLength
                let breakChar = KeyCodeMap.wordBreakCharacter(for: keyCode)
                let vietDisplay = currentDisplay
                resetSyllable()
                // UNDO: khôi phục về bản tiếng Việt vừa bị đổi thành phím thô.
                armUndo(shown: raw + String(breakChar),
                        original: vietDisplay + String(breakChar))
                queueOutput(backspaces: backspaces, text: raw + String(breakChar))
                return nil  // nuốt phím ngắt gốc (ta đã tự gõ nó kèm từ khôi phục)
            }

            // TỰ SỬA LỖI GÕ NHANH: từ vừa gõ khớp một lỗi phổ biến hoặc dấu thanh đặt
            // sai vị trí -> thay bằng từ đúng (vd "giừo" -> "giờ", "nhièu" -> "nhiều").
            // Chạy SAU khôi-phục-tiếng-Anh để không tranh chỗ với từ tiếng Anh.
            if autoCorrect, !currentDisplay.isEmpty,
               let result = AutoCorrect.correctWord(currentDisplay, dictionary: autoCorrectDict) {
                let backspaces = committedLength
                let breakChar = KeyCodeMap.wordBreakCharacter(for: keyCode)
                let beforeCorrect = currentDisplay
                resetSyllable()
                // UNDO: khôi phục về từ TRƯỚC khi tự-sửa (vd "giừo" thay vì "giờ").
                armUndo(shown: result.corrected + String(breakChar),
                        original: beforeCorrect + String(breakChar))
                queueOutput(backspaces: backspaces, text: result.corrected + String(breakChar))
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
            emojiMatcher.reset()
            return Unmanaged.passUnretained(event)
        }

        // GÕ TẮT EMOJI: xử lý dấu ':' TRƯỚC engine (':' vốn là ngắt-từ với engine).
        // Nếu ':' đóng khớp shortcode -> bung emoji, nuốt phím gốc.
        if emojiShortcutsEnabled, ch == ":" {
            if let (emoji, deleteCount, shortcode) = emojiMatcher.onColon() {
                // THỐNG KÊ: đã hiện ':code' (deleteCount) + ':' đóng = deleteCount+1 phím,
                // thay bằng emoji (thường 1 ký tự) -> tiết kiệm phần chênh.
                StatsTracker.shared.recordCharsSaved(deleteCount + 1 - emoji.count)
                resetSyllable()
                // UNDO: khôi phục về shortcode gốc ":code:" nếu Backspace ngay.
                armUndo(shown: emoji, original: shortcode)
                queueOutput(backspaces: deleteCount, text: emoji)
                return nil
            }
            // Không khớp -> onColon() đã mở buffer ":" mới. ':' đi qua tự nhiên.
        }

        // THỐNG KÊ (bộ gõ BẬT): đếm phím chữ/số gõ khi đang gõ tiếng Việt.
        if ch.isLetter || ch.isNumber {
            StatsTracker.shared.recordKeystroke(vietnamese: true)
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
            // Ngắt-từ KHÔNG phải ':' (space/dấu câu) huỷ shortcode đang gõ dở.
            // (Dấu ':' đã được onColon() xử lý ở trên, không rơi xuống đây khi mở.)
            if ch != ":" { emojiMatcher.reset() }
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

        // GÕ TẮT EMOJI: nối ký tự vào buffer CHỈ KHI engine gõ ra đúng 1 ký tự thô
        // (không biến đổi tiếng Việt). Nếu Telex vừa biến đổi (vd 'oo'->'ô', 'dd'->'đ')
        // thì buffer không còn khớp màn hình -> matcher tự huỷ, tránh xoá nhầm khi bung.
        if emojiShortcutsEnabled {
            let renderedSelf = (rendered.count == backspaces + 1) && (rendered.last == ch)
            emojiMatcher.onCharacter(ch, renderedSelf: renderedSelf)
        }

        queueOutput(backspaces: backspaces, text: rendered)
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

    /// Vũ trang undo cho lần bung vừa rồi (nếu tính năng đang bật). `shown` = chuỗi
    /// đã hiện, `original` = chuỗi gốc để khôi phục khi Backspace ngay sau đó.
    private func armUndo(shown: String, original: String) {
        guard undoExpansionEnabled else { return }
        expansionUndo.arm(shown: shown, original: original)
    }

}

/// Hộp Bool để thread tap báo kết quả khởi tạo về cho `start()`.
private final class BoolBox: @unchecked Sendable {
    var value = false
}

/// Cờ boolean ĐƯỢC LÀM MỚI NGẦM.
///
/// VÌ SAO? Hai phép dò mà bộ gõ cần trước mỗi lần gõ-thay — "ô focus có phải thanh
/// địa chỉ không" (AX query xuyên tiến trình) và "Spotlight có đang hiện không"
/// (`CGWindowListCopyWindowInfo` liệt kê mọi cửa sổ) — có thể mất hàng chục ms khi
/// máy bận. Chạy chúng TRONG callback event tap là tự bóp cổ mình: callback chậm quá
/// ngưỡng thì macOS tắt tap, phím và phím tắt "chết" tới lần phục hồi kế tiếp.
///
/// Ở đây `get()` KHÔNG BAO GIỜ chặn: luôn trả giá trị đã cache và chỉ kick một lượt
/// làm mới trên queue nền khi quá hạn. Đổi lại giá trị có thể trễ một nhịp — vô hại
/// vì nó chỉ chọn CÁCH xoá ký tự, không quyết định đúng/sai chữ. Những thời điểm ô
/// focus có thể vừa đổi (click chuột, ⌘L, đổi app) gọi `refresh()` để làm mới ngay,
/// nên tới lúc người dùng gõ phím đầu tiên cache đã đúng.
final class BackgroundFlag: @unchecked Sendable {
    /// Queue RIÊNG mỗi cờ: một lần AX treo (app đích bận) không được chặn luôn việc
    /// làm mới cờ quyền / Spotlight.
    private let queue = DispatchQueue(label: "bowgo.background-flag", qos: .userInitiated)

    private let lock = NSLock()
    private let ttl: CFTimeInterval
    private let compute: @Sendable () -> Bool
    private var value = false
    private var checkedAt: CFTimeInterval = -.greatestFiniteMagnitude
    private var refreshing = false

    init(ttl: CFTimeInterval, initial: Bool = false, compute: @escaping @Sendable () -> Bool) {
        self.ttl = ttl
        self.value = initial
        self.compute = compute
    }

    /// Giá trị hiện có — KHÔNG chặn. Kick làm mới nếu đã quá hạn.
    func get() -> Bool {
        lock.lock()
        let current = value
        let stale = CACurrentMediaTime() - checkedAt >= ttl
        lock.unlock()
        if stale { refresh() }
        return current
    }

    /// Ép làm mới (bỏ qua TTL), không chờ kết quả.
    ///
    /// `delay`: khi gọi ngay lúc click/⌘L, app đích CHƯA kịp chuyển focus — dò liền
    /// sẽ lưu câu trả lời của ô CŨ kèm mốc thời gian mới. Chờ một nhịp cho app xử lý.
    /// Gọi trúng lúc đang dò dở thì KHÔNG bỏ: chạy thêm một lượt sau lượt hiện tại.
    func refresh(after delay: TimeInterval = 0) {
        lock.lock()
        if refreshing {
            rerunDelay = max(rerunDelay ?? 0, delay)
            lock.unlock()
            return
        }
        refreshing = true
        lock.unlock()
        schedule(after: delay)
    }

    private var rerunDelay: TimeInterval?

    private func schedule(after delay: TimeInterval) {
        queue.asyncAfter(deadline: .now() + delay) { [self] in
            let v = compute()
            lock.lock()
            value = v
            checkedAt = CACurrentMediaTime()
            let again = rerunDelay
            rerunDelay = nil
            refreshing = again != nil
            lock.unlock()
            if let again { schedule(after: again) }
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
