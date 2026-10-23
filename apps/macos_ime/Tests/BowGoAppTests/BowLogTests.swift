// BowLogTests.swift
// -----------------
// Log chẩn đoán phải ĐỌC ĐƯỢC (public) trong unified log — NSLog bị che "<private>".
// Ghi một dòng có mã riêng rồi đọc lại bằng `log show`.

import Testing
import Foundation
@testable import BowGoApp

@Suite("bowLog: log đọc được trong Console")
struct BowLogTests {

    @Test("dòng log hiện nguyên văn, không bị che <private>")
    func messageIsPublic() async throws {
        let marker = "bowlog-test-\(UUID().uuidString)"
        bowLog("[Test] \(marker)")
        try await Task.sleep(for: .seconds(1))

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        task.arguments = ["show", "--last", "1m", "--style", "compact",
                          "--predicate", "subsystem == \"com.bowgo.keyboard\""]
        let pipe = Pipe()
        task.standardOutput = pipe
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()

        #expect(String(decoding: data, as: UTF8.self).contains(marker))
    }
}
