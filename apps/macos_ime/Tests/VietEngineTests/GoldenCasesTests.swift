// GoldenCasesTests.swift
// ----------------------
// Chạy BỘ CA GÕ CHUẨN DÙNG CHUNG (packages/viet_engine/spec/typing_cases.tsv) qua
// engine Swift. Engine Dart và C++ nạp đúng file này — bản nào lệch là đỏ.

import Foundation
import Testing
@testable import VietEngine

/// Gõ `keys` vào một engine mới ("<" = Backspace), trả chuỗi âm tiết sau phím cuối.
private func type(_ keys: String, method: InputMethod, toneStyle: VietEngine.ToneStyle) -> String {
    let engine = VietEngine(method: method, toneStyle: toneStyle)
    var current = ""
    for ch in keys {
        current = (ch == "<" ? engine.backspace() : engine.process(ch)) ?? ""
    }
    return current
}

@Suite("Bộ ca gõ chuẩn dùng chung (typing_cases.tsv)")
struct GoldenCases {

    @Test("Engine Swift khớp mọi ca trong spec chung")
    func sharedSpec() throws {
        // Tests/VietEngineTests/<file> -> lên 5 cấp là gốc repo.
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        url.appendPathComponent("packages/viet_engine/spec/typing_cases.tsv")
        let text = try String(contentsOf: url, encoding: .utf8)

        var count = 0
        for (i, line) in text.split(whereSeparator: \.isNewline).enumerated() {
            if line.hasPrefix("#") { continue }
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            let valid = cols.count == 4 && !cols.contains("")
            let method: InputMethod? = valid ? ["telex": .telex, "vni": .vni][cols[0]] : nil
            let style: VietEngine.ToneStyle? = valid ? ["modern": .modern, "old": .old][cols[1]] : nil
            guard let method, let style else {
                Issue.record("typing_cases.tsv: dòng sai định dạng (dòng không rỗng thứ \(i + 1)): \(line)")
                continue
            }
            let expected = cols[3] == "∅" ? "" : cols[3]
            let got = type(cols[2], method: method, toneStyle: style)
            // So từng scalar: String == của Swift coi NFC và NFD là bằng nhau, Dart/C++ thì không.
            #expect(Array(got.unicodeScalars) == Array(expected.unicodeScalars),
                    "\(cols[0])/\(cols[1]) \(cols[2]) -> \(got) (mong \(expected))")
            count += 1
        }
        #expect(count > 0, "không nạp được ca nào từ \(url.path)")
    }
}
