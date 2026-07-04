// PixelAlertWindow.swift
// ----------------------
// HỘP THOẠI THÔNG BÁO / XÁC NHẬN kiểu PIXEL-ART dùng chung — thay cho NSAlert
// mặc định vốn lạc phong cách. Hỗ trợ 1 hoặc 2 nút; mỗi nút có nhãn + kiểu
// (primary tô xanh, destructive tô đỏ, thường tô xám) + callback.
//
// Bất đồng bộ: mở cửa sổ, bấm nút -> đóng rồi gọi callback của nút đó. Dùng cho
// "Sửa lỗi quyền?", "Đã reset quyền", "Cần quyền Ghi màn hình"…

import SwiftUI
import AppKit

// MARK: - Mô tả nút

struct PixelAlertButton {
    enum Kind { case primary, destructive, normal }
    var label: String
    var kind: Kind
    var action: () -> Void

    init(_ label: String, kind: Kind = .normal, action: @escaping () -> Void) {
        self.label = label
        self.kind = kind
        self.action = action
    }
}

// MARK: - Window

final class PixelAlertWindow: NSPanel {
    static var shared: PixelAlertWindow?

    /// Mở hộp thoại. `buttons` xếp từ TRÁI sang PHẢI (nút xác nhận nên để cuối).
    /// Bấm nút -> đóng cửa sổ rồi chạy action. Esc = chạy nút đầu tiên có kiểu
    /// `.normal` (thường là Huỷ); nếu không có thì chỉ đóng.
    @MainActor
    static func present(title: String, message: String, buttons: [PixelAlertButton]) {
        shared?.dismiss()
        let window = PixelAlertWindow(title: title, message: message, buttons: buttons)
        shared = window
        window.showWindow()
    }

    private init(title: String, message: String, buttons: [PixelAlertButton]) {
        // Bọc action mỗi nút để tự đóng cửa sổ trước khi chạy.
        let wrapped = buttons.map { btn in
            PixelAlertButton(btn.label, kind: btn.kind) {
                PixelAlertWindow.shared?.dismiss()
                btn.action()
            }
        }
        let escAction: () -> Void = {
            PixelAlertWindow.shared?.dismiss()
            // Esc chạy nút "thường" đầu tiên (Huỷ/Để sau) nếu có.
            if let cancel = buttons.first(where: { $0.kind == .normal }) {
                cancel.action()
            }
        }

        let content = NSHostingView(rootView: PixelAlertView(
            title: title, message: message, buttons: wrapped, onEscape: escAction
        ))

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
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
        if PixelAlertWindow.shared === self { PixelAlertWindow.shared = nil }
        NSApp.hide(nil)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private func showWindow() {
        // Kích thước co theo nội dung (đo view), tối thiểu 460×200.
        let fitting = (contentView as? NSHostingView<PixelAlertView>)?.fittingSize ?? .zero
        let w: CGFloat = 460
        let h = max(200, min(520, fitting.height))
        setContentSize(NSSize(width: w, height: h))

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
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

struct PixelAlertView: View {
    let title: String
    let message: String
    let buttons: [PixelAlertButton]
    let onEscape: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var t: Pixel.Tokens { Pixel.tokens(for: colorScheme) }

    var body: some View {
        PixelPanel(fill: t.panel, border: t.outline, shadow: t.shadow) {
            VStack(spacing: 0) {
                header
                Rectangle().fill(t.outline).frame(height: Pixel.borderThin)
                content
            }
        }
        .frame(width: 460)
        .overlay(PixelScanlines(color: t.scanline))
        .onExitCommand { onEscape() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            PixelWindowDots(outline: t.outline, onClose: onEscape)
            Spacer()
            Text(title.uppercased())
                .font(.pixelHead(9))
                .foregroundColor(t.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer()
            Color.clear.frame(width: 47, height: 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(message)
                .font(.pixelBody(17))
                .foregroundColor(t.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Spacer()
                ForEach(Array(buttons.enumerated()), id: \.offset) { _, btn in
                    button(btn)
                }
            }
        }
        .padding(16)
    }

    private func button(_ btn: PixelAlertButton) -> some View {
        let fill: Color = switch btn.kind {
        case .primary:     Pixel.grass.opacity(0.35)
        case .destructive: Pixel.red.opacity(0.30)
        case .normal:      t.inset
        }
        return Button(action: btn.action) {
            Text(btn.label)
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
