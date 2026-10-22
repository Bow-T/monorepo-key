// SelectionCounter.swift
// ----------------------
// ĐẾM VÙNG BÔI ĐEN: đọc text đang chọn ở app phía trước rồi hiện toast số từ/ký tự/dòng.
// CHỈ ĐỌC (không ghi/dán) -> an toàn tuyệt đối, không đụng clipboard trừ fallback.
//
// Đọc vùng chọn: ưu tiên Accessibility (kAXSelectedTextAttribute); nếu app không hỗ
// trợ (Electron/web) thì fallback ⌘C rồi khôi phục clipboard. Logic đếm ở `TextStats`
// (engine, test được).

import AppKit
import ApplicationServices
import VietEngine

@MainActor
enum SelectionCounter {

    /// Đếm vùng đang bôi đen và hiện toast. Không sửa nội dung.
    static func run() {
        guard let text = readSelection(), !text.isEmpty else {
            ToastHUD.show("CHƯA BÔI ĐEN CHỮ NÀO")
            return
        }
        ToastHUD.show(TextStats.of(text).summary.uppercased())
    }

    // MARK: - Đọc vùng chọn

    /// Đọc text đang chọn: AX trước, fallback clipboard (có khôi phục). Nil nếu không được.
    private static func readSelection() -> String? {
        if let ax = readSelectionViaAX() { return ax }
        return ClipboardManager.shared.copySelection(restoreAfter: true)
    }

    private static func readSelectionViaAX() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef
        ) == .success, let focused = focusedRef else {
            return nil
        }
        let element = focused as! AXUIElement
        var selectedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextAttribute as CFString, &selectedRef
        ) == .success, let selected = selectedRef as? String else {
            return nil
        }
        return selected
    }
}
