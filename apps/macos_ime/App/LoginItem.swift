// LoginItem.swift
// ---------------
// Khởi động cùng hệ thống (Launch at Login) — dùng SMAppService (macOS 13+).
//
// Vì sao SMAppService thay vì SMLoginItemSetEnabled/LSSharedFileList cũ?
//   - API cũ đã DEPRECATED, cần một "helper app" phụ đóng gói bên trong -> phức tạp.
//   - SMAppService.mainApp đăng ký CHÍNH app này làm login item chỉ bằng register()/
//     unregister(), không cần helper. Trạng thái đọc qua `.status`.
//
// Người dùng vẫn có thể tắt thủ công ở System Settings > General > Login Items;
// khi đó `.status` trả `.notRegistered` hoặc `.requiresApproval` -> ta phản ánh đúng.

import Foundation
import ServiceManagement

enum LoginItem {

    /// Có đang đăng ký khởi động cùng hệ thống không? (đọc trạng thái thực từ hệ thống)
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Bật/tắt khởi động cùng hệ thống. Trả về `true` nếu thao tác thành công.
    /// Nếu lỗi (vd người dùng chưa duyệt), trả `false` và ghi log — caller giữ nguyên UI.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                // Nếu đang ở trạng thái cần duyệt, register() vẫn gọi được; hệ thống
                // sẽ hiện Login Items để người dùng bật. Tránh gọi lại nếu đã enabled.
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return true
        } catch {
            NSLog("[LoginItem] Không đổi được trạng thái khởi động cùng hệ thống: \(error.localizedDescription)")
            return false
        }
    }

    /// Đồng bộ trạng thái đăng ký theo mong muốn của cấu hình (gọi lúc áp config).
    /// Chỉ gọi register/unregister khi trạng thái hiện tại KHÁC mong muốn -> tránh
    /// đăng ký lặp gây thông báo hệ thống thừa.
    static func sync(desired: Bool) {
        let current = isEnabled
        guard current != desired else { return }
        setEnabled(desired)
    }
}
