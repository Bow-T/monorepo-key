// AIResultWindow.swift
// --------------------
// POPUP KẾT QUẢ TRỢ LÝ AI — cửa sổ pixel-art (theo SymbolPickerWindow) hiện tại
// con trỏ. Ba trạng thái: ĐANG HỎI (spinner) → KẾT QUẢ (text + nút Copy) hoặc
// LỖI. KHÔNG ghi đè văn bản gốc — chỉ hiển thị để người dùng đọc/copy.
//
// Vì kết quả tới BẤT ĐỒNG BỘ (sau mạng), ta giữ một model `ObservableObject`
// dùng chung: mở popup ở trạng thái loading, rồi service gọi update(result:)/
// update(error:) để đổi nội dung ngay trong cửa sổ đang mở.

import SwiftUI
import AppKit
import VietEngine

// MARK: - Model trạng thái (cập nhật bất đồng bộ)

@MainActor
final class AIResultModel: ObservableObject {
    enum State {
        case loading
        case result(String)
        case failed(String)
    }
    @Published var title: String
    @Published var state: State
    /// Câu hỏi người dùng đã gửi cho thao tác này (để "Hỏi tiếp" mở chat có ngữ cảnh).
    @Published var sourceUserMessage: String

    init(title: String, state: State, sourceUserMessage: String = "") {
        self.title = title
        self.state = state
        self.sourceUserMessage = sourceUserMessage
    }
}

// MARK: - Window

final class AIResultWindow: NSPanel {
    static var shared: AIResultWindow?
    /// Model dùng chung để service cập nhật kết quả sau khi mạng trả về.
    private static var model: AIResultModel?

    /// Mở popup. `loading` = true -> hiện spinner "đang hỏi". Nếu đã có cửa sổ,
    /// dùng lại (đổi tiêu đề + về trạng thái loading).
    @MainActor
    static func present(title: String, loading: Bool, sourceUserMessage: String = "") {
        if let existing = shared, let m = model {
            m.title = title
            m.sourceUserMessage = sourceUserMessage
            m.state = loading ? .loading : m.state
            existing.showWindow()
            return
        }
        let m = AIResultModel(
            title: title,
            state: loading ? .loading : .result(""),
            sourceUserMessage: sourceUserMessage
        )
        model = m
        let window = AIResultWindow(model: m)
        shared = window
        window.showWindow()
    }

    /// Cập nhật popup với kết quả (gọi từ service khi mạng trả về thành công).
    @MainActor
    static func update(result: String) {
        model?.state = .result(result)
    }

    /// Cập nhật popup với thông báo lỗi.
    @MainActor
    static func update(error: String) {
        model?.state = .failed(error)
    }

