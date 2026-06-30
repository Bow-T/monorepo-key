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

import CoreGraphics
import Foundation

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

    /// Thay thế: xoá `backspaces` ký tự cũ rồi gõ `text` mới (đồng bộ, qua proxy).
    static func replace(backspaces: Int, with text: String, proxy: CGEventTapProxy) {
        sendBackspaces(backspaces, proxy: proxy)
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
