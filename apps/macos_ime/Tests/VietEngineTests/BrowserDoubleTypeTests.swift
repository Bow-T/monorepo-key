// BrowserDoubleTypeTests.swift
// -----------------------------
// KIỂM CHỨNG "GÕ ĐÔI Ở Ô AUTOCOMPLETE" (thanh địa chỉ/tìm kiếm Chromium — Edge,
// Chrome, Brave, Cốc Cốc; Spotlight) VÀ mẹo "phá highlight" sửa nó.
//
// CƠ CHẾ LỖI: khi ô có gợi ý autocomplete đang BÔI ĐEN, phím Backspace TỔNG HỢP của
// bộ gõ bị ô gợi ý "nuốt" (dùng để đóng gợi ý) thay vì xoá ký tự thật -> ký tự cũ
// còn nguyên, ta gõ thêm bản mới -> NHÂN ĐÔI.
//   Gõ "d" -> hiện "d" (và ô mở gợi ý, highlight bật).
//   Gõ "o" -> engine cần dựng "do": gửi 1 Backspace (bị highlight NUỐT) + gõ "do".
//            => màn hình: "d" (cũ, không xoá được) + "do" = "ddo".  ❌
//
// MẸO SỬA: trước khi Backspace, gửi MỘT ký tự RỖNG (U+202F). Nó khiến
// trình duyệt BỎ highlight (coi như vừa gõ thêm). Sau đó Backspace hoạt động lại
// bình thường; ta gửi kèm 1 Backspace phụ để xoá luôn ký tự rỗng.
//   Gõ "o": [rỗng] (tắt highlight) + [Backspace xoá rỗng] + [Backspace xoá "d"] + "do"
//          => "do".  ✅

import Testing
import Foundation
@testable import VietEngine

/// Mô hình ô nhập liệu có AUTOCOMPLETE HIGHLIGHT.
///
/// - `highlightOn`: true khi ô đang bôi đen gợi ý. Bật lên sau MỖI ký tự hiển thị
///   (giống address bar: gõ xong là có gợi ý ngay).
/// - Backspace: nếu `highlightOn` -> chỉ TẮT highlight, KHÔNG xoá ký tự (bị "nuốt").
///   Nếu `highlightOn` == false -> xoá 1 ký tự như thường.
/// - Gõ ký tự thường (kể cả ký tự rỗng): chèn vào buffer VÀ bật lại highlight.
///   Riêng ký tự rỗng: chèn rồi bật highlight — nhưng vì nó "tắt rồi bật lại" nên
///   Backspace NGAY SAU nó rơi vào trạng thái highlight? Không: mô hình address bar
///   thực tế là ký tự rỗng khiến chuỗi query đổi -> gợi ý được tính lại và trong
///   khoảnh khắc đó highlight TẮT, nên Backspace kế tiếp ăn được. Ta mô hình bằng
///   cách: ký tự rỗng chèn vào và để `highlightOn=false` (query vừa đổi, chưa kịp
///   bôi lại) -> Backspace sau đó xoá được.
private struct AutocompleteField {
    private(set) var text = ""
    private var highlightOn = false

    mutating func type(_ s: String) {
        for ch in s {
            text.append(ch)
            // Ký tự rỗng (U+202F): query vừa đổi, highlight tạm tắt -> backspace kế ăn.
            // Ký tự thường: ô hiện gợi ý mới -> highlight bật.
            highlightOn = (ch != "\u{202F}")
        }
    }

    mutating func backspace() {
        if highlightOn {
            // Bị nuốt: chỉ tắt highlight, ký tự thật còn nguyên.
            highlightOn = false
            return
        }
        if !text.isEmpty { text.removeLast() }
    }

    /// Bỏ các ký tự rỗng còn sót (để so sánh nội dung "nhìn thấy được").
    var visibleText: String { text.replacingOccurrences(of: "\u{202F}", with: "") }
}

