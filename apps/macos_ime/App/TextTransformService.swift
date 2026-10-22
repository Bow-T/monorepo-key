// TextTransformService.swift
// ---------------------------
// BIẾN ĐỔI VĂN BẢN ĐÃ BÔI ĐEN — tận dụng engine `TextConverter` sẵn có.
//
// Người dùng bôi đen một đoạn văn ở BẤT KỲ ứng dụng nào, rồi chọn một thao tác
// (bỏ dấu / IN HOA / thường / Hoa đầu câu / Hoa Mỗi Từ / chuyển mã…). Đoạn được
// thay ngay TẠI CHỖ.
//
// Cách lấy & ghi text đã chọn — hai đường, ưu tiên đường an toàn hơn:
//   1. Accessibility API (AXUIElement): đọc `kAXSelectedTextAttribute` rồi ghi đè
//      `kAXSelectedTextAttribute` bằng chuỗi mới. KHÔNG đụng clipboard, không giả
//      lập phím -> sạch nhất. Chạy được ở đa số ô nhập liệu native (TextField,
//      TextView, Xcode, Notes, Mail…).
//   2. Fallback qua clipboard: nếu AX không ĐỌC được vùng chọn (nhiều app
//      Electron/web), ta: ⌘C để lấy vùng chọn -> biến đổi -> đặt vào clipboard ->
//      ⌘V dán đè. AX đọc được mà không ghi được (Terminal, ô chỉ-đọc) thì CHỈ
//      chép — ⌘V lúc đó dễ dán nhầm vào dấu nhắc shell / ô soạn tin.
//
// DÙ ĐI ĐƯỜNG NÀO, kết quả LUÔN được để lại trong clipboard. Lý do: rất nhiều
// vùng bôi đen không ghi đè được (đoạn văn trên trang web, PDF, ô chỉ đọc) —
// khi đó thay tại chỗ bất khả thi, nhưng người dùng vẫn muốn ⌘V kết quả sang
// chỗ khác. Clipboard cũ không mất trắng: ClipboardManager đã lưu nó vào lịch
// sử (⌃⇧V để lấy lại).
//
// KHÔNG đi qua event tap của bộ gõ: đây là thao tác một-phát do người dùng chủ
// động gọi (phím tắt/menu), tách hẳn khỏi luồng gõ realtime nhạy cảm.

import AppKit
import ApplicationServices
import VietEngine

@MainActor
enum TextTransformService {

    /// Các phép biến đổi mà người dùng chọn. Ánh xạ 1-1 sang `TextConverter`.
    enum Transform: String, CaseIterable {
        case removeDiacritics       // bỏ dấu:        "Tiếng Việt" -> "Tieng Viet"
        case upper                  // TẤT CẢ HOA
        case lower                  // tất cả thường
        case capitalizeFirst        // Hoa đầu câu
        case capitalizeWords        // Hoa Mỗi Từ
        case toTCVN3                // Unicode -> TCVN3 (.VnTime)
        case toVNI                  // Unicode -> VNI-Windows
        case fromTCVN3              // TCVN3 -> Unicode
        case fromVNI                // VNI-Windows -> Unicode
        case calc                   // tính biểu thức (bôi đen "5*3+2" -> "17")
        case numberToWords          // đọc số thành chữ ("123" -> "một trăm hai mươi ba")
        case groupNumber            // thêm dấu phân nhóm ("1500000" -> "1.500.000")
        case ungroupNumber          // bỏ dấu phân nhóm ("1.500.000" -> "1500000")
        case normalizeSpaces        // chuẩn hoá khoảng trắng (gộp space, trim, gộp dòng trống)

        /// Nhãn tiếng Việt hiển thị trên menu.
        var title: String {
            switch self {
            case .removeDiacritics: return "Bỏ dấu"
            case .upper:            return "IN HOA"
            case .lower:            return "in thường"
            case .capitalizeFirst:  return "Hoa đầu câu"
            case .capitalizeWords:  return "Hoa Mỗi Từ"
            case .toTCVN3:          return "Unicode → TCVN3"
            case .toVNI:            return "Unicode → VNI"
            case .fromTCVN3:        return "TCVN3 → Unicode"
            case .fromVNI:          return "VNI → Unicode"
            case .calc:             return "Tính (= kết quả)"
            case .numberToWords:    return "Đọc số thành chữ"
            case .groupNumber:      return "Số: thêm dấu chấm"
            case .ungroupNumber:    return "Số: bỏ dấu chấm"
            case .normalizeSpaces:  return "Dọn khoảng trắng"
            }
        }

        /// Áp phép biến đổi lên chuỗi.
        func apply(_ text: String) -> String {
            switch self {
            case .removeDiacritics: return TextConverter.removeDiacritics(text)
            case .upper:            return TextConverter.changeCase(text, to: .allUpper)
            case .lower:            return TextConverter.changeCase(text, to: .allLower)
            case .capitalizeFirst:  return TextConverter.changeCase(text, to: .capitalizeFirst)
            case .capitalizeWords:  return TextConverter.changeCase(text, to: .capitalizeWords)
            case .toTCVN3:          return TextConverter.convert(text, from: .unicode, to: .tcvn3)
            case .toVNI:            return TextConverter.convert(text, from: .unicode, to: .vniWindows)
            case .fromTCVN3:        return TextConverter.convert(text, from: .tcvn3, to: .unicode)
            case .fromVNI:          return TextConverter.convert(text, from: .vniWindows, to: .unicode)
            // Biểu thức hợp lệ -> kết quả; không hợp lệ -> giữ nguyên (no-op).
            case .calc:             return Calculator.eval(text) ?? text
            // Số hợp lệ -> đọc thành chữ; không phải số -> giữ nguyên (no-op).
            case .numberToWords:    return NumberToWords.convert(text) ?? text
            // Số hợp lệ -> thêm/bỏ dấu phân nhóm; không phải số -> giữ nguyên (no-op).
            case .groupNumber:      return NumberGrouping.group(text) ?? text
            case .ungroupNumber:    return NumberGrouping.ungroup(text) ?? text
            case .normalizeSpaces:  return WhitespaceNormalizer.normalize(text)
            }
        }
    }

