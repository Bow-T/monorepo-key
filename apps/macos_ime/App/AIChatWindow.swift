// AIChatWindow.swift
// ------------------
// CỬA SỔ TRÒ CHUYỆN với Trợ lý AI — pixel-art (khớp AIResultWindow), NHIỀU LƯỢT
// hỏi–đáp và LƯU LỊCH SỬ nhiều cuộc (giống ChatGPT).
//
// Bố cục:
//   ┌──────────────┬───────────────────────────────┐
//   │ DANH SÁCH    │ HEADER (tiêu đề cuộc)          │
//   │ cuộc (mới    ├───────────────────────────────┤
//   │  → cũ),      │ LƯỢT hỏi/đáp (cuộn)            │
//   │ + Cuộc mới   │                                │
//   │ + Xoá hết    ├───────────────────────────────┤
//   │              │ Ô NHẬP + nút Gửi              │
//   └──────────────┴───────────────────────────────┘
//
// LUỒNG: gõ → Gửi → thêm lượt .user → gọi AIChatService → thêm lượt .assistant.
// Mỗi lần đổi, lưu cuộc xuống ChatHistoryStore (ai_chats.json).
//
// KHÁC AIResultWindow: cửa sổ này CẦN focus bàn phím (gõ được) nên là panel bình
// thường, activate app; và co giãn được để chat thoải mái.

import SwiftUI
import AppKit
import VietEngine

// MARK: - Model trạng thái (ObservableObject dùng chung để service cập nhật)

@MainActor
final class AIChatModel: ObservableObject {
    /// Danh sách cuộc (mirror ChatHistoryStore, mới nhất lên đầu).
    @Published var threads: [ChatThread]
    /// Cuộc đang mở.
    @Published var current: ChatThread
    /// Đang chờ AI trả lời (khoá ô nhập + hiện "đang trả lời…").
    @Published var isSending = false
    /// Thông báo lỗi lần gọi gần nhất (nil = không lỗi).
    @Published var errorText: String?

    init(threads: [ChatThread], current: ChatThread) {
        self.threads = threads
        self.current = current
    }
}

// MARK: - Window

final class AIChatWindow: NSPanel {
    static var shared: AIChatWindow?
    private static var model: AIChatModel?

    /// Mở cửa sổ chat. `seed` (tuỳ chọn) = đoạn văn bản bôi đen để bắt đầu cuộc mới
    /// với câu hỏi mở đầu; nil = mở cuộc mới trống (hoặc dùng lại cửa sổ đang mở).
    @MainActor
    static func present(seedMessages: [ChatMessage] = []) {
        let store = ChatHistoryStore.shared

        // Đã mở sẵn: chỉ đưa lên trước (giữ nguyên cuộc đang chat).
        if let existing = shared, let m = model, seedMessages.isEmpty {
            m.threads = store.threads
            existing.showWindow()
            return
        }

        // Bắt đầu cuộc mới (rỗng, hoặc seed từ đoạn bôi đen).
        var thread = store.createThread()
        thread.messages = seedMessages
        // Lưu seed vào store NGAY: câu trả lời được ghép vào bản trong store, nếu
        // store còn giữ cuộc rỗng thì câu hỏi + trả lời gốc biến mất.
        if !seedMessages.isEmpty {
            store.upsert(thread)
            thread = store.thread(id: thread.id) ?? thread   // lấy bản đã có tiêu đề
        }
        let m = AIChatModel(threads: store.threads, current: thread)
        model = m
        // Chỉ tự gửi khi lượt cuối là câu người dùng. Seed từ "Hỏi tiếp" kết thúc
        // bằng câu trả lời AI -> chờ người dùng hỏi, không bắn thêm request.
        let shouldReply = seedMessages.last?.role == .user

        if let existing = shared {
            existing.model = m
            existing.rebuildContent()
            existing.showWindow()
            if shouldReply { AIChatService.reply(model: m) }
            return
        }

        let window = AIChatWindow(model: m)
        shared = window
        window.showWindow()
        if shouldReply { AIChatService.reply(model: m) }
    }

    /// Truy cập model đang mở (service dùng để cập nhật khi mạng trả về).
    static var activeModel: AIChatModel? { model }

