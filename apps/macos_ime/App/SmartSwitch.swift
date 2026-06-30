// SmartSwitch.swift
// -----------------
// "Smart Switch": tự nhớ trạng thái bật/tắt bộ gõ theo TỪNG APP.
//
// Hành vi (chế độ auto):
//   - Khi bạn đổi sang app khác đang focus: nếu đã từng nhớ trạng thái cho app đó
//     -> khôi phục; nếu chưa -> giữ nguyên trạng thái hiện tại (mặc định toàn cục).
//   - Khi bạn bật/tắt (phím tắt/menu) trong lúc một app đang focus -> ghi nhớ lựa
//     chọn đó cho app hiện tại.
//
// Theo dõi app focus qua NSWorkspace.didActivateApplicationNotification. Định danh
// app bằng bundleIdentifier (vd "com.apple.Terminal").

import AppKit

@MainActor
final class SmartSwitch {

    /// Bật/tắt toàn bộ tính năng (từ cài đặt).
    var isOn: Bool = false

    /// Bundle id của app đang focus (nil nếu không xác định được).
    private(set) var currentApp: String?

    /// Bảng nhớ: bundleId -> enabled.
    private var perApp: [String: Bool] = [:]

    /// Hỏi/đặt trạng thái bật/tắt thực tế của bộ gõ. Do AppDelegate cung cấp để
    /// SmartSwitch không phụ thuộc trực tiếp vào EventTapController.
    var getEnabled: (() -> Bool)?
    var setEnabled: ((Bool) -> Void)?

    /// Lưu trạng thái nhớ cho app xuống đĩa (để app UI Flutter thấy).
    var persistPerApp: ((_ bundleId: String, _ enabled: Bool) -> Void)?

    private var observer: NSObjectProtocol?

    func start() {
        currentApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            // Notification handler chạy trên main queue; nhảy vào MainActor cho chắc.
            let app = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
            MainActor.assumeIsolated {
                self?.didActivate(app?.bundleIdentifier)
            }
        }
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
    }

    /// Cập nhật cấu hình từ file (smartSwitch on/off + bảng nhớ).
    func apply(isOn: Bool, perApp: [String: Bool]) {
        self.isOn = isOn
        self.perApp = perApp
        // Áp ngay cho app đang focus nếu vừa bật tính năng.
        if isOn, let app = currentApp, let remembered = perApp[app] {
            setEnabled?(remembered)
        }
    }

    /// Người dùng vừa bật/tắt bộ gõ -> ghi nhớ cho app hiện tại.
    func userToggled(to enabled: Bool) {
        guard isOn, let app = currentApp else { return }
        perApp[app] = enabled
        persistPerApp?(app, enabled)
    }

    // MARK: - Riêng tư

    private func didActivate(_ bundleId: String?) {
        currentApp = bundleId
        guard isOn, let bundleId else { return }

        if let remembered = perApp[bundleId] {
            // Đã nhớ app này -> khôi phục đúng trạng thái.
            if getEnabled?() != remembered {
                setEnabled?(remembered)
            }
        }
        // Chưa nhớ -> giữ nguyên trạng thái hiện tại (không can thiệp).
    }
}
