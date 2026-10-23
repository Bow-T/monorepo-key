// SecureInput.swift
// -----------------
// "Nhập bảo mật" (Secure Event Input) — khi BẤT KỲ app nào bật nó (ô mật khẩu đang
// focus, Terminal bật Secure Keyboard Entry, trình quản lý mật khẩu…), macOS KHÔNG
// đưa phím thường tới event tap nào cả (chỉ còn modifier). Bộ gõ khi đó im lặng
// "chết": không gõ tiếng Việt, mọi phím tắt (⌃S chụp màn hình…) không ăn — người
// dùng tưởng Bow Go hỏng. Đo thực tế: Edge giữ Secure Input -> tap nhận 0/5 phím.
//
// Ta không tắt được nó (chỉ app giữ mới tắt), nên chỉ phát hiện và BÁO rõ app nào.

import AppKit
import Carbon.HIToolbox
import IOKit

enum SecureInput {
    /// Có app nào đang bật Nhập bảo mật không (rẻ, gọi mỗi nhịp health check được).
    static var isOn: Bool { IsSecureEventInputEnabled() }

    /// Đang bật bởi một app KHÁC. Chính Bow Go cũng bật nó khi ô nhập API key
    /// (SecureField) đang focus — lúc đó người dùng đang gõ key, không phải lỗi.
    static var heldByOtherApp: Bool {
        isOn && ownerPID() != ProcessInfo.processInfo.processIdentifier
    }

    /// PID app đang giữ, đọc từ IOConsoleUsers (giống `ioreg`). KHÔNG dùng
    /// `CGSessionCopyCurrentDictionary`: trường PID ở đó là app đang ở trước, không
    /// phải app giữ (đo được: báo TextEdit trong khi Edge mới là app giữ).
    static func ownerPID() -> pid_t? {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }
        let users = IORegistryEntryCreateCFProperty(
            root, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? [[String: Any]] ?? []
        return users.lazy
            .compactMap { ($0["kCGSSessionSecureInputPID"] as? NSNumber)?.int32Value }
            .first
    }

    /// Tên app đang giữ (nil nếu không xác định được).
    static func ownerName() -> String? {
        ownerPID().flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName }
    }
}

/// Theo dõi Nhập bảo mật theo nhịp health check. Chỉ báo `.stuck` MỘT lần khi bật
/// LIÊN TỤC đủ lâu: gõ mật khẩu bình thường cũng bật nó trong chốc lát, không đáng
/// làm phiền; bật mãi (app quên tắt) mới là lúc người dùng thấy bộ gõ "chết".
struct SecureInputMonitor {
    static let stuckAfter: TimeInterval = 30

    enum Change: Equatable { case stuck }

    private var onSince: Date?
    private var reported = false

    mutating func update(isOn: Bool, now: Date = Date()) -> Change? {
        guard isOn else {
            onSince = nil
            reported = false
            return nil
        }
        let since = onSince ?? now
        onSince = since
        guard !reported, now.timeIntervalSince(since) >= Self.stuckAfter else { return nil }
        reported = true
        return .stuck
    }
}
