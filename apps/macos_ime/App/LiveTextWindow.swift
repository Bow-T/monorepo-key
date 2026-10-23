// LiveTextWindow.swift
// --------------------
// Cửa sổ "copy chữ trong ảnh" kiểu Preview/Quick Look của macOS (Live Text):
// hiển thị ảnh, TRỎ CHUỘT vào chữ để bôi đen đúng đoạn cần rồi ⌘C — thay vì
// copy toàn bộ chữ một cục. Dùng VisionKit:
//   - ImageAnalyzer: phân tích ảnh, nhận diện vùng chữ (offline, có tiếng Việt).
//   - ImageAnalysisOverlayView: lớp phủ cho phép bôi đen/copy như Preview.
//
// Dùng ở 2 chỗ: nút COPY TEXT trên overlay chụp màn hình, và nút OCR trên các
// mục ảnh trong cửa sổ lịch sử Clipboard. Khung cửa sổ theo phong cách pixel
// (dùng chung design tokens `Pixel` với ClipboardHistoryWindow).

import AppKit
import SwiftUI
import VisionKit

@MainActor
final class LiveTextWindow: NSPanel {

    static var shared: LiveTextWindow?

    private let overlay = ImageAnalysisOverlayView()
    private var onDismiss: (() -> Void)?

    /// Phân tích ảnh rồi mở cửa sổ bôi-đen-chữ. Ảnh không có chữ -> chỉ toast.
    /// `onDismiss` chạy khi cửa sổ đóng (để trả focus về app trước đó).
    static func present(image: NSImage, onDismiss: (() -> Void)? = nil) {
        Task { @MainActor in
            guard ImageAnalyzer.isSupported else {
                ToastHUD.show("MÁY KHÔNG HỖ TRỢ NHẬN DẠNG CHỮ")
                onDismiss?()
                return
            }
            do {
                let analyzer = ImageAnalyzer()
                let analysis = try await analyzer.analyze(
                    image, orientation: .up,
                    configuration: ImageAnalyzer.Configuration([.text])
                )
                guard !analysis.transcript.isEmpty else {
                    ToastHUD.show("KHÔNG THẤY CHỮ TRONG ẢNH")
                    onDismiss?()
                    return
                }
                show(image: image, analysis: analysis, onDismiss: onDismiss)
            } catch {
                bowLog("[LiveText] Phân tích ảnh thất bại: \(error)")
                ToastHUD.show("KHÔNG NHẬN DẠNG ĐƯỢC CHỮ")
                onDismiss?()
            }
        }
    }

    private static func show(image: NSImage, analysis: ImageAnalysis,
                             onDismiss: (() -> Void)?) {
        shared?.dismiss()

        // Cỡ vùng ảnh: theo điểm của ảnh, kẹp trong ~80% màn hình chứa chuột.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let maxW = visible.width * 0.8
        let maxH = visible.height * 0.8 - 90  // chừa header + footer
        let ratio = min(1, maxW / max(image.size.width, 1), maxH / max(image.size.height, 1))
        let imageSize = NSSize(
            width: max(380, image.size.width * ratio),
            height: max(140, image.size.height * ratio)
        )

        let window = LiveTextWindow(image: image, analysis: analysis,
                                    imageSize: imageSize, onDismiss: onDismiss)
        shared = window

        // Giữa màn hình chứa chuột.
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        ))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init(image: NSImage, analysis: ImageAnalysis,
                 imageSize: NSSize, onDismiss: (() -> Void)?) {
        super.init(
            contentRect: NSRect(origin: .zero, size: imageSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.onDismiss = onDismiss

        overlay.preferredInteractionTypes = [.textSelection]
        overlay.analysis = analysis

        let host = NSHostingView(rootView: LiveTextPanelView(
            image: image,
            imageSize: imageSize,
            overlay: overlay,
            onCopyAll: { [weak self] in self?.copyText(analysis.transcript) },
            onClose: { [weak self] in self?.dismiss() }
        ))
        host.frame.size = host.fittingSize
        setContentSize(host.fittingSize)
        contentView = host

        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        becomesKeyOnlyIfNeeded = false

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleResignKey),
            name: NSWindow.didResignKeyNotification,
            object: self
        )
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    @objc private func handleResignKey() {
        dismiss()
    }

    func dismiss() {
        orderOut(nil)
        if Self.shared === self { Self.shared = nil }
        let callback = onDismiss
        onDismiss = nil
        callback?()
    }

    // Esc đóng cửa sổ (ImageAnalysisOverlayView không xử lý phím này).
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {  // Esc
            dismiss()
            return
        }
        super.keyDown(with: event)
    }

    // ⌘C: copy phần chữ ĐANG BÔI ĐEN. App không có menu Edit nên phải tự bắt
    // key equivalent ở cửa sổ (chuột phải > Copy của overlay vẫn hoạt động).
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "c" {
            if overlay.hasActiveTextSelection, !overlay.selectedText.isEmpty {
                copyText(overlay.selectedText, close: false)
            } else {
                ToastHUD.show("TRỎ VÀO CHỮ VÀ BÔI ĐEN TRƯỚC ĐÃ")
            }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private func copyText(_ text: String, close: Bool = true) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        ToastHUD.show("ĐÃ COPY TEXT")
        if close { dismiss() }
    }
}

// MARK: - SwiftUI khung cửa sổ

private struct LiveTextPanelView: View {
    let image: NSImage
    let imageSize: NSSize
    let overlay: ImageAnalysisOverlayView
    let onCopyAll: () -> Void
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var t: Pixel.Tokens { Pixel.tokens(for: colorScheme) }

    var body: some View {
        PixelPanel(fill: t.panel, border: t.outline, shadow: t.shadow) {
            VStack(spacing: 0) {
                header
                Rectangle().fill(t.outline).frame(height: Pixel.borderThin)
                LiveTextImageView(image: image, overlay: overlay)
                    .frame(width: imageSize.width, height: imageSize.height)
                Rectangle().fill(t.outline).frame(height: Pixel.borderThin)
                footer
            }
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            PixelWindowDots(outline: t.outline, onClose: onClose)

            Image(systemName: "text.viewfinder")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 18, height: 18)
                .background(Pixel.leaf)
                .overlay(Rectangle().strokeBorder(t.outline, lineWidth: 2))

            Text("COPY CHỮ TRONG ẢNH")
                .font(.pixelHead(8))
                .foregroundColor(t.textPrimary)
                .lineLimit(1)

            Spacer()

            Button(action: onCopyAll) {
                Text("COPY HẾT")
                    .font(.pixelHead(7))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Pixel.grass)
                    .overlay(Rectangle().strokeBorder(t.outline, lineWidth: 2))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        Text("TRỎ VÀO CHỮ ĐỂ BÔI ĐEN • ⌘C COPY • ESC ĐÓNG")
            .font(.pixelHead(7))
            .foregroundColor(t.textMuted)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
    }
}

/// NSImageView + ImageAnalysisOverlayView: overlay tự bám theo vị trí ảnh
/// (kể cả khi ảnh bị letterbox) nhờ `trackingImageView`.
private struct LiveTextImageView: NSViewRepresentable {
    let image: NSImage
    let overlay: ImageAnalysisOverlayView

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown

        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.trackingImageView = imageView
        imageView.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: imageView.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
        ])
        return imageView
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {}
}
