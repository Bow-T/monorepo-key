import Testing
@testable import VietEngine

/// Chống tái phát bug "cặp đảo" (dạy→dậy, đẻ→để…): bộ gieo mặc định KHÔNG được
/// chứa cặp mà vế 'sai' thật ra là một từ đúng chính tả.
@Suite("defaultPairs không còn cặp đảo")
struct DefaultPairsCheck {
    @Test("defaultPairs: vế wrong không phải từ đúng")
    func noReversedPairs() {
        let pairs = AutoCorrectDictionary.defaultPairs()
        let bad = pairs.filter { AutoCorrectDictionary.isRealWord($0.wrong) }
        #expect(bad.isEmpty)
        let wrongs = Set(pairs.map { $0.wrong })
        for w in ["dạy", "đẻ", "đáy", "máy", "vè", "rồi"] {
            #expect(!wrongs.contains(w))
        }
    }
}
