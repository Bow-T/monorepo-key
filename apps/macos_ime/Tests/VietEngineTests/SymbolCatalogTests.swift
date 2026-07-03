// SymbolCatalogTests.swift
// ------------------------
// Kiểm tra danh mục ký tự picker: không rỗng, không trùng trong mỗi nhóm, emoji
// đều lấy được từ bảng shortcode (một nguồn sự thật).

import Testing
import Foundation
@testable import VietEngine

@Suite("Danh mục ký tự picker")
struct SymbolCatalogTests {

    @Test("Có đủ nhóm, mỗi nhóm có mục và tiêu đề")
    func groups() {
        let groups = SymbolCatalog.groups()
        #expect(groups.count >= 2)
        for g in groups {
            #expect(!g.title.isEmpty)
            #expect(!g.items.isEmpty)
        }
    }

    @Test("Không mục nào rỗng")
    func noEmptyItems() {
        for g in SymbolCatalog.groups() {
            for item in g.items {
                #expect(!item.isEmpty)
            }
        }
    }

    @Test("Không trùng lặp trong từng nhóm")
    func noDuplicatesPerGroup() {
        for g in SymbolCatalog.groups() {
            #expect(Set(g.items).count == g.items.count, "Nhóm \(g.title) có mục trùng")
        }
    }

    @Test("Emoji trong catalog đều là giá trị hợp lệ từ bảng shortcode")
    func emojisFromTable() {
        let known = Set(EmojiShortcodes.table.values)
        for emoji in SymbolCatalog.emojis {
            #expect(known.contains(emoji), "emoji \(emoji) không có trong bảng shortcode")
        }
        // Danh sách emoji không rỗng (đề phòng đổi keyword mà quên cập nhật).
        #expect(!SymbolCatalog.emojis.isEmpty)
    }

    @Test("Ký tự đặc biệt đủ nhiều để hữu dụng")
    func specialsPresent() {
        #expect(SymbolCatalog.specials.count >= 20)
        #expect(SymbolCatalog.specials.contains("→"))
        #expect(SymbolCatalog.specials.contains("₫"))
        #expect(SymbolCatalog.specials.contains("✓"))
    }
}
