// AppDelegate.swift
// -----------------
// Vòng đời app + menu bar (NSStatusItem). App chạy dạng accessory (không dock icon)
// nhờ LSUIElement trong Info.plist.
//
// Trách nhiệm:
//   - Khi khởi động: kiểm tra quyền, nếu thiếu thì hướng dẫn người dùng cấp.
//   - Tạo menu bar để bật/tắt bộ gõ, đổi Telex/VNI, thoát.
//   - Health check định kỳ giữ event tap luôn sống.

import AppKit
import CoreText
import VietEngine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    static private(set) var shared: AppDelegate?

    private let tapController = EventTapController()
    private let settingsStore = SettingsStore()
    private let smartSwitch = SmartSwitch()
    private let screenshotController = ScreenshotController()
    private var statusItem: NSStatusItem?
    private var healthCheckTimer: Timer?
    /// Đếm nhịp health check (1 nhịp = 1 giây) — việc nặng chỉ chạy mỗi 5 nhịp.
    private var healthTick = 0
    /// Nhập bảo mật bật lâu = bộ gõ "chết" im lặng -> báo (xem SecureInput.swift).
    private var secureInputMonitor = SecureInputMonitor()
    /// Timer riêng ghi status.json mỗi ~1s cho app Cài đặt (Flutter) đọc — để UI
    /// phản ánh quyền gần như tức thì mà KHÔNG cần app Flutter tự gọi TCC API
    /// (việc đó khiến nó xuất hiện trong danh sách quyền như một entry thừa).
    private var statusWriteTimer: Timer?
    private var launchedWithoutPermissions = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        Self.registerPixelFonts()
        StatsTracker.shared.load()   // đọc thống kê gõ tích luỹ (nếu có)
        setupMenuBar()
        setupSmartSwitch()

        // Gieo giá trị mặc định vào file nếu lần đầu chạy (để UI Flutter thấy).
        settingsStore.seedLaunchAtLoginIfAbsent(default: true)
        settingsStore.seedAutoCorrectPairsIfAbsent()

        // Đọc cấu hình do app UI (Flutter) ghi, rồi theo dõi để áp ngay khi đổi.
        if let cfg = settingsStore.read() {
            tapController.apply(config: cfg)
            LoginItem.sync(desired: cfg.launchAtLogin)
            smartSwitch.apply(isOn: cfg.smartSwitch, perApp: cfg.perApp)

            ClipboardManager.shared.enabled = cfg.clipboardHistoryEnabled
            ClipboardManager.shared.limit = cfg.clipboardHistoryLimit
            if cfg.clipboardHistoryEnabled {
                ClipboardManager.shared.start()
            }
            // Mục "Chụp màn hình"/"Trợ lý AI" ẩn/hiện được quyết định khi DỰNG menu
            // (đọc screenshotEnabled/aiEnabled tươi) — xem showMenuBarMenu.
            applyAIConfig(cfg)
        }
        updateMenuTitle()
        settingsStore.onChange = { [weak self] cfg in
            guard let self else { return }
            self.tapController.apply(config: cfg)
            LoginItem.sync(desired: cfg.launchAtLogin)
            self.smartSwitch.apply(isOn: cfg.smartSwitch, perApp: cfg.perApp)

            ClipboardManager.shared.enabled = cfg.clipboardHistoryEnabled
            ClipboardManager.shared.limit = cfg.clipboardHistoryLimit
            if cfg.clipboardHistoryEnabled {
                ClipboardManager.shared.start()
            } else {
                ClipboardManager.shared.stop()
            }
            self.applyAIConfig(cfg)

            self.updateMenuTitle()
            bowLog("[App] Đã áp cấu hình mới từ UI.")
        }
        // Phím tắt ⌃⌥ Space bật/tắt -> cập nhật icon + ghi lại file để UI đồng bộ,
        // và để Smart Switch ghi nhớ lựa chọn cho app đang focus.
        tapController.onToggle = { [weak self] enabled in
            guard let self else { return }
            self.updateMenuTitle()
            self.settingsStore.writeEnabled(enabled)
            self.smartSwitch.userToggled(to: enabled)
        }
        settingsStore.startWatching()

        // Ghi trạng thái quyền ra file để app UI (Flutter) hiển thị.
        Permissions.writeStatus()

        if Permissions.ready() {
            startTyping()
        } else {
            launchedWithoutPermissions = true
            promptForPermissions()
        }

        // Health check mỗi 1 GIÂY: nếu macOS tắt tap thì bật lại.
        //
        // VÌ SAO 1s (trước là 5s)? Khi macOS tắt tap thì không còn phím nào tới nữa,
        // nên `checkAndRecover()` bên trong tap không tự cứu được — timer này là
        // đường phục hồi DUY NHẤT. 5 giây "chết phím tắt" là quá lâu để người dùng
        // không nhận ra. Riêng phần việc nặng (ghi file, dựng lại menu) vẫn giữ nhịp
        // 5 giây qua `healthTick` để không tốn I/O.
        //
        // Nếu chưa start (do lúc mở thiếu quyền) mà nay đã đủ quyền -> start luôn.
        // Timer callback chạy nonisolated -> nhảy về MainActor để chạm UI/tap.
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.healthTick += 1
                let heavyTick = self.healthTick % 5 == 0
                if self.secureInputMonitor.update(isOn: SecureInput.heldByOtherApp) == .stuck {
                    let who = SecureInput.ownerName() ?? "Một ứng dụng"
                    bowLog("[SecureInput] \(who) bật Nhập bảo mật quá \(Int(SecureInputMonitor.stuckAfter))s — event tap không nhận phím.")
                    ToastHUD.show("\(who.uppercased()) ĐANG BẬT NHẬP BẢO MẬT — BOW GO TẠM KHÔNG GÕ ĐƯỢC")
                }
                if heavyTick {
                    // Cập nhật trạng thái quyền cho app UI (Flutter) đọc.
                    Permissions.writeStatus()
                    // Flush thống kê gõ ra đĩa nếu có thay đổi (nhẹ, bỏ qua nếu không).
                    StatsTracker.shared.flush()
                    // Lần chạy đầu settings.json chưa có lúc startWatching -> thử lại.
                    if !self.settingsStore.isWatching { self.settingsStore.startWatching() }
                }
                if self.tapController.isStarted {
                    self.tapController.ensureAlive()
                } else if heavyTick, Permissions.ready() {
                    if self.launchedWithoutPermissions {
                        bowLog("[App] Phát hiện quyền mới được cấp. Tự động relaunch để macOS áp dụng quyền.")
                        self.relaunchApp()
                    } else {
                        self.startTyping()
                    }
                }
                if heavyTick { self.updateMenuTitle() }
            }
        }

        // Ghi status.json mỗi 1s để app Cài đặt (Flutter) đọc trạng thái quyền gần
        // như tức thì — thay cho việc app Flutter tự gọi TCC API (vốn đăng ký nó
        // vào danh sách quyền như một entry "Bow Go" thừa). writeStatus() chỉ thật
        // sự ghi khi trạng thái đổi nên gọi dày không tốn I/O.
        statusWriteTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in Permissions.writeStatus() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        tapController.stop()
        smartSwitch.stop()
        healthCheckTimer?.invalidate()
        statusWriteTimer?.invalidate()
        StatsTracker.shared.flush()   // ghi nốt thống kê trước khi thoát
    }

    // MARK: - Smart Switch

    private func setupSmartSwitch() {
        // SmartSwitch điều khiển bộ gõ gián tiếp qua các closure này.
        smartSwitch.getEnabled = { [weak self] in
            self?.tapController.enabled ?? false
        }
        smartSwitch.setEnabled = { [weak self] enabled in
            guard let self else { return }
            self.tapController.enabled = enabled
            self.updateMenuTitle()
            // Ghi `enabled` toàn cục để UI phản ánh trạng thái app hiện tại.
            self.settingsStore.writeEnabled(enabled)
        }
        smartSwitch.persistPerApp = { [weak self] bundleId, enabled in
            self?.settingsStore.writePerApp(bundleId: bundleId, enabled: enabled)
        }
        smartSwitch.start()
    }

    // MARK: - Bộ gõ

    private func startTyping() {
        if tapController.start() {
            bowLog("[App] Bộ gõ đã sẵn sàng.")
        }
        updateMenuTitle()
    }

    private func promptForPermissions() {
        // KHÔNG dùng NSAlert modal tự nhảy lên (trải nghiệm tệ). Thay vào đó mở
        // app Cài đặt (Flutter) — nó có màn onboarding liệt kê 2 quyền và tự đổi
        // sang ✓ theo realtime khi người dùng bật quyền (đọc status.json). Bộ gõ
        // ghi status.json ngầm mỗi 5s; khi đủ quyền, health-check tự relaunch.
        Permissions.writeStatus()
        openSettingsApp()
    }

    // MARK: - Menu bar

    private func setupMenuBar() {
        let item = NSStatusItem.create()

        // Icon menu bar: chữ V/E trong vòng tròn đặc. V xanh lá (đang gõ tiếng Việt),
        // E xám mờ (tiếng Anh) — nhìn phát biết đang bật hay tắt.
        // Click icon -> mở menu pixel-art tự vẽ (thay NSMenu mặc định lạc phong cách).
        if let button = item.button {
            button.image = Self.menuBarIcon(vietnamese: true)
            button.imagePosition = .imageOnly
            button.title = ""
            button.target = self
            button.action = #selector(statusItemClicked)
        }
        statusItem = item
    }

    /// Bấm icon menu bar -> mở menu pixel-art ngay dưới icon.
    @objc private func statusItemClicked() {
        showMenuBarMenu()
    }

    /// Dựng & hiện MENU BAR pixel-art. Dựng lại mỗi lần mở nên trạng thái (checkmark
    /// Việt/Anh, Telex/VNI, các toggle) luôn tươi — không cần cache NSMenuItem.
    private func showMenuBarMenu() {
        let on = tapController.enabled && Permissions.ready()
        let method = tapController.currentMethod
        let cfg = settingsStore.read()
        let screenshotEnabled = cfg?.screenshotEnabled ?? false
        let aiEnabled = cfg?.aiEnabled ?? false

        // Submenu: Bộ gõ (Telex/VNI)
        let boGoSub: [PixelMenuItem] = [
            .item("Telex", checked: method == .telex) { [weak self] in self?.useTelex() },
            .item("VNI", checked: method == .vni) { [weak self] in self?.useVNI() },
        ]

        // Submenu: Biến đổi chữ đã chọn
        var transformSub: [PixelMenuItem] = []
        for transform in TextTransformService.Transform.allCases {
            transformSub.append(.item(transform.title) { [weak self] in
                self?.runTextTransformFromMenu(transform)
            })
        }

        // Submenu: Trợ lý AI
        var aiSub: [PixelMenuItem] = [
            .item("Trò chuyện với AI…", symbol: "bubble.left.and.bubble.right") { [weak self] in
                self?.openAIChat()
            },
            .separator,
        ]
        let previousApp = NSWorkspace.shared.frontmostApplication
        for operation in AIOperation.allCases {
            aiSub.append(.item(operation.title, symbol: operation.symbol) {
                AIAssistantService.run(operation, previousApp: previousApp)
            })
        }
        aiSub.append(.separator)
        aiSub.append(.item("Nhập API key Claude…", symbol: "key") { [weak self] in self?.enterClaudeKey() })
        aiSub.append(.item("Nhập API key OpenAI…", symbol: "key") { [weak self] in self?.enterOpenAIKey() })

        // Submenu: Tính năng
        var featuresSub: [PixelMenuItem] = [
            .item("Lịch sử Copy", symbol: "doc.on.clipboard") { [weak self] in self?.openClipboardHistory() },
            .item("Gõ nhanh ký tự & emoji", symbol: "character.textbox") { [weak self] in self?.openSymbolPicker() },
            .item("Dán sticker (emoji ảnh)", symbol: "face.smiling") { [weak self] in self?.openStickerPicker() },
        ]
        if screenshotEnabled {
            featuresSub.append(.item("Chụp màn hình", symbol: "camera.viewfinder") { [weak self] in
                self?.openScreenshotCapture()
            })
        }
        featuresSub.append(.submenu("Biến đổi chữ đã chọn", symbol: "textformat.abc", items: transformSub))
        if aiEnabled {
            featuresSub.append(.submenu("Trợ lý AI (chữ đã chọn)", symbol: "sparkles", items: aiSub))
        }
        featuresSub.append(.item("Đếm từ & ký tự đã chọn", symbol: "number.square") { [weak self] in
            self?.countSelection()
        })
        featuresSub.append(.item("Tự sửa lỗi gõ nhanh", symbol: "wand.and.stars",
                                 checked: tapController.autoCorrectOn) { [weak self] in
            self?.toggleAutoCorrect()
        })
        featuresSub.append(.item("Khởi động cùng hệ thống", symbol: "power",
                                 checked: LoginItem.isEnabled) { [weak self] in
            self?.toggleLaunchAtLogin()
        })

        // Submenu: Sửa lỗi
        let fixSub: [PixelMenuItem] = [
            .item("Khởi động lại bộ gõ", symbol: "arrow.clockwise") { [weak self] in self?.restartEngine() },
            .item("Sửa lỗi quyền (gõ không được)…", symbol: "lock.shield") { [weak self] in self?.repairPermissions() },
        ]

        // Nhập bảo mật đang bật -> mọi phím bị chặn khỏi bộ gõ: nói rõ lý do ngay đầu menu.
        var secureInputNotice: [PixelMenuItem] = []
        if SecureInput.heldByOtherApp {
            let who = SecureInput.ownerName() ?? "Một ứng dụng"
            secureInputNotice = [
                .header("🔒 \(who) đang bật Nhập bảo mật"),
                .header("Bow Go tạm không gõ được — đóng ô mật khẩu hoặc mở lại \(who)"),
                .separator,
            ]
        }

        // Menu gốc
        let items: [PixelMenuItem] = secureInputNotice + [
            .header("Chế độ gõ (⌃ + ⇧)"),
            .item("Ⓥ  Tiếng Việt", checked: on) { [weak self] in self?.enableVietnamese() },
            .item("Ⓔ  Tiếng Anh", checked: !on) { [weak self] in self?.enableEnglish() },
            .separator,
            .submenu("Bộ gõ", symbol: "keyboard", items: boGoSub),
            .separator,
            .item("Tự khôi phục tiếng Anh", checked: tapController.autoRestoreEnglishOn) { [weak self] in
                self?.toggleAutoRestore()
            },
            .item("Gõ tắt", checked: tapController.macroOn) { [weak self] in self?.toggleMacro() },
            .item("Gõ tắt emoji (:cry: → 😢)", checked: tapController.emojiShortcutsOn) { [weak self] in
                self?.toggleEmojiShortcuts()
            },
            .item("Undo khi bung (Backspace)", checked: tapController.undoExpansionOn) { [weak self] in
                self?.toggleUndoExpansion()
            },
            .separator,
            .submenu("Tính năng", symbol: "square.grid.2x2", items: featuresSub),
            .separator,
            .submenu("Sửa lỗi", symbol: "wrench.and.screwdriver", items: fixSub),
            .separator,
            .item("Mở Cài đặt…", symbol: "gearshape") { [weak self] in self?.openSettingsApp() },
            .separator,
            .header("ⓘ  Về Bow Go v1.0.10"),
            .item("⏻  Thoát Bow Go", symbol: "power") { [weak self] in self?.quit() },
        ]

        PixelMenuWindow.presentBelowStatusItem(title: "Bow Go", items: items, statusItem: statusItem)
    }

    /// Trả focus app cũ rồi chạy transform (dùng cho menu bar — gọi trực tiếp).
    private func runTextTransformFromMenu(_ transform: TextTransformService.Transform) {
        let previousApp = NSWorkspace.shared.frontmostApplication
        if let app = previousApp, app.isTerminated == false { app.activate() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            TextTransformService.run(transform)
        }
    }

    /// Cập nhật icon menu bar theo trạng thái bật/tắt. Checkmark trong menu KHÔNG
    /// cần cập nhật ở đây nữa: menu pixel-art dựng lại mỗi lần mở nên luôn đọc trạng
    /// thái tươi (xem showMenuBarMenu).
    private func updateMenuTitle() {
        let on = tapController.enabled && Permissions.ready()
        guard let button = statusItem?.button else { return }
        button.image = Self.menuBarIcon(vietnamese: on)
        button.appearsDisabled = false
    }

    /// Đăng ký font pixel (PressStart2P + VT323) từ bundle để cửa sổ lịch sử
    /// Clipboard dùng được — khớp phong cách pixel của app cài đặt.
    private static func registerPixelFonts() {
        let fontFiles = ["PressStart2P-Regular", "VT323-Regular"]
        for name in fontFiles {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                bowLog("[Font] Không tìm thấy \(name).ttf trong bundle")
                continue
            }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                // Bỏ qua lỗi "đã đăng ký" — không nghiêm trọng.
                bowLog("[Font] Đăng ký \(name) lỗi (có thể đã đăng ký): \(String(describing: error))")
            }
        }
    }

    /// Bản đồ pixel cho chữ cái dùng trên icon menu bar (1 = tô, hàng 0 ở ĐỈNH).
    /// V, I, E dùng lưới 3×5; N dùng lưới 4×5 để nét chéo rõ, dễ đọc.
    private static let pixelGlyphs: [Character: [[Int]]] = [
        "V": [[1, 0, 1],
              [1, 0, 1],
              [1, 0, 1],
              [1, 0, 1],
              [0, 1, 0]],
        "I": [[1, 1, 1],
              [0, 1, 0],
              [0, 1, 0],
              [0, 1, 0],
              [1, 1, 1]],
        "E": [[1, 1, 1],
              [1, 0, 0],
              [1, 1, 0],
              [1, 0, 0],
              [1, 1, 1]],
        "N": [[1, 0, 0, 1],
              [1, 1, 0, 1],
              [1, 0, 1, 1],
              [1, 0, 0, 1],
              [1, 0, 0, 1]],
    ]

    /// Icon menu bar: BADGE bo góc + chữ "VI"/"EN" kiểu PIXEL-ART.
    ///   - vietnamese = true  -> nền xanh lá grass (#5DA130), chữ "VI" — đang gõ tiếng Việt
    ///   - vietnamese = false -> nền xám, chữ "EN" — tiếng Anh
    /// Nền bo góc mượt cho gọn; chữ vẽ bằng lưới ô vuông có khe hở -> chất pixel.
    /// KHÔNG dùng template để giữ được màu (template sẽ bị macOS tô đen/trắng).
    private static func menuBarIcon(vietnamese: Bool) -> NSImage? {
        let side: CGFloat = 18
        // Màu nền badge: VI = xanh lá grass (#5DA130); EN = xám.
        let bg: NSColor = vietnamese
            ? NSColor(red: 0x5D / 255.0, green: 0xA1 / 255.0, blue: 0x30 / 255.0, alpha: 1.0)
            : NSColor(white: 0.60, alpha: 1.0)
        let text = vietnamese ? "VI" : "EN"

        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            // Nền bo góc mượt (badge).
            let rect = NSRect(x: 0.4, y: 2.0, width: side - 0.8, height: side - 4.0)
            bg.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 2.6, yRadius: 2.6).fill()

            // Bố cục lưới chữ: mỗi glyph rộng theo bản đồ, cách nhau 1 cột trống.
            let chars = Array(text)
            let widths = chars.map { (Self.pixelGlyphs[$0]?.first?.count) ?? 3 }
            let glyphH = 5
            let totalCols = widths.reduce(0, +) + (chars.count - 1)

            // Ô pixel vừa trong nền, chừa lề trong; có khe hở để lộ nét pixel.
            // padExtra: lề thêm mỗi chiều -> chữ nhỏ lại & nằm gọn giữa badge.
            let padExtra: CGFloat = 1.6
            let innerW = rect.width - 3.0 - padExtra * 2
            let innerH = rect.height - 3.2 - padExtra * 2
            let cell = min(innerW / CGFloat(totalCols), innerH / CGFloat(glyphH))
            let gap = cell * 0.16
            let usedW = cell * CGFloat(totalCols)
            let usedH = cell * CGFloat(glyphH)
            let ox = rect.midX - usedW / 2
            let oy = rect.midY - usedH / 2

            NSColor.white.setFill()
            var colBase = 0
            for (idx, ch) in chars.enumerated() {
                let g = Self.pixelGlyphs[ch] ?? []
                let gw = widths[idx]
                for r in 0..<g.count {
                    for c in 0..<gw where g[r][c] == 1 {
                        let x = ox + CGFloat(colBase + c) * cell
                        // Hàng 0 ở ĐỈNH; toạ độ NSImage gốc dưới nên lật trục y.
                        let y = oy + CGFloat(glyphH - 1 - r) * cell
                        let px = NSRect(x: x + gap / 2, y: y + gap / 2,
                                        width: cell - gap, height: cell - gap)
                        NSBezierPath(rect: px).fill()
                    }
                }
                colBase += gw + 1
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: - Hành động menu

    @objc private func enableVietnamese() {
        tapController.enabled = true
        updateMenuTitle()
        settingsStore.writeEnabled(true)
        smartSwitch.userToggled(to: true)
    }

    @objc private func enableEnglish() {
        tapController.enabled = false
        updateMenuTitle()
        settingsStore.writeEnabled(false)
        smartSwitch.userToggled(to: false)
    }

    @objc private func useTelex() {
        tapController.setMethod(.telex)
        updateMenuTitle()
    }

    @objc private func useVNI() {
        tapController.setMethod(.vni)
        updateMenuTitle()
    }

    @objc private func toggleAutoRestore() {
        let on = !tapController.autoRestoreEnglishOn
        tapController.setAutoRestoreEnglish(on)
        settingsStore.writeAutoRestoreEnglish(on)
        updateMenuTitle()
    }

    @objc private func toggleAutoCorrect() {
        let on = !tapController.autoCorrectOn
        tapController.setAutoCorrect(on)
        settingsStore.writeAutoCorrect(on)
        updateMenuTitle()
    }

    @objc private func toggleMacro() {
        let on = !tapController.macroOn
        tapController.setMacroEnabled(on)
        settingsStore.writeMacroEnabled(on)
        updateMenuTitle()
    }

    @objc private func toggleEmojiShortcuts() {
        let on = !tapController.emojiShortcutsOn
        tapController.setEmojiShortcuts(on)
        settingsStore.writeEmojiShortcutsEnabled(on)
        updateMenuTitle()
    }

    @objc private func toggleUndoExpansion() {
        let on = !tapController.undoExpansionOn
        tapController.setUndoExpansion(on)
        settingsStore.writeUndoExpansionEnabled(on)
        updateMenuTitle()
    }

    @objc private func toggleLaunchAtLogin() {
        // Đảo theo trạng thái THỰC của hệ thống (nguồn chân lý), rồi ghi vào file.
        let desired = !LoginItem.isEnabled
        let ok = LoginItem.setEnabled(desired)
        if ok { settingsStore.writeLaunchAtLogin(desired) }
        updateMenuTitle()
    }

    /// Đếm vùng bôi đen -> hiện toast số từ/ký tự/dòng (gọi từ menu hoặc phím tắt).
    @objc func countSelection() {
        SelectionCounter.run()
    }

    /// Popup chọn thao tác biến đổi tại vị trí con trỏ (gọi từ phím tắt ⌃⇧T).
    /// Bôi đen chữ ở app bất kỳ -> ⌃⇧T -> chọn thao tác -> thay ngay tại chỗ.
    func showTextTransformMenu() {
        // Ghi nhớ app đang focus: mở menu sẽ kích hoạt app ta, nên trước khi chạy
        // transform phải trả focus về app cũ (để ⌘C/⌘V fallback gõ đúng chỗ).
        let previousApp = NSWorkspace.shared.frontmostApplication

        var items: [PixelMenuItem] = [.header("Chọn kiểu biến đổi:")]
        for transform in TextTransformService.Transform.allCases {
            items.append(.item(transform.title) {
                // Trả focus về app cũ trước, rồi chạy transform (AX/⌘C cần app đó ở
                // phía trước). Delay nhỏ để app kịp nhận focus.
                if let app = previousApp, app.isTerminated == false { app.activate() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    TextTransformService.run(transform)
                }
            })
        }
        PixelMenuWindow.present(title: "Biến đổi chữ đã chọn", items: items)
    }

    // MARK: - Trợ lý AI

    /// Áp cấu hình AI vào service (gọi lúc khởi động & khi UI đổi). Việc ẩn/hiện
    /// mục "Trợ lý AI" trong menu quyết định khi dựng menu (đọc aiEnabled tươi).
    private func applyAIConfig(_ cfg: BowConfig) {
        AIAssistantService.config = AIAssistantService.Config(
            provider: AIProvider(rawValue: cfg.aiProvider) ?? .claude,
            claudeModel: cfg.aiClaudeModel,
            openaiModel: cfg.aiOpenAIModel
        )
    }


    /// Popup chọn thao tác AI tại con trỏ (gọi từ phím tắt ⌃⇧G). Bôi đen chữ ->
    /// ⌃⇧G -> chọn thao tác -> kết quả hiện trong popup.
    func showAIMenu() {
        // Ghi nhớ app đang focus: mở menu sẽ kích hoạt app ta, cần trả focus về
        // app cũ trước khi đọc vùng chọn.
        let previousApp = NSWorkspace.shared.frontmostApplication

        var items: [PixelMenuItem] = [
            .item("Trò chuyện với AI…", symbol: "bubble.left.and.bubble.right") { [weak self] in
                self?.openAIChat()
            },
            .separator,
            .header("Trên chữ đã chọn:"),
        ]
        for operation in AIOperation.allCases {
            items.append(.item(operation.title, symbol: operation.symbol) {
                AIAssistantService.run(operation, previousApp: previousApp)
            })
        }
        PixelMenuWindow.present(title: "Trợ lý AI", items: items)
    }

    /// Mở cửa sổ TRÒ CHUYỆN với AI (nhiều lượt, lưu lịch sử). Gọi từ menu bar hoặc
    /// phím tắt. Không cần bôi đen — mở cuộc mới trống (hoặc dùng lại cửa sổ đang mở).
    @objc func openAIChat() {
        guard AIAssistantService.config.provider == .claude
              ? AIKeychain.hasKey(.claude) || AIKeychain.hasKey(.openai)
              : AIKeychain.hasKey(.openai) || AIKeychain.hasKey(.claude) else {
            ToastHUD.show("CHƯA NHẬP API KEY — VÀO CÀI ĐẶT")
            return
        }
        AIChatWindow.present()
    }

    @objc private func enterClaudeKey() { promptAndSaveKey(for: .claude) }
    @objc private func enterOpenAIKey() { promptAndSaveKey(for: .openai) }

    /// Hộp thoại pixel-art nhập & lưu API key vào Keychain của bộ gõ cho một hãng.
    private func promptAndSaveKey(for provider: AIProvider) {
        let existing = AIKeychain.read(provider) ?? ""
        AIKeyPromptWindow.presentKey(provider: provider, existingKey: existing) { key in
            AIKeychain.write(key, for: provider)
            ToastHUD.show(key.isEmpty
                ? "ĐÃ XOÁ API KEY"
                : "ĐÃ LƯU API KEY \(provider.title.uppercased())")
        }
    }

    @objc private func openClipboardHistory() {
        showClipboardHistory()
    }

    @objc private func openSymbolPicker() {
        showSymbolPicker()
    }

    @objc private func openStickerPicker() {
        showStickerPicker()
    }

    @objc private func openScreenshotCapture() {
        startScreenshotCapture()
    }

    /// Bắt đầu phiên chụp màn hình (gọi từ phím tắt qua event tap hoặc menu).
    func startScreenshotCapture() {
        screenshotController.beginCapture()
    }

    @objc private func openSettingsApp() {
        // 1. Thử mở helper app cài đặt nhúng bên trong main bundle trước
        let helperURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/Bow Go.app")
        if FileManager.default.fileExists(atPath: helperURL.path) {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: helperURL, configuration: config, completionHandler: { _, error in
                if let error = error {
                    bowLog("[App] Lỗi mở helper app nhúng: \(error)")
                }
            })
            bowLog("[App] Đã mở app cài đặt Flutter nhúng: \(helperURL.path)")
        }
        // 2. Nếu không tìm thấy hoặc chưa cài đặt nhúng, thử qua Bundle ID
        else if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.bowgo.app") {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: appURL, configuration: config, completionHandler: nil)
            bowLog("[App] Đã mở app cài đặt Flutter qua Bundle ID.")
        }
        // 3. Fallback cuối cùng là mở System Settings
        else {
            Permissions.openSettings(.accessibility)
            bowLog("[App] Không tìm thấy app cài đặt, fallback mở System Settings.")
        }
    }

    @objc private func openPermissions() {
        Permissions.openSettings(.accessibility)
    }

    private func relaunchApp() {
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension == "app" else {
            bowLog("[App] Không thể relaunch: không phải app bundle (\(bundleURL.path))")
            return
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        let parentPID = ProcessInfo.processInfo.processIdentifier
        let script = """
        while kill -0 \(parentPID) 2>/dev/null; do
            sleep 0.2
        done
        sleep 0.2
        exec /usr/bin/open -n "\(bundleURL.path)"
        """
        task.arguments = ["-c", script]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.standardInput = nil

        do {
            try task.run()
            bowLog("[App] Đang đóng app hiện tại để relaunch...")
            NSApp.terminate(nil)
        } catch {
            bowLog("[App] Khởi động helper relaunch thất bại: \(error)")
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Sửa lỗi gõ tiếng Việt

    /// Mức NHẸ: tắt/bật lại event tap + đọc lại config, rồi relaunch app.
    /// Dùng khi bộ gõ "đơ" (macOS treo tap) nhưng quyền vẫn còn — không đụng quyền.
    @objc private func restartEngine() {
        bowLog("[Fix] Khởi động lại bộ gõ…")
        tapController.stop()
        // Đọc lại cấu hình mới nhất rồi áp.
        if let cfg = settingsStore.read() {
            tapController.apply(config: cfg)
        }
        // Relaunch để macOS gắn lại tap sạch sẽ (cách chắc ăn nhất).
        relaunchApp()
    }

    /// Mức MẠNH: reset bản ghi quyền TCC (Accessibility + Input Monitoring) cho
    /// bundle này rồi mở Settings + relaunch. Dùng khi đã cấp quyền mà vẫn gõ
    /// không được — nguyên nhân là quyền "mồ côi" do app ký ad-hoc đổi hash sau
    /// mỗi lần build/cập nhật.
    @objc private func repairPermissions() {
        PixelAlertWindow.present(
            title: "Sửa lỗi quyền gõ tiếng Việt?",
            message: """
            Thao tác này sẽ:
              1. Xoá (reset) quyền cũ của Bow Go: Accessibility + Input Monitoring + Screen Recording (chụp màn hình).
              2. Mở System Settings để bạn BẬT LẠI quyền cho Bow Go.
              3. Tự khởi động lại app.

            Dùng khi đã cấp quyền mà vẫn không gõ được tiếng Việt / không chụp được màn hình.
            """,
            buttons: [
                PixelAlertButton("HUỶ", kind: .normal) {},
                PixelAlertButton("SỬA NGAY", kind: .destructive) { [weak self] in
                    self?.performPermissionRepair()
                },
            ]
        )
    }

    /// Thực thi reset quyền + mở Settings + hiện hướng dẫn rồi relaunch.
    private func performPermissionRepair() {
        let bundleId = Bundle.main.bundleIdentifier ?? "com.bowgo.keyboard"
        // tccutil reset cho từng loại quyền (ScreenCapture = Ghi màn hình, cho
        // tính năng chụp màn hình — cũng bị "mồ côi" sau mỗi lần build lại).
        for service in ["Accessibility", "ListenEvent", "PostEvent", "ScreenCapture"] {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            task.arguments = ["reset", service, bundleId]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            try? task.run()
            task.waitUntilExit()
        }
        bowLog("[Fix] Đã reset quyền cho \(bundleId).")

        // Mở các trang Settings để người dùng cấp lại. System Settings chỉ hiện
        // 1 trang mỗi lúc — mở Screen Recording TRƯỚC để 2 quyền gõ phím (quan
        // trọng hơn) nằm trên cùng.
        Permissions.openSettings(.screenRecording)
        Permissions.openSettings(.inputMonitoring)
        Permissions.openSettings(.accessibility)

        // Hướng dẫn rồi relaunch.
        PixelAlertWindow.present(
            title: "Đã reset quyền",
            message: """
            Trong System Settings vừa mở:
              • Accessibility: bật Bow Go (thêm bằng dấu + nếu chưa có)
              • Input Monitoring: bật Bow Go
              • Screen Recording: bật Bow Go (nếu dùng chụp màn hình)

            Bấm Khởi động lại. Sau khi bật quyền, app sẽ nhận lại.
            """,
            buttons: [
                PixelAlertButton("KHỞI ĐỘNG LẠI", kind: .primary) { [weak self] in
                    self?.relaunchApp()
                },
            ]
        )
    }

    // MARK: - Clipboard History HUD

    func showClipboardHistory() {
        // Nếu đã hiển thị thì đóng/ẩn
        if let window = ClipboardHistoryWindow.shared {
            window.orderOut(nil)
            ClipboardHistoryWindow.shared = nil
            NSApp.hide(nil)
            return
        }

        // Ghi nhớ app đang focus để trả lại sau khi OCR (không dùng NSApp.hide ở
        // nhánh OCR — hide sẽ ẩn luôn toast xác nhận).
        let previousApp = NSWorkspace.shared.frontmostApplication

        let entries = ClipboardManager.shared.history
        let window = ClipboardHistoryWindow(entries: entries, onSelect: { selectedEntry in
            ClipboardHistoryWindow.shared?.orderOut(nil)
            ClipboardHistoryWindow.shared = nil

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            if let imagePath = selectedEntry.imagePath,
               let image = NSImage(contentsOfFile: imagePath) {
                // Mục ảnh: ghi ảnh vào pasteboard để dán đúng định dạng.
                pasteboard.writeObjects([image])
            } else {
                pasteboard.setString(selectedEntry.text, forType: .string)
            }

            NSApp.hide(nil)

            // Trì hoãn 100ms để đảm bảo focus đã trả về ứng dụng cũ trước khi paste
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                KeyOutput.simulatePaste()
            }
        }, onOCR: { entry in
            ClipboardHistoryWindow.shared?.orderOut(nil)
            ClipboardHistoryWindow.shared = nil

            let restoreFocus = {
                if let app = previousApp, app.isTerminated == false {
                    app.activate()
                } else {
                    NSApp.hide(nil)
                }
            }
            guard let path = entry.imagePath,
                  let image = NSImage(contentsOfFile: path) else {
                restoreFocus()
                return
            }
            // Cửa sổ bôi-đen-chữ kiểu Preview: trỏ vào chữ trong ảnh để copy.
            LiveTextWindow.present(image: image, onDismiss: restoreFocus)
        })

        ClipboardHistoryWindow.shared = window
        window.showWindow()
    }

    // MARK: - Bảng gõ nhanh ký tự & emoji (picker)

    /// Mở/đóng bảng gõ nhanh ký tự đặc biệt & emoji. Chọn một ô -> chèn vào ô đang
    /// gõ của app trước đó (qua clipboard + ⌘V, đáng tin ở mọi app) rồi đóng.
    func showSymbolPicker() {
        // Đang mở -> đóng (toggle).
        if let window = SymbolPickerWindow.shared {
            window.close(restoreFocus: true)
            return
        }

        // Ghi nhớ app đang focus để trả lại + chèn đúng chỗ sau khi chọn.
        let previousApp = NSWorkspace.shared.frontmostApplication

        let window = SymbolPickerWindow(
            recentItems: RecentPickerStore.recentSymbols(),
            onPick: { symbol in
                SymbolPickerWindow.shared?.close(restoreFocus: false)
                RecentPickerStore.useSymbol(symbol)   // ghi nhớ "gần đây"

                // Đưa ký tự vào clipboard rồi trả focus + dán vào app trước.
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(symbol, forType: .string)

                if let app = previousApp, app.isTerminated == false {
                    app.activate()
                } else {
                    NSApp.hide(nil)
                }
                // Trì hoãn để focus kịp trả về trước khi dán.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    KeyOutput.simulatePaste()
                }
            },
            onClose: {
                SymbolPickerWindow.shared?.close(restoreFocus: true)
            }
        )
        SymbolPickerWindow.shared = window
        window.showWindow()
    }

    // MARK: - Bảng dán sticker (emoji ảnh)

    /// Mở/đóng bảng dán sticker. Chọn một sticker -> DÁN ẢNH (đã thu nhỏ) vào ô đang
    /// gõ của app trước (qua clipboard hình ảnh + ⌘V) rồi đóng.
    func showStickerPicker() {
        if let window = StickerPickerWindow.shared {
            window.close(restoreFocus: true)
            return
        }

        let previousApp = NSWorkspace.shared.frontmostApplication

        let window = StickerPickerWindow(
            recentSlugs: RecentPickerStore.recentStickers(),
            onPick: { sticker in
                StickerPickerWindow.shared?.close(restoreFocus: false)
                RecentPickerStore.useSticker(sticker.slug)   // ghi nhớ "gần đây"

                guard let full = StickerStore.image(for: sticker) else {
                    if let app = previousApp, app.isTerminated == false { app.activate() }
                    return
                }
                // Ảnh gốc 256×256 quá to để dán inline -> thu về ~72px.
                let pasteImage = Self.resized(full, to: NSSize(width: 72, height: 72))

                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.writeObjects([pasteImage])

                if let app = previousApp, app.isTerminated == false {
                    app.activate()
                } else {
                    NSApp.hide(nil)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    KeyOutput.simulatePaste()
                }
            },
            onClose: {
                StickerPickerWindow.shared?.close(restoreFocus: true)
            }
        )
        StickerPickerWindow.shared = window
        window.showWindow()
    }

    /// Thu ảnh về kích thước `size` (giữ chất lượng), trả NSImage mới.
    private static func resized(_ image: NSImage, to size: NSSize) -> NSImage {
        let out = NSImage(size: size)
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy, fraction: 1.0)
        out.unlockFocus()
        return out
    }
}

private extension NSStatusItem {
    static func create() -> NSStatusItem {
        NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    }
}
