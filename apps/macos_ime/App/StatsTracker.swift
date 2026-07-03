// StatsTracker.swift
// ------------------
// Gom số đếm thống kê gõ TRONG BỘ NHỚ rồi flush ra stats.json ĐỊNH KỲ — KHÔNG ghi
// đĩa mỗi phím (giữ callback event tap nhẹ). Các hàm record...() chỉ tăng biến.
//
// File stats.json nằm cùng thư mục settings.json (~/Library/Application Support/
// BowGo/), RIÊNG biệt để app UI (Flutter) đọc & hiển thị mà không đụng cấu hình.
//
// Luồng: EventTapController gọi record...() (đồng bộ, trong callback). Một Timer
// 10s (ở AppDelegate) gọi flush() để ghi nếu có thay đổi. Ghi cả khi app thoát.

import Foundation
import VietEngine

/// Theo dõi thống kê gõ + flush ra đĩa. KHÔNG @MainActor: record...() gọi từ
/// callback event tap (nền). Bảo vệ trạng thái bằng một khoá nhẹ.
final class StatsTracker: @unchecked Sendable {

    static let shared = StatsTracker()

    private let lock = NSLock()
    private var stats = TypingStats()
    private var dirty = false
    private var loaded = false

    private init() {}

    /// stats.json cùng thư mục settings.json.
    static var fileURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("BowGo", isDirectory: true)
            .appendingPathComponent("stats.json")
    }

    /// Đọc stats.json (nếu có) vào bộ nhớ. Gọi 1 lần lúc khởi động.
    func load() {
        lock.lock(); defer { lock.unlock() }
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: Self.fileURL),
              let decoded = try? JSONDecoder().decode(TypingStats.self, from: data)
        else { return }
        stats = decoded
    }

    // MARK: - Ghi nhận (nhẹ, gọi từ callback)

    func recordKeystroke(vietnamese: Bool) {
        lock.lock(); defer { lock.unlock() }
        stats.addKeystroke(vietnamese: vietnamese)
        dirty = true
    }

    func recordVietWord() {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        // Streak nối chuỗi khi ngày mới liền kề ngày hoạt động gần nhất.
        stats.addVietWord(
            today: Self.dayString(now),
            yesterday: Self.dayString(now.addingTimeInterval(-86_400))
        )
        dirty = true
    }

    func recordCharsSaved(_ n: Int) {
        lock.lock(); defer { lock.unlock() }
        stats.addCharsSaved(n)
        dirty = true
    }

    // MARK: - Flush

    /// Ghi ra đĩa nếu có thay đổi kể từ lần flush trước. Gọi định kỳ + lúc thoát.
    func flush() {
        lock.lock()
        guard dirty else { lock.unlock(); return }
        let snapshot = stats
        dirty = false
        lock.unlock()

        guard let out = try? JSONEncoder().encode(snapshot) else { return }
        let url = Self.fileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? out.write(to: url, options: .atomic)
    }

    // MARK: - Ngày

    /// "yyyy-MM-dd" theo lịch & múi giờ hiện tại.
    static func dayString(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
