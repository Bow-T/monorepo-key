// NumberGroupingTests.swift
// -------------------------
// Test định dạng số có/không dấu phân nhóm hàng nghìn (kiểu VN).

import Testing
import Foundation
@testable import VietEngine

@Suite("Định dạng số phân nhóm")
struct NumberGroupingTests {

    // MARK: - group

    @Test("group: thêm dấu chấm mỗi 3 chữ số")
    func groupBasic() {
        #expect(NumberGrouping.group("1500000") == "1.500.000")
        #expect(NumberGrouping.group("1000") == "1.000")
        #expect(NumberGrouping.group("999") == "999")           // <1000 không đổi
        #expect(NumberGrouping.group("1000000000") == "1.000.000.000")
    }

    @Test("group: giữ dấu âm")
    func groupNegative() {
        #expect(NumberGrouping.group("-1000") == "-1.000")
        #expect(NumberGrouping.group("-2500000") == "-2.500.000")
    }

    @Test("group: phần thập phân dùng dấu phẩy, không chèn nhóm")
    func groupDecimal() {
        #expect(NumberGrouping.group("1234,5") == "1.234,5")
        #expect(NumberGrouping.group("1000000,25") == "1.000.000,25")
    }

    @Test("group: bỏ 0 đầu thừa")
    func groupLeadingZeros() {
        #expect(NumberGrouping.group("0001500") == "1.500")
        #expect(NumberGrouping.group("0") == "0")
    }

    // MARK: - ungroup

    @Test("ungroup: bỏ dấu phân nhóm")
    func ungroupBasic() {
        #expect(NumberGrouping.ungroup("1.500.000") == "1500000")
        #expect(NumberGrouping.ungroup("1.000") == "1000")
        #expect(NumberGrouping.ungroup("999") == "999")
    }

    @Test("ungroup: chuyển thập phân phẩy → chấm (máy đọc)")
    func ungroupDecimal() {
        #expect(NumberGrouping.ungroup("1.234,5") == "1234.5")
        #expect(NumberGrouping.ungroup("1.000.000,25") == "1000000.25")
    }

    @Test("ungroup: giữ dấu âm")
    func ungroupNegative() {
        #expect(NumberGrouping.ungroup("-1.000") == "-1000")
    }

    // MARK: - Khứ hồi

    @Test("group rồi ungroup trở lại số gốc")
    func roundTrip() {
        for n in ["1500000", "1000", "42", "999999999"] {
            let g = NumberGrouping.group(n)!
            #expect(NumberGrouping.ungroup(g) == n)
        }
    }

    // MARK: - Đầu vào không hợp lệ

    @Test("Chuỗi không phải số -> nil")
    func invalid() {
        #expect(NumberGrouping.group("abc") == nil)
        #expect(NumberGrouping.group("12a3") == nil)
        #expect(NumberGrouping.group("") == nil)
        #expect(NumberGrouping.ungroup("xyz") == nil)
    }

    @Test("Khoảng trắng bao quanh được bỏ")
    func whitespace() {
        #expect(NumberGrouping.group("  1500000  ") == "1.500.000")
    }
}
