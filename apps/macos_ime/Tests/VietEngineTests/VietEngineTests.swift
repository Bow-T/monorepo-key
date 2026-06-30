// VietEngineTests.swift
// ---------------------
// Test engine bằng cách "gõ" một chuỗi phím rồi xem kết quả âm tiết cuối cùng.
// Chạy: swift test
//
// Đây là tài sản quý nhất khi học làm bộ gõ: bạn sửa thuật toán xong, chạy test,
// biết ngay có làm hỏng gì không — KHÔNG cần build app hay xin quyền macOS.

import Testing
@testable import VietEngine

/// Helper: gõ lần lượt từng ký tự của `keys` qua engine, trả về chuỗi hiển thị
/// của âm tiết cuối cùng.
private func type(_ keys: String,
                  method: InputMethod = .telex,
                  toneStyle: VietEngine.ToneStyle = .modern) -> String {
    let engine = VietEngine(method: method, toneStyle: toneStyle)
    var current = ""
    for ch in keys {
        if let rendered = engine.process(ch) {
            current = rendered
        } else {
            current = ""   // gặp ký tự ngắt từ -> bắt đầu âm tiết mới
        }
    }
    return current
}

@Suite("Telex cơ bản")
struct TelexBasics {

    @Test("Dấu thanh đơn giản")
    func tones() {
        #expect(type("as") == "á")
        #expect(type("af") == "à")
        #expect(type("ar") == "ả")
        #expect(type("ax") == "ã")
        #expect(type("aj") == "ạ")
    }

    @Test("Dấu mũ bằng cách lặp chữ")
    func circumflex() {
        #expect(type("aa") == "â")
        #expect(type("ee") == "ê")
        #expect(type("oo") == "ô")
    }

    @Test("Dấu trăng / móc bằng w")
    func hornAndBreve() {
        #expect(type("aw") == "ă")
        #expect(type("ow") == "ơ")
        #expect(type("uw") == "ư")
    }

    @Test("dd -> đ")
    func dyet() {
        #expect(type("dd") == "đ")
    }

    @Test("Kết hợp mũ + thanh: ê + sắc -> ế")
    func markPlusTone() {
        #expect(type("ees") == "ế")
        #expect(type("oof") == "ồ")
        #expect(type("uwx") == "ữ")
    }

    @Test("Từ hoàn chỉnh")
    func words() {
        #expect(type("tieengs") == "tiếng")   // mục tiêu kinh điển
        #expect(type("ddaays") == "đấy")
        #expect(type("Vieetj") == "Việt")
    }

    @Test("Xoá dấu bằng z")
    func removeTone() {
        #expect(type("asz") == "a")
    }
}

@Suite("Quy tắc đặt dấu chính tả (modern)")
struct ToneePlacement {

    @Test("Cụm hở 2 nguyên âm: dấu lên nguyên âm đầu")
    func openTwoVowelsHead() {
        #expect(type("muaf") == "mùa")     // mùa: lên u
        #expect(type("biaf") == "bìa")     // bìa: lên i
    }

    @Test("Đuôi mở oa/oe/uy: dấu lên nguyên âm sau (modern)")
    func openTailException() {
        #expect(type("hoaf") == "hoà")     // hoà (không phải hòa)
        #expect(type("khoer") == "khoẻ")   // khoẻ
        #expect(type("quys") == "quý")     // quý
    }

    @Test("Có phụ âm cuối: dấu lên nguyên âm cuối của cụm")
    func withFinalConsonant() {
        #expect(type("toans") == "toán")   // toán: lên a
        #expect(type("hoangf") == "hoàng") // hoàng: lên a
    }

    @Test("Nguyên âm có dấu biến âm luôn được ưu tiên")
    func markedVowelWins() {
        #expect(type("tieengs") == "tiếng") // lên ê
        #expect(type("nuowngs") == "nướng") // lên ơ
        #expect(type("dduwowcj") == "được") // được
    }

    @Test("Ba nguyên âm: dấu lên nguyên âm giữa")
    func threeVowels() {
        #expect(type("ngoaif") == "ngoài")  // ngoài: lên a (giữa, có i cuối)
    }
}

@Suite("Chế độ đặt dấu cũ (old orthography)")
struct OldToneStyle {

    @Test("Đuôi mở oa/oe/uy: dấu lên nguyên âm đầu")
    func openTailOld() {
        #expect(type("hoaf", toneStyle: .old) == "hòa")   // hòa (không phải hoà)
        #expect(type("quys", toneStyle: .old) == "qúy")   // qúy
        #expect(type("khoer", toneStyle: .old) == "khỏe") // khỏe
    }

    @Test("Trường hợp có phụ âm cuối / biến âm: giống modern")
    func sameAsModern() {
        #expect(type("toans", toneStyle: .old) == "toán")
        #expect(type("tieengs", toneStyle: .old) == "tiếng")
    }
}