    /// Kết quả một lần biến đổi — để hiển thị toast phản hồi.
    enum Result {
        case success(Transform)
        case emptySelection       // không có text nào được bôi đen
        case failed               // đọc/ghi thất bại (thiếu quyền hoặc app không hỗ trợ)
    }

    /// Biến đổi văn bản đang được bôi đen ở ứng dụng phía trước.
    /// Kết quả luôn được đặt vào clipboard, kể cả khi không thay được tại chỗ.
    @discardableResult
    static func run(_ transform: Transform) -> Result {
        let label = transform.title.uppercased()

        // Ưu tiên đường AX (đọc/ghi thẳng vùng chọn, không cần giả lập phím).
        switch transformViaAX(transform) {
        case .replaced:
            ToastHUD.show("✓ \(label) · ĐÃ CHÉP")
            return .success(transform)

        case .empty:
            ToastHUD.show("CHƯA BÔI ĐEN CHỮ NÀO")
            return .emptySelection

        case .copiedNotReplaced:
            // Kết quả đã nằm trong clipboard. KHÔNG thử ⌘C/⌘V: ở Terminal, Slack…
            // ⌘V sẽ dán kết quả vào dấu nhắc shell / ô soạn tin thay vì vùng chọn.
            // Người dùng tự ⌘V vào chỗ muốn.
            ToastHUD.show("✓ \(label) · ĐÃ CHÉP (KHÔNG SỬA TẠI CHỖ)")
            return .success(transform)

        case .unavailable:
            // Không đọc được vùng chọn qua AX -> đi hẳn đường clipboard.
            if transformViaClipboard(transform) {
                ToastHUD.show("✓ \(label) · ĐÃ CHÉP")
                return .success(transform)
            }
            ToastHUD.show("KHÔNG BIẾN ĐỔI ĐƯỢC VÙNG CHỌN")
            return .failed
        }
    }

    /// Đặt kết quả vào clipboard. Gọi ở CẢ hai đường để người dùng luôn ⌘V được
    /// kết quả sang chỗ khác, không phụ thuộc vùng chọn có ghi đè được hay không.
    private static func putOnClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Đường 1: Accessibility API

    /// Kết quả nội bộ của đường AX — chi tiết hơn `Result` để `run` chọn đúng
    /// bước tiếp theo và đúng thông báo.
    private enum AXOutcome {
        case replaced             // đọc + ghi đè xong, thay tại chỗ thành công
        case copiedNotReplaced    // đọc được (kết quả đã ở clipboard) nhưng ghi đè hỏng
        case empty                // đọc được nhưng vùng chọn rỗng
        case unavailable          // không đọc được (app không hỗ trợ AX)
    }

    /// Đọc `kAXSelectedTextAttribute` của phần tử focus, biến đổi, chép kết quả
    /// vào clipboard, rồi ghi đè lại vùng chọn.
    private static func transformViaAX(_ transform: Transform) -> AXOutcome {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef
        ) == .success, let focused = focusedRef else {
            return .unavailable
        }
        let element = focused as! AXUIElement

        var selectedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextAttribute as CFString, &selectedRef
        ) == .success, let selected = selectedRef as? String else {
            return .unavailable
        }

        if selected.isEmpty { return .empty }

        let transformed = transform.apply(selected)
        // Chép trước khi ghi: dù ghi đè có thất bại, người dùng vẫn ⌘V được kết quả.
        putOnClipboard(transformed)

        if transformed == selected {
            // Không đổi gì (vd bỏ dấu chuỗi vốn không dấu) -> coi như xong, khỏi ghi.
            return .replaced
        }

        let ok = AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString, transformed as CFTypeRef
        ) == .success
        return ok ? .replaced : .copiedNotReplaced
    }

    // MARK: - Đường 2: Clipboard (⌘C -> biến đổi -> ⌘V)

    /// Fallback cho app không cho ghi `kAXSelectedTextAttribute` (Electron/web).
    /// Lấy vùng chọn qua ⌘C, biến đổi, dán đè qua ⌘V — và ĐỂ LẠI kết quả trong
    /// clipboard. Clipboard cũ chỉ được khôi phục khi thao tác THẤT BẠI (không
    /// lấy được vùng chọn), để lần bấm nhầm không phá clipboard đang dùng.
    private static func transformViaClipboard(_ transform: Transform) -> Bool {
        guard let selection = ClipboardManager.shared.copySelection(restoreAfter: false)
        else { return false }

        let transformed = transform.apply(selection)
        putOnClipboard(transformed)
        KeyOutput.simulatePaste()

        // KHÔNG khôi phục clipboard cũ ở đây: kết quả phải ở lại để ⌘V được sang
        // chỗ khác (vùng bôi đen thường chỉ-đọc — đoạn văn web, PDF). Nội dung
        // clipboard cũ vẫn nằm trong lịch sử của ClipboardManager.
        return true
    }
}
