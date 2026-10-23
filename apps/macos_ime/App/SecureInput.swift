// SecureInput.swift
// -----------------
// "Nhập bảo mật" (Secure Event Input) — khi BẤT KỲ app nào bật nó (ô mật khẩu đang
// focus, Terminal bật Secure Keyboard Entry, trình quản lý mật khẩu…), macOS KHÔNG
// đưa phím thường tới event tap nào cả (chỉ còn modifier). Bộ gõ khi đó im lặng
// "chết": không gõ tiếng Việt, mọi phím tắt (⌃S chụp màn hình…) không ăn — người
// dùng tưởng Bow Go hỏng. Đo thực tế: Edge giữ Secure Input -> tap nhận 0/5 phím.
//
// Ta không tắt được nó (chỉ app giữ mới tắt), nên phát hiện, BÁO rõ app nào, và chỉ
// cách gỡ. Đo thực tế 23/10: thoát hẳn Edge xong macOS vẫn kẹt Secure Input dưới PID
// cũ đã chết — mở lại app KHÔNG gỡ, khoá + mở khoá màn hình thì gỡ. Nhưng có lần mở
// khoá xong chính loginwindow giữ luôn (thoát hết Xcode/Edge vẫn bật) -> còn kẹt thì
// phải đăng xuất (phiên mới = trạng thái sạch).

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

    /// Tên app đang giữ (nil nếu không xác định được, kể cả khi app giữ đã tắt).
    static func ownerName() -> String? {
        ownerPID().flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName }
    }

    /// Cách gỡ hiển thị cho người dùng (toast + menu).
    static let fixHint = "khoá màn hình (⌃⌘Q) rồi mở khoá; vẫn kẹt thì đăng xuất"

    /// `SACLockScreenImmediate` (login.framework, private) — hàm mà mục "Khoá màn hình"
    /// trong menu Apple gọi. nil nếu bản macOS nào đó bỏ nó.
    static let lockScreenFunction: (@convention(c) () -> Int32)? = {
        let login = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY)
        guard let sym = dlsym(login, "SACLockScreenImmediate") else { return nil }
        return unsafeBitCast(sym, to: (@convention(c) () -> Int32).self)
    }()

    /// Khoá màn hình ngay, như ⌃⌘Q.
    static func lockScreen() {
        guard let lock = lockScreenFunction else {
            bowLog("[SecureInput] Không tìm thấy SACLockScreenImmediate — không khoá được màn hình.")
            return
        }
        _ = lock()
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
