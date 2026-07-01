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
    private var statusItem: NSStatusItem?
    private var vietMenuItem: NSMenuItem?
    private var engMenuItem: NSMenuItem?
    private var telexMenuItem: NSMenuItem?
    private var vniMenuItem: NSMenuItem?
    private var autoRestoreMenuItem: NSMenuItem?
    private var macroMenuItem: NSMenuItem?
    private var autoCorrectMenuItem: NSMenuItem?
    private var healthCheckTimer: Timer?
    private var launchedWithoutPermissions = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        Self.registerPixelFonts()
        setupMenuBar()
        setupSmartSwitch()

        // Gieo bộ cặp tự-sửa mặc định vào file nếu lần đầu chạy (để UI Flutter thấy).
        settingsStore.seedAutoCorrectPairsIfAbsent()

        // Đọc cấu hình do app UI (Flutter) ghi, rồi theo dõi để áp ngay khi đổi.
        if let cfg = settingsStore.read() {
            tapController.apply(config: cfg)
            smartSwitch.apply(isOn: cfg.smartSwitch, perApp: cfg.perApp)

            ClipboardManager.shared.enabled = cfg.clipboardHistoryEnabled
            ClipboardManager.shared.limit = cfg.clipboardHistoryLimit
            if cfg.clipboardHistoryEnabled {
                ClipboardManager.shared.start()
            }
        }
        updateMenuTitle()
        settingsStore.onChange = { [weak self] cfg in
            guard let self else { return }
            self.tapController.apply(config: cfg)
            self.smartSwitch.apply(isOn: cfg.smartSwitch, perApp: cfg.perApp)

            ClipboardManager.shared.enabled = cfg.clipboardHistoryEnabled
            ClipboardManager.shared.limit = cfg.clipboardHistoryLimit
            if cfg.clipboardHistoryEnabled {
                ClipboardManager.shared.start()
            } else {
                ClipboardManager.shared.stop()
            }

            self.updateMenuTitle()
            NSLog("[App] Đã áp cấu hình mới từ UI.")
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

        // Health check mỗi 5 giây: nếu macOS tắt tap thì bật lại.
        // Nếu chưa start (do lúc mở thiếu quyền) mà nay đã đủ quyền -> start luôn.
        // Timer callback chạy nonisolated -> nhảy về MainActor để chạm UI/tap.
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                // Cập nhật trạng thái quyền cho app UI (Flutter) đọc.
                Permissions.writeStatus()
                if self.tapController.isStarted {
                    self.tapController.ensureAlive()
                } else if Permissions.ready() {
                    if self.launchedWithoutPermissions {
                        NSLog("[App] Phát hiện quyền mới được cấp. Tự động relaunch để macOS áp dụng quyền.")
                        self.relaunchApp()
                    } else {
                        self.startTyping()
                    }
                }
                self.updateMenuTitle()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        tapController.stop()
        smartSwitch.stop()
        healthCheckTimer?.invalidate()
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
            NSLog("[App] Bộ gõ đã sẵn sàng.")
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
        if let button = item.button {
            button.image = Self.menuBarIcon(vietnamese: true)
            button.imagePosition = .imageOnly
            button.title = ""
        }

        let menu = NSMenu()

        // 1. Header (disabled)
        let header = NSMenuItem(title: "Chế độ gõ (⌃ + ⇧)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        // 2. Ⓥ Tiếng Việt
        let vietItem = makeItem("Ⓥ  Tiếng Việt", #selector(enableVietnamese))
        menu.addItem(vietItem)
        self.vietMenuItem = vietItem

        // 3. Ⓔ Tiếng Anh
        let engItem = makeItem("Ⓔ  Tiếng Anh", #selector(enableEnglish))
        menu.addItem(engItem)
        self.engMenuItem = engItem

        menu.addItem(.separator())

        // 4. Submenu: ⌨️ Bộ gõ
        let boGoItem = NSMenuItem(title: "⌨️  Bộ gõ", action: nil, keyEquivalent: "")
        let boGoSub = NSMenu()
        let telexItem = makeItem("Telex", #selector(useTelex))
        let vniItem = makeItem("VNI", #selector(useVNI))
        boGoSub.addItem(telexItem)
        boGoSub.addItem(vniItem)
        boGoItem.submenu = boGoSub
        menu.addItem(boGoItem)
        self.telexMenuItem = telexItem
        self.vniMenuItem = vniItem

        menu.addItem(.separator())

        // 4b. Bật/tắt nhanh các tính năng (có checkmark)
        let restoreItem = makeItem("Tự khôi phục tiếng Anh", #selector(toggleAutoRestore))
        menu.addItem(restoreItem)
        self.autoRestoreMenuItem = restoreItem

        let macroItem = makeItem("Gõ tắt", #selector(toggleMacro))
        menu.addItem(macroItem)
        self.macroMenuItem = macroItem

        menu.addItem(.separator())

        // 4c. Submenu: Tính năng (chứa các tiện ích như Lịch sử Copy)
        let featuresItem = NSMenuItem(title: "Tính năng", action: nil, keyEquivalent: "")
        setSymbol(featuresItem, "square.grid.2x2")
        let featuresSub = NSMenu()

        let clipboardItem = NSMenuItem(
            title: "Lịch sử Copy", action: #selector(openClipboardHistory), keyEquivalent: ""
        )
        clipboardItem.target = self
        setSymbol(clipboardItem, "doc.on.clipboard")
        featuresSub.addItem(clipboardItem)

        // Tự sửa lỗi gõ nhanh (toggle có checkmark) — nằm trong submenu Tính năng.
        let autoCorrectItem = makeItem("Tự sửa lỗi gõ nhanh", #selector(toggleAutoCorrect))
        setSymbol(autoCorrectItem, "wand.and.stars")
        featuresSub.addItem(autoCorrectItem)
        self.autoCorrectMenuItem = autoCorrectItem

        featuresItem.submenu = featuresSub
        menu.addItem(featuresItem)

        menu.addItem(.separator())

        // 4d. Submenu: Sửa lỗi (khi không gõ được tiếng Việt)
        let fixItem = NSMenuItem(title: "Sửa lỗi", action: nil, keyEquivalent: "")
        setSymbol(fixItem, "wrench.and.screwdriver")
        let fixSub = NSMenu()

        let restartItem = NSMenuItem(
            title: "Khởi động lại bộ gõ", action: #selector(restartEngine), keyEquivalent: ""
        )
        restartItem.target = self
        setSymbol(restartItem, "arrow.clockwise")
        fixSub.addItem(restartItem)

        let fixPermItem = NSMenuItem(
            title: "Sửa lỗi quyền (gõ không được)…", action: #selector(repairPermissions), keyEquivalent: ""
        )
        fixPermItem.target = self
        setSymbol(fixPermItem, "lock.shield")
        fixSub.addItem(fixPermItem)

        fixItem.submenu = fixSub
        menu.addItem(fixItem)

        menu.addItem(.separator())

        // 5. Mở Cài đặt...
        let settingsItem = NSMenuItem(title: "Mở Cài đặt...", action: #selector(openSettingsApp), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.target = self
        setSymbol(settingsItem, "gearshape")
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        // 6. ⓘ Về Bow Go
        let aboutItem = NSMenuItem(title: "ⓘ  Về Bow Go v1.0.3", action: nil, keyEquivalent: "")
        aboutItem.isEnabled = false
        menu.addItem(aboutItem)

        // 7. Thoát
        let quitItem = NSMenuItem(title: "⏻  Thoát Bow Go", action: #selector(quit), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = .command
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    private func makeItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    /// Gắn SF Symbol làm icon trái cho menu item — đồng bộ phong cách macOS,
    /// nét hơn emoji và tự đổi màu theo light/dark. `symbol` là tên SF Symbol.
    private func setSymbol(_ item: NSMenuItem, _ symbol: String) {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
    }

    private func updateMenuTitle() {
        let on = tapController.enabled && Permissions.ready()
        guard let button = statusItem?.button else { return }
        button.image = Self.menuBarIcon(vietnamese: on)
        button.appearsDisabled = false

        vietMenuItem?.state = on ? .on : .off
        engMenuItem?.state = on ? .off : .on

        telexMenuItem?.state = tapController.currentMethod == .telex ? .on : .off
        vniMenuItem?.state = tapController.currentMethod == .vni ? .on : .off

        autoRestoreMenuItem?.state = tapController.autoRestoreEnglishOn ? .on : .off
        macroMenuItem?.state = tapController.macroOn ? .on : .off
        autoCorrectMenuItem?.state = tapController.autoCorrectOn ? .on : .off
    }

    /// Đăng ký font pixel (PressStart2P + VT323) từ bundle để cửa sổ lịch sử
    /// Clipboard dùng được — khớp phong cách pixel của app cài đặt.
    private static func registerPixelFonts() {
        let fontFiles = ["PressStart2P-Regular", "VT323-Regular"]
        for name in fontFiles {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else {
                NSLog("[Font] Không tìm thấy \(name).ttf trong bundle")
                continue
            }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                // Bỏ qua lỗi "đã đăng ký" — không nghiêm trọng.
                NSLog("[Font] Đăng ký \(name) lỗi (có thể đã đăng ký): \(String(describing: error))")
            }
        }
    }

    /// Icon menu bar: chữ V/E trong vòng tròn ĐẶC.
    ///   - vietnamese = true  -> "v.circle.fill" màu xanh lá grass (đang gõ tiếng Việt)
    ///   - vietnamese = false -> "e.circle.fill" màu xám mờ (tiếng Anh)
    /// KHÔNG dùng template để giữ được màu (template sẽ bị macOS tô đen/trắng).
    private static func menuBarIcon(vietnamese: Bool) -> NSImage? {
        let symbolName = vietnamese ? "v.circle.fill" : "e.circle.fill"
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: vietnamese ? "Tiếng Việt" : "Tiếng Anh")?
            .withSymbolConfiguration(config) else { return nil }

        // Màu: V = xanh lá grass (#5DA130) đồng bộ theme app; E = xám mờ.
        let tint: NSColor = vietnamese
            ? NSColor(red: 0x5D / 255.0, green: 0xA1 / 255.0, blue: 0x30 / 255.0, alpha: 1.0)
            : NSColor.secondaryLabelColor

        let size = base.size
        let tinted = NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect)
            tint.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.isTemplate = false
        return tinted
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

    @objc private func openClipboardHistory() {
        showClipboardHistory()
    }

    @objc private func openSettingsApp() {
        // 1. Thử mở helper app cài đặt nhúng bên trong main bundle trước
        let helperURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/Bow Go.app")
        if FileManager.default.fileExists(atPath: helperURL.path) {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: helperURL, configuration: config, completionHandler: { _, error in
                if let error = error {
                    NSLog("[App] Lỗi mở helper app nhúng: \(error)")
                }
            })
            NSLog("[App] Đã mở app cài đặt Flutter nhúng: \(helperURL.path)")
        }
        // 2. Nếu không tìm thấy hoặc chưa cài đặt nhúng, thử qua Bundle ID
        else if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.bowgo.app") {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: appURL, configuration: config, completionHandler: nil)
            NSLog("[App] Đã mở app cài đặt Flutter qua Bundle ID.")
        }
        // 3. Fallback cuối cùng là mở System Settings
        else {
            Permissions.openSettings(.accessibility)
            NSLog("[App] Không tìm thấy app cài đặt, fallback mở System Settings.")
        }
    }

    @objc private func openPermissions() {
        Permissions.openSettings(.accessibility)
    }

    private func relaunchApp() {
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension == "app" else {
            NSLog("[App] Không thể relaunch: không phải app bundle (\(bundleURL.path))")
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
            NSLog("[App] Đang đóng app hiện tại để relaunch...")
            NSApp.terminate(nil)
        } catch {
            NSLog("[App] Khởi động helper relaunch thất bại: \(error)")
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Sửa lỗi gõ tiếng Việt

    /// Mức NHẸ: tắt/bật lại event tap + đọc lại config, rồi relaunch app.
    /// Dùng khi bộ gõ "đơ" (macOS treo tap) nhưng quyền vẫn còn — không đụng quyền.
    @objc private func restartEngine() {
        NSLog("[Fix] Khởi động lại bộ gõ…")
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
        let alert = NSAlert()
        alert.messageText = "Sửa lỗi quyền gõ tiếng Việt?"
        alert.informativeText = """
        Thao tác này sẽ:
          1. Xoá (reset) quyền cũ của Bow Go trong Accessibility + Input Monitoring.
          2. Mở System Settings để bạn BẬT LẠI quyền cho Bow Go.
          3. Tự khởi động lại app.

        Dùng khi đã cấp quyền mà vẫn không gõ được tiếng Việt.
        """
        alert.addButton(withTitle: "Sửa ngay")
        alert.addButton(withTitle: "Huỷ")
        alert.alertStyle = .warning

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let bundleId = Bundle.main.bundleIdentifier ?? "com.bowgo.keyboard"
        // tccutil reset cho từng loại quyền.
        for service in ["Accessibility", "ListenEvent", "PostEvent"] {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            task.arguments = ["reset", service, bundleId]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            try? task.run()
            task.waitUntilExit()
        }
        NSLog("[Fix] Đã reset quyền cho \(bundleId).")

        // Mở 2 trang Settings để người dùng cấp lại.
        Permissions.openSettings(.accessibility)
        Permissions.openSettings(.inputMonitoring)

        // Hướng dẫn rồi relaunch.
        let done = NSAlert()
        done.messageText = "Đã reset quyền"
        done.informativeText = """
        Trong System Settings vừa mở:
          • Accessibility: bật Bow Go (thêm bằng dấu + nếu chưa có)
          • Input Monitoring: bật Bow Go

        Bấm OK để khởi động lại Bow Go. Sau khi bật quyền, app sẽ nhận lại.
        """
        done.addButton(withTitle: "Khởi động lại")
        done.runModal()
        relaunchApp()
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

        let entries = ClipboardManager.shared.history
        let window = ClipboardHistoryWindow(entries: entries) { selectedEntry in
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
        }

        ClipboardHistoryWindow.shared = window
        window.showWindow()
    }
}

private extension NSStatusItem {
    static func create() -> NSStatusItem {
        NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    }
}
