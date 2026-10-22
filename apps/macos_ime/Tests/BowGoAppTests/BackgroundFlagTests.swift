// BackgroundFlagTests.swift
// -------------------------
// Cờ dò nền của event tap ("ô focus có phải thanh địa chỉ", "Spotlight đang hiện",
// "còn quyền Accessibility"): đọc KHÔNG được chặn đường phím, làm mới trễ phải dò
// SAU khi app đích đổi focus, và yêu cầu làm mới lúc đang dò dở KHÔNG được bỏ
// (lỗi cũ: ⌘L rồi gõ ngay -> cờ giữ câu trả lời của ô cũ -> gõ đôi "ddo").

import Testing
import Foundation
@testable import BowGoApp

/// Giá trị mà "app đích" trả lời — đổi từ test, đọc từ queue nền.
private final class Answer: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }
}

@Suite("BackgroundFlag: cờ dò nền của event tap")
struct BackgroundFlagTests {

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("get() không chặn kể cả khi phép dò chậm")
    func getNeverBlocks() {
        let flag = BackgroundFlag(ttl: 0.5) {
            Thread.sleep(forTimeInterval: 0.3)  // AX query của app đích đang bận
            return true
        }
        let start = Date()
        _ = flag.get()
        _ = flag.get()
        #expect(Date().timeIntervalSince(start) < 0.05)
    }

    @Test("refresh(after:) dò SAU khi focus đã đổi")
    func delayedRefreshSeesNewFocus() async throws {
        let answer = Answer()
        let flag = BackgroundFlag(ttl: 100) { answer.value }
        flag.refresh(after: 0.08)   // ngay lúc ⌘L: Chrome chưa chuyển focus
        answer.value = true         // Chrome chuyển focus vào thanh địa chỉ
        try await waitUntil { flag.get() }
        #expect(flag.get() == true)
    }

    @Test("refresh lúc đang dò dở: chạy thêm một lượt, không bỏ")
    func refreshDuringFlightReruns() async throws {
        let answer = Answer()
        let flag = BackgroundFlag(ttl: 100) {
            let v = answer.value
            Thread.sleep(forTimeInterval: 0.1)
            return v
        }
        flag.refresh()              // lượt 1 bắt đầu, đọc false
        try await Task.sleep(for: .milliseconds(30))
        answer.value = true
        flag.refresh()              // tới giữa lượt 1 -> phải dò lại
        try await waitUntil { flag.get() }
        #expect(flag.get() == true, "lượt làm mới thứ hai bị bỏ thì cờ kẹt ở false (TTL 100s)")
    }
}
