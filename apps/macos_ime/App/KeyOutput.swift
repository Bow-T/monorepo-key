// KeyOutput.swift
// ---------------
// "Gõ thay" kết quả tiếng Việt vào ứng dụng đang focus.
//
// Cơ chế:
//   Khi engine biến "tieengs" thành "tiếng", ta cần:
//     1. Xoá những ký tự thô đã trót hiện ra (gửi N phím Backspace).
//     2. Gõ chuỗi tiếng Việt mới vào (post sự kiện keyboard mang Unicode).
//
// Ta dùng CGEvent với keyboardSetUnicodeString — gửi thẳng chuỗi Unicode mà không
// cần keyCode tương ứng. Đây là cách post ký tự "không có trên bàn phím" như "ế".
//
// POST QUA PROXY, ĐỒNG BỘ:
//   Sự kiện thay thế được post ngay trong callback của event tap qua
//   `tapPostEvent(proxy)` — KHÔNG dùng DispatchQueue.async. Post đồng bộ giữ ĐÚNG
//   THỨ TỰ so với phím người dùng và đẩy sự kiện trở lại đúng vị trí trong chuỗi
//   tap. Cách cũ (.cghidEventTap + async) gây race với các ô có autocomplete xử lý
//   phím tức thì (thanh địa chỉ trình duyệt, Spotlight): phím gốc lọt qua trước rồi
//   sự kiện async gõ thêm -> nhân đôi ký tự ("des" -> "ddé").
//
// PHÁ HIGHLIGHT AUTOCOMPLETE (chống gõ đôi "ddo" ở Chromium/Spotlight):
//   Post đồng bộ ở trên KHÔNG đủ khi ô đang BÔI ĐEN gợi ý: phím Backspace tổng hợp
//   bị ô gợi ý "nuốt" (để đóng dropdown) thay vì xoá ký tự thật -> ký tự cũ còn
//   nguyên, ta gõ thêm bản mới -> "d"+"o" thành "ddo". `replace(...,
//   erase: .breakAutocompleteHighlight)` gửi TRƯỚC một ký tự rỗng (U+202F) để trình
//   duyệt bỏ highlight, rồi Backspace mới ăn.

import CoreGraphics
import Foundation
import ApplicationServices

enum KeyOutput {

    /// Tạo nguồn sự kiện mới mỗi lần dùng. Dùng .privateState để sự kiện ta tạo
    /// không trộn lẫn trạng thái phím thật. (Không lưu static để tránh va chạm
    /// strict-concurrency của Swift 6 — CGEventSource không Sendable.)
    private static func makeSource() -> CGEventSource? {
        CGEventSource(stateID: .privateState)
    }

    /// Đánh dấu để event tap của CHÍNH TA nhận ra sự kiện do ta tự tạo và bỏ qua,
    /// tránh vòng lặp vô tận (ta post -> tap ta bắt lại -> xử lý -> post...).
    static let marker: Int64 = 0x42_4F_57_4B   // "BOWK" cho vui; giá trị bất kỳ là được

    /// Post một sự kiện tổng hợp trở lại CHÍNH chuỗi tap qua proxy (đồng bộ).
    private static func post(_ event: CGEvent?, proxy: CGEventTapProxy) {
        guard let event else { return }
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        event.tapPostEvent(proxy)
    }

    /// Giới hạn AN TOÀN số Backspace gửi trong một lần thay thế. Một âm tiết tiếng
    /// Việt dài nhất (vd "nghiêng") chỉ ~7 ký tự hiển thị, nên không bao giờ cần xoá
    /// nhiều hơn ngần này. Nếu state engine lỗi và trả số lớn bất thường, clamp lại
    /// để KHÔNG xoá nhầm hàng loạt ký tự người dùng đã gõ.
    static let maxBackspaces = 15

