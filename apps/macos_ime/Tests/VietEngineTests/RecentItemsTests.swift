// RecentItemsTests.swift
// ----------------------
// Test danh sách MRU "gần đây": đưa lên đầu, khử trùng, cắt theo giới hạn.

import Testing
import Foundation
@testable import VietEngine

@Suite("Gần đây (MRU)")
struct RecentItemsTests {

    @Test("use đưa mục lên đầu")
    func useMovesToFront() {
        var r = RecentItems(limit: 5)
        r.use("a")
        r.use("b")
        r.use("c")
        #expect(r.items == ["c", "b", "a"])
    }

    @Test("Dùng lại mục cũ -> chuyển lên đầu, không nhân đôi")
    func reuseDedups() {
        var r = RecentItems(limit: 5)
        r.use("a"); r.use("b"); r.use("c")
        r.use("a")   // a đã có -> lên đầu
        #expect(r.items == ["a", "c", "b"])
        #expect(r.items.count == 3)
    }

    @Test("Cắt theo limit, bỏ mục cũ nhất")
    func trimsToLimit() {
        var r = RecentItems(limit: 3)
        for k in ["a", "b", "c", "d", "e"] { r.use(k) }
        #expect(r.items == ["e", "d", "c"])   // a, b bị đẩy ra
    }

    @Test("Khởi tạo từ đĩa: khử trùng + cắt limit")
    func initCleansData() {
        // Dữ liệu đĩa có thể trùng / quá dài -> làm sạch.
        let r = RecentItems(items: ["a", "b", "a", "c", "b", "d"], limit: 3)
        #expect(r.items == ["a", "b", "c"])   // giữ thứ tự lần xuất hiện đầu, cắt 3
    }

    @Test("Bỏ qua khoá rỗng")
    func ignoresEmpty() {
        var r = RecentItems(limit: 5)
        r.use("")
        r.use("a")
        r.use("")
        #expect(r.items == ["a"])
    }

    @Test("clear xoá hết")
    func clearEmpties() {
        var r = RecentItems(limit: 5)
        r.use("a"); r.use("b")
        r.clear()
        #expect(r.isEmpty)
    }

    @Test("limit tối thiểu là 1")
    func minLimitOne() {
        var r = RecentItems(limit: 0)
        r.use("a"); r.use("b")
        #expect(r.items == ["b"])   // limit bị kẹp lên 1
    }
}
