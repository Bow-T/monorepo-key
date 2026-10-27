// CoreBridgeTests.swift
// ---------------------
// Lớp bọc VietEngine -> core Rust: phím Swift `Character` được đổi thành một Unicode
// scalar (dựng sẵn NFC trước), ký tự vẫn nhiều scalar thì là phím ngắt từ.

import Testing
@testable import VietEngine

@Suite("Lớp bọc core Rust: phím Unicode")
struct CoreBridge {

    @Test("Phím NFD có dạng dựng sẵn -> vào core như một chữ, ra NFC")
    func nfdKeyIsComposed() {
        let got = VietEngine().process("a\u{0323}")
        #expect(got?.unicodeScalars.map(\.value) == [0x1EA1])   // ạ
    }

    @Test("Cụm nhiều scalar không dựng sẵn được -> phím ngắt từ, âm tiết mới bắt đầu sau đó")
    func multiScalarIsWordBreak() {
        let e = VietEngine()
        _ = e.process("a")
        #expect(e.process("x\u{0323}") == nil)
        #expect(e.process("s") == "s")
    }

    @Test("Emoji -> phím ngắt từ")
    func emojiIsWordBreak() {
        #expect(VietEngine().process("👍🏽") == nil)
    }

    @Test("Bật tự sửa lỗi: âm tiết rỗng (kể cả sau clear) -> ngắt từ thường, không autoCorrect")
    func autoCorrectSkipsEmptySyllable() {
        let e = VietEngine(autoCorrect: true)
        #expect(e.processKey(" ") == .wordBreak(" "))
        _ = e.processKey("a")
        e.clear()   // core rỗng nhưng phím thô cấp từ vẫn còn "a"
        #expect(e.processKey(" ") == .wordBreak(" "))
    }
}
