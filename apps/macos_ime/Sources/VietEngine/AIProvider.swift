// AIProvider.swift
// ----------------
// TRỢ LÝ AI trên văn bản bôi đen — phần LOGIC THUẦN (không mạng, không UI) để test.
//
// Người dùng bôi đen 1 đoạn ở app bất kỳ, chọn 1 thao tác (dịch / tóm tắt / sửa
// ngữ pháp / hỏi tự do). Ta dựng request cho hãng AI đã chọn (Claude hoặc OpenAI),
// gửi đi (tầng App lo `URLSession`), rồi bóc kết quả từ JSON trả về.
//
// TÁCH BẠCH rõ:
//   • `AIProvider`   — hãng nào (endpoint + cách dựng body + cách bóc response).
//   • `AIOperation`  — thao tác nào (system/user prompt template).
//   • `AIRequestSpec`— gói (url, headers, body) sẵn sàng cho URLSession.
// Nhờ tách, TEST chỉ cần kiểm body/headers dựng đúng và parse response đúng —
// KHÔNG cần gọi mạng thật.

import Foundation

/// Hãng AI. Người dùng chọn ở Cài đặt; mỗi hãng có endpoint + shape riêng.
public enum AIProvider: String, CaseIterable, Sendable {
    case claude   // Anthropic Messages API
    case openai   // OpenAI Chat Completions API

    /// Nhãn hiển thị trên UI.
    public var title: String {
        switch self {
        case .claude: return "Claude (Anthropic)"
        case .openai: return "ChatGPT (OpenAI)"
        }
    }

    /// Model mặc định khi người dùng chưa cấu hình riêng.
    public var defaultModel: String {
        switch self {
        case .claude: return "claude-opus-4-8"
        case .openai: return "gpt-4o"
        }
    }
}

/// Bốn thao tác AI (đã chốt với người dùng). `CaseIterable` để tự sinh menu.
public enum AIOperation: String, CaseIterable, Sendable {
    case translate    // Dịch Anh↔Việt (tự nhận chiều)
    case summarize    // Tóm tắt / giải thích (gồm phân tích chat tiếng Anh)
    case grammar      // Sửa ngữ pháp / viết lại
    case ask          // Hỏi tự do (người dùng nhập prompt riêng)

    /// Nhãn tiếng Việt cho menu.
    public var title: String {
        switch self {
        case .translate: return "Dịch Anh ↔ Việt"
        case .summarize: return "Tóm tắt / giải thích"
        case .grammar:   return "Sửa ngữ pháp / viết lại"
        case .ask:       return "Hỏi tự do…"
        }
    }

    /// Thao tác này có cần người dùng nhập thêm câu hỏi không (chỉ `ask`).
    public var needsUserPrompt: Bool { self == .ask }

    /// System prompt định hướng cho mô hình. Ngắn gọn, tiếng Việt.
    public var systemPrompt: String {
        switch self {
        case .translate:
            return """
            Bạn là trợ lý dịch thuật Anh–Việt. Nếu văn bản là tiếng Anh, dịch sang \
            tiếng Việt tự nhiên, đúng ngữ cảnh. Nếu là tiếng Việt, dịch sang tiếng \
            Anh chuẩn mực. Nếu lẫn lộn, dịch phần không phải tiếng Việt sang tiếng \
            Việt. CHỈ trả về bản dịch, không thêm giải thích hay lời dẫn.
            """
        case .summarize:
            return """
            Bạn là trợ lý tóm tắt và giải thích. Tóm tắt hoặc giải thích văn bản \
            được cung cấp bằng tiếng Việt, rõ ràng và ngắn gọn. Nếu đó là một đoạn \
            hội thoại (ví dụ tin nhắn Slack tiếng Anh), hãy tóm tắt ai nói gì và ý \
            chính của cuộc trò chuyện. CHỈ trả về nội dung tóm tắt/giải thích.
            """
        case .grammar:
            return """
            Bạn là trợ lý biên tập. Sửa ngữ pháp, chính tả và diễn đạt của văn bản \
            cho tự nhiên, đúng chuẩn, GIỮ NGUYÊN ngôn ngữ gốc và ý nghĩa. CHỈ trả \
            về văn bản đã sửa, không giải thích thay đổi.
            """
        case .ask:
            return """
            Bạn là trợ lý hữu ích. Người dùng cung cấp một đoạn văn bản kèm một yêu \
            cầu. Thực hiện yêu cầu dựa trên đoạn văn bản đó. Trả lời bằng tiếng Việt \
            trừ khi được yêu cầu khác. Đi thẳng vào câu trả lời.
            """
        }
    }

