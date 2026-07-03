// RecentItems.swift
// -----------------
// DANH SÁCH "GẦN ĐÂY" (MRU — most-recently-used) cho các bảng picker: sticker &
// ký tự/emoji. Logic THUẦN (mảng String) -> test được; tầng App lo lưu/đọc đĩa.
//
// Quy tắc: mục vừa dùng đẩy lên ĐẦU; nếu đã có thì chuyển lên đầu (khử trùng);
// cắt còn tối đa `limit` mục. Mục là một khoá chuỗi (slug sticker hoặc ký tự).

import Foundation

public struct RecentItems: Equatable {

    /// Danh sách khoá, mục mới nhất ở ĐẦU (index 0).
    public private(set) var items: [String]

    /// Số mục tối đa giữ lại.
    public let limit: Int

    public init(items: [String] = [], limit: Int = 12) {
        self.limit = max(1, limit)
        // Khử trùng giữ thứ tự, rồi cắt theo limit (phòng dữ liệu đĩa hỏng).
        var seen = Set<String>()
        var cleaned: [String] = []
        for it in items where !it.isEmpty && seen.insert(it).inserted {
            cleaned.append(it)
        }
        self.items = Array(cleaned.prefix(self.limit))
    }

    /// Ghi nhận vừa dùng `key`: đưa lên đầu, khử trùng, cắt theo limit.
    public mutating func use(_ key: String) {
        guard !key.isEmpty else { return }
        items.removeAll { $0 == key }
        items.insert(key, at: 0)
        if items.count > limit { items = Array(items.prefix(limit)) }
    }

    /// Xoá toàn bộ (nút "Xoá gần đây").
    public mutating func clear() {
        items.removeAll()
    }

    public var isEmpty: Bool { items.isEmpty }
}
