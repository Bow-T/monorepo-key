// ParagraphSimTests.swift
// ------------------------
// KIỂM CHỨNG "MẤT CHỮ": gõ nguyên một đoạn văn tiếng Việt qua MÔ PHỎNG CHÍNH XÁC
// state machine của EventTapController (gồm nhánh "cho phím đi qua tự nhiên vs
// nuốt-rồi-gõ-thay" thêm ở 1.0.1), rồi so kết quả với văn bản gốc.
//
// Ở đây ta mô phỏng "buffer ứng dụng":
//   • Phím đi qua TỰ NHIÊN  -> app tự chèn ký tự gốc `ch`.
//   • Nuốt + gõ thay        -> ta xoá `backspaces` ký tự cuối rồi nối `rendered`.
// Nếu logic quyết định committedLength / backspaces bị lệch, buffer mô phỏng sẽ
// KHÁC văn bản gốc -> lộ chữ bị nuốt/nhân đôi.

import Testing
import Foundation
@testable import VietEngine

// MARK: - Chữ có dấu -> phím Telex (đảo ngược để sinh chuỗi phím)

/// Ký tự hiển thị (đã BỎ dấu thanh, còn mũ/móc/trăng) -> phím Telex thô.
private let baseKeyMap: [Character: String] = [
    "â":"aa", "ê":"ee", "ô":"oo", "ă":"aw", "ơ":"ow", "ư":"uw", "đ":"dd",
]

/// Ký tự có DẤU THANH -> ký tự bỏ thanh (giữ mũ/móc/trăng).
private let stripToneMap: [Character: Character] = {
    var m: [Character: Character] = [:]
    func add(_ keep: Character, _ toned: String) { for c in toned { m[c] = keep } }
    add("a","áàảãạ"); add("ă","ắằẳẵặ"); add("â","ấầẩẫậ")
    add("e","éèẻẽẹ"); add("ê","ếềểễệ")
    add("i","íìỉĩị")
    add("o","óòỏõọ"); add("ô","ốồổỗộ"); add("ơ","ớờởỡợ")
    add("u","úùủũụ"); add("ư","ứừửữự")
    add("y","ýỳỷỹỵ")
    return m
}()

/// Ký tự có thanh -> phím thanh Telex (s/f/r/x/j).
private let toneKeyOf: [Character: Character] = {
    var m: [Character: Character] = [:]
    func add(_ key: Character, _ toned: String) { for c in toned { m[c] = key } }
    add("s","áắấéếíóốớúứý")   // sắc
    add("f","àằầèềìòồờùừỳ")   // huyền
    add("r","ảẳẩẻểỉỏổởủửỷ")   // hỏi
    add("x","ãẵẫẽễĩõỗỡũữỹ")   // ngã
    add("j","ạặậẹệịọộợụựỵ")   // nặng
    return m
}()

/// Chuyển một ĐOẠN hiển thị (có dấu) thành chuỗi phím Telex.
/// Mỗi từ: chữ cái map qua baseKeyMap; dấu thanh gõ ở CUỐI từ ("rooif"->rồi,
/// "menhj"->mệnh) đúng cách gõ Telex thực tế.
private func toTelexKeys(_ text: String) -> String {
    var out = ""
    var wordBuf = ""
    var wordTone: Character? = nil

    func flushWord() {
        out += wordBuf
        if let t = wordTone { out.append(t) }
        wordBuf = ""
        wordTone = nil
    }

    for chDisp in text.precomposedStringWithCanonicalMapping {
        guard chDisp.isLetter else { flushWord(); out.append(chDisp); continue }
        let lower = Character(chDisp.lowercased())
        if let tone = toneKeyOf[lower] { wordTone = tone }
        let stripped = stripToneMap[lower] ?? lower
        wordBuf += baseKeyMap[stripped] ?? String(stripped)
    }
    flushWord()
    return out
}

// MARK: - Mô phỏng EventTapController

/// Mô phỏng buffer ứng dụng khi gõ chuỗi phím `keys` qua controller-logic.
/// `naturalPassthrough`: bật/tắt nhánh "cho phím đi qua tự nhiên" của 1.0.1.
private func simulateTyping(_ keys: String, autoRestore: Bool = false,
                            naturalPassthrough: Bool = true) -> String {
    let engine = VietEngine(method: .telex, autoRestoreEnglish: autoRestore)
    var appBuffer = ""
    var committedLength = 0
    var currentDisplay = ""
    var wordRawKeys = ""

    func resetSyllable() {
        engine.clear(); committedLength = 0; wordRawKeys = ""; currentDisplay = ""
    }
    func replace(backspaces: Int, with text: String) {
        let safe = min(backspaces, 15)
        if safe > 0 { appBuffer = String(appBuffer.dropLast(safe)) }
        appBuffer += text
    }

    for ch in keys {
        if ch == " " || ch == "\n" || ch == "\t" {
            if autoRestore, !wordRawKeys.isEmpty,
               let raw = VietEngine.englishRestoreKeys(rawKeys: wordRawKeys, display: currentDisplay) {
                let bs = committedLength
                resetSyllable()
                replace(backspaces: bs, with: raw + String(ch))
                continue
            }
            resetSyllable()
            appBuffer.append(ch)
            continue
        }
        if autoRestore, ch.isLetter || ch.isNumber { wordRawKeys.append(ch) }

        guard let rendered = engine.process(ch) else {
            committedLength = 0; wordRawKeys = ""; currentDisplay = ""
            appBuffer.append(ch)
            continue
        }
        if naturalPassthrough, rendered == currentDisplay + String(ch) {
            committedLength = rendered.count
            currentDisplay = rendered
            appBuffer.append(ch)          // <-- app nhận ký tự gốc trực tiếp
            continue
        }
        let bs = committedLength
        committedLength = rendered.count
        currentDisplay = rendered
        replace(backspaces: bs, with: rendered)
    }
    return appBuffer
}

