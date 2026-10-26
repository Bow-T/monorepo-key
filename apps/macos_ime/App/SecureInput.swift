// SecureInput.swift
// -----------------
// "Nhập bảo mật" (Secure Event Input) — khi BẤT KỲ app nào bật nó (ô mật khẩu đang
// focus, Terminal bật Secure Keyboard Entry, trình quản lý mật khẩu…), macOS KHÔNG
// đưa phím thường tới event tap nào cả (chỉ còn modifier). Bộ gõ khi đó im lặng
// "chết": không gõ tiếng Việt, mọi phím tắt (⌃S chụp màn hình…) không ăn — người
// dùng tưởng Bow Go hỏng. Đo thực tế: Edge giữ Secure Input -> tap nhận 0/5 phím.
//
// Ta không tắt được nó (chỉ app giữ mới tắt), nên phát hiện, BÁO, và chỉ cách gỡ. Đo
// 26/10: tiến trình khác bật-rồi-tắt Secure Input KHÔNG gỡ được phần của app đang giữ,
// nên không có cách tự gỡ từ Bow Go.
//
// PID macOS ghi lại (IOConsoleUsers) là app ĐANG Ở TRƯỚC lúc Secure Input bật, chưa
// chắc là app giữ (đo 26/10: tiến trình nền bật -> ghi "Microsoft Edge" đang ở trước).
// Khoá màn hình thì loginwindow bật nó cho ô mật khẩu rồi tắt khi mở khoá; nếu app
// thật vẫn giữ, macOS vẫn ghi loginwindow -> tên đó luôn sai, không hiện cho người dùng.
// Cũng vì thế khoá/mở khoá KHÔNG gỡ được app còn sống đang giữ (đo 26/10: mở khoá 2 lần,
// vẫn bật thêm 6 phút) — chỉ dọn được PID kẹt của app đã tắt; còn kẹt thì đăng xuất.

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

    /// Màn hình đang khoá? loginwindow ghi `CGSSessionScreenIsLocked` vào từ điển phiên
    /// lúc khoá; không khoá thì không có khoá này. Đọc mỗi nhịp thay vì nghe notification
    /// khoá/mở khoá: lỡ một notification (hay khởi động lúc đang khoá) không làm kẹt trạng thái.
    static var screenIsLocked: Bool {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    /// Tên app đang giữ (nil nếu không xác định được, kể cả khi app giữ đã tắt, hoặc
    /// macOS ghi loginwindow — xem đầu file).
    static func ownerName() -> String? { ownerPID().flatMap(appName) }

    static func appName(pid: pid_t) -> String? {
        guard let app = NSRunningApplication(processIdentifier: pid),
              app.bundleIdentifier != "com.apple.loginwindow" else { return nil }
        return app.localizedName
    }

    /// Cách gỡ chắc nhất: app thật sự giữ tự nhả.
    private static let quitHolderStep = "thoát app vừa nhập mật khẩu (trình duyệt, 1Password, Terminal…)"

    /// Các bước gỡ hiển thị cho người dùng (toast + menu), chắc nhất trước. Mỗi bước
    /// một dòng: menu pixel và toast không tự xuống dòng, câu dài kéo cả khung rộng ra.
    static let fixSteps = [
        "1. \(quitHolderStep)",
        "2. vẫn kẹt: khoá màn hình rồi mở bằng mật khẩu",
        "3. vẫn kẹt nữa: đăng xuất",
    ]

    /// Mở khoá màn hình xong mà vẫn bật: bước khoá màn hình vừa thử rồi, không gợi lại.
    static let afterUnlockSteps = [
        "khoá màn hình không gỡ được lần này",
        "1. \(quitHolderStep)",
        "2. vẫn kẹt: đăng xuất",
    ]

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
///
/// Khoá màn hình: im (ô mật khẩu của loginwindow bật nó là đúng). Đã bật sẵn trước khi
/// khoá mà mở khoá vẫn bật = người dùng khoá máy để gỡ mà không được -> đợt MỚI, báo
/// sớm. Trước đây đợt đã báo trước khi khoá kéo dài qua lần mở khoá nên người dùng làm
/// theo hướng dẫn xong vẫn không gõ được mà Bow Go im lặng (đo 26/10). Chưa bật trước
/// khi khoá (vd mở khoá ra gặp ngay ô mật khẩu) thì vẫn là ngưỡng 30s như thường.
struct SecureInputMonitor {
    static let stuckAfter: TimeInterval = 30
    /// Khoá/mở khoá mà vẫn bật -> báo sớm; đủ để loginwindow nhả phần của chính nó.
    static let stuckAfterUnlock: TimeInterval = 3

    enum Change: Equatable { case stuck, stillStuckAfterUnlock }

    private var onSince: Date?
    private var reported = false
    private var screenWasLocked = false
    private var onBeforeLock = false
    /// Đợt hiện tại là "khoá/mở khoá rồi vẫn bật" — menu bỏ bước khoá màn hình.
    private(set) var lockDidNotHelp = false

    mutating func update(isOn: Bool, screenLocked: Bool = false, now: Date = Date()) -> Change? {
        if screenLocked {
            if !screenWasLocked { onBeforeLock = onSince != nil }
            screenWasLocked = true
            return nil
        }
        if screenWasLocked {
            screenWasLocked = false
            reported = false
            lockDidNotHelp = onBeforeLock
            onSince = onBeforeLock ? now : nil
        }
        guard isOn else {
            onSince = nil
            reported = false
            lockDidNotHelp = false
            return nil
        }
        let since = onSince ?? now
        onSince = since
        let after = lockDidNotHelp ? Self.stuckAfterUnlock : Self.stuckAfter
        guard !reported, now.timeIntervalSince(since) >= after else { return nil }
        reported = true
        return lockDidNotHelp ? .stillStuckAfterUnlock : .stuck
    }
}