    /// Dựng nội dung user message từ đoạn bôi đen `selection` và (với `ask`) câu
    /// hỏi tự do `userPrompt`.
    public func userMessage(selection: String, userPrompt: String?) -> String {
        switch self {
        case .translate, .summarize, .grammar:
            return selection
        case .ask:
            let q = (userPrompt ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let request = q.isEmpty ? "Hãy xử lý đoạn văn bản này." : q
            return "Yêu cầu: \(request)\n\nĐoạn văn bản:\n\(selection)"
        }
    }
}

/// Lỗi khi gọi AI (để tầng UI hiện thông báo tiếng Việt gọn).
public enum AIError: Error, Sendable, Equatable {
    case missingAPIKey        // chưa nhập key cho hãng đang chọn
    case emptyResponse        // gọi được nhưng không có nội dung trả về
    case http(Int, String)    // mã lỗi HTTP + thân (để chẩn đoán)
    case decode               // JSON trả về không đúng dạng mong đợi
    case network(String)      // lỗi mạng (mất kết nối…)

    /// Thông báo tiếng Việt gọn cho người dùng.
    public var vietnameseMessage: String {
        switch self {
        case .missingAPIKey: return "Chưa nhập API key. Vào Cài đặt → Trợ lý AI."
        case .emptyResponse: return "AI không trả về nội dung."
        case .http(let code, _): return "Lỗi từ máy chủ AI (mã \(code))."
        case .decode: return "Không đọc được phản hồi từ AI."
        case .network(let msg): return "Lỗi mạng: \(msg)"
        }
    }
}

/// Gói request đã dựng xong, sẵn sàng cho `URLSession` ở tầng App.
public struct AIRequestSpec: Equatable, Sendable {
    public let url: URL
    public let headers: [String: String]
    public let body: Data

    public init(url: URL, headers: [String: String], body: Data) {
        self.url = url
        self.headers = headers
        self.body = body
    }
}

/// Bộ dựng-request & bóc-response THUẦN cho từng hãng — test được không cần mạng.
public enum AIClient {

    /// Số token tối đa cho phần trả lời (kết quả ngắn — dịch/tóm tắt/sửa).
    public static let maxTokens = 2048

    // MARK: - Dựng request

    /// Dựng `AIRequestSpec` cho một lần gọi. Trả `nil` KHÔNG dùng ở đây — thay vào
    /// đó ném lỗi `missingAPIKey` nếu key rỗng để tầng gọi biết mà báo.
    public static func makeRequest(
        provider: AIProvider,
        model: String,
        operation: AIOperation,
        selection: String,
        userPrompt: String?,
        apiKey: String
    ) throws -> AIRequestSpec {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AIError.missingAPIKey }

        let system = operation.systemPrompt
        let user = operation.userMessage(selection: selection, userPrompt: userPrompt)

        switch provider {
        case .claude:  return try makeClaudeRequest(model: model, system: system, user: user, key: key)
        case .openai:  return try makeOpenAIRequest(model: model, system: system, user: user, key: key)
        }
    }

    /// Anthropic Messages API — `POST /v1/messages`.
    /// Adaptive thinking để chất lượng tốt cho model 4.6+; header `anthropic-version`.
    private static func makeClaudeRequest(
        model: String, system: String, user: String, key: String
    ) throws -> AIRequestSpec {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        let payload: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "thinking": ["type": "adaptive"],
            "system": system,
            "messages": [
                ["role": "user", "content": user]
            ],
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let headers = [
            "content-type": "application/json",
            "x-api-key": key,
            "anthropic-version": "2023-06-01",
        ]
        return AIRequestSpec(url: url, headers: headers, body: body)
    }

    /// OpenAI Chat Completions API — `POST /v1/chat/completions`.
    private static func makeOpenAIRequest(
        model: String, system: String, user: String, key: String
    ) throws -> AIRequestSpec {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        let payload: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let headers = [
            "content-type": "application/json",
            "authorization": "Bearer \(key)",
        ]
        return AIRequestSpec(url: url, headers: headers, body: body)
    }

    // MARK: - Bóc response

    /// Bóc chuỗi kết quả từ dữ liệu JSON của hãng. Ném `AIError` nếu không hợp lệ.
    public static func parseResponse(provider: AIProvider, data: Data) throws -> String {
        switch provider {
        case .claude:  return try parseClaude(data)
        case .openai:  return try parseOpenAI(data)
        }
    }

    /// Claude: `{ "content": [ {"type":"text","text":"..."}, ... ] }`.
    /// Bỏ qua các block không phải text (vd thinking rỗng), ghép các block text.
    private static func parseClaude(_ data: Data) throws -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.decode
        }
        // Lỗi cấp API trả trong { "error": { "message": ... } }.
        if let err = obj["error"] as? [String: Any] {
            let msg = (err["message"] as? String) ?? "unknown"
            throw AIError.http(0, msg)
        }
        guard let content = obj["content"] as? [[String: Any]] else { throw AIError.decode }
        let text = content
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AIError.emptyResponse }
        return text
    }

    /// OpenAI: `{ "choices": [ {"message": {"content": "..."}} ] }`.
    private static func parseOpenAI(_ data: Data) throws -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIError.decode
        }
        if let err = obj["error"] as? [String: Any] {
            let msg = (err["message"] as? String) ?? "unknown"
            throw AIError.http(0, msg)
        }
        guard let choices = obj["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw AIError.decode
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIError.emptyResponse }
        return trimmed
    }
}