// MARK: - Test

@Suite("Gõ nguyên đoạn văn — không được nuốt/sai chữ")
struct ParagraphSim {

    // LƯU Ý: tránh các từ có cụm "oa/oe/uy" mang thanh (hoà/hóa/họa/khoẻ/thúy...)
    // vì engine đặt dấu KIỂU CŨ (hoà) còn văn bản mẫu hay viết KIỂU MỚI (hòa) —
    // đó là khác biệt phong cách, KHÔNG phải bug mất chữ, nên loại khỏi corpus này.
    private func corpus() -> String {
        """
        Em chịu á, em thua chị rồi. Anh nói gì em cũng chịu á.
        Trăm năm trong cõi người ta, chữ tài chữ mệnh khéo là ghét nhau.
        Chị ơi em đói quá, chị cho em ăn cơm với. Ừ để chị nấu cho em bát canh chua cá.
        Một hai nghiêng nước nghiêng thành, sắc đành đòi một tài đành đòi hai.
        Buổi sáng hôm ấy trời se lạnh, gió mùa đông bắc thổi về mang theo hơi ẩm của biển.
        Những chiếc lá vàng rơi lả tả trên con đường vắng, tạo nên khung cảnh nên thơ.
        Đứa trẻ chạy nhảy tung tăng, thả diều bay cao vút giữa bầu trời trong xanh.
        Người nông dân cần mẫn gặt hái sau bao ngày vất vả chăm bón trên đồng ruộng.
        """
    }

    /// Sinh phím -> mô phỏng -> so với gốc. Trả về (khớp?, chuỗi mô tả lệch).
    /// So sánh không phân biệt HOA/thường vì generator gõ toàn chữ thường (Telex
    /// không mã hoá Shift ở đây) — ta chỉ quan tâm CÓ MẤT/NHÂN ĐÔI chữ hay không.
    private func check(_ text: String, naturalPassthrough: Bool) -> (Bool, String) {
        let typed = simulateTyping(toTelexKeys(text), naturalPassthrough: naturalPassthrough)
        if typed.lowercased() == text.lowercased() { return (true, "") }
        let a = Array(text.lowercased()), b = Array(typed.lowercased())
        var i = 0
        while i < min(a.count, b.count) && a[i] == b[i] { i += 1 }
        let ctxA = String(a[max(0,i-12)..<min(a.count, i+12)])
        let ctxB = String(b[max(0,i-12)..<min(b.count, i+12)])
        return (false, "lệch @\(i): gốc=…\(ctxA)…  gõ=…\(ctxB)…")
    }

    // BẢN ĐANG DÙNG (đã sửa): luôn nuốt+gõ-thay (naturalPassthrough=off). Đây là
    // đường thực thi thật của EventTapController sau khi bỏ nhánh passthrough.
    @Test("Bản đã sửa (luôn nuốt+gõ thay) — không mất/nhân đôi chữ")
    func fixedBranch() {
        let (ok, msg) = check(corpus(), naturalPassthrough: false)
        if !ok { Issue.record("LỖI: \(msg)") }
        #expect(ok)
    }

    // Nhánh passthrough cũ (1.0.1) — giữ để tài liệu hoá: ở MỨC LOGIC nó cũng cho
    // kết quả đúng; bug thật là RACE TIMING tầng OS (không mô phỏng được ở đây).
    @Test("Nhánh passthrough cũ — đúng ở mức logic (bug thật là race OS)")
    func passthroughBranchLogic() {
        let (ok, msg) = check(corpus(), naturalPassthrough: true)
        if !ok { Issue.record("LỖI: \(msg)") }
        #expect(ok)
    }

    @Test("Cụm 'em chịu á' — cả hai bản")
    func emChiuA() {
        #expect(simulateTyping(toTelexKeys("em chịu á"), naturalPassthrough: true) == "em chịu á")
        #expect(simulateTyping(toTelexKeys("em chịu á"), naturalPassthrough: false) == "em chịu á")
    }

    /// Chốt kết luận: ở mức MÔ PHỎNG (không có race), hai bản cho kết quả GIỐNG HỆT.
    /// -> Bug thực tế KHÔNG ở logic mà ở RACE TIMING tầng OS do nhánh passthrough
    ///    (phím đi qua tự nhiên chưa commit kịp thì backspace tổng hợp đã tới).
    @Test("1.0.0 và 1.0.1 cho kết quả giống nhau (ở mức logic)")
    func sameAtLogicLevel() {
        let keys = toTelexKeys(corpus())
        #expect(simulateTyping(keys, naturalPassthrough: true)
                == simulateTyping(keys, naturalPassthrough: false))
    }
}
