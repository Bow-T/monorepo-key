// ScreenshotCaptureTests.swift
// ----------------------------
// Phím tắt chụp màn hình "bấm không thấy gì": nếu ScreenCaptureKit không trả ảnh
// (replayd treo / khởi động lại), cờ "đang chụp dở" kẹt mãi và mọi lần bấm sau bị
// bỏ qua im lặng. Phiên treo phải được bỏ sau thời hạn để lần bấm kế tiếp chụp lại.
// Ảnh giả không bao giờ trả về -> test không mở overlay thật.

import Testing
import Foundation
import CoreGraphics
@testable import BowGoApp

private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return _count }
    func hit() { lock.lock(); _count += 1; lock.unlock() }
}

private struct NeverReturns: Error {}

@MainActor
@Suite("Chụp màn hình: phiên treo không khoá phím tắt", .serialized)
struct ScreenshotCaptureTests {

    private func makeController(timeout: TimeInterval, calls: CallCounter) -> ScreenshotController {
        ScreenshotController(
            captureTimeout: timeout,
            capture: { _, _, _ in
                calls.hit()
                try await Task.sleep(for: .seconds(1))   // "treo" lâu hơn thời hạn
                throw NeverReturns()
            },
            hasPermission: { true }
        )
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("đang chụp dở: bấm lần nữa bị bỏ qua (không mở phiên thứ hai)")
    func secondPressWhilePreparingIsIgnored() async throws {
        let calls = CallCounter()
        let controller = makeController(timeout: 10, calls: calls)
        controller.beginCapture()
        try await waitUntil { calls.count == 1 }
        controller.beginCapture()
        try await Task.sleep(for: .milliseconds(100))
        #expect(calls.count == 1)
    }

    @Test("chụp treo quá hạn: lần bấm sau CHỤP LẠI được")
    func hungCaptureIsAbandonedAfterTimeout() async throws {
        let calls = CallCounter()
        let controller = makeController(timeout: 0.2, calls: calls)
        controller.beginCapture()
        try await waitUntil { calls.count == 1 }

        try await Task.sleep(for: .milliseconds(400))   // quá thời hạn 0.2s
        controller.beginCapture()
        try await waitUntil { calls.count == 2 }
        #expect(calls.count == 2, "cờ đang-chụp kẹt thì phím tắt chết tới khi khởi động lại")
    }
}
