// CalculatorTests.swift
// ---------------------
// Test máy tính biểu thức cho macro `calc` + biến đổi "Tính" vùng bôi đen.

import Testing
import Foundation
@testable import VietEngine

@Suite("Máy tính biểu thức")
struct CalculatorTests {

    @Test("Bốn phép cơ bản")
    func basicOps() {
        #expect(Calculator.eval("2+3") == "5")
        #expect(Calculator.eval("10-4") == "6")
        #expect(Calculator.eval("6*7") == "42")
        #expect(Calculator.eval("20/5") == "4")
    }

    @Test("Ưu tiên toán tử (* / trước + -)")
    func precedence() {
        #expect(Calculator.eval("5*3+2") == "17")
        #expect(Calculator.eval("2+3*4") == "14")
        #expect(Calculator.eval("10-2*3") == "4")
    }

    @Test("Dấu ngoặc")
    func parentheses() {
        #expect(Calculator.eval("(2+3)*4") == "20")
        #expect(Calculator.eval("(2+3)/4") == "1.25")
        #expect(Calculator.eval("2*(3+(4-1))") == "12")
    }

    @Test("Số thập phân & số âm")
    func decimalsAndNegatives() {
        #expect(Calculator.eval("1.5+2.5") == "4")
        #expect(Calculator.eval("-3+5") == "2")
        #expect(Calculator.eval("3*-2") == "-6")
        #expect(Calculator.eval("10/4") == "2.5")
    }

    @Test("Khoảng trắng được bỏ qua")
    func whitespace() {
        #expect(Calculator.eval(" 2 + 3 * 4 ") == "14")
    }

    @Test("Kết quả nguyên không có .0")
    func integerFormat() {
        #expect(Calculator.eval("4/2") == "2")
        #expect(Calculator.eval("9/3") == "3")
    }

    @Test("Số lẻ tuần hoàn -> tối đa 6 chữ số, bỏ 0 thừa")
    func repeatingDecimal() {
        #expect(Calculator.eval("1/3") == "0.333333")
        #expect(Calculator.eval("1/8") == "0.125")
    }

    @Test("Chia 0 -> nil")
    func divideByZero() {
        #expect(Calculator.eval("5/0") == nil)
        #expect(Calculator.eval("1/(2-2)") == nil)
    }

    @Test("Biểu thức sai cú pháp -> nil")
    func invalid() {
        #expect(Calculator.eval("abc") == nil)
        #expect(Calculator.eval("2+") == nil)
        #expect(Calculator.eval("(2+3") == nil)     // ngoặc lệch
        #expect(Calculator.eval("2+3)") == nil)
        #expect(Calculator.eval("") == nil)
        #expect(Calculator.eval("2 3") == nil)      // hai số không toán tử
    }

    @Test("Chuỗi văn bản thường (không phải biểu thức) -> nil (giữ nguyên khi transform)")
    func plainText() {
        #expect(Calculator.eval("Xin chào") == nil)
        #expect(Calculator.eval("Tiếng Việt") == nil)
    }
}
