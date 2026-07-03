// TypingStatsTests.swift
// ----------------------
// Test model thống kê gõ — trọng tâm là logic streak (chuỗi ngày) & tỉ lệ Việt/Anh.

import Testing
import Foundation
@testable import VietEngine

@Suite("Thống kê gõ")
struct TypingStatsTests {

    @Test("Đếm phím & phân loại Việt/Anh")
    func keystrokes() {
        var s = TypingStats()
        s.addKeystroke(vietnamese: true)
        s.addKeystroke(vietnamese: true)
        s.addKeystroke(vietnamese: false)
        #expect(s.keystrokes == 3)
        #expect(s.vietKeystrokes == 2)
        #expect(s.engKeystrokes == 1)
        #expect(abs(s.vietRatio - 2.0 / 3.0) < 1e-9)
    }

    @Test("vietRatio = 0 khi chưa gõ")
    func ratioEmpty() {
        #expect(TypingStats().vietRatio == 0)
    }

    @Test("charsSaved bỏ qua giá trị ≤ 0")
    func charsSaved() {
        var s = TypingStats()
        s.addCharsSaved(5)
        s.addCharsSaved(0)
        s.addCharsSaved(-3)
        s.addCharsSaved(2)
        #expect(s.charsSaved == 7)
    }

    @Test("Streak: ngày đầu tiên = 1")
    func streakFirstDay() {
        var s = TypingStats()
        s.addVietWord(today: "2026-07-03", yesterday: "2026-07-02")
        #expect(s.streak == 1)
        #expect(s.vietWords == 1)
        #expect(s.wordsToday == 1)
        #expect(s.lastActiveDay == "2026-07-03")
    }

    @Test("Streak: cùng ngày không tăng, wordsToday cộng dồn")
    func streakSameDay() {
        var s = TypingStats()
        s.addVietWord(today: "2026-07-03", yesterday: "2026-07-02")
        s.addVietWord(today: "2026-07-03", yesterday: "2026-07-02")
        s.addVietWord(today: "2026-07-03", yesterday: "2026-07-02")
        #expect(s.streak == 1)
        #expect(s.vietWords == 3)
        #expect(s.wordsToday == 3)
    }

    @Test("Streak: ngày liền kề -> nối chuỗi, wordsToday reset")
    func streakConsecutive() {
        var s = TypingStats()
        s.addVietWord(today: "2026-07-03", yesterday: "2026-07-02") // streak 1
        s.addVietWord(today: "2026-07-04", yesterday: "2026-07-03") // liền kề -> 2
        #expect(s.streak == 2)
        #expect(s.wordsToday == 1)   // sang ngày mới -> reset rồi +1
        #expect(s.vietWords == 2)    // tổng vẫn cộng dồn
    }

    @Test("Streak: cách quãng -> reset về 1")
    func streakGap() {
        var s = TypingStats()
        s.addVietWord(today: "2026-07-03", yesterday: "2026-07-02") // streak 1
        s.addVietWord(today: "2026-07-04", yesterday: "2026-07-03") // 2
        s.addVietWord(today: "2026-07-10", yesterday: "2026-07-09") // nhảy cóc -> 1
        #expect(s.streak == 1)
        #expect(s.wordsToday == 1)
        #expect(s.vietWords == 3)
    }

    @Test("Round-trip Codable giữ nguyên")
    func codableRoundTrip() throws {
        var s = TypingStats()
        s.addKeystroke(vietnamese: true)
        s.addVietWord(today: "2026-07-03", yesterday: "2026-07-02")
        s.addCharsSaved(9)
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(TypingStats.self, from: data)
        #expect(back == s)
    }
}
