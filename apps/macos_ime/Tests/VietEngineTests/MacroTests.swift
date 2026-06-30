// MacroTests.swift
// ----------------
// Test gõ tắt / macro. Gõ chuỗi phím rồi quan sát KeyResult cuối cùng.

import Testing
import Foundation
@testable import VietEngine

/// Gõ `keys` qua engine có macro; trả về văn bản cuối cùng caller sẽ thấy
/// (mô phỏng caller: âm tiết hiển thị, hoặc bung macro = xoá rồi chèn).
private func typeMacro(_ keys: String, store: MacroStore) -> String {
    let engine = VietEngine(method: .telex, macros: store)
    var visible = ""          // toàn bộ văn bản đã xuất
    var currentSyllable = ""  // phần âm tiết đang hiển thị (chưa chốt)
    for ch in keys {
        switch engine.processKey(ch) {
        case .syllable(let s):
            // thay phần âm tiết hiện tại bằng s
            visible.removeLast(currentSyllable.count)
            visible += s
            currentSyllable = s
        case .wordBreak(let c):
            visible.append(c)
            currentSyllable = ""
        case .macro(let deleteCount, let insert, let breakChar):
            visible.removeLast(min(deleteCount, visible.count))
            visible += insert
            visible.append(breakChar)
            currentSyllable = ""
        }
    }
    return visible
}

@Suite("Gõ tắt / Macro")
struct MacroBasics {

    @Test("Macro tĩnh: vn -> Việt Nam khi gặp space")
    func staticExpand() {
        let store = MacroStore([
            .init(keyword: "vn", content: "Việt Nam"),
            .init(keyword: "kb", content: "không biết"),
        ])
        #expect(typeMacro("vn ", store: store) == "Việt Nam ")
        #expect(typeMacro("kb ", store: store) == "không biết ")
    }

    @Test("Macro bung với nhiều loại phím ngắt từ")
    func variousBreaks() {
        let store = MacroStore([.init(keyword: "btw", content: "by the way")])
        #expect(typeMacro("btw ", store: store) == "by the way ")
        #expect(typeMacro("btw.", store: store) == "by the way.")
        #expect(typeMacro("btw,", store: store) == "by the way,")
    }

    @Test("Không khớp -> gõ bình thường (tiếng Việt vẫn chạy)")
    func noMatchFallsThrough() {
        let store = MacroStore([.init(keyword: "vn", content: "Việt Nam")])
        // "as" -> "á" (telex), rồi space. Không phải macro.
        #expect(typeMacro("as ", store: store) == "á ")
        // "tieengs" -> "tiếng"
        #expect(typeMacro("tieengs ", store: store) == "tiếng ")
    }

    @Test("Từ khoá khớp theo PHÍM THÔ, không theo chữ đã bỏ dấu")
    func matchesRawKeys() {
        // từ khoá "as" — nhưng gõ "as" ra "á". Khớp theo phím thô "as".
        let store = MacroStore([.init(keyword: "as", content: "ALONsO")])
        #expect(typeMacro("as ", store: store) == "ALONsO ")
    }

    @Test("Macro chỉ bung ở ranh giới từ, không giữa từ")
    func onlyAtWordBoundary() {
        let store = MacroStore([.init(keyword: "vn", content: "Việt Nam")])
        // "xvn " — từ khoá phải khớp TOÀN BỘ phím thô của từ; "xvn" != "vn".
        #expect(typeMacro("xvn ", store: store) == "xvn ")
    }
}

@Suite("Macro nội dung động")
struct MacroDynamic {

    private func fixedDate() -> Date {
        // 2026-06-30 09:05:07
        var c = DateComponents()
        c.year = 2026; c.month = 6; c.day = 30
        c.hour = 9; c.minute = 5; c.second = 7
        return Calendar.current.date(from: c)!
    }

    @Test("Ngày / giờ theo format")
    func dateTime() {
        let env = MacroStore.Environment(now: fixedDate)
        let store = MacroStore([
            .init(keyword: "td", content: "dd/MM/yyyy", type: .date),
            .init(keyword: "tg", content: "HH:mm:ss", type: .time),
        ], environment: env)
        #expect(store.expand(keyword: "td") == "30/06/2026")
        #expect(store.expand(keyword: "tg") == "09:05:07")
    }

    @Test("Counter tăng dần")
    func counter() {
        let store = MacroStore([.init(keyword: "no", content: "#", type: .counter)])
        #expect(store.expand(keyword: "no") == "#1")
        #expect(store.expand(keyword: "no") == "#2")
        #expect(store.expand(keyword: "no") == "#3")
    }

    @Test("Random chọn theo index tiêm vào (deterministic)")
    func random() {
        let env = MacroStore.Environment(randomIndex: { _ in 1 })  // luôn lấy phần tử thứ 2
        let store = MacroStore([.init(keyword: "rr", content: "a, b, c", type: .random)],
                               environment: env)
        #expect(store.expand(keyword: "rr") == "b")
    }
}
