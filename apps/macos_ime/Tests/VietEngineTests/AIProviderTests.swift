// AIProviderTests.swift
// ---------------------
// Test lớp THUẦN của trợ lý AI: dựng request đúng cho từng hãng, bóc response
// đúng, và ném lỗi đúng. KHÔNG gọi mạng — chỉ kiểm body/headers và parse JSON.

import Testing
import Foundation
@testable import VietEngine

@Suite("AI: prompt & operation")
struct AIOperationTests {

    @Test("4 thao tác + nhãn không rỗng")
    func allOperations() {
        #expect(AIOperation.allCases.count == 4)
        for op in AIOperation.allCases {
            #expect(!op.title.isEmpty)
            #expect(!op.systemPrompt.isEmpty)
        }
    }

    @Test("Chỉ 'ask' cần người dùng nhập câu hỏi")
    func onlyAskNeedsPrompt() {
        #expect(AIOperation.ask.needsUserPrompt)
        #expect(!AIOperation.translate.needsUserPrompt)
        #expect(!AIOperation.summarize.needsUserPrompt)
        #expect(!AIOperation.grammar.needsUserPrompt)
    }

    @Test("Thao tác thường: user message = nguyên đoạn bôi đen")
    func plainOperationUserMessage() {
        let sel = "Hello world"
        #expect(AIOperation.translate.userMessage(selection: sel, userPrompt: nil) == sel)
        #expect(AIOperation.summarize.userMessage(selection: sel, userPrompt: "bỏ qua") == sel)
        #expect(AIOperation.grammar.userMessage(selection: sel, userPrompt: nil) == sel)
    }

    @Test("Hỏi tự do: ghép câu hỏi + đoạn văn bản")
    func askUserMessage() {
        let msg = AIOperation.ask.userMessage(selection: "abc", userPrompt: "dịch hộ")
        #expect(msg.contains("dịch hộ"))
        #expect(msg.contains("abc"))
    }

    @Test("Hỏi tự do: câu hỏi rỗng -> vẫn có yêu cầu mặc định")
    func askEmptyPrompt() {
        let msg = AIOperation.ask.userMessage(selection: "abc", userPrompt: "  ")
        #expect(msg.contains("abc"))
        #expect(!msg.isEmpty)
    }
}

@Suite("AI: provider")
struct AIProviderTests {

    @Test("2 hãng + model mặc định đúng")
    func providers() {
        #expect(AIProvider.allCases.count == 2)
        #expect(AIProvider.claude.defaultModel == "claude-opus-4-8")
        #expect(AIProvider.openai.defaultModel == "gpt-4o")
    }

    @Test("Key rỗng -> ném missingAPIKey")
    func emptyKeyThrows() {
        #expect(throws: AIError.missingAPIKey) {
            _ = try AIClient.makeRequest(
                provider: .claude, model: "claude-opus-4-8",
                operation: .translate, selection: "x", userPrompt: nil, apiKey: "  "
            )
        }
    }
}

@Suite("AI: dựng request Claude")
struct AIClaudeRequestTests {

    private func body(_ spec: AIRequestSpec) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: spec.body)) as? [String: Any] ?? [:]
    }

    @Test("Endpoint + headers đúng")
    func endpointAndHeaders() throws {
        let spec = try AIClient.makeRequest(
            provider: .claude, model: "claude-opus-4-8",
            operation: .translate, selection: "Hello", userPrompt: nil, apiKey: "sk-ant-xxx"
        )
        #expect(spec.url.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(spec.headers["x-api-key"] == "sk-ant-xxx")
        #expect(spec.headers["anthropic-version"] == "2023-06-01")
        #expect(spec.headers["content-type"] == "application/json")
    }

    @Test("Body có model, adaptive thinking, system, message")
    func bodyShape() throws {
        let spec = try AIClient.makeRequest(
            provider: .claude, model: "claude-opus-4-8",
            operation: .translate, selection: "Hello", userPrompt: nil, apiKey: "k"
        )
        let b = body(spec)
        #expect(b["model"] as? String == "claude-opus-4-8")
        #expect((b["thinking"] as? [String: Any])?["type"] as? String == "adaptive")
        #expect((b["system"] as? String)?.isEmpty == false)
        let msgs = b["messages"] as? [[String: Any]]
        #expect(msgs?.first?["role"] as? String == "user")
        #expect(msgs?.first?["content"] as? String == "Hello")
    }
}

@Suite("AI: dựng request OpenAI")
struct AIOpenAIRequestTests {