// Regression: phím-dấu (s f r x j z) đứng sau phụ âm đầu mà CHƯA có nguyên âm
// không được nuốt làm dấu thanh. Đối chiếu commit PHTV 0adc2129
// ("prevent initial consonants from being consumed as tone markers").
@Suite("Phụ âm-dấu sau phụ âm đầu (chưa có nguyên âm)")
struct LeadingConsonantToneKey {

    @Test("tr- không bị nuốt thành dấu hỏi")
    func trCluster() {
        #expect(type("tre") == "tre")     // cây tre, KHÔNG phải "tẻ"
        #expect(type("tres") == "tré")
        #expect(type("treen") == "trên")  // trên, KHÔNG phải "tển"
        #expect(type("trong") == "trong")
        #expect(type("truowcs") == "trước")
    }

    @Test("các cụm phụ âm khác (gr/xr/...) giữ nguyên phím-dấu")
    func otherClusters() {
        #expect(type("gra") == "gra")
        #expect(type("xra") == "xra")
        #expect(type("strong") == "strong")
    }

    @Test("phụ âm-dấu là chữ ĐẦU vẫn giữ nguyên (đã đúng từ trước)")
    func leadingMarkerStaysLiteral() {
        #expect(type("sai") == "sai")
        #expect(type("xin") == "xin")
        #expect(type("rum") == "rum")
        #expect(type("fan") == "fan")
        #expect(type("zap") == "zap")
    }
}

@Suite("Gõ lại để bỏ/đổi dấu")
struct ReTyping {

    @Test("Gõ lại trùng dấu thanh -> bỏ dấu, trả ký tự thô")
    func cancelTone() {
        #expect(type("hoaf") == "hoà")
        #expect(type("hoaff") == "hoaf")   // f lần 2: bỏ huyền, f hiện ra
        #expect(type("ass") == "as")       // sắc bị huỷ, s hiện ra
    }

    @Test("Gõ dấu khác -> đổi dấu")
    func changeTone() {
        #expect(type("hoafs") == "hoá")    // huyền -> sắc
        #expect(type("asx") == "ã")        // sắc -> ngã
    }

    @Test("Gõ lại trùng biến âm -> bỏ biến âm")
    func cancelMark() {
        #expect(type("aaa") == "aa")       // mũ bị huỷ, a hiện ra
        #expect(type("oww") == "ow")       // móc bị huỷ, w hiện ra
    }

    @Test("z là phím xoá dấu thuần (không tự hiện chữ z)")
    func zRemovesTone() {
        #expect(type("asz") == "a")        // z xoá sắc
        #expect(type("azz") == "a")        // z gõ mấy lần cũng chỉ giữ 'không dấu'
    }
}

@Suite("Backspace (dựng lại từ buffer phím thô)")
struct Backspacing {

    /// Gõ `keys`, rồi nhấn backspace `n` lần, trả về chuỗi âm tiết cuối.
    private func typeThenBackspace(_ keys: String, _ n: Int,
                                   method: InputMethod = .telex) -> String {
        let engine = VietEngine(method: method)
        var current = ""
        for ch in keys { current = engine.process(ch) ?? "" }
        for _ in 0..<n { current = engine.backspace() ?? "" }
        return current
    }

    @Test("Backspace xoá 1 phím thô rồi dựng lại đúng")
    func basic() {
        // "tieengs" = tiếng. Xoá 's' (phím thô cuối) -> mất dấu sắc -> "tieng" = "tiêng".
        #expect(typeThenBackspace("tieengs", 1) == "tiêng")
        // Xoá thêm 'g' -> "tieen" = "tiên".
        #expect(typeThenBackspace("tieengs", 2) == "tiên")
    }

    @Test("Backspace qua phím tạo biến âm")
    func throughMark() {
        // "aas" = ấ (a + a[mũ] + s[sắc]). Xoá 's' -> "aa" = "â".
        #expect(typeThenBackspace("aas", 1) == "â")
        // Xoá thêm 'a' -> "a".
        #expect(typeThenBackspace("aas", 2) == "a")
    }

    @Test("Backspace tới rỗng")
    func toEmpty() {
        #expect(typeThenBackspace("as", 2) == "")
    }

    @Test("Backspace khi buffer rỗng -> nil (caller để phím đi qua)")
    func emptyBuffer() {
        let engine = VietEngine()
        #expect(engine.backspace() == nil)
    }
}

@Suite("VNI cơ bản")
struct VNIBasics {

    @Test("Thanh bằng số")
    func tones() {
        #expect(type("a1", method: .vni) == "á")
        #expect(type("a2", method: .vni) == "à")
    }

    @Test("Biến âm bằng số")
    func marks() {
        #expect(type("a6", method: .vni) == "â")
        #expect(type("o7", method: .vni) == "ơ")
        #expect(type("a8", method: .vni) == "ă")
        #expect(type("d9", method: .vni) == "đ")
    }

    @Test("Từ hoàn chỉnh VNI: tie61ng -> tiếng")
    func word() {
        #expect(type("tie61ng", method: .vni) == "tiếng")
    }
}
