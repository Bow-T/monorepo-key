// SettingsStoreTests.swift
// ------------------------
// Đồng bộ settings.json phía bộ gõ, chạy trên FILE TẠM (không đụng cấu hình thật):
//   • watcher vẫn sống sau khi chính bộ gõ ghi file (ghi atomic = thay inode) — lỗi
//     cũ: cancel handler đóng nhầm fd mới, watcher chết, cài đặt từ UI bị bỏ qua;
//   • app Cài đặt ghi kiểu tạm + rename vẫn được nhận;
//   • file hỏng được cất .bak chứ không bị bỏ qua mãi / ghi đè mất;
//   • lần chạy đầu chưa có thư mục BowGo vẫn ghi được.

import Testing
import Foundation
@testable import BowGoApp

@MainActor
@Suite("SettingsStore: đồng bộ settings.json", .serialized)
struct SettingsStoreTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bowgo-settings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func json(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// Chờ (nhường main queue cho DispatchSource) tới khi điều kiện đúng, tối đa 3s.
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !condition() {
            if Date() > deadline { return }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    /// Hộp gom các lần onChange (closure không Sendable, test chạy trên main).
    private final class Received { var enabled: [Bool] = [] }

    @Test("watcher sống qua nhiều lần bộ gõ tự ghi + app Cài đặt ghi tạm-rồi-rename")
    func watcherSurvivesAtomicWrites() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("settings.json")
        try Data(#"{"enabled": true}"#.utf8).write(to: url)

        let store = SettingsStore(fileURL: url)
        let received = Received()
        store.onChange = { received.enabled.append($0.enabled) }
        store.startWatching()
        defer { store.stopWatching() }

        // Bộ gõ tự ghi (⌃⇧) hai lần — mỗi lần thay inode.
        store.writeEnabled(false)
        try await waitUntil { received.enabled.last == false }
        #expect(received.enabled.last == false)

        store.writeEnabled(true)
        try await waitUntil { received.enabled.last == true }
        #expect(received.enabled.last == true)

        // App Cài đặt ghi kiểu Flutter: file tạm rồi rename đè.
        let tmp = dir.appendingPathComponent("settings.json.tmp")
        try Data(#"{"enabled": false}"#.utf8).write(to: tmp)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        try await waitUntil { received.enabled.last == false }
        #expect(received.enabled.last == false, "watcher phải còn sống sau 3 lần thay inode")
        #expect(store.isWatching)
    }

    @Test("file hỏng: cất sang .bak rồi ghi file mới (không bỏ qua mãi)")
    func corruptFileIsBackedUp() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("settings.json")
        try Data("{hỏng".utf8).write(to: url)

        SettingsStore(fileURL: url).writeEnabled(false)

        let backup = url.appendingPathExtension("bak")
        #expect(try String(contentsOf: backup, encoding: .utf8) == "{hỏng")
        #expect(try json(at: url)["enabled"] as? Bool == false)
    }

    @Test("ghi giữ nguyên khoá khác (macro, cặp tự-sửa của app Cài đặt)")
    func updateKeepsOtherKeys() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("settings.json")
        try Data(#"{"enabled": true, "macros": [{"keyword": "vn", "content": "Việt Nam"}]}"#.utf8)
            .write(to: url)

        SettingsStore(fileURL: url).writeEnabled(false)

        let obj = try json(at: url)
        #expect(obj["enabled"] as? Bool == false)
        #expect((obj["macros"] as? [[String: Any]])?.first?["keyword"] as? String == "vn")
    }

    @Test("lần chạy đầu: chưa có thư mục BowGo vẫn gieo được mặc định")
    func firstRunCreatesDirectory() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("BowGo/settings.json")

        let store = SettingsStore(fileURL: url)
        store.seedLaunchAtLoginIfAbsent(default: true)
        store.seedAutoCorrectPairsIfAbsent()

        let obj = try json(at: url)
        #expect(obj["launchAtLogin"] as? Bool == true)
        #expect(((obj["autoCorrectPairs"] as? [Any])?.isEmpty) == false)
    }
}
