// TextStatsTests.swift
// --------------------
// Test đếm từ / ký tự / dòng cho tính năng "Đếm vùng bôi đen".

import Testing
import Foundation
@testable import VietEngine

@Suite("Đếm từ & ký tự")
struct TextStatsTests {

    @Test("Đếm từ cơ bản")
    func words() {
        #expect(TextStats.of("xin chào các bạn").words == 4)
        #expect(TextStats.of("một").words == 1)
        #expect(TextStats.of("").words == 0)
    }

    @Test("Nhiều khoảng trắng liên tiếp không đếm thành từ rỗng")
    func extraSpaces() {
        #expect(TextStats.of("a    b   c").words == 3)
        #expect(TextStats.of("  xin  chào  ").words == 2)
    }

    @Test("Ký tự: tính cả khoảng trắng, theo grapheme")
    func characters() {
        #expect(TextStats.of("abc").characters == 3)
        #expect(TextStats.of("a b").characters == 3)         // gồm dấu cách
        #expect(TextStats.of("Tiếng Việt").characters == 10) // dấu tính vào grapheme
    }

    @Test("Ký tự không tính khoảng trắng")
    func charactersNoSpaces() {
        #expect(TextStats.of("a b c").charactersNoSpaces == 3)
        #expect(TextStats.of("  xin chào  ").charactersNoSpaces == 7) // "xinchào" = 7
    }

    @Test("Emoji & cờ tính 1 grapheme")
    func emoji() {
        #expect(TextStats.of("🇻🇳").characters == 1)     // cờ VN = 1 grapheme
        #expect(TextStats.of("👍 ok").words == 2)
        #expect(TextStats.of("😢😢").characters == 2)
    }

    @Test("Đếm dòng")
    func lines() {
        #expect(TextStats.of("một dòng").lines == 1)
        #expect(TextStats.of("dòng 1\ndòng 2").lines == 2)
        #expect(TextStats.of("a\nb\nc").lines == 3)
        #expect(TextStats.of("").lines == 0)
        #expect(TextStats.of("a\r\nb\rc").lines == 3)   // quy \r\n, \r về \n
    }

    @Test("Chuỗi chỉ toàn khoảng trắng")
    func whitespaceOnly() {
        let s = TextStats.of("   \n  ")
        #expect(s.words == 0)
        #expect(s.charactersNoSpaces == 0)
    }

    @Test("summary: gọn, chỉ hiện dòng khi >1")
    func summary() {
        #expect(TextStats.of("xin chào").summary == "2 từ · 8 ký tự")
        #expect(TextStats.of("a\nb").summary == "2 từ · 3 ký tự · 2 dòng")
    }

    @Test("Đoạn văn thực tế")
    func realParagraph() {
        let text = "Hôm nay trời đẹp.\nTôi đi học."
        let s = TextStats.of(text)
        #expect(s.words == 7)      // Hôm nay trời đẹp. Tôi đi học.
        #expect(s.lines == 2)
    }
}
