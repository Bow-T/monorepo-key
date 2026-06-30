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

    /// Gửi `count` phím Backspace để xoá ký tự thô đã hiện.
    static func sendBackspaces(_ count: Int) {
        guard count > 0 else { return }
        for _ in 0..<count {
            postKey(keyCode: 51, down: true)   // 51 = Backspace
            postKey(keyCode: 51, down: false)
        }
    }

    /// Gõ một chuỗi Unicode vào ứng dụng đang focus.
    static func sendString(_ text: String) {
        guard !text.isEmpty else { return }
        let utf16 = Array(text.utf16)
        let source = makeSource()

        let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        down?.flags = []
        down?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        down?.setIntegerValueField(.eventSourceUserData, value: marker)
        down?.post(tap: .cghidEventTap)

        let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        up?.flags = []
        up?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        up?.setIntegerValueField(.eventSourceUserData, value: marker)
        up?.post(tap: .cghidEventTap)
    }

    /// Thay thế: xoá `backspaces` ký tự cũ rồi gõ `text` mới.
    static func replace(backspaces: Int, with text: String) {
        sendBackspaces(backspaces)
        sendString(text)
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

    // MARK: - Private

    private static func postKey(keyCode: CGKeyCode, down: Bool) {
        let event = CGEvent(keyboardEventSource: makeSource(), virtualKey: keyCode, keyDown: down)
        event?.setIntegerValueField(.eventSourceUserData, value: marker)
        event?.post(tap: .cghidEventTap)
    }
}
