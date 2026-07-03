// StickerPickerWindow.swift
// -------------------------
// BẢNG DÁN STICKER (emoji ẢNH). Bật bằng phím tắt (mặc định ⌃⇧J) hoặc menu bar,
// hiện lưới ảnh emoji pixel-art; chọn một cái -> DÁN ẢNH vào ô đang gõ của app trước.
//
// Khác SymbolPickerWindow (chèn ký tự Unicode text): ở đây item là NSImage, dán qua
// clipboard hình ảnh + ⌘V. Ảnh gốc 256×256 -> thu về ~72px khi dán cho vừa inline.
//
// Tái dùng: hệ design `Pixel`/`PixelPanel`/`PixelScanlines`, dữ liệu `StickerCatalog`
// + nạp ảnh `StickerStore`, cách dán như lịch sử Clipboard. KHÔNG qua event tap.

import SwiftUI
import AppKit
import VietEngine

// MARK: - Window

final class StickerPickerWindow: NSPanel {
    static var shared: StickerPickerWindow?

    init(recentSlugs: [String],
         onPick: @escaping (StickerCatalog.Sticker) -> Void,
         onClose: @escaping () -> Void) {
        let content = NSHostingView(rootView: StickerPickerView(
            stickers: StickerCatalog.all,
            recentSlugs: recentSlugs,
            onPick: onPick,
            onClose: onClose
        ))

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 400),
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
            self,
            selector: #selector(handleResignKey),
            name: NSWindow.didResignKeyNotification,
            object: self
        )
    }

    @objc private func handleResignKey() {
        close(restoreFocus: true)
    }

    func close(restoreFocus: Bool) {
        NotificationCenter.default.removeObserver(self)
        orderOut(nil)
        if StickerPickerWindow.shared === self { StickerPickerWindow.shared = nil }
        if restoreFocus { NSApp.hide(nil) }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func showWindow() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let w: CGFloat = 340, h: CGFloat = 400
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

struct StickerPickerView: View {
    let stickers: [StickerCatalog.Sticker]
    /// Slug các sticker dùng gần đây (mới nhất trước) — hiện thành hàng đầu.
    let recentSlugs: [String]
    let onPick: (StickerCatalog.Sticker) -> Void
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering: String? = nil
    @FocusState private var isFocused: Bool

    private var t: Pixel.Tokens { Pixel.tokens(for: colorScheme) }

    /// Sticker gần đây (đã lọc bỏ slug không còn trong danh mục), giữ thứ tự MRU.
    private var recentStickers: [StickerCatalog.Sticker] {
        recentSlugs.compactMap { slug in stickers.first { $0.slug == slug } }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(58), spacing: 8), count: 4)
    }

    var body: some View {
        PixelPanel(fill: t.panel, border: t.outline, shadow: t.shadow) {
            VStack(spacing: 0) {
                header
                Rectangle().fill(t.outline).frame(height: Pixel.borderThin)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if !recentStickers.isEmpty {
                            sectionLabel("GẦN ĐÂY")
                            LazyVGrid(columns: columns, spacing: 8) {
                                // id dùng slug + "recent" để không đụng key với lưới đầy đủ.
                                ForEach(recentStickers, id: \.slug) { cell($0, keySuffix: "r") }
                            }
                            sectionLabel("TẤT CẢ")
                        }
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(stickers, id: \.slug) { cell($0, keySuffix: "a") }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(width: 340, height: 400)
        .overlay(PixelScanlines(color: t.scanline))
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onKeyPress(.escape) { onClose(); return .handled }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.pixelHead(7))
            .foregroundColor(t.textMuted)
    }

    private var header: some View {
        HStack(spacing: 8) {
            PixelWindowDots(outline: t.outline, onClose: onClose)
            Spacer()
            Text("STICKER")
                .font(.pixelHead(9))
                .foregroundColor(t.textSecondary)
            Spacer()
            Color.clear.frame(width: 47, height: 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// `keySuffix` phân biệt ô ở hàng "gần đây" ("r") với lưới đầy đủ ("a") để
    /// hover không sáng cùng lúc hai ô trùng slug.
    private func cell(_ sticker: StickerCatalog.Sticker, keySuffix: String) -> some View {
        let hoverKey = sticker.slug + keySuffix
        let isHover = hovering == hoverKey
        return Group {
            if let image = StickerStore.image(for: sticker) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(6)
            } else {
                // Thiếu ảnh -> ô trống có dấu ? để lộ vấn đề, không crash.
                Text("?")
                    .font(.pixelHead(10))
                    .foregroundColor(t.textMuted)
            }
        }
        .frame(width: 58, height: 58)
        .background(isHover ? t.inset : Color.clear)
        .overlay(
            Rectangle().strokeBorder(
                isHover ? Pixel.grass : t.outline.opacity(0.2),
                lineWidth: Pixel.borderThin
            )
        )
        .contentShape(Rectangle())
        .help(sticker.label)
        .onHover { hovering = $0 ? hoverKey : nil }
        .onTapGesture { onPick(sticker) }
    }
}
