// ExpansionUndo.swift
// -------------------
// UNDO NGAY SAU KHI BUNG gõ tắt / emoji / tự-sửa / tự-khôi-phục-Anh.
//
// Hành vi (chuẩn của các bộ gõ tốt): người dùng vừa để một chuỗi được bung tự động
// (vd gõ "vn " -> "Việt Nam "), nếu NHẤN BACKSPACE NGAY LẬP TỨC thì thay vì xoá 1
// ký tự, ta khôi phục lại nguyên chuỗi gốc ("vn "). Chỉ đúng MỘT nhịp: phím kế tiếp
// (dù là gì) đều huỷ trạng thái undo.
//
// Lớp này THUẦN LOGIC (không AppKit) -> test được. Bộ điều khiển lo đồng bộ màn hình:
//   • Khi bung: gọi arm(shown:original:) với chuỗi ĐÃ HIỆN và chuỗi GỐC cần trả lại.
//   • Ở phím kế: nếu là Backspace, gọi consumeBackspace() -> nếu có undo, trả về
//     (số ký tự cần xoá, chuỗi gốc để gõ lại). Phím khác -> gọi disarm().

import Foundation

public struct ExpansionUndo {

    /// Thông tin để thực hiện undo: xoá `deleteCount` ký tự đã hiện, gõ lại `restore`.
    public struct Action: Equatable {
        public let deleteCount: Int
        public let restore: String
    }

    /// Chuỗi đã hiển thị sau bung (để biết cần xoá bao nhiêu ký tự).
    private var shown: String?
    /// Chuỗi gốc cần khôi phục.
    private var original: String?

    public init() {}

    /// Có đang "vũ trang" (sẵn sàng undo ở Backspace kế tiếp) không.
    public var isArmed: Bool { shown != nil }

    /// Ghi nhận một lần bung. `shown` = chuỗi vừa hiện trên màn (vd "Việt Nam ");
    /// `original` = chuỗi gốc để trả lại khi undo (vd "vn "). Bỏ qua nếu rỗng hoặc
    /// hai chuỗi giống hệt (không có gì để undo).
    public mutating func arm(shown: String, original: String) {
        guard !shown.isEmpty, shown != original else { disarm(); return }
        self.shown = shown
        self.original = original
    }

    /// Xoá trạng thái undo (gọi khi phím kế KHÔNG phải Backspace, hoặc sau khi undo).
    public mutating func disarm() {
        shown = nil
        original = nil
    }

    /// Người dùng vừa nhấn Backspace. Nếu đang vũ trang -> trả Action để bộ điều khiển
    /// khôi phục chuỗi gốc, đồng thời TỰ disarm (undo chỉ 1 nhịp). Nếu không -> nil.
    public mutating func consumeBackspace() -> Action? {
        guard let shown, let original else { return nil }
        let action = Action(deleteCount: shown.count, restore: original)
        disarm()
        return action
    }
}
