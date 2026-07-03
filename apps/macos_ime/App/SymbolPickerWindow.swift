// SymbolPickerWindow.swift
// ------------------------
// BẢNG GÕ NHANH ký tự đặc biệt & emoji (picker). Bật bằng phím tắt (mặc định ⌃⇧E),
// hiện overlay pixel-art tại con trỏ; chọn một ô -> chèn thẳng vào ô đang gõ của
// app trước đó rồi đóng.
//
// Tái dùng: hệ design `Pixel` + `PixelPanel`/`PixelScanlines` (ClipboardHistoryWindow),
// dữ liệu `SymbolCatalog` (engine), và cách chèn qua clipboard + ⌘V như lịch sử copy
// (đáng tin ở mọi app). KHÔNG đi qua event tap của bộ gõ.

import SwiftUI
import AppKit
import VietEngine

// MARK: - Window

final class SymbolPickerWindow: NSPanel {
    static var shared: SymbolPickerWindow?

    init(recentItems: [String],
         onPick: @escaping (String) -> Void,
         onClose: @escaping () -> Void) {
        let content = NSHostingView(rootView: SymbolPickerView(
            groups: SymbolCatalog.groups(),
            recentItems: recentItems,
            onPick: onPick,
            onClose: onClose
        ))

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 420),
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
        // Click ra ngoài / mất focus -> đóng như bấm Esc.
        close(restoreFocus: true)
    }

    /// Đóng cửa sổ. `restoreFocus` = trả focus về app trước (để người dùng gõ tiếp).
    func close(restoreFocus: Bool) {
        NotificationCenter.default.removeObserver(self)
        orderOut(nil)
        if SymbolPickerWindow.shared === self { SymbolPickerWindow.shared = nil }
        if restoreFocus { NSApp.hide(nil) }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func showWindow() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let w: CGFloat = 360, h: CGFloat = 420
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

struct SymbolPickerView: View {
    let groups: [SymbolCatalog.Group]
    /// Ký tự/emoji dùng gần đây (mới nhất trước) — hiện thành nhóm đầu.
    let recentItems: [String]
    let onPick: (String) -> Void
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering: String? = nil
    @FocusState private var isFocused: Bool

    private var t: Pixel.Tokens { Pixel.tokens(for: colorScheme) }

    var body: some View {
        PixelPanel(fill: t.panel, border: t.outline, shadow: t.shadow) {
            VStack(spacing: 0) {
                header
                Rectangle().fill(t.outline).frame(height: Pixel.borderThin)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        recentSection
                        ForEach(groups.indices, id: \.self) { i in
                            groupSection(groups[i])
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(width: 360, height: 420)
        .overlay(PixelScanlines(color: t.scanline))
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onKeyPress(.escape) { onClose(); return .handled }
    }

    /// Nhóm "gần đây" ghép từ danh sách MRU (nếu có), dùng làm nhóm đầu.
    @ViewBuilder
    private var recentSection: some View {
        if !recentItems.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("GẦN ĐÂY")
                    .font(.pixelHead(7))
                    .foregroundColor(t.textMuted)
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(38), spacing: 6), count: 7),
                    spacing: 6
                ) {
                    ForEach(recentItems, id: \.self) { cell($0, keySuffix: "r") }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            PixelWindowDots(outline: t.outline, onClose: onClose)
            Spacer()
            Text("GÕ NHANH KÝ TỰ")
                .font(.pixelHead(9))
                .foregroundColor(t.textSecondary)
            Spacer()
            // Giữ cân đối với cụm dots bên trái.
            Color.clear.frame(width: 47, height: 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func groupSection(_ group: SymbolCatalog.Group) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(group.title.uppercased())
                .font(.pixelHead(7))
                .foregroundColor(t.textMuted)
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(38), spacing: 6), count: 7),
                spacing: 6
            ) {
                ForEach(group.items, id: \.self) { item in
                    cell(item, keySuffix: "g")
                }
            }
        }
    }

    /// `keySuffix` phân biệt ô ở nhóm "gần đây" ("r") với nhóm thường ("g") để
    /// hover không sáng cùng lúc hai ô trùng ký tự.
    private func cell(_ item: String, keySuffix: String) -> some View {
        let hoverKey = item + keySuffix
        let isHover = hovering == hoverKey
        return Text(item)
            .font(.system(size: 20))
            .frame(width: 38, height: 38)
            .background(isHover ? t.inset : Color.clear)
            .overlay(
                Rectangle().strokeBorder(
                    isHover ? Pixel.grass : t.outline.opacity(0.25),
                    lineWidth: Pixel.borderThin
                )
            )
            .contentShape(Rectangle())
            .onHover { hovering = $0 ? hoverKey : nil }
            .onTapGesture { onPick(item) }
    }
}
