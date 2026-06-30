// EnglishRestoreTests.swift
// Tự khôi phục tiếng Anh: gõ từ Anh bị biến dạng -> khôi phục phím thô.

import Testing
@testable import VietEngine

/// Gõ `keys` qua engine (telex), trả về chuỗi hiển thị của âm tiết.
private func render(_ keys: String) -> String {
    let e = VietEngine(method: .telex)
    var out = ""
    for ch in keys { out = e.process(ch) ?? "" }
    return out
}

@Suite("Tự khôi phục tiếng Anh (heuristic)")
struct EnglishRestore {

    /// Mô phỏng: gõ `keys`, lấy display, rồi hỏi có khôi phục không.
    private func restore(_ keys: String) -> String? {
        let display = render(keys)
        return VietEngine.englishRestoreKeys(rawKeys: keys, display: display)
    }

    @Test("Từ tiếng Anh bị biến dạng -> khôi phục phím thô")
    func restoresEnglish() {
        // "file" -> telex biến 'fi'? thực ra f không là dấu ở đầu. Lấy ví dụ rõ:
        // "boong" -> "boong"? Ta dùng từ mà telex biến dạng + không hợp lệ VN.
        // "waht": w->ư... -> biến dạng, không phải VN.
        #expect(restore("waht") == "waht")
        // "aas" -> "ấ" (biến dạng) nhưng "ấ" hợp lệ VN -> KHÔNG khôi phục
        #expect(restore("aas") == nil)
    }

    @Test("Từ ASCII không biến dạng -> không khôi phục (giữ nguyên)")
    func keepsPlainAscii() {
        // "test" telex: không có phím dấu áp được -> hiển thị "test" == raw -> nil
        #expect(restore("test") == nil)
        #expect(restore("code") == nil)
    }

    @Test("Từ tiếng Việt thật -> KHÔNG khôi phục")
    func keepsVietnamese() {
        #expect(restore("tieengs") == nil)   // tiếng
        #expect(restore("ddaays") == nil)    // đấy
        #expect(restore("nuowngs") == nil)   // nướng
        #expect(restore("hoaf") == nil)      // hoà
    }

    @Test("Engine có autoRestore: trả phím thô qua API instance")
    func instanceApi() {
        let e = VietEngine(method: .telex, autoRestoreEnglish: true)
        for ch in "waht" { _ = e.processKey(ch) }
        #expect(e.englishRestoreOnWordBreak() == "waht")

        let e2 = VietEngine(method: .telex, autoRestoreEnglish: true)
        for ch in "tieengs" { _ = e2.processKey(ch) }
        #expect(e2.englishRestoreOnWordBreak() == nil)  // tiếng -> giữ
    }

    @Test("autoRestore tắt -> luôn nil")
    func disabled() {
        let e = VietEngine(method: .telex, autoRestoreEnglish: false)
        for ch in "waht" { _ = e.processKey(ch) }
        #expect(e.englishRestoreOnWordBreak() == nil)
    }
}