/// Mô phỏng gõ chuỗi phím Telex vào ô autocomplete qua controller-logic.
/// `breakHighlight`: bật mẹo phá-highlight (bản đã sửa) hay không (bản cũ).
private func typeIntoAutocomplete(_ keys: String, breakHighlight: Bool) -> String {
    let engine = VietEngine(method: .telex)
    var field = AutocompleteField()
    var committedLength = 0

    func replace(backspaces: Int, with text: String) {
        if breakHighlight, backspaces > 0 {
            field.type("\u{202F}")                 // phá highlight
            for _ in 0..<(backspaces + 1) { field.backspace() }  // +1 xoá ký tự rỗng
        } else {
            for _ in 0..<backspaces { field.backspace() }
        }
        field.type(text)
    }

    for ch in keys {
        if ch == " " { engine.clear(); committedLength = 0; field.type(" "); continue }
        guard let rendered = engine.process(ch) else {
            committedLength = 0; field.type(String(ch)); continue
        }
        let bs = committedLength
        committedLength = rendered.count
        replace(backspaces: bs, with: rendered)
    }
    return field.visibleText
}

/// Gõ vào ô THƯỜNG (không autocomplete-highlight): Backspace luôn xoá được. Đây là
/// kết quả "đúng lý tưởng" của engine để đối chiếu.
private func typeIntoAutocompletePlain(_ keys: String) -> String {
    let engine = VietEngine(method: .telex)
    var text = ""
    var committedLength = 0
    for ch in keys {
        if ch == " " { engine.clear(); committedLength = 0; text.append(" "); continue }
        guard let rendered = engine.process(ch) else {
            committedLength = 0; text.append(ch); continue
        }
        if committedLength > 0 { text.removeLast(committedLength) }
        committedLength = rendered.count
        text.append(rendered)
    }
    return text
}

@Suite("Gõ đôi ở ô autocomplete (Edge/Chrome/Spotlight) + mẹo phá highlight")
struct BrowserDoubleType {

    @Test("Bản CŨ nhân đôi 'd' -> 'ddo'; bản MỚI cho 'do' đúng")
    func doBug() {
        // Gõ "do" (phím d, o). "d" đơn không biến đổi; "o" khiến dựng lại "do".
        #expect(typeIntoAutocomplete("do", breakHighlight: false) == "ddo")  // lỗi tái hiện
        #expect(typeIntoAutocomplete("do", breakHighlight: true)  == "do")   // đã sửa
    }

    @Test("'dd' -> 'đ' ở ô autocomplete không còn nhân đôi")
    func ddToDDyet() {
        // Telex "dd" -> "đ". Bản cũ: "d" kẹt lại -> "dđ". Bản mới -> "đ".
        #expect(typeIntoAutocomplete("dd", breakHighlight: false) == "dđ")
        #expect(typeIntoAutocomplete("dd", breakHighlight: true)  == "đ")
    }

    @Test("Nhiều âm tiết có dấu vẫn đúng với mẹo phá highlight")
    func syllablesWithMarks() {
        // "tieengs" -> "tiếng"; "dda"->"đa"; "vieejt"->"việt".
        #expect(typeIntoAutocomplete("tieengs", breakHighlight: true) == "tiếng")
        #expect(typeIntoAutocomplete("dda", breakHighlight: true) == "đa")
        #expect(typeIntoAutocomplete("vieejt", breakHighlight: true) == "việt")
    }

    @Test("Không nhân đôi ký tự đầu dù engine có biến đổi Telex (bản mới)")
    func noLeadingDouble() {
        // Engine BIẾN ĐỔI theo Telex ("google"->"gôgle" vì oo->ô, "search"->"seảch").
        // Đó là hành vi Telex bình thường; điều ta kiểm là KHÔNG có ký tự đầu bị nhân
        // đôi (không "ggôgle"/"ssearch"). So với chính kết quả engine gõ ở ô THƯỜNG.
        for word in ["google", "search", "download", "settings"] {
            let inField = typeIntoAutocomplete(word, breakHighlight: true)
            let plain = typeIntoAutocompletePlain(word)   // ô không highlight
            #expect(inField == plain, "khác nhau ở '\(word)': field=\(inField) plain=\(plain)")
        }
    }

    @Test("Cả một cụm gõ liền không rớt/thừa ký tự (bản mới)")
    func phrase() {
        // "ddi hoc" -> "đi hoc" (không dấu ở 'hoc' vì gõ thô); trọng tâm: không nhân đôi.
        #expect(typeIntoAutocomplete("ddi hoc", breakHighlight: true) == "đi hoc")
    }
}

