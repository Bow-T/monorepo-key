// NonVietClusterTests.swift
// Regression: âm tiết mở đầu bằng tổ hợp phụ âm phi-Việt (cl/str/pr...) -> engine
// KHÔNG áp dấu, giữ nguyên phím thô. Tránh phá lệnh terminal & từ tiếng Anh.

import Testing
@testable import VietEngine

private func render(_ keys: String, _ method: InputMethod = .telex) -> String {
    let e = VietEngine(method: method)
    var out = ""
    for ch in keys { out = e.process(ch) ?? out }
    return out
}

@Suite("Tổ hợp phụ âm đầu phi-Việt (terminal/English)")
struct NonVietCluster {
    @Test("lệnh terminal & từ Anh có cụm phụ âm phi-Việt giữ nguyên (Telex)")
    func keepsTerminalCommands() {
        // Cụm phi-Việt ở 2 chữ ĐẦU -> giữ nguyên toàn bộ phím thô.
        #expect(render("clear") == "clear")
        #expect(render("printf") == "printf")
        #expect(render("strings") == "strings")
        #expect(render("brew") == "brew")
        #expect(render("drop") == "drop")
        #expect(render("flag") == "flag")
        #expect(render("scp") == "scp")
        #expect(render("blur") == "blur")
        #expect(render("split") == "split")
    }

    @Test("KHÔNG chặn gõ tắt 'w' (sw->sư, tw->tư) dù chứa w")
    func keepsWShortcut() {
        // 'w' là phím gõ tắt -> 'ư'. KHÔNG được coi sw/tw là cụm phi-Việt.
        #expect(render("tw") == "tư")
        #expect(render("sw") == "sư")
    }

    @Test("KHÔNG đụng từ tiếng Việt hợp lệ")
    func keepsVietnamese() {
        // Các từ này KHÔNG mở đầu bằng cụm phi-Việt -> vẫn gõ dấu bình thường.
        #expect(render("tieengs") == "tiếng")
        #expect(render("ddaays") == "đấy")
        #expect(render("nuowngs") == "nướng")
        #expect(render("cuar") == "của")     // 'c'+'u' không phải cụm phi-Việt
        #expect(render("tooi") == "tôi")
        // 'tr' là phụ âm đầu Việt hợp lệ -> 'trees' vẫn được áp dấu (không bị chặn).
        #expect(render("trees") != "trees")
    }

    @Test("dd -> đ KHÔNG bị chặn (không phải cụm phi-Việt)")
    func doesNotBlockDd() {
        #expect(render("dd") == "đ")
        #expect(render("ddi") == "đi")
    }
}