    private func body(_ spec: AIRequestSpec) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: spec.body)) as? [String: Any] ?? [:]
    }

    @Test("Endpoint + header Bearer đúng")
    func endpointAndHeaders() throws {
        let spec = try AIClient.makeRequest(
            provider: .openai, model: "gpt-4o",
            operation: .summarize, selection: "Hi", userPrompt: nil, apiKey: "sk-openai"
        )
        #expect(spec.url.absoluteString == "https://api.openai.com/v1/chat/completions")
        #expect(spec.headers["authorization"] == "Bearer sk-openai")
    }

    @Test("Body có system + user message theo thứ tự")
    func bodyShape() throws {
        let spec = try AIClient.makeRequest(
            provider: .openai, model: "gpt-4o",
            operation: .grammar, selection: "teh cat", userPrompt: nil, apiKey: "k"
        )
        let b = body(spec)
        #expect(b["model"] as? String == "gpt-4o")
        let msgs = b["messages"] as? [[String: Any]]
        #expect(msgs?.count == 2)
        #expect(msgs?[0]["role"] as? String == "system")
        #expect(msgs?[1]["role"] as? String == "user")
        #expect(msgs?[1]["content"] as? String == "teh cat")
    }
}

@Suite("AI: bóc response")
struct AIParseResponseTests {

    @Test("Claude: ghép các block text, bỏ block khác")
    func parseClaudeText() throws {
        let json = """
        {"content":[{"type":"thinking","text":""},{"type":"text","text":"Xin chào"},{"type":"text","text":" bạn"}]}
        """.data(using: .utf8)!
        let out = try AIClient.parseResponse(provider: .claude, data: json)
        #expect(out == "Xin chào bạn")
    }

    @Test("Claude: content rỗng -> emptyResponse")
    func parseClaudeEmpty() {
        let json = #"{"content":[]}"#.data(using: .utf8)!
        #expect(throws: AIError.emptyResponse) {
            _ = try AIClient.parseResponse(provider: .claude, data: json)
        }
    }

    @Test("Claude: có error -> ném http")
    func parseClaudeError() {
        let json = #"{"error":{"type":"invalid_request_error","message":"bad key"}}"#.data(using: .utf8)!
        #expect(throws: AIError.self) {
            _ = try AIClient.parseResponse(provider: .claude, data: json)
        }
    }

    @Test("OpenAI: lấy choices[0].message.content")
    func parseOpenAIText() throws {
        let json = """
        {"choices":[{"message":{"role":"assistant","content":"Kết quả"}}]}
        """.data(using: .utf8)!
        let out = try AIClient.parseResponse(provider: .openai, data: json)
        #expect(out == "Kết quả")
    }

    @Test("OpenAI: JSON sai dạng -> decode")
    func parseOpenAIBadShape() {
        let json = #"{"foo":"bar"}"#.data(using: .utf8)!
        #expect(throws: AIError.decode) {
            _ = try AIClient.parseResponse(provider: .openai, data: json)
        }
    }
}

@Suite("AI: bóc & diễn giải lỗi HTTP")
struct AIErrorMessageTests {

    @Test("Bóc message lỗi từ body { error: { message } }")
    func extractsErrorMessage() {
        let json = #"{"error":{"message":"You exceeded your current quota","type":"insufficient_quota"}}"#.data(using: .utf8)!
        #expect(AIClient.extractErrorMessage(from: json) == "You exceeded your current quota")
    }

    @Test("Body không có error -> chuỗi rỗng")
    func noErrorField() {
        let json = #"{"choices":[]}"#.data(using: .utf8)!
        #expect(AIClient.extractErrorMessage(from: json) == "")
    }

    @Test("429 -> diễn giải hết quota + kèm message máy chủ")
    func message429() {
        let msg = AIError.http(429, "You exceeded your current quota").vietnameseMessage
        #expect(msg.contains("429"))
        #expect(msg.contains("hạn mức") || msg.contains("credit"))
        #expect(msg.contains("You exceeded your current quota"))
    }

    @Test("401 -> nói key không hợp lệ")
    func message401() {
        let msg = AIError.http(401, "").vietnameseMessage
        #expect(msg.contains("key") || msg.contains("Key"))
    }

    @Test("500 -> nói máy chủ lỗi")
    func message500() {
        let msg = AIError.http(503, "").vietnameseMessage
        #expect(msg.contains("503") || msg.contains("Máy chủ"))
    }
}