    /// Gửi `count` phím Backspace để xoá ký tự thô đã hiện.
    static func sendBackspaces(_ count: Int, proxy: CGEventTapProxy) {
        guard count > 0 else { return }
        let safe = min(count, maxBackspaces)
        if count > maxBackspaces {
            NSLog("[KeyOutput] Chặn số Backspace bất thường: %d -> %d", count, maxBackspaces)
        }
        let source = makeSource()
        for _ in 0..<safe {
            let down = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: true)  // 51 = Backspace
            down?.flags.insert(.maskNonCoalesced)   // chống macOS gộp các phím lặp
            post(down, proxy: proxy)
            let up = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: false)
            up?.flags.insert(.maskNonCoalesced)
            post(up, proxy: proxy)
        }
    }

    /// keyCode mũi tên trái (macOS). Dùng cho cách thay-thế-bằng-bôi-đen (Spotlight).
    private static let leftArrowKey: CGKeyCode = 123

    /// Gửi `count` lần Shift+Mũi-tên-trái để BÔI ĐEN `count` ký tự bên trái con trỏ.
    /// Sau đó gõ chuỗi mới sẽ GHI ĐÈ vùng bôi đen (không cần Backspace).
    ///
    /// Vì sao cần cách này? Ở Spotlight, Backspace tổng hợp không xoá đáng tin (giống
    /// autocomplete trình duyệt) NHƯNG ký tự rỗng cũng không phá được highlight và có
    /// thể để lại vệt. Bôi-đen-rồi-ghi-đè né cả hai.
    static func sendShiftLeftArrow(_ count: Int, proxy: CGEventTapProxy) {
        guard count > 0 else { return }
        let safe = min(count, maxBackspaces)
        if count > maxBackspaces {
            NSLog("[KeyOutput] Chặn số Shift+Left bất thường: %d -> %d", count, maxBackspaces)
        }
        let source = makeSource()
        for _ in 0..<safe {
            let down = CGEvent(keyboardEventSource: source, virtualKey: leftArrowKey, keyDown: true)
            down?.flags.insert(.maskShift)
            down?.flags.insert(.maskNonCoalesced)
            post(down, proxy: proxy)
            let up = CGEvent(keyboardEventSource: source, virtualKey: leftArrowKey, keyDown: false)
            up?.flags.insert(.maskShift)
            up?.flags.insert(.maskNonCoalesced)
            post(up, proxy: proxy)
        }
    }

    /// Ký tự "rỗng" gửi trước để PHÁ HIGHLIGHT autocomplete của trình duyệt.
    ///
    /// Ở ô có autocomplete (thanh địa chỉ/tìm kiếm Chromium — Edge/Chrome/Brave/Cốc
    /// Cốc), khi gợi ý đang được bôi đen, phím Backspace TỔNG HỢP của ta bị ô gợi ý
    /// "nuốt" (dùng để đóng dropdown) thay vì xoá ký tự thật -> ký tự cũ còn nguyên,
    /// ta gõ thêm bản mới -> NHÂN ĐÔI ("d" + "o" -> "ddo").
    ///
    /// (SPOTLIGHT dùng cách KHÁC — bôi đen bằng Shift+Mũi-tên-trái, xem
    /// `sendShiftLeftArrow` — vì ký tự rỗng không phá được highlight của Spotlight và
    /// có nguy cơ để lại vệt.)
    ///
    /// Mẹo: gửi MỘT ký tự rỗng trước. Nó khiến trình duyệt BỎ highlight gợi ý (như
    /// vừa gõ thêm chữ), sau đó Backspace hoạt động BÌNH THƯỜNG trở lại. Ta gửi kèm 1
    /// Backspace phụ để xoá luôn ký tự rỗng này.
    ///
    /// Dùng U+202F (NARROW NO-BREAK SPACE): một ký tự khoảng trắng "vô hình" mà trình
    /// duyệt coi là ký tự chèn thêm (đủ để bỏ highlight). KHÔNG dùng khoảng trắng
    /// thường để tránh chèn nhầm space thấy được nếu một app không xoá kịp.
    static let emptyChar: UnicodeScalar = "\u{202F}"

    /// Gửi ký tự rỗng (phá highlight autocomplete). Xem `emptyChar`.
    static func sendEmptyCharacter(proxy: CGEventTapProxy) {
        let utf16 = Array(String(emptyChar).utf16)
        let source = makeSource()
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        down?.flags = []
        down?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        post(down, proxy: proxy)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        up?.flags = []
        up?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        post(up, proxy: proxy)
    }

    /// Gõ một chuỗi Unicode vào ứng dụng đang focus.
    static func sendString(_ text: String, proxy: CGEventTapProxy) {
        guard !text.isEmpty else { return }
        let utf16 = Array(text.utf16)
        let source = makeSource()

        let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        down?.flags = []
        down?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        post(down, proxy: proxy)

        let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        up?.flags = []
        up?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        post(up, proxy: proxy)
    }

    /// Cách "xoá ký tự cũ" khi gõ thay — tuỳ ô nhập liệu.
    enum EraseStrategy {
        /// Backspace thường. Dùng cho hầu hết app.
        case backspace
        /// Ô autocomplete trình duyệt Chromium: gửi ký tự rỗng (U+202F) phá highlight
        /// trước rồi Backspace (kèm 1 backspace phụ xoá ký tự rỗng). Chống gõ đôi "ddo".
        case breakAutocompleteHighlight
        /// Spotlight: bôi đen bằng Shift+Mũi-tên-trái rồi ghi đè. Backspace/ký-tự-rỗng
        /// đều không đáng tin ở Spotlight; bôi-đen-ghi-đè né cả hai.
        case selectionReplacement
    }

    /// Sử dụng Accessibility API (AXUIElement) để trực tiếp thay thế nội dung trong ô nhập liệu đang focus.
    /// Trả về true nếu thành công, false nếu thất bại (không có quyền AX hoặc không hỗ trợ).
    static func replaceFocusedTextViaAX(backspaces: Int, insertText: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focused = focusedRef else {
            return false
        }
        let element = focused as! AXUIElement

        // Đọc giá trị hiện tại
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let valueStr = valueRef as? String else {
            return false
        }

        let valueNSString = valueStr as NSString
        let valueLength = valueNSString.length

        // Đọc vị trí con trỏ và vùng bôi đen (nếu có)
        var caretLocation = valueLength
        var selectedLength = 0
        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let range = rangeRef {
            var sel = CFRange()
            if AXValueGetValue(range as! AXValue, .cfRange, &sel) {
                caretLocation = sel.location
                selectedLength = sel.length
            }
        }

        // Kẹp caretLocation trong khoảng hợp lệ
        if caretLocation < 0 { caretLocation = 0 }
        if caretLocation > valueLength { caretLocation = valueLength }

        // Xác định vị trí và độ dài cần xoá/ghi đè
        var start = caretLocation
        var len = 0
        let selectionAtEnd = selectedLength > 0 && (caretLocation + selectedLength == valueLength)

        if selectedLength > 0 && !selectionAtEnd {
            // Đang bôi đen ở giữa: chỉ ghi đè vùng bôi đen
            start = caretLocation
            len = selectedLength
        } else {
            // Không bôi đen hoặc bôi đen gợi ý Spotlight ở cuối: xoá backspaces ký tự thô
            let deleteStart = max(0, caretLocation - backspaces)
            if selectionAtEnd {
                start = deleteStart
                len = (caretLocation - deleteStart) + selectedLength
            } else {
                start = deleteStart
                len = caretLocation - deleteStart
            }
        }

        // Kẹp lại độ dài
        if start + len > valueLength {
            len = valueLength - start
        }
        if len < 0 { len = 0 }

        let newValue = valueNSString.replacingCharacters(in: NSRange(location: start, length: len), with: insertText)

        // Ghi giá trị mới
        guard AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, newValue as CFTypeRef) == .success else {
            return false
        }

        // Cập nhật vị trí con trỏ
        let newCaret = start + (insertText as NSString).length
        var newSel = CFRange(location: newCaret, length: 0)
        if let newRange = AXValueCreate(.cfRange, &newSel) {
            _ = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, newRange)
        }

        return true
    }

    /// Thay thế: xoá `backspaces` ký tự cũ rồi gõ `text` mới (đồng bộ, qua proxy).
    ///
    /// `erase` chọn cách xoá theo ô nhập liệu (xem `EraseStrategy`). Với các cách đặc
    /// biệt (autocomplete/Spotlight), CHỈ kích hoạt khi thực sự có ký tự cần xoá
    /// (`backspaces > 0`); khi gõ ký tự MỞ ĐẦU âm tiết (`backspaces == 0`) thì không có
    /// highlight/vùng chọn nào để xử lý nên rơi về gõ thẳng.
    static func replace(backspaces: Int, with text: String, proxy: CGEventTapProxy,
                        erase: EraseStrategy = .backspace) {
        if erase == .selectionReplacement {
            if replaceFocusedTextViaAX(backspaces: backspaces, insertText: text) {
                return
            }
            // Fallback nếu AX API thất bại
        }

        switch erase {
        case .breakAutocompleteHighlight where backspaces > 0:
            sendEmptyCharacter(proxy: proxy)                // phá highlight autocomplete
            sendBackspaces(backspaces + 1, proxy: proxy)    // +1 để xoá ký tự rỗng
        case .selectionReplacement where backspaces > 0:
            sendShiftLeftArrow(backspaces, proxy: proxy)    // bôi đen -> chuỗi mới ghi đè
        default:
            sendBackspaces(backspaces, proxy: proxy)
        }
        sendString(text, proxy: proxy)
    }

    /// Giả lập tổ hợp phím Command + V để paste dữ liệu hiện tại từ clipboard.
    static func simulatePaste() {
        let source = makeSource()
        // Phím 'V' có keyCode là 9 trên macOS
        let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        down?.flags = .maskCommand
        down?.setIntegerValueField(.eventSourceUserData, value: marker)
        down?.post(tap: .cghidEventTap)

        let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        up?.flags = []
        up?.setIntegerValueField(.eventSourceUserData, value: marker)
        up?.post(tap: .cghidEventTap)
    }
}