// MARK: - Spotlight: bôi đen bằng Shift+Mũi-tên-trái rồi ghi đè (selection replacement)

/// Mô hình ô SPOTLIGHT. Khác autocomplete trình duyệt:
///   - Ký tự RỖNG U+202F KHÔNG phá được highlight (Spotlight bám gợi ý riêng) và có
///     thể để lại vệt -> KHÔNG dùng cách empty-char ở đây.
///   - Cách đúng: Shift+Mũi-tên-trái bôi đen N ký tự, rồi gõ chuỗi mới GHI ĐÈ vùng bôi
///     đen. Bôi-đen-ghi-đè hoạt động đáng tin ở Spotlight.
///
/// Mô hình: giữ `text` + độ dài vùng đang bôi đen `sel` (tính từ cuối chuỗi).
///   - shiftLeft(): mở rộng vùng bôi đen thêm 1 ký tự về trái.
///   - type(s): nếu đang có vùng bôi đen -> XOÁ vùng đó trước rồi chèn (ghi đè); ngược
///     lại chèn bình thường.
///   - backspace ở Spotlight: mô hình bi quan là KHÔNG đáng tin (bỏ qua) — để bảo đảm
///     chỉ cách selection-replacement mới cho kết quả đúng.
private struct SpotlightField {
    private(set) var text = ""
    private var sel = 0   // số ký tự cuối đang được bôi đen

    mutating func shiftLeft() {
        if sel < text.count { sel += 1 }
    }

    mutating func type(_ s: String) {
        if sel > 0 {
            text.removeLast(sel)   // gõ đè -> vùng bôi đen bị thay
            sel = 0
        }
        text.append(contentsOf: s)
    }

    var visibleText: String { text }
}

/// Gõ chuỗi phím Telex vào Spotlight qua controller-logic với cách chọn ô = Spotlight.
/// `useSelectionReplacement`: bản mới (Shift+Left) hay bản cũ (Backspace bị bỏ qua).
private func typeIntoSpotlight(_ keys: String, useSelectionReplacement: Bool) -> String {
    let engine = VietEngine(method: .telex)
    var field = SpotlightField()
    var committedLength = 0

    func replace(backspaces: Int, with text: String) {
        if useSelectionReplacement, backspaces > 0 {
            for _ in 0..<backspaces { field.shiftLeft() }  // bôi đen -> type() ghi đè
        }
        // bản cũ: "backspace" ở Spotlight coi như bị nuốt (không xoá) -> mô hình bỏ qua.
        field.type(text)
    }

    for ch in keys {
        if ch == " " { engine.clear(); committedLength = 0; field.type(" "); continue }
        guard let rendered = engine.process(ch) else {
            committedLength = 0; field.type(String(ch)); continue
        }
        let bs = committedLength
        committedLength = rendered.count
        replace(backspaces: bs, with: rendered)
    }
    return field.visibleText
}

@Suite("Spotlight: bôi đen + ghi đè (Shift+Mũi-tên-trái)")
struct SpotlightSelectionReplacement {

    @Test("Bản CŨ (Backspace bị nuốt) nhân đôi; bản MỚI (Shift+Left) đúng")
    func doBug() {
        #expect(typeIntoSpotlight("do", useSelectionReplacement: false) == "ddo")
        #expect(typeIntoSpotlight("do", useSelectionReplacement: true)  == "do")
    }

    @Test("Âm tiết có dấu ghi đè đúng ở Spotlight")
    func marks() {
        #expect(typeIntoSpotlight("tieengs", useSelectionReplacement: true) == "tiếng")
        #expect(typeIntoSpotlight("dd", useSelectionReplacement: true) == "đ")
        #expect(typeIntoSpotlight("vieejt", useSelectionReplacement: true) == "việt")
    }

    @Test("Cụm nhiều từ ở Spotlight không rớt/thừa ký tự")
    func phrase() {
        #expect(typeIntoSpotlight("ddi hoc", useSelectionReplacement: true) == "đi hoc")
    }
}
