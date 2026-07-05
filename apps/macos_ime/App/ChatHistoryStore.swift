// ChatHistoryStore.swift
// ----------------------
// LƯU LỊCH SỬ TRÒ CHUYỆN với Trợ lý AI ra đĩa (nhiều cuộc, giống ChatGPT).
//
// Mỗi cuộc = `ChatThread` (tiêu đề + danh sách lượt `ChatMessage` + thời gian).
// Toàn bộ ghi ra JSON dùng chung, cùng thư mục với clipboard_history.json /
// settings.json:  ~/Library/Application Support/BowGo/ai_chats.json
//
// RIÊNG TƯ: nội dung chat được GỬI RA API bên ngoài (Anthropic/OpenAI) và cũng
// LƯU tại máy trong file trên. Người dùng xoá được từng cuộc hoặc xoá hết (bên
// dưới + trong UI cửa sổ chat). File chỉ nằm trên máy người dùng, không đồng bộ.
//
// Tái dùng `ChatMessage` (Codable) từ VietEngine để khỏi định nghĩa lại shape.

import Foundation
import VietEngine

/// Một cuộc trò chuyện đã lưu. `title` sinh tự động từ câu hỏi đầu (rút gọn).
struct ChatThread: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    let createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), title: String = "", messages: [ChatMessage] = [],
         createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Rút gọn câu người dùng đầu tiên thành tiêu đề (<= 40 ký tự, 1 dòng).
    static func makeTitle(from firstUserText: String) -> String {
        let oneLine = firstUserText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if oneLine.isEmpty { return "Cuộc trò chuyện mới" }
        if oneLine.count <= 40 { return oneLine }
        let idx = oneLine.index(oneLine.startIndex, offsetBy: 40)
        return String(oneLine[..<idx]) + "…"
    }
}

@MainActor
final class ChatHistoryStore {
    static let shared = ChatHistoryStore()

    /// Tất cả cuộc, MỚI NHẤT LÊN ĐẦU (sắp theo `updatedAt` giảm dần).
    private(set) var threads: [ChatThread] = []

    /// Giới hạn số cuộc giữ lại (cắt cuộc cũ nhất khi vượt).
    private let limit = 100

    private var bowGoDir: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("BowGo", isDirectory: true)
    }

    private var fileURL: URL {
        bowGoDir.appendingPathComponent("ai_chats.json")
    }

    private init() {
        load()
    }

    // MARK: - Đọc/ghi đĩa

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([ChatThread].self, from: data) {
            threads = decoded.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    private func persist() {
        try? FileManager.default.createDirectory(
            at: bowGoDir, withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(threads) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: - Thao tác trên cuộc

    /// Lấy cuộc theo id (nil nếu đã xoá).
    func thread(id: UUID) -> ChatThread? {
        threads.first { $0.id == id }
    }

    /// Tạo cuộc mới rỗng, đưa lên đầu, trả về để UI làm cuộc đang mở.
    @discardableResult
    func createThread() -> ChatThread {
        let thread = ChatThread()
        threads.insert(thread, at: 0)
        // Chưa persist: cuộc rỗng chưa có nội dung, để lần lưu message đầu mới ghi.
        return thread
    }

    /// Lưu (thêm/thay) một cuộc rồi ghi đĩa. Dùng khi thêm lượt hỏi/đáp mới.
    /// Tự cập nhật `updatedAt`, sinh `title` nếu còn rỗng, đưa cuộc lên đầu.
    func upsert(_ thread: ChatThread) {
        var updated = thread
        updated.updatedAt = Date()
        if updated.title.isEmpty,
           let firstUser = updated.messages.first(where: { $0.role == .user }) {
            updated.title = ChatThread.makeTitle(from: firstUser.text)
        }
        threads.removeAll { $0.id == updated.id }
        threads.insert(updated, at: 0)
        if threads.count > limit {
            threads = Array(threads.prefix(limit))
        }
        persist()
    }

    /// Xoá một cuộc.
    func delete(id: UUID) {
        threads.removeAll { $0.id == id }
        persist()
    }

    /// Xoá TOÀN BỘ lịch sử (quyền riêng tư).
    func deleteAll() {
        threads.removeAll()
        persist()
    }
}