    private var model: AIChatModel

    /// Kích thước cố định (khối pixel vuông, không dùng titlebar/resize native để
    /// giữ đồng bộ phong cách với các dialog pixel khác — SymbolPicker/ClipboardHistory).
    static let winSize = NSSize(width: 760, height: 560)

    init(model: AIChatModel) {
        self.model = model
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.winSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.isMovableByWindowBackground = true
        self.isFloatingPanel = true
        self.level = .floating
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        rebuildContent()
    }

    fileprivate func rebuildContent() {
        self.contentView = NSHostingView(rootView: AIChatView(
            model: model,
            onClose: { AIChatWindow.shared?.dismiss() }
        ))
    }

    func dismiss() {
        orderOut(nil)
        if AIChatWindow.shared === self {
            AIChatWindow.shared = nil
            AIChatWindow.model = nil
        }
        NSApp.hide(nil)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func showWindow() {
        if let screen = NSScreen.main?.visibleFrame {
            let size = frame.size
            let origin = NSPoint(
                x: screen.midX - size.width / 2,
                y: screen.midY - size.height / 2
            )
            setFrameOrigin(origin)
        }
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - View

struct AIChatView: View {
    @ObservedObject var model: AIChatModel
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var draft = ""
    @State private var confirmClearAll = false
    @FocusState private var inputFocused: Bool

    private var t: Pixel.Tokens { Pixel.tokens(for: colorScheme) }

    var body: some View {
        PixelPanel(fill: t.panel, border: t.outline, shadow: t.shadow) {
            VStack(spacing: 0) {
                header
                Rectangle().fill(t.outline).frame(height: Pixel.borderThin)
                HStack(spacing: 0) {
                    sidebar
                    Rectangle().fill(t.outline).frame(width: Pixel.borderThin)
                    conversation
                }
            }
        }
        .frame(width: AIChatWindow.winSize.width, height: AIChatWindow.winSize.height)
        .overlay(PixelScanlines(color: t.scanline))
        .onExitCommand { onClose() }
        .onAppear { inputFocused = true }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            PixelWindowDots(outline: t.outline, onClose: onClose)
            Spacer()
            Text("TRÒ CHUYỆN VỚI AI")
                .font(.pixelHead(9))
                .foregroundColor(t.textSecondary)
            Spacer()
            Color.clear.frame(width: 47, height: 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: Sidebar — danh sách cuộc

    private var sidebar: some View {
        VStack(spacing: 0) {
            Button(action: newChat) {
                Text("+ CUỘC MỚI")
                    .font(.pixelHead(8))
                    .foregroundColor(t.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Pixel.grass.opacity(0.35))
                    .overlay(Rectangle().strokeBorder(t.outline, lineWidth: Pixel.borderThin))
            }
            .buttonStyle(.plain)
            .padding(10)

            Rectangle().fill(t.outline).frame(height: Pixel.borderThin)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(model.threads) { thread in
                        threadRow(thread)
                    }
                }
                .padding(8)
            }

            Rectangle().fill(t.outline).frame(height: Pixel.borderThin)

            // Xoá hết lịch sử (2 nhịp xác nhận).
            Button(action: clearAllTapped) {
                Text(confirmClearAll ? "XÁC NHẬN XOÁ HẾT?" : "XOÁ HẾT LỊCH SỬ")
                    .font(.pixelHead(7))
                    .foregroundColor(confirmClearAll ? .white : t.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(confirmClearAll ? Pixel.red : Color.clear)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 200)
    }

    private func threadRow(_ thread: ChatThread) -> some View {
        let isCurrent = thread.id == model.current.id
        return HStack(spacing: 4) {
            Button(action: { openThread(thread) }) {
                Text(thread.title.isEmpty ? "Cuộc trò chuyện mới" : thread.title)
                    .font(.pixelBody(15))
                    .foregroundColor(isCurrent ? t.textPrimary : t.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button(action: { deleteThread(thread) }) {
                Text("✕")
                    .font(.pixelBody(14))
                    .foregroundColor(t.textMuted)
            }
            .buttonStyle(.plain)
            .help("Xoá cuộc này")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isCurrent ? t.inset : Color.clear)
        .overlay(
            Rectangle().strokeBorder(
                isCurrent ? t.outline : Color.clear, lineWidth: Pixel.borderThin
            )
        )
    }

    // MARK: Conversation — lượt hỏi/đáp + ô nhập

    private var conversation: some View {
        VStack(spacing: 0) {
            messageList
            Rectangle().fill(t.outline).frame(height: Pixel.borderThin)
            inputBar
        }
        .frame(maxWidth: .infinity)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if model.current.messages.isEmpty && !model.isSending {
                        emptyState
                    }
                    ForEach(model.current.messages) { msg in
                        messageBubble(msg).id(msg.id)
                    }
                    if model.isSending {
                        sendingRow.id("sending")
                    }
                    if let err = model.errorText {
                        errorRow(err).id("error")
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: model.current.messages.count) { scrollToEnd(proxy) }
            .onChange(of: model.isSending) { scrollToEnd(proxy) }
            .onChange(of: model.current.id) { scrollToEnd(proxy) }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(.none) {
            if model.isSending {
                proxy.scrollTo("sending", anchor: .bottom)
            } else if model.errorText != nil {
                proxy.scrollTo("error", anchor: .bottom)
            } else if let last = model.current.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("Bắt đầu trò chuyện")
                .font(.pixelHead(9))
                .foregroundColor(t.textSecondary)
            Text("Gõ câu hỏi bên dưới rồi nhấn Gửi (hoặc Enter).")
                .font(.pixelBody(16))
                .foregroundColor(t.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private func messageBubble(_ msg: ChatMessage) -> some View {
        let isUser = msg.role == .user
        return HStack {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 4) {
                Text(isUser ? "BẠN" : "AI")
                    .font(.pixelHead(7))
                    .foregroundColor(t.textMuted)
                SelectableText(
                    text: msg.text,
                    fontName: Pixel.body,
                    fontSize: 17,
                    color: NSColor(t.textPrimary)
                )
                .frame(minHeight: bubbleHeight(msg.text), alignment: .topLeading)
            }
            .padding(10)
            .background(isUser ? Pixel.grass.opacity(0.25) : t.inset)
            .overlay(Rectangle().strokeBorder(t.outline, lineWidth: Pixel.borderThin))
            .frame(maxWidth: 460, alignment: .leading)
            if !isUser { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    /// Ước lượng chiều cao ô text theo độ dài (SelectableText cuộn được nhưng ta
    /// muốn bong bóng cao vừa đủ, không cuộn nội bộ với đoạn ngắn).
    private func bubbleHeight(_ text: String) -> CGFloat {
        let lines = text.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
        let approxWrapped = max(1, (text.count / 52) + lines)
        return min(CGFloat(approxWrapped) * 22 + 4, 320)
    }

    private var sendingRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("AI ĐANG TRẢ LỜI…")
                .font(.pixelHead(7))
                .foregroundColor(t.textMuted)
        }
        .padding(.vertical, 4)
    }

    private func errorRow(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("⚠︎").foregroundColor(Pixel.red)
            Text(msg)
                .font(.pixelBody(16))
                .foregroundColor(t.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Pixel.red.opacity(0.12))
        .overlay(Rectangle().strokeBorder(Pixel.red, lineWidth: Pixel.borderThin))
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ChatInputField(
                text: $draft,
                placeholder: "Nhập câu hỏi… (Enter để gửi, ⇧Enter xuống dòng)",
                fontName: Pixel.body,
                fontSize: 18,
                textColor: NSColor(t.textPrimary),
                placeholderColor: NSColor(t.textMuted),
                onSubmit: send
            )
            .frame(minHeight: 40, maxHeight: 96)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(t.inset)
            .overlay(Rectangle().strokeBorder(t.outline, lineWidth: Pixel.borderThin))
            .focused($inputFocused)

            Button(action: send) {
                Text("GỬI")
                    .font(.pixelHead(8))
                    .foregroundColor(t.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(canSend ? Pixel.grass.opacity(0.4) : t.inset)
                    .overlay(Rectangle().strokeBorder(t.outline, lineWidth: Pixel.borderThin))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(12)
    }

    private var canSend: Bool {
        !model.isSending &&
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Hành động

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !model.isSending else { return }
        draft = ""
        model.errorText = nil
        model.current.messages.append(ChatMessage(role: .user, text: text))
        ChatHistoryStore.shared.upsert(model.current)
        model.threads = ChatHistoryStore.shared.threads
        AIChatService.reply(model: model)
        inputFocused = true
    }

    private func newChat() {
        confirmClearAll = false
        let thread = ChatHistoryStore.shared.createThread()
        model.current = thread
        model.threads = ChatHistoryStore.shared.threads
        model.errorText = nil
        draft = ""
        inputFocused = true
    }

    private func openThread(_ thread: ChatThread) {
        confirmClearAll = false
        // Lấy bản mới nhất từ store (phòng khi vừa đổi).
        model.current = ChatHistoryStore.shared.thread(id: thread.id) ?? thread
        model.errorText = nil
        inputFocused = true
    }

    private func deleteThread(_ thread: ChatThread) {
        ChatHistoryStore.shared.delete(id: thread.id)
        model.threads = ChatHistoryStore.shared.threads
        if model.current.id == thread.id {
            // Đang mở cuộc bị xoá -> chuyển sang cuộc đầu hoặc tạo mới.
            if let first = model.threads.first {
                model.current = first
            } else {
                model.current = ChatHistoryStore.shared.createThread()
                model.threads = ChatHistoryStore.shared.threads
            }
        }
    }

    private func clearAllTapped() {
        if confirmClearAll {
            ChatHistoryStore.shared.deleteAll()
            model.current = ChatHistoryStore.shared.createThread()
            model.threads = ChatHistoryStore.shared.threads
            model.errorText = nil
            confirmClearAll = false
        } else {
            confirmClearAll = true
        }
    }
}

// MARK: - Ô nhập nhiều dòng (NSTextView) — Enter gửi, ⇧Enter xuống dòng

/// Ô nhập text nhiều dòng bọc NSTextView để: (1) gõ tiếng Việt mượt, (2) Enter =
/// gửi còn ⇧Enter = xuống dòng (TextField SwiftUI không tách được hai phím này).
struct ChatInputField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let fontName: String
    let fontSize: CGFloat
    let textColor: NSColor
    var placeholderColor: NSColor = .secondaryLabelColor
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let tv = SubmitTextView()
        tv.onSubmit = onSubmit
        tv.delegate = context.coordinator
        tv.isEditable = true
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 2, height: 2)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.lineFragmentPadding = 0
        tv.font = NSFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
        tv.textColor = textColor
        tv.insertionPointColor = textColor       // con trỏ khớp màu chữ pixel
        tv.placeholder = placeholder
        tv.placeholderColor = placeholderColor

        scroll.documentView = tv
        context.coordinator.textView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? SubmitTextView else { return }
        let font = NSFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
        if tv.string != text {
            tv.string = text
        }
        tv.font = font
        tv.textColor = textColor
        tv.insertionPointColor = textColor
        tv.placeholder = placeholder
        tv.placeholderColor = placeholderColor
        tv.onSubmit = onSubmit
        tv.needsDisplay = true
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChatInputField
        weak var textView: NSTextView?
        init(_ parent: ChatInputField) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }
    }
}

/// NSTextView bắt Enter (không Shift) = gửi; ⇧Enter/⌥Enter = xuống dòng bình thường.
/// Vẽ PLACEHOLDER pixel (mờ) khi rỗng — NSTextView không có placeholder sẵn.
final class SubmitTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var placeholder: String = ""
    var placeholderColor: NSColor = .secondaryLabelColor

    override func keyDown(with event: NSEvent) {
        // keyCode 36 = Return, 76 = Enter (numpad). Không kèm Shift -> gửi.
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        let hasShift = event.modifierFlags.contains(.shift)
        if isReturn && !hasShift {
            onSubmit?()
            return
        }
        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 18),
            .foregroundColor: placeholderColor,
        ]
        let inset = textContainerInset
        let pad = textContainer?.lineFragmentPadding ?? 0
        placeholder.draw(
            at: NSPoint(x: inset.width + pad, y: inset.height),
            withAttributes: attrs
        )
    }
}