    init(model: AIResultModel) {
        let content = NSHostingView(rootView: AIResultView(
            model: model,
            onClose: { AIResultWindow.shared?.close(restoreFocus: true) },
            onContinue: { seed in
                // Đóng popup kết quả, mở cửa sổ chat với ngữ cảnh câu hỏi + trả lời.
                AIResultWindow.shared?.close(restoreFocus: false)
                AIChatWindow.present(seedMessages: seed)
            }
        ))

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.contentView = content
        self.isFloatingPanel = true
        self.level = .floating
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.becomesKeyOnlyIfNeeded = false

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleResignKey),
            name: NSWindow.didResignKeyNotification, object: self
        )
    }

    @objc private func handleResignKey() {
        // Click ra ngoài -> đóng (giữ lại kết quả để lần sau mở nhanh không cần).
        close(restoreFocus: true)
    }

    func close(restoreFocus: Bool) {
        NotificationCenter.default.removeObserver(self)
        orderOut(nil)
        if AIResultWindow.shared === self {
            AIResultWindow.shared = nil
            AIResultWindow.model = nil
        }
        if restoreFocus { NSApp.hide(nil) }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func showWindow() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let w: CGFloat = 420, h: CGFloat = 360
        if let f = screen?.visibleFrame {
            var origin = NSPoint(x: mouse.x - w / 2, y: mouse.y - h / 2)
            if origin.x < f.minX { origin.x = f.minX }
            if origin.x + w > f.maxX { origin.x = f.maxX - w }
            if origin.y < f.minY { origin.y = f.minY }
            if origin.y + h > f.maxY { origin.y = f.maxY - h }
            setFrameOrigin(origin)
        }
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - View

struct AIResultView: View {
    @ObservedObject var model: AIResultModel
    let onClose: () -> Void
    /// Mở chat nối tiếp: nhận các lượt (câu hỏi + trả lời) làm ngữ cảnh cuộc mới.
    let onContinue: ([ChatMessage]) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var copied = false

    private var t: Pixel.Tokens { Pixel.tokens(for: colorScheme) }

    var body: some View {
        PixelPanel(fill: t.panel, border: t.outline, shadow: t.shadow) {
            VStack(spacing: 0) {
                header
                Rectangle().fill(t.outline).frame(height: Pixel.borderThin)
                bodyContent
                Rectangle().fill(t.outline).frame(height: Pixel.borderThin)
                footer
            }
        }
        .frame(width: 420, height: 360)
        .overlay(PixelScanlines(color: t.scanline))
        .onKeyPress(.escape) { onClose(); return .handled }
    }

    private var header: some View {
        HStack(spacing: 8) {
            PixelWindowDots(outline: t.outline, onClose: onClose)
            Spacer()
            Text("TRỢ LÝ AI")
                .font(.pixelHead(9))
                .foregroundColor(t.textSecondary)
            Spacer()
            Color.clear.frame(width: 47, height: 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var bodyContent: some View {
        switch model.state {
        case .loading:
            VStack(spacing: 12) {
                Spacer()
                ProgressView()
                    .controlSize(.large)
                Text("ĐANG HỎI \(model.title.uppercased())…")
                    .font(.pixelHead(8))
                    .foregroundColor(t.textMuted)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(16)

        case .result(let text):
            // NSTextView read-only, selectable -> bôi đen + ⌘C chắc chắn hoạt động
            // ở mọi trường hợp (SwiftUI .textSelection trong NSPanel borderless đôi
            // khi không kích hoạt drag-to-select).
            SelectableText(
                text: text,
                fontName: Pixel.body,
                fontSize: 18,
                color: NSColor(t.textPrimary)
            )
            .padding(14)

        case .failed(let msg):
            ScrollView {
                VStack(spacing: 10) {
                    Text("⚠︎")
                        .font(.system(size: 28))
                        .foregroundColor(Pixel.red)
                    Text(msg)
                        .font(.pixelBody(18))
                        .foregroundColor(t.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(16)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 10) {
            // Nhãn nhắc riêng tư: chữ đã gửi ra API bên ngoài.
            Text("Gửi qua API bên ngoài")
                .font(.pixelBody(15))
                .foregroundColor(t.textMuted)
            Spacer()
            if case .result(let text) = model.state, !text.isEmpty {
                Button(action: { continueChat(result: text) }) {
                    Text("HỎI TIẾP →")
                        .font(.pixelHead(8))
                        .foregroundColor(t.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(t.inset)
                        .overlay(Rectangle().strokeBorder(t.outline, lineWidth: Pixel.borderThin))
                }
                .buttonStyle(.plain)
                .help("Chuyển kết quả này thành cuộc trò chuyện nhiều lượt")

                Button(action: { copy(text) }) {
                    Text(copied ? "✓ ĐÃ COPY" : "COPY")
                        .font(.pixelHead(8))
                        .foregroundColor(t.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(copied ? Pixel.grass.opacity(0.35) : t.inset)
                        .overlay(Rectangle().strokeBorder(t.outline, lineWidth: Pixel.borderThin))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// Dựng ngữ cảnh chat từ câu hỏi gốc + kết quả, rồi mở cửa sổ chat nối tiếp.
    private func continueChat(result: String) {
        var seed: [ChatMessage] = []
        let userMsg = model.sourceUserMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !userMsg.isEmpty {
            seed.append(ChatMessage(role: .user, text: userMsg))
        }
        seed.append(ChatMessage(role: .assistant, text: result))
        onContinue(seed)
    }

    private func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
}

// MARK: - Text chọn được (NSTextView read-only)

/// Bọc NSTextView read-only + selectable để người dùng BÔI ĐEN & ⌘C từng phần nội
/// dung AI (SwiftUI `.textSelection` trong NSPanel borderless đôi khi không kích
/// hoạt drag-to-select). Cuộn dọc, tự xuống dòng theo bề rộng.
struct SelectableText: NSViewRepresentable {
    let text: String
    let fontName: String
    let fontSize: CGFloat
    let color: NSColor

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let tv = NSTextView()
        tv.isEditable = false
        tv.isSelectable = true            // bôi đen được
        tv.drawsBackground = false
        tv.textContainerInset = .zero
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.lineFragmentPadding = 0
        // Cho phép ⌘C (copy) và ⌘A (chọn hết) mặc định của NSTextView.

        scroll.documentView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        let font = NSFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
        if tv.string != text {
            tv.string = text
        }
        // Áp font + màu cho toàn bộ nội dung.
        tv.font = font
        tv.textColor = color
        let full = NSRange(location: 0, length: (tv.string as NSString).length)
        tv.textStorage?.addAttribute(.font, value: font, range: full)
        tv.textStorage?.addAttribute(.foregroundColor, value: color, range: full)
    }
}
