// WhitespaceNormalizerTests.swift
// -------------------------------
// Test chuẩn hoá khoảng trắng: gộp space, trim dòng, gộp dòng trống, quy space lạ.

import Testing
import Foundation
@testable import VietEngine

@Suite("Chuẩn hoá khoảng trắng")
struct WhitespaceNormalizerTests {

    @Test("Gộp nhiều dấu cách thành một")
    func collapseSpaces() {
        #expect(WhitespaceNormalizer.normalize("a    b") == "a b")
        #expect(WhitespaceNormalizer.normalize("xin   chào   bạn") == "xin chào bạn")
    }

    @Test("Trim đầu & cuối mỗi dòng")
    func trimLines() {
        #expect(WhitespaceNormalizer.normalize("   a b   ") == "a b")
        #expect(WhitespaceNormalizer.normalize("\t hello \t") == "hello")
    }

    @Test("Tab quy về dấu cách")
    func tabsToSpace() {
        #expect(WhitespaceNormalizer.normalize("a\tb\t\tc") == "a b c")
    }

    @Test("Non-breaking space & space Unicode quy về ' '")
    func exoticSpaces() {
        #expect(WhitespaceNormalizer.normalize("a\u{00A0}b") == "a b")       // NBSP
        #expect(WhitespaceNormalizer.normalize("a\u{202F}\u{2009}b") == "a b") // narrow + thin
    }

    @Test("Gộp nhiều dòng trống thành một")
    func collapseBlankLines() {
        #expect(WhitespaceNormalizer.normalize("a\n\n\n\nb") == "a\n\nb")
        #expect(WhitespaceNormalizer.normalize("a\n\nb\n\n\nc") == "a\n\nb\n\nc")
    }

    @Test("Bỏ dòng trống ở đầu & cuối")
    func trimBlankLinesEnds() {
        #expect(WhitespaceNormalizer.normalize("\n\na\nb\n\n") == "a\nb")
        #expect(WhitespaceNormalizer.normalize("\n\n\n") == "")
    }

    @Test("Dòng chỉ toàn khoảng trắng -> thành dòng trống (giữ như ngắt đoạn)")
    func whitespaceOnlyLine() {
        // Dòng giữa chỉ có spaces -> collapse thành dòng trống -> giữ 1 dòng trống
        // (người dùng cách 2 đoạn bằng dòng "trống" chứa space -> vẫn là ngắt đoạn).
        #expect(WhitespaceNormalizer.normalize("a\n   \nb") == "a\n\nb")
        // NHƯNG nhiều dòng-toàn-space liên tiếp vẫn gộp thành MỘT dòng trống.
        #expect(WhitespaceNormalizer.normalize("a\n  \n\t\nb") == "a\n\nb")
    }

    @Test("Ngắt dòng \\r\\n và \\r được chuẩn hoá về \\n")
    func normalizeNewlines() {
        #expect(WhitespaceNormalizer.normalize("a\r\nb\rc") == "a\nb\nc")
    }

    @Test("Đoạn văn thực tế lộn xộn từ PDF")
    func realWorld() {
        let messy = "  Xin   chào  \n\n\n   Đây là   đoạn văn.  \t\n  \n Kết thúc.  "
        let expected = "Xin chào\n\nĐây là đoạn văn.\n\nKết thúc."
        #expect(WhitespaceNormalizer.normalize(messy) == expected)
    }

    @Test("Chuỗi rỗng & chuỗi đã sạch")
    func edgeCases() {
        #expect(WhitespaceNormalizer.normalize("") == "")
        #expect(WhitespaceNormalizer.normalize("đã sạch rồi") == "đã sạch rồi")
        #expect(WhitespaceNormalizer.normalize("một dòng") == "một dòng")
    }
}
