import Testing
@testable import VietEngine

private func typeR(_ keys: String,
                   method: InputMethod = .telex,
                   toneStyle: VietEngine.ToneStyle = .modern) -> String {
    let engine = VietEngine(method: method, toneStyle: toneStyle)
    var current = ""
    for ch in keys {
        if let rendered = engine.process(ch) { current = rendered }
        else { current = "" }
    }
    return current
}

@Suite("Regression: dấu/móc gõ sau phụ âm cuối (bug đuocự)")
struct ToneMarkAfterFinalConsonant {

    /// Bug gốc: gõ "được" ra "đuocự" vì 'w'/dấu gõ SAU phụ âm cuối không tìm được
    /// cụm nguyên âm. Mỗi từ test ở NHIỀU thứ tự phím tự nhiên người dùng hay gõ.
    @Test("Telex: ươ + phụ âm cuối, w/dấu gõ ở mọi vị trí")
    func telex() {
        let cases: [(String, String)] = [
            // được — các thứ tự gõ
            ("dduocwj", "được"), ("dduocjw", "được"),
            ("dduowcj", "được"), ("dduowjc", "được"),
            // nước / nược
            ("nuocws", "nước"), ("nuocjw", "nược"), ("nuowsc", "nước"),
            // đường / thường / hường (ươ + ng, w sau cùng)
            ("dduongwf", "đường"), ("dduongfw", "đường"),
            ("thuongwf", "thường"), ("huongwf", "hường"),
            ("xuongws", "xướng"), ("nuongws", "nướng"),
            // người (ươ + i)
            ("nguoiwf", "người"), ("nguwowif", "người"),
            // mướn / muốn
            ("muonws", "mướn"), ("muoons", "muốn"),
            // bướm
            ("buomws", "bướm"), ("buowms", "bướm"),
            // thuở (không phụ âm cuối -> chỉ móc 'o')
            ("thuowr", "thuở"), ("thuorw", "thuở"),
            // ơ/ư đơn trước phụ âm cuối
            ("comw", "cơm"), ("comws", "cớm"),
            ("tuwj", "tự"), ("tujw", "tự"),
            // ă trước phụ âm cuối
            ("manw", "măn"), ("manws", "mắn"), ("nawng", "năng"), ("nangw", "năng"),
        ]
        for (inp, exp) in cases {
            #expect(typeR(inp) == exp, "Telex \(inp) -> \(typeR(inp)) (mong \(exp))")
        }
    }

    @Test("VNI: 7/dấu gõ sau phụ âm cuối")
    func vni() {
        // 1 sắc, 2 huyền, 3 hỏi, 4 ngã, 5 nặng, 7 móc.
        let cases: [(String, String)] = [
            ("d9uoc75", "được"), ("d9uo7c5", "được"),
            ("nuoc71", "nước"), ("nuoc75", "nược"),
            ("thuong72", "thường"), ("nguoi72", "người"),
            ("muon71", "mướn"),
            ("qua7", "qua7"),   // qu: 'u' bán phụ âm -> không thành qưa
            ("quo7", "quơ"),
        ]
        for (inp, exp) in cases {
            #expect(typeR(inp, method: .vni) == exp, "VNI \(inp) -> \(typeR(inp, method: .vni)) (mong \(exp))")
        }
    }
}
