// AIKeyPromptWindow.swift
// -----------------------
// HỘP THOẠI NHẬP LIỆU kiểu PIXEL-ART (khớp AIResultWindow / SymbolPicker) — thay
// cho NSAlert mặc định vốn lạc phong cách. Dùng cho hai việc của Trợ lý AI:
//   • Nhập API key (ô che chữ, secure) — lưu Keychain qua callback.
//   • Hỏi tự do (ô text thường) — nhập câu hỏi về đoạn đã chọn.
// Nút Lưu/Huỷ (hoặc Gửi/Huỷ). Enter = xác nhận, Esc = huỷ.

import SwiftUI
import AppKit
import VietEngine

// MARK: - Cấu hình hộp thoại

struct AIPromptConfig {
    var title: String            // tiêu đề trên header
    var message: String          // dòng mô tả chính
    var note: String?            // dòng nhắc phụ (nhỏ, mờ) — vd cảnh báo riêng tư
    var placeholder: String      // gợi ý trong ô nhập
    var initialText: String      // giá trị ban đầu (key đã lưu / rỗng)
    var secure: Bool             // true = ô che chữ (key)
    var confirmLabel: String     // nhãn nút xác nhận ("LƯU" / "GỬI")
}

// MARK: - Window

final class AIKeyPromptWindow: NSPanel {
    static var shared: AIKeyPromptWindow?

    /// Mở hộp thoại nhập API key cho một hãng.
    @MainActor
    static func presentKey(provider: AIProvider, existingKey: String,
                           onSave: @escaping (String) -> Void) {
        present(config: AIPromptConfig(
            title: "API KEY \(provider == .claude ? "CLAUDE" : "CHATGPT")",
            message: "Dán API key của bạn. Key lưu an toàn trong Keychain của máy — KHÔNG ghi vào file cài đặt. Để trống rồi Lưu để xoá.",
            note: "Lưu ý: văn bản bạn chọn sẽ được gửi tới máy chủ \(provider.title) khi dùng Trợ lý AI.",
            placeholder: provider == .claude ? "sk-ant-…" : "sk-…",
            initialText: existingKey,
            secure: true,
            confirmLabel: "LƯU"
        ), onConfirm: onSave)
    }

    /// Mở hộp thoại "Hỏi tự do" (ô text thường). `onConfirm` nhận chuỗi đã trim;
    /// KHÔNG gọi nếu người dùng huỷ.
    @MainActor
    static func presentAsk(onConfirm: @escaping (String) -> Void) {
        present(config: AIPromptConfig(
            title: "HỎI AI VỀ ĐOẠN ĐÃ CHỌN",
            message: "Nhập yêu cầu của bạn — ví dụ: dịch, giải thích thuật ngữ này, trả lời câu hỏi trong đoạn…",
            note: nil,
            placeholder: "Yêu cầu của bạn…",
            initialText: "",
            secure: false,
            confirmLabel: "GỬI"
        ), onConfirm: onConfirm)
    }

    /// Lõi dùng chung. Đóng cửa sổ trước khi gọi `onConfirm`.
    @MainActor
    private static func present(config: AIPromptConfig, onConfirm: @escaping (String) -> Void) {
        shared?.dismiss()
        let window = AIKeyPromptWindow(config: config, onConfirm: onConfirm)
        shared = window
        window.showWindow()
    }

    private init(config: AIPromptConfig, onConfirm: @escaping (String) -> Void) {
        let content = NSHostingView(rootView: AIKeyPromptView(
            config: config,
            onConfirm: { text in
                AIKeyPromptWindow.shared?.dismiss()
                onConfirm(text)
            },
            onCancel: { AIKeyPromptWindow.shared?.dismiss() }
        ))

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 300),
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
    }

    func dismiss() {
        orderOut(nil)
        if AIKeyPromptWindow.shared === self { AIKeyPromptWindow.shared = nil }
        NSApp.hide(nil)
    }

    // Cần key để ô nhập nhận được phím gõ.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private func showWindow() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let w: CGFloat = 440, h: CGFloat = 300
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

struct AIKeyPromptView: View {
    let config: AIPromptConfig
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var text: String
    @FocusState private var focused: Bool

    init(config: AIPromptConfig, onConfirm: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.config = config
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _text = State(initialValue: config.initialText)
    }

    private var t: Pixel.Tokens { Pixel.tokens(for: colorScheme) }

    private func confirm() {
        onConfirm(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var body: some View {
        PixelPanel(fill: t.panel, border: t.outline, shadow: t.shadow) {
            VStack(spacing: 0) {
                header
                Rectangle().fill(t.outline).frame(height: Pixel.borderThin)
                content
            }
        }
        .frame(width: 440, height: 300)
        .overlay(PixelScanlines(color: t.scanline))
        .onExitCommand { onCancel() }   // Esc
    }

    private var header: some View {
        HStack(spacing: 8) {
            PixelWindowDots(outline: t.outline, onClose: onCancel)
            Spacer()
            Text(config.title)
                .font(.pixelHead(9))
                .foregroundColor(t.textSecondary)
            Spacer()
            Color.clear.frame(width: 47, height: 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(config.message)
                .font(.pixelBody(16))
                .foregroundColor(t.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            inputField

            if let note = config.note {
                Text(note)
                    .font(.pixelBody(15))
                    .foregroundColor(t.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Spacer()
                pixelButton("HUỶ", fill: t.inset) { onCancel() }
                pixelButton(config.confirmLabel, fill: Pixel.grass.opacity(0.35)) { confirm() }
            }
        }
        .padding(16)
        .onAppear { focused = true }
    }

    /// Ô nhập: che chữ (key) hoặc text thường (hỏi tự do), khung pixel.
    @ViewBuilder
    private var inputField: some View {
        Group {
            if config.secure {
                SecureField(config.placeholder, text: $text)
            } else {
                TextField(config.placeholder, text: $text)
            }
        }
        .textFieldStyle(.plain)
        .font(.pixelBody(18))
        .foregroundColor(t.textPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(t.inset)
        .overlay(Rectangle().strokeBorder(t.outline, lineWidth: Pixel.borderThin))
        .focused($focused)
        .onSubmit { confirm() }
    }

    private func pixelButton(_ label: String, fill: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.pixelHead(8))
                .foregroundColor(t.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(fill)
                .overlay(Rectangle().strokeBorder(t.outline, lineWidth: Pixel.borderThin))
        }
        .buttonStyle(.plain)
    }
}
