// NumberToWordsTests.swift
// ------------------------
// Test đọc số thành chữ tiếng Việt — trọng tâm là các quy tắc chính tả đặc thù:
// mười/mươi, mốt, lăm, linh, nhóm nghìn/triệu/tỷ.

import Testing
import Foundation
@testable import VietEngine

@Suite("Đọc số thành chữ")
struct NumberToWordsTests {

    @Test("Số một chữ số")
    func singleDigit() {
        #expect(NumberToWords.convert("0") == "không")
        #expect(NumberToWords.convert("1") == "một")
        #expect(NumberToWords.convert("5") == "năm")
        #expect(NumberToWords.convert("9") == "chín")
    }

    @Test("Hàng chục: mười vs mươi")
    func tens() {
        #expect(NumberToWords.convert("10") == "mười")
        #expect(NumberToWords.convert("11") == "mười một")
        #expect(NumberToWords.convert("15") == "mười lăm")       // lăm, không phải "năm"
        #expect(NumberToWords.convert("20") == "hai mươi")       // mươi
        #expect(NumberToWords.convert("21") == "hai mươi mốt")   // mốt, không phải "một"
        #expect(NumberToWords.convert("25") == "hai mươi lăm")   // lăm
        #expect(NumberToWords.convert("99") == "chín mươi chín")
    }

    @Test("Hàng trăm + linh")
    func hundreds() {
        #expect(NumberToWords.convert("100") == "một trăm")
        #expect(NumberToWords.convert("101") == "một trăm linh một")  // linh
        #expect(NumberToWords.convert("105") == "một trăm linh năm")
        #expect(NumberToWords.convert("110") == "một trăm mười")
        #expect(NumberToWords.convert("111") == "một trăm mười một")
        #expect(NumberToWords.convert("115") == "một trăm mười lăm")
        #expect(NumberToWords.convert("123") == "một trăm hai mươi ba")
        #expect(NumberToWords.convert("999") == "chín trăm chín mươi chín")
    }

    @Test("Hàng nghìn")
    func thousands() {
        #expect(NumberToWords.convert("1000") == "một nghìn")
        #expect(NumberToWords.convert("1500") == "một nghìn năm trăm")
        // 1005: nhóm đơn vị = 005 -> "không trăm linh năm"
        #expect(NumberToWords.convert("1005") == "một nghìn không trăm linh năm")
        #expect(NumberToWords.convert("1234") == "một nghìn hai trăm ba mươi bốn")
        #expect(NumberToWords.convert("10000") == "mười nghìn")
    }

    @Test("Hàng triệu / tỷ")
    func millionsBillions() {
        #expect(NumberToWords.convert("1000000") == "một triệu")
        #expect(NumberToWords.convert("1500000") == "một triệu năm trăm nghìn")
        #expect(NumberToWords.convert("1000000000") == "một tỷ")
        #expect(NumberToWords.convert("1234567") ==
                "một triệu hai trăm ba mươi bốn nghìn năm trăm sáu mươi bảy")
    }

    @Test("Số âm")
    func negative() {
        #expect(NumberToWords.convert("-5") == "âm năm")
        #expect(NumberToWords.convert("-123") == "âm một trăm hai mươi ba")
    }

    @Test("Số thập phân: phẩy + đọc từng chữ số")
    func decimal() {
        #expect(NumberToWords.convert("1.5") == "một phẩy năm")
        #expect(NumberToWords.convert("3.14") == "ba phẩy một bốn")
        #expect(NumberToWords.convert("0.5") == "không phẩy năm")
    }

    @Test("Dấu phân nhóm hàng nghìn được bỏ")
    func groupSeparators() {
        #expect(NumberToWords.convert("1,500,000") == "một triệu năm trăm nghìn")
        // Nhiều dấu '.' -> phân nhóm (không phải thập phân).
        #expect(NumberToWords.convert("1.500.000") == "một triệu năm trăm nghìn")
    }

    @Test("Số 0 ở đầu được chuẩn hoá")
    func leadingZeros() {
        #expect(NumberToWords.convert("007") == "bảy")
        #expect(NumberToWords.convert("0100") == "một trăm")
    }

    @Test("Chuỗi không phải số -> nil")
    func invalid() {
        #expect(NumberToWords.convert("abc") == nil)
        #expect(NumberToWords.convert("12a3") == nil)
        #expect(NumberToWords.convert("") == nil)
        #expect(NumberToWords.convert("1.2.3.4a") == nil)
        #expect(NumberToWords.convert(".5") == nil)   // thiếu phần nguyên
        #expect(NumberToWords.convert("5.") == nil)   // thiếu phần lẻ
    }

    @Test("Khoảng trắng bao quanh được bỏ")
    func whitespace() {
        #expect(NumberToWords.convert("  42  ") == "bốn mươi hai")
    }
}
