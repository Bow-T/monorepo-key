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

    // Regression: 'u' sau 'q' và 'i' sau 'g' là phần của phụ âm đầu, KHÔNG nhận
    // dấu thanh (quy tắc chính tả "gi"/"qu").
    @Test("qu-: dấu không lên u (quà, quá, quán)")
    func quCluster() {
        #expect(type("quaf") == "quà")     // KHÔNG phải "qùa"
        #expect(type("quas") == "quá")
        #expect(type("quans") == "quán")
        #expect(type("quys") == "quý")     // u-y: y là nguyên âm chính -> lên y
    }

    @Test("gi-: dấu không lên i (già, giá, giò, giúp)")
    func giCluster() {
        #expect(type("giaf") == "già")     // KHÔNG phải "gìa"
        #expect(type("gias") == "giá")
        #expect(type("giof") == "giò")
        #expect(type("giups") == "giúp")
        #expect(type("giuwxa") == "giữa")
    }

    @Test("gi-/qu- khi nguyên âm đó là DUY NHẤT thì vẫn nhận dấu")
    func giQuSingleVowel() {
        #expect(type("gif") == "gì")       // i duy nhất -> dấu lên i
        #expect(type("gir") == "gỉ")
    }
}

@Suite("Chế độ đặt dấu cũ (old orthography)")
struct OldToneStyle {

    @Test("Đuôi mở oa/oe/uy: dấu lên nguyên âm đầu")
    func openTailOld() {
        #expect(type("hoaf", toneStyle: .old) == "hòa")   // hòa (không phải hoà)
        // Dùng "uy" THẬT (thùy), không phải "quy" — trong "qu" thì 'u' là bán phụ âm
        // nên "quý" luôn đặt dấu trên y ở cả hai chế độ (xem suite qu-/gi- ở trên).
        #expect(type("thuyf", toneStyle: .old) == "thùy") // thùy (lên u)
        #expect(type("khoer", toneStyle: .old) == "khỏe") // khỏe
    }

    @Test("\"quy\" đặt dấu trên y ở cả modern lẫn old (u là bán phụ âm)")
    func quyAlwaysOnY() {
        #expect(type("quys") == "quý")
        #expect(type("quys", toneStyle: .old) == "quý")
    }

    @Test("Trường hợp có phụ âm cuối / biến âm: giống modern")
    func sameAsModern() {
        #expect(type("toans", toneStyle: .old) == "toán")
        #expect(type("tieengs", toneStyle: .old) == "tiếng")
    }
}

// Gõ tắt 'w': 'w' đơn (không ghép được a/o/u) tạo 'ư'; cụm "ưo" tự thành "ươ"
// khi có âm đóng {n,c,i,m,p,t} đứng sau (quy tắc chính tả cụm "ươ").
@Suite("Gõ tắt 'w'")
struct WShortcut {

    @Test("'w' đơn -> ư (sau phụ âm hoặc đầu từ)")
    func standaloneW() {
        #expect(type("w") == "ư")
        #expect(type("tw") == "tư")
        #expect(type("cw") == "cư")
        #expect(type("qw") == "qư")
        #expect(type("mwf") == "mừ")
        #expect(type("dwfng") == "dừng")
        #expect(type("mwfng") == "mừng")
        #expect(type("wf") == "ừ")
    }

    @Test("\"ưo\" -> \"ươ\" khi có âm đóng kế tiếp")
    func uoHornPropagation() {
        #expect(type("huwong") == "hương")
        #expect(type("huwongs") == "hướng")
        #expect(type("tuwong") == "tương")
        #expect(type("thuwong") == "thương")
        #expect(type("nuwocs") == "nước")
    }

    @Test("Không phá cách gõ chuẩn uw / aw / ow / uow")
    func standardStillWorks() {
        #expect(type("uw") == "ư")
        #expect(type("aw") == "ă")
        #expect(type("ow") == "ơ")
        #expect(type("huowng") == "hương")
        #expect(type("huow") == "hươ")   // gõ dở, chưa âm đóng -> giữ nguyên
    }

    @Test("Telex ua + w -> ưa và quaw -> quă")
    func telexUaW() {
        #expect(type("muaw") == "mưa")
        #expect(type("chuaw") == "chưa")
        #expect(type("luawj") == "lựa")
        #expect(type("dduaw") == "đưa")
        #expect(type("quaw") == "quă") // không thành qưa
    }

    @Test("Telex quow -> quơ")
    func telexQuow() {
        #expect(type("quow") == "quơ") // không thành quươ
    }

