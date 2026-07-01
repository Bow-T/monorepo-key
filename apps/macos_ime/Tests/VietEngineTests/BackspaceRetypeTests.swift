// BackspaceRetypeTests.swift
// --------------------------
// KHOÁ BUG "gõ sai → xoá đi → gõ lại bị NUỐT CHỮ".
//
// Bug gốc: nhánh Backspace của EventTapController cho phím Backspace VẬT LÝ đi qua
// (giả định nó xoá đúng 1 ký tự hiển thị), rồi đặt committedLength = rebuilt.count.
// Nhưng engine.backspace() lùi theo PHÍM THÔ và "tháo dấu" (ư=u+w, â=a+a...), nên
// chuỗi hiển thị mới có thể DÀI BẰNG chuỗi cũ ("mư"→"mu", "ấ"→"â"). Khi đó màn hình
// (mất 1 ký tự) và engine (giữ nguyên số ký tự) LỆCH nhau → gõ lại nuốt chữ.
//
// Bản sửa: controller NUỐT phím Backspace gốc và tự đồng bộ màn hình = engine
// (xoá committedLength ký tự cũ, gõ lại rebuilt). Test này mô phỏng ĐÚNG vòng lặp
// đó và kiểm chứng: gõ sai, Backspace tới khi màn rỗng, gõ lại → ra đúng từ.

import Testing
import Foundation
@testable import VietEngine

/// Mô phỏng buffer ứng dụng + đồng bộ engine y hệt EventTapController (bản đã sửa).
private final class ControllerSim {
    let engine: VietEngine
    var app = ""
    var committed = 0

    init(method: InputMethod = .telex) { engine = VietEngine(method: method) }

    private func replace(_ backspaces: Int, _ text: String) {
        let safe = min(max(backspaces, 0), 15)
        if safe > 0 { app = String(app.dropLast(safe)) }
        app += text
    }

    /// Gõ một ký tự thường (nhánh gõ thay đồng bộ của controller).
    func type(_ ch: Character) {
        guard let rendered = engine.process(ch) else {
            committed = 0; app.append(ch); return
        }
        let bs = committed
        committed = rendered.count
        replace(bs, rendered)
    }

    /// Nhấn Backspace (nhánh đã sửa): nuốt phím gốc, đồng bộ màn = engine.
    func backspace() {
        if let rebuilt = engine.backspace() {
            let bs = committed
            committed = rebuilt.count
            replace(bs, rebuilt)
        } else {
            committed = 0
            app = String(app.dropLast(1))
        }
    }

    func typeString(_ s: String) { for c in s { type(c) } }

    /// Nhấn Backspace tới khi màn hình rỗng (như người dùng xoá sạch một từ).
    func backspaceUntilEmpty() {
        var guardN = 0
        while !app.isEmpty && guardN < 40 { backspace(); guardN += 1 }
    }
}

@Suite("Gõ sai → xoá đi → gõ lại (không nuốt chữ)")
struct BackspaceRetype {

    // Phím Telex -> chữ hiển thị, gồm nhiều loại biến âm 2-phím (w, aa, dd, oo).
    private let words: [(keys: String, shown: String)] = [
        ("muw", "mư"), ("aa", "â"), ("dd", "đ"), ("oo", "ô"),
        ("tieengs", "tiếng"), ("dduwowcj", "được"), ("nguwowif", "người"),
        ("chuwowng", "chương"), ("thees", "thế"), ("cas", "cá"),
        ("ban", "ban"), ("nhaf", "nhà"), ("khoer", "khoẻ"), ("truwowngf", "trường"),
    ]

    @Test("Gõ từng từ rồi Backspace tới rỗng → màn hình sạch, engine sạch")
    func backspaceToEmptyClears() {
        for w in words {
            let sim = ControllerSim()
            sim.typeString(w.keys)
            #expect(sim.app == w.shown)         // gõ đúng trước đã
            sim.backspaceUntilEmpty()
            #expect(sim.app == "")              // màn hình phải sạch
            #expect(sim.committed == 0)         // engine cũng phải sạch
        }
    }

    @Test("Xoá sạch một từ rồi gõ từ khác → KHÔNG nuốt/dính chữ")
    func retypeAfterClearAllPairs() {
        for a in words {
            for b in words {
                let sim = ControllerSim()
                sim.typeString(a.keys)
                sim.backspaceUntilEmpty()
                sim.typeString(b.keys)
                #expect(sim.app == b.shown,
                        "Sau khi gõ '\(a.shown)', xoá sạch, gõ lại '\(b.shown)' → '\(sim.app)'")
            }
        }
    }

    @Test("Kịch bản thực: gõ thiếu dấu → xoá hết → gõ lại có dấu")
    func fixMissingTone() {
        let scenarios: [(bad: String, good: String, expect: String)] = [
            ("tieng",  "tieengs",  "tiếng"),
            ("duoc",   "dduwowcj", "được"),
            ("nguoi",  "nguwowif", "người"),
            ("mu",     "muw",      "mư"),
            ("khoe",   "khoer",    "khoẻ"),
            ("truong", "truwowngf","trường"),
        ]
        for s in scenarios {
            let sim = ControllerSim()
            sim.typeString(s.bad)
            sim.backspaceUntilEmpty()
            sim.typeString(s.good)
            #expect(sim.app == s.expect,
                    "gõ '\(s.bad)', xoá hết, gõ lại '\(s.good)' → '\(sim.app)' (đợi '\(s.expect)')")
        }
    }

    @Test("Xoá vài ký tự giữa từ rồi gõ tiếp → phần đầu giữ nguyên")
    func partialBackspaceThenContinue() {
        // Gõ "tiếng", xoá 2 ký tự (dấu + phụ âm cuối theo phím thô), gõ lại "gs".
        let sim = ControllerSim()
        sim.typeString("tieengs")            // "tiếng"
        #expect(sim.app == "tiếng")
        sim.backspace()                       // tháo 's' → "tiêng"
        sim.backspace()                       // tháo 'g' → "tiên"
        sim.typeString("gs")                  // gõ lại 'g' + 's' → "tiếng"
        #expect(sim.app == "tiếng", "gõ lại sau Backspace giữa từ → '\(sim.app)'")
    }
}
