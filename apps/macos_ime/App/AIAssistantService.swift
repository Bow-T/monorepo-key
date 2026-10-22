// AIAssistantService.swift
// ------------------------
// TRỢ LÝ AI — tầng App: đọc vùng bôi đen (CHỈ ĐỌC), gọi hãng AI qua URLSession,
// trả kết quả về cho popup hiển thị. Logic dựng request/parse nằm ở VietEngine
// (AIClient) — file này chỉ lo I/O: đọc selection + mạng.
//
// LUỒNG:
//   1. Người dùng bôi đen chữ ở app bất kỳ, nhấn phím tắt (hoặc menu).
//   2. Đọc vùng chọn (AX -> clipboard fallback, tái dùng pattern SelectionCounter).
//   3. Với "Hỏi tự do": hỏi thêm câu prompt qua NSAlert.
//   4. Gọi provider (Claude/OpenAI) — key lấy từ Keychain.
//   5. Hiện kết quả trong AIResultWindow (popup pixel-art + nút Copy).
//
// KHÔNG ghi đè văn bản gốc — chỉ hiển thị. Văn bản bôi đen ĐƯỢC GỬI RA API BÊN
// NGOÀI (Anthropic/OpenAI); UI có ghi rõ điều này cho người dùng biết.

import AppKit
import ApplicationServices
import VietEngine

@MainActor
enum AIAssistantService {

    /// Cấu hình đọc từ file settings (provider + model). Key luôn lấy từ Keychain.
    struct Config {
        var provider: AIProvider = .claude
        var claudeModel: String = AIProvider.claude.defaultModel
        var openaiModel: String = AIProvider.openai.defaultModel

        /// Model đang dùng theo provider đã chọn.
        var activeModel: String {
            provider == .claude ? claudeModel : openaiModel
        }
    }

    /// Cấu hình hiện hành (AppDelegate cập nhật mỗi khi settings đổi).
    static var config = Config()

    /// Bắt đầu một thao tác AI trên vùng bôi đen. Gọi từ phím tắt/menu.
    /// `previousApp` = app đang focus trước khi menu ta chiếm focus (để trả lại).
    static func run(_ operation: AIOperation, previousApp: NSRunningApplication?) {
        // Trả focus về app gốc trước khi đọc selection (AX/⌘C cần app đó ở trước).
        if let app = previousApp, !app.isTerminated {
            app.activate()
        }

        // Trì hoãn ngắn để focus kịp trả về, rồi đọc vùng chọn.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard let selection = readSelection(), !selection.isEmpty else {
                ToastHUD.show("CHƯA BÔI ĐEN CHỮ NÀO")
                return
            }

            // Key phải có trước khi hỏi gì thêm.
            guard AIKeychain.hasKey(config.provider) else {
                ToastHUD.show("CHƯA NHẬP API KEY — VÀO CÀI ĐẶT")
                return
            }

            // Hỏi tự do: xin câu hỏi qua hộp thoại pixel-art (bất đồng bộ). Các thao
            // tác khác: chạy luôn.
            if operation.needsUserPrompt {
                AIKeyPromptWindow.presentAsk { prompt in
                    guard !prompt.isEmpty else { return }
                    perform(operation, selection: selection, userPrompt: prompt)
                }
            } else {
                perform(operation, selection: selection, userPrompt: nil)
            }
        }
    }

    // MARK: - Gọi AI

    private static func perform(_ operation: AIOperation, selection: String, userPrompt: String?) {
        let provider = config.provider
        let model = config.activeModel
        guard let apiKey = AIKeychain.read(provider), !apiKey.isEmpty else {
            ToastHUD.show("CHƯA NHẬP API KEY — VÀO CÀI ĐẶT")
            return
        }

        let spec: AIRequestSpec
        do {
            spec = try AIClient.makeRequest(
                provider: provider, model: model, operation: operation,
                selection: selection, userPrompt: userPrompt, apiKey: apiKey
            )
        } catch {
            let msg = (error as? AIError)?.vietnameseMessage ?? "Không dựng được yêu cầu."
            ToastHUD.show(msg.uppercased())
            return
        }

        // Mở popup ở trạng thái "đang hỏi…" ngay, rồi cập nhật khi có kết quả.
        // Gói câu người dùng đã gửi (đoạn bôi đen + yêu cầu) để nút "Hỏi tiếp" mở
        // chat nối tiếp có đúng ngữ cảnh.
        let sourceUser = operation.userMessage(selection: selection, userPrompt: userPrompt)
        AIResultWindow.present(title: operation.title, loading: true, sourceUserMessage: sourceUser)

        var request = URLRequest(url: spec.url)
        request.httpMethod = "POST"
        request.httpBody = spec.body
        request.timeoutInterval = 60
        for (k, v) in spec.headers { request.setValue(v, forHTTPHeaderField: k) }

        // Popup dùng chung: hỏi A rồi hỏi B, A trả về SAU thì không được đè kết quả B.
        latestRequest += 1
        let requestID = latestRequest
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                guard requestID == latestRequest else { return }
                handleResponse(provider: provider, data: data, response: response, error: error)
            }
        }
        task.resume()
    }

    private static var latestRequest = 0

    /// Xử lý phản hồi mạng trên main thread: cập nhật popup với kết quả/lỗi.
    private static func handleResponse(
        provider: AIProvider, data: Data?, response: URLResponse?, error: Error?
    ) {
        if let error {
            AIResultWindow.update(error: AIError.network(error.localizedDescription).vietnameseMessage)
            return
        }
        guard let data else {
            AIResultWindow.update(error: AIError.emptyResponse.vietnameseMessage)
            return
        }
        // HTTP != 2xx: dùng ĐÚNG mã HTTP + thông điệp thật từ máy chủ (nếu có) để
        // AIError.vietnameseMessage diễn giải rõ nguyên nhân (vd 429 = hết quota).
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let detail = AIClient.extractErrorMessage(from: data)
            let err = AIError.http(http.statusCode, detail)
            AIResultWindow.update(error: err.vietnameseMessage)
            return
        }
        do {
            let text = try AIClient.parseResponse(provider: provider, data: data)
            AIResultWindow.update(result: text)
        } catch {
            let msg = (error as? AIError)?.vietnameseMessage ?? "Không đọc được phản hồi."
            AIResultWindow.update(error: msg)
        }
    }

    // MARK: - Đọc vùng chọn (CHỈ ĐỌC — tái dùng pattern SelectionCounter)

    private static func readSelection() -> String? {
        if let ax = readSelectionViaAX() { return ax }
        return ClipboardManager.shared.copySelection(restoreAfter: true)
    }

    private static func readSelectionViaAX() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef
        ) == .success, let focused = focusedRef else {
            return nil
        }
        let element = focused as! AXUIElement
        var selectedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextAttribute as CFString, &selectedRef
        ) == .success, let selected = selectedRef as? String else {
            return nil
        }
        return selected
    }
}
