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

            // Hỏi tự do: xin câu hỏi qua hộp thoại. Các thao tác khác: chạy luôn.
            if operation.needsUserPrompt {
                guard let prompt = askUserPrompt(), !prompt.isEmpty else { return }
                perform(operation, selection: selection, userPrompt: prompt)
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
        AIResultWindow.present(title: operation.title, loading: true)

        var request = URLRequest(url: spec.url)
        request.httpMethod = "POST"
        request.httpBody = spec.body
        request.timeoutInterval = 60
        for (k, v) in spec.headers { request.setValue(v, forHTTPHeaderField: k) }

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                handleResponse(provider: provider, data: data, response: response, error: error)
            }
        }
        task.resume()
    }

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
        // HTTP != 2xx: cố bóc thông điệp lỗi từ thân, nếu không thì báo mã.
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let detail = (try? AIClient.parseResponse(provider: provider, data: data))
                ?? "Lỗi từ máy chủ AI (mã \(http.statusCode))."
            AIResultWindow.update(error: detail)
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

    // MARK: - Hỏi tự do (nhập prompt)

    /// Hộp thoại xin câu hỏi cho thao tác "Hỏi tự do". Nil nếu người dùng huỷ.
    private static func askUserPrompt() -> String? {
        let alert = NSAlert()
        alert.messageText = "Hỏi AI về đoạn đã chọn"
        alert.informativeText = "Nhập yêu cầu của bạn (ví dụ: dịch, giải thích thuật ngữ này…)."
        alert.addButton(withTitle: "Gửi")
        alert.addButton(withTitle: "Huỷ")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "Yêu cầu của bạn…"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Đọc vùng chọn (CHỈ ĐỌC — tái dùng pattern SelectionCounter)

    private static func readSelection() -> String? {
        if let ax = readSelectionViaAX() { return ax }
        return readSelectionViaClipboard()
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

    /// Fallback: ⌘C lấy vùng chọn, đọc, rồi KHÔI PHỤC clipboard nguyên vẹn.
    private static func readSelectionViaClipboard() -> String? {
        let pasteboard = NSPasteboard.general
        let savedItems = pasteboard.pasteboardItems?.compactMap { item -> NSPasteboardItem? in
            let copy = NSPasteboardItem()
            var wroteAny = false
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type); wroteAny = true }
            }
            return wroteAny ? copy : nil
        } ?? []

        let before = pasteboard.changeCount
        KeyOutput.simulateCopy()

        let deadline = Date().addingTimeInterval(0.4)
        var text: String? = nil
        while Date() < deadline {
            if pasteboard.changeCount != before {
                text = pasteboard.string(forType: .string)
                break
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }

        if !savedItems.isEmpty {
            pasteboard.clearContents()
            pasteboard.writeObjects(savedItems)
        }
        return text
    }
}