    @Test("Telex thuo + w -> thuơ và thuowng -> thương")
    func telexThuoW() {
        #expect(type("thuow") == "thuơ")
        #expect(type("thuowr") == "thuở")
        #expect(type("thuowng") == "thương")
    }

    @Test("Telex consecutive w collapsing")
    func telexConsecutiveW() {
        #expect(type("ww") == "w")
        #expect(type("uww") == "ưw")
        #expect(type("tww") == "tw")
    }
}

// Regression: phím-dấu (s f r x j z) đứng sau phụ âm đầu mà CHƯA có nguyên âm
// không được nuốt làm dấu thanh (phụ âm đầu không bị hiểu nhầm là phím-dấu).
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
        #expect(type("oww") == "ơw")       // oww -> ơw (standard Telex/Unikey)
        #expect(type("ddd") == "dd")       // đ bị huỷ, d hiện ra (đối xứng aaa)
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

    // Regression: gõ lại số-biến-âm trùng -> huỷ biến âm, số hiện ra như ký tự thô
    // (cơ chế toggle: gỡ dấu rồi chèn phím thô).
    @Test("Gõ lại số-biến-âm trùng -> huỷ biến âm + số thô")
    func toggleMarkDigit() {
        #expect(type("a66", method: .vni) == "a6")  // huỷ mũ
        #expect(type("o77", method: .vni) == "o7")  // huỷ móc
        #expect(type("a88", method: .vni) == "a8")  // huỷ trăng
        #expect(type("d99", method: .vni) == "d9")  // huỷ đ
    }

    @Test("Kết hợp số-thanh + số-biến-âm vẫn đúng")
    func toneThenMark() {
        #expect(type("a16", method: .vni) == "ấ")   // sắc rồi mũ -> ấ
        #expect(type("a61", method: .vni) == "ấ")   // mũ rồi sắc -> ấ
    }

    @Test("VNI ua/uo + 7 -> ưa/ươ và qua7/quo7")
    func vniUaUo7() {
        #expect(type("mua7", method: .vni) == "mưa")
        #expect(type("muo7n", method: .vni) == "mươn")
        #expect(type("muo75n", method: .vni) == "mượn")
        #expect(type("qua7", method: .vni) == "qua7") // không thành qưa
        #expect(type("quo7", method: .vni) == "quơ")  // không thành quươ
        #expect(type("thuo7", method: .vni) == "thuơ")
        #expect(type("thuo73", method: .vni) == "thuở")
        #expect(type("thuo7ng", method: .vni) == "thương")
    }
}

// Kéo dài nguyên âm (vowel stretching) — đối chiếu engine PHTV.
// Khi gõ lặp một nguyên âm để NHẤN MẠNH (vd "khôngggg", "đẹp quáaa"), chu kỳ mũ
// chỉ áp cho CẶP đầu, sau đó các phím lặp chỉ nối thô; dấu thanh GIỮ NGUYÊN trên
// nguyên âm gốc, không trôi sang nguyên âm bị kéo dài.
@Suite("Kéo dài nguyên âm (elongation)")
struct VowelElongation {

    @Test("Chu kỳ mũ theo số lần gõ, không tạo lại mũ sau khi gỡ")
    func circumflexCycle() {
        #expect(type("aa") == "â")       // lần 2 -> mũ
        #expect(type("aaa") == "aa")     // lần 3 -> gỡ mũ, nối thô
        #expect(type("aaaa") == "aaa")   // lần 4 -> KHÔNG tạo lại mũ (regression)
        #expect(type("aaaaa") == "aaaa")
        #expect(type("eee") == "ee")
        #expect(type("ooo") == "oo")
        #expect(type("cooo") == "coo")
        #expect(type("theee") == "thee")
    }

    @Test("Phím-thanh xen giữa không phá chu kỳ mũ (casa == caas)")
    func toneKeyDoesNotBreakCycle() {
        #expect(type("these") == "thế")  // 1 e thừa sau thé -> tạo mũ -> thế
        #expect(type("baasm") == "bấm")  // mũ trước thanh -> giữ mũ
        #expect(type("casa") == type("caas"))  // tone-before-shape Telex
    }

    @Test("Dấu thanh giữ trên nguyên âm gốc khi nguyên âm bị kéo dài")
    func tonePlacementStableUnderStretch() {
        // "oi" -> dấu lên o; kéo dài i không làm dấu trôi sang i.
        #expect(type("choifiii") == "chòiiii")
        #expect(type("choiiiif") == "chòiiii")
        #expect(type("ojooo") == "ọoo")
        #expect(type("curaaa") == "củaa")
    }
}
