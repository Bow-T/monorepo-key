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
import VietEngine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

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
    private var healthCheckTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupSmartSwitch()

        // Đọc cấu hình do app UI (Flutter) ghi, rồi theo dõi để áp ngay khi đổi.
        if let cfg = settingsStore.read() {
            tapController.apply(config: cfg)
            smartSwitch.apply(isOn: cfg.smartSwitch, perApp: cfg.perApp)
        }
        updateMenuTitle()
        settingsStore.onChange = { [weak self] cfg in
            guard let self else { return }
            self.tapController.apply(config: cfg)
            self.smartSwitch.apply(isOn: cfg.smartSwitch, perApp: cfg.perApp)
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

        if Permissions.ready() {
            startTyping()
        } else {
            promptForPermissions()
        }

        // Health check mỗi 5 giây: nếu macOS tắt tap thì bật lại.
        // Timer callback chạy nonisolated -> nhảy về MainActor để chạm UI/tap.
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tapController.ensureAlive()
                self?.updateMenuTitle()
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
        let alert = NSAlert()
        alert.messageText = "Cần cấp quyền để bộ gõ hoạt động"
        alert.informativeText = """
        Bow Key cần 2 quyền trong System Settings:
          • Accessibility (Trợ năng)
          • Input Monitoring (Giám sát đầu vào)

        Bấm nút bên dưới để mở cài đặt, bật Bow Key ở cả hai mục, rồi khởi động lại app.
        """
        alert.addButton(withTitle: "Mở Accessibility")
        alert.addButton(withTitle: "Mở Input Monitoring")
        alert.addButton(withTitle: "Để sau")

        // Gọi prompt hệ thống trước (đăng ký app vào danh sách TCC).
        Permissions.requestAccessibility()
        Permissions.requestInputMonitoring()

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Permissions.openSettings(.accessibility)
        case .alertSecondButtonReturn:
            Permissions.openSettings(.inputMonitoring)
        default:
            break
        }
    }

    // MARK: - Menu bar

    private func setupMenuBar() {
        let item = NSStatusItem.create()

        // Logo Bow Key: ảnh "template" (đen trên nền trong suốt) -> macOS tự tô
        // màu theo menu bar sáng/tối. Kèm nhãn VN/EN để thấy rõ đang bật hay tắt.
        if let button = item.button {
            button.image = Self.menuBarIcon()
            button.imagePosition = .imageLeading
            button.title = "VN"
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

        // 5. 🎛️ Mở Cài đặt...
        let settingsItem = NSMenuItem(title: "🎛️  Mở Cài đặt...", action: #selector(openPermissions), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        // 6. ⓘ Về BowKey
        let aboutItem = NSMenuItem(title: "ⓘ  Về BowKey v0.1", action: nil, keyEquivalent: "")
        aboutItem.isEnabled = false
        menu.addItem(aboutItem)

        // 7. Thoát
        let quitItem = NSMenuItem(title: "⏻  Thoát BowKey", action: #selector(quit), keyEquivalent: "q")
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

    private func updateMenuTitle() {
        let on = tapController.enabled && Permissions.ready()
        guard let button = statusItem?.button else { return }
        button.title = on ? "VN" : "EN"
        button.appearsDisabled = !on

        vietMenuItem?.state = on ? .on : .off
        engMenuItem?.state = on ? .off : .on

        telexMenuItem?.state = tapController.currentMethod == .telex ? .on : .off
        vniMenuItem?.state = tapController.currentMethod == .vni ? .on : .off

        autoRestoreMenuItem?.state = tapController.autoRestoreEnglishOn ? .on : .off
        macroMenuItem?.state = tapController.macroOn ? .on : .off
    }

    /// Nạp logo menu bar từ Resources (menubar.png + @2x), đánh dấu là template
    /// để macOS tự đổi màu theo light/dark. Trả nil thì button chỉ hiện chữ.
    private static func menuBarIcon() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "menubar", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
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

    @objc private func toggleMacro() {
        let on = !tapController.macroOn
        tapController.setMacroEnabled(on)
        settingsStore.writeMacroEnabled(on)
        updateMenuTitle()
    }

    @objc private func openPermissions() {
        Permissions.openSettings(.accessibility)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

private extension NSStatusItem {
    static func create() -> NSStatusItem {
        NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    }
}
