// TypingStats.swift
// -----------------
// THỐNG KÊ GÕ (cục bộ, không gửi đi đâu). Chỉ LOGIC thuần: cộng dồn số đếm, chuỗi
// ngày (streak), số theo ngày. Tầng App lo I/O file + flush định kỳ + đồng hồ.
//
// Đếm gì:
//   • keystrokes     — tổng phím chữ đã gõ (thô)
//   • vietWords      — số từ tiếng Việt đã chốt (ở phím ngắt từ)
//   • charsSaved     — ký tự tiết kiệm nhờ gõ tắt (macro/emoji): len(nội dung) - len(từ khoá)
//   • vietKeystrokes — phím gõ khi ĐANG bật bộ gõ (để tính tỉ lệ Việt/Anh)
//   • engKeystrokes  — phím gõ khi bộ gõ TẮT
//   • streak         — số ngày liên tiếp có gõ; today/yesterday theo chuỗi "yyyy-MM-dd"
//
// Bất biến streak: cập nhật khi có hoạt động trong ngày. Nếu ngày mới liền kề ngày
// hoạt động gần nhất -> streak+1; cách quãng -> streak reset về 1; cùng ngày -> giữ.

import Foundation

/// Bản ghi thống kê — serialize thẳng ra stats.json. Value type để test dễ.
public struct TypingStats: Equatable, Codable {
    public var keystrokes: Int = 0
    public var vietWords: Int = 0
    public var charsSaved: Int = 0
    public var vietKeystrokes: Int = 0
    public var engKeystrokes: Int = 0

    /// Chuỗi ngày liên tiếp có gõ.
    public var streak: Int = 0
    /// Ngày hoạt động gần nhất, "yyyy-MM-dd". Rỗng = chưa có.
    public var lastActiveDay: String = ""
    /// Số từ tiếng Việt gõ RIÊNG trong `lastActiveDay` (reset khi sang ngày mới).
    public var wordsToday: Int = 0

    public init() {}

    /// Tỉ lệ phím gõ khi bật bộ gõ / tổng phím có phân loại (0…1). 0 nếu chưa có.
    public var vietRatio: Double {
        let total = vietKeystrokes + engKeystrokes
        return total == 0 ? 0 : Double(vietKeystrokes) / Double(total)
    }

    // MARK: - Cập nhật

    /// Ghi một phím chữ đã gõ. `vietnamese` = bộ gõ đang bật hay tắt (để chia tỉ lệ).
    public mutating func addKeystroke(vietnamese: Bool) {
        keystrokes += 1
        if vietnamese { vietKeystrokes += 1 } else { engKeystrokes += 1 }
    }

    /// Ghi một từ tiếng Việt đã chốt, cập nhật streak/wordsToday theo `today`.
    /// `yesterday` = ngày liền trước (để nối chuỗi streak khi gõ ngày kế tiếp).
    public mutating func addVietWord(today: String, yesterday: String) {
        rollDay(today, yesterday: yesterday)   // cập nhật streak & reset wordsToday nếu sang ngày
        vietWords += 1
        wordsToday += 1
    }

    /// Ghi số ký tự tiết kiệm nhờ một lần bung gõ tắt (macro/emoji). Bỏ qua nếu ≤ 0.
    public mutating func addCharsSaved(_ n: Int) {
        guard n > 0 else { return }
        charsSaved += n
    }

    /// Cập nhật streak & reset bộ đếm ngày khi bước sang ngày mới.
    /// `today` dạng "yyyy-MM-dd"; `yesterday` là ngày liền trước (tầng App tính sẵn).
    public mutating func rollDay(_ today: String, yesterday: String? = nil) {
        guard today != lastActiveDay else { return }   // cùng ngày -> không đổi streak
        if lastActiveDay.isEmpty {
            streak = 1
        } else if let y = yesterday, lastActiveDay == y {
            streak += 1                                 // liền kề -> nối chuỗi
        } else {
            streak = 1                                  // cách quãng -> chuỗi mới
        }
        lastActiveDay = today
        wordsToday = 0
    }
}
