// RecentPickerStore.swift
// -----------------------
// Lưu/đọc danh sách "gần đây" cho hai bảng picker (sticker & ký tự/emoji) vào
// UserDefaults (bộ nhớ nhỏ, cục bộ, riêng máy — KHÔNG đụng settings.json/stats.json).
//
// Logic MRU ở `RecentItems` (engine, test được); đây chỉ lo bền hoá qua UserDefaults.
// Chỉ dùng từ MainActor (bảng picker chạy trên UI).

import Foundation
import VietEngine

@MainActor
enum RecentPickerStore {

    private static let stickerKey = "recentStickers"
    private static let symbolKey = "recentSymbols"
    private static let limit = 12

    // MARK: - Sticker (theo slug)

    static func recentStickers() -> [String] {
        load(stickerKey)
    }

    static func useSticker(_ slug: String) {
        var r = RecentItems(items: load(stickerKey), limit: limit)
        r.use(slug)
        save(stickerKey, r.items)
    }

    // MARK: - Ký tự/emoji (theo chuỗi)

    static func recentSymbols() -> [String] {
        load(symbolKey)
    }

    static func useSymbol(_ symbol: String) {
        var r = RecentItems(items: load(symbolKey), limit: limit)
        r.use(symbol)
        save(symbolKey, r.items)
    }

    // MARK: - Đĩa

    private static func load(_ key: String) -> [String] {
        (UserDefaults.standard.array(forKey: key) as? [String]) ?? []
    }

    private static func save(_ key: String, _ items: [String]) {
        UserDefaults.standard.set(items, forKey: key)
    }
}
