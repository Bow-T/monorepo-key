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
    private var statusItem: NSStatusItem?
    private var healthCheckTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()

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
        healthCheckTimer?.invalidate()
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

        menu.addItem(makeItem("Bật/tắt bộ gõ", #selector(toggleEnabled)))
        menu.addItem(.separator())
        menu.addItem(makeItem("Kiểu gõ: Telex", #selector(useTelex)))
        menu.addItem(makeItem("Kiểu gõ: VNI", #selector(useVNI)))
        menu.addItem(.separator())
        menu.addItem(makeItem("Mở cài đặt quyền…", #selector(openPermissions)))
        menu.addItem(.separator())
        menu.addItem(makeItem("Thoát", #selector(quit)))

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
        // Khi tắt: làm mờ logo để báo trạng thái "không gõ tiếng Việt".
        button.appearsDisabled = !on
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

    @objc private func toggleEnabled() {
        tapController.enabled.toggle()
        updateMenuTitle()
    }

    @objc private func useTelex() {
        tapController.setMethod(.telex)
    }

    @objc private func useVNI() {
        tapController.setMethod(.vni)
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
