// Permissions.swift
// -----------------
// Bộ gõ cần 2 quyền hệ thống của macOS để hoạt động:
//
//   1. Accessibility  — để "gõ thay" ký tự vào ứng dụng khác (post sự kiện bàn phím).
//   2. Input Monitoring — để CGEvent tap được phép ĐỌC phím người dùng gõ.
//
// Cả hai do hệ thống TCC (Transparency, Consent, Control) quản lý. App phải xin
// và người dùng cấp thủ công trong System Settings. Đây là phần người mới hay vấp,
// nên ta tách riêng và kiểm tra rõ ràng.

import ApplicationServices
import CoreGraphics

enum Permissions {

    /// Đã được cấp Accessibility chưa? Phải gọi trên main thread.
    static func hasAccessibility() -> Bool {
        AXIsProcessTrusted()
    }

    /// Đã được cấp Input Monitoring chưa?
    static func hasInputMonitoring() -> Bool {
        // CGPreflightListenEventAccess: kiểm tra mà KHÔNG hiện prompt.
        CGPreflightListenEventAccess()
    }

    /// Cả hai quyền đã sẵn sàng để tạo event tap?
    static func ready() -> Bool {
        hasAccessibility() && hasInputMonitoring()
    }

    /// Ghi trạng thái quyền ra file dùng chung để app UI (Flutter) đọc & hiển thị.
    /// File riêng (status.json) — KHÔNG đụng settings.json mà UI làm chủ, để khỏi
    /// kích hoạt vòng watch cấu hình. Chỉ ghi khi trạng thái đổi (tránh I/O thừa).
    static func writeStatus() {
        let acc = hasAccessibility()
        let im = hasInputMonitoring()
        let obj: [String: Any] = [
            "accessibility": acc,
            "inputMonitoring": im,
            "ready": acc && im,
        ]
        let url = statusFileURL
        guard let out = try? JSONSerialization.data(
            withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]
        ) else { return }
        // Bỏ qua nếu nội dung không đổi.
        if let old = try? Data(contentsOf: url), old == out { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? out.write(to: url, options: .atomic)
    }

    /// ~/Library/Application Support/BowGo/status.json (cùng thư mục settings.json).
    static var statusFileURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("BowGo", isDirectory: true)
            .appendingPathComponent("status.json")
    }

    /// Hiện prompt xin Accessibility (mở được hộp thoại dẫn tới System Settings).
    @discardableResult
    static func requestAccessibility() -> Bool {
        // kAXTrustedCheckOptionPrompt là global var không-Sendable trong Swift 6;
        // dùng thẳng chuỗi giá trị của nó để tránh va chạm concurrency.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Hiện prompt xin Input Monitoring.
    @discardableResult
    static func requestInputMonitoring() -> Bool {
        CGRequestListenEventAccess()
    }

    /// Mở thẳng trang cài đặt tương ứng trong System Settings để người dùng bật.
    static func openSettings(_ pane: SettingsPane) {
        let url = URL(string: pane.rawValue)!
        NSWorkspace.shared.open(url)
    }

    enum SettingsPane: String {
        case accessibility =
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case inputMonitoring =
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
    }
}

import AppKit
