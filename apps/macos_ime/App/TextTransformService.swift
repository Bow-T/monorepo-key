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
//   2. Fallback qua clipboard: nếu AX không đọc/ghi được (nhiều app Electron/web
//      chỉ hỗ trợ selection một chiều), ta: sao lưu clipboard -> ⌘C để lấy vùng
//      chọn -> biến đổi -> đặt vào clipboard -> ⌘V dán đè -> khôi phục clipboard.
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
    @discardableResult
    static func run(_ transform: Transform) -> Result {
        // Ưu tiên đường AX (sạch, không đụng clipboard).
        switch transformViaAX(transform) {
        case .success:
            ToastHUD.show("✓ \(transform.title.uppercased())")
            return .success(transform)
        case .emptySelection:
            ToastHUD.show("CHƯA BÔI ĐEN CHỮ NÀO")
            return .emptySelection
        case .failed:
            // AX không đọc/ghi được -> thử đường clipboard.
            break
        }

        if transformViaClipboard(transform) {
            ToastHUD.show("✓ \(transform.title.uppercased())")
            return .success(transform)
        }
        ToastHUD.show("KHÔNG BIẾN ĐỔI ĐƯỢC VÙNG CHỌN")
        return .failed
    }

    // MARK: - Đường 1: Accessibility API

    /// Đọc `kAXSelectedTextAttribute` của phần tử focus, biến đổi, ghi đè lại.
    /// Trả `.emptySelection` nếu đọc được nhưng RỖNG; `.failed` nếu không đọc/ghi được.
    private static func transformViaAX(_ transform: Transform) -> Result {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef
        ) == .success, let focused = focusedRef else {
            return .failed
        }
        let element = focused as! AXUIElement

        var selectedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextAttribute as CFString, &selectedRef
        ) == .success, let selected = selectedRef as? String else {
            return .failed
        }

        if selected.isEmpty { return .emptySelection }

        let transformed = transform.apply(selected)
        if transformed == selected {
            // Không đổi gì (vd bỏ dấu chuỗi vốn không dấu) -> coi như thành công, khỏi ghi.
            return .success(transform)
        }

        let ok = AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString, transformed as CFTypeRef
        ) == .success
        return ok ? .success(transform) : .failed
    }

    // MARK: - Đường 2: Clipboard (⌘C -> biến đổi -> ⌘V), khôi phục clipboard

    /// Fallback cho app không cho ghi `kAXSelectedTextAttribute` (Electron/web).
    /// Sao lưu clipboard, lấy vùng chọn qua ⌘C, biến đổi, dán đè qua ⌘V, trả clipboard.
    private static func transformViaClipboard(_ transform: Transform) -> Bool {
        let pasteboard = NSPasteboard.general

        // Sao lưu toàn bộ item hiện có để khôi phục nguyên vẹn (kể cả ảnh/định dạng).
        let savedItems = pasteboard.pasteboardItems?.compactMap { item -> NSPasteboardItem? in
            let copy = NSPasteboardItem()
            var wroteAny = false
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                    wroteAny = true
                }
            }
            return wroteAny ? copy : nil
        } ?? []

        let beforeChange = pasteboard.changeCount
        KeyOutput.simulateCopy()

        // ⌘C là bất đồng bộ — chờ pasteboard đổi (tối đa ~0.4s) rồi mới đọc.
        let selection = waitForPasteboardText(after: beforeChange, pasteboard: pasteboard)
        guard let selection, !selection.isEmpty else {
            restore(items: savedItems, to: pasteboard)
            return false
        }

        let transformed = transform.apply(selection)
        pasteboard.clearContents()
        pasteboard.setString(transformed, forType: .string)
        KeyOutput.simulatePaste()

        // Chờ paste ăn xong rồi mới trả clipboard cũ (nếu trả sớm sẽ dán nhầm nội dung cũ).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.restore(items: savedItems, to: pasteboard)
        }
        return true
    }

    /// Bận-chờ ngắn cho ⌘C: pasteboard đổi `changeCount` khi có nội dung mới.
    private static func waitForPasteboardText(
        after previousChange: Int, pasteboard: NSPasteboard
    ) -> String? {
        let deadline = Date().addingTimeInterval(0.4)
        while Date() < deadline {
            if pasteboard.changeCount != previousChange {
                return pasteboard.string(forType: .string)
            }
            // Bơm run loop để không chặn cứng main thread trong lúc chờ.
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        // Hết giờ mà changeCount không đổi (vùng chọn rỗng hoặc app nuốt ⌘C).
        return pasteboard.changeCount != previousChange ? pasteboard.string(forType: .string) : nil
    }

    private static func restore(items: [NSPasteboardItem], to pasteboard: NSPasteboard) {
        guard !items.isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.writeObjects(items)
    }
}
