// AIChatService.swift
// -------------------
// TRÒ CHUYỆN AI — tầng App: gửi TOÀN BỘ lượt của cuộc đang mở lên hãng AI qua
// URLSession, nhận câu trả lời, thêm lượt .assistant vào cuộc và lưu lịch sử.
//
// Logic dựng request/parse nằm ở VietEngine (AIClient.makeChatRequest / parse-
// Response) — file này chỉ lo I/O mạng, giống AIAssistantService cho thao tác
// một-phát. Provider + model lấy từ AIAssistantService.config; key từ Keychain.
//
// RIÊNG TƯ: nội dung chat được gửi ra API bên ngoài (Anthropic/OpenAI).

import AppKit
import VietEngine

@MainActor
enum AIChatService {

    /// Gửi cuộc đang mở trong `model` để lấy 1 lượt trả lời của AI. Giả định lượt
    /// cuối trong `model.current.messages` là câu người dùng vừa hỏi.
    static func reply(model: AIChatModel) {
        let provider = AIAssistantService.config.provider
        let chatModel = AIAssistantService.config.activeModel

        guard let apiKey = AIKeychain.read(provider), !apiKey.isEmpty else {
            model.isSending = false
            model.errorText = AIError.missingAPIKey.vietnameseMessage
            return
        }

        let spec: AIRequestSpec
        do {
            spec = try AIClient.makeChatRequest(
                provider: provider,
                model: chatModel,
                messages: model.current.messages,
                apiKey: apiKey
            )
        } catch {
            model.isSending = false
            model.errorText = (error as? AIError)?.vietnameseMessage ?? "Không dựng được yêu cầu."
            return
        }

        model.isSending = true
        model.errorText = nil

        var request = URLRequest(url: spec.url)
        request.httpMethod = "POST"
        request.httpBody = spec.body
        request.timeoutInterval = 90
        for (k, v) in spec.headers { request.setValue(v, forHTTPHeaderField: k) }

        // Ghim id cuộc để nếu người dùng chuyển cuộc khác khi đang chờ, ta vẫn ghép
        // câu trả lời vào ĐÚNG cuộc đã hỏi (không đổ nhầm sang cuộc đang xem).
        let threadID = model.current.id

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                handle(model: model, threadID: threadID, provider: provider,
                       data: data, response: response, error: error)
            }
        }
        task.resume()
    }

    private static func handle(
        model: AIChatModel, threadID: UUID, provider: AIProvider,
        data: Data?, response: URLResponse?, error: Error?
    ) {
        model.isSending = false

        let store = ChatHistoryStore.shared

        func fail(_ message: String) {
            // Chỉ hiện lỗi nếu người dùng vẫn đang xem cuộc vừa hỏi.
            if model.current.id == threadID { model.errorText = message }
        }

        if let error {
            fail(AIError.network(error.localizedDescription).vietnameseMessage)
            return
        }
        guard let data else {
            fail(AIError.emptyResponse.vietnameseMessage)
            return
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let detail = AIClient.extractErrorMessage(from: data)
            fail(AIError.http(http.statusCode, detail).vietnameseMessage)
            return
        }

        let reply: String
        do {
            reply = try AIClient.parseResponse(provider: provider, data: data)
        } catch {
            fail((error as? AIError)?.vietnameseMessage ?? "Không đọc được phản hồi.")
            return
        }

        // Ghép câu trả lời vào cuộc đã hỏi (lấy bản mới nhất từ store để không mất
        // lượt nếu có thay đổi giữa chừng), rồi lưu.
        guard var thread = store.thread(id: threadID) else { return }
        thread.messages.append(ChatMessage(role: .assistant, text: reply))
        store.upsert(thread)

        model.threads = store.threads
        if model.current.id == threadID {
            model.current = thread
        }
    }
}
