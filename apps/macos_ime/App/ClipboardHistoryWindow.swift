// ClipboardHistoryWindow.swift
// ----------------------------
// Overlay panel hiển thị lịch sử clipboard bằng SwiftUI, theo phong cách
// PIXEL ART khớp với app cài đặt (Flutter settings_ui):
//   - Fill phẳng, viền vuông đen CỨNG, bóng đổ cứng (offset, không blur).
//   - KHÔNG bo góc, KHÔNG gradient, KHÔNG kính mờ.
//   - Font pixel: "Press Start 2P" (tiêu đề) + "VT323" (nội dung).
//   - Bảng màu forest-night / daytime-meadow, theo sáng/tối hệ thống.
//   - Window dots vuông + scanline overlay.

import SwiftUI
import AppKit

// MARK: - Design tokens (đồng bộ app_theme.dart)

/// Bảng màu + hằng số hình học pixel. Đổi theo sáng/tối hệ thống.
enum Pixel {
    // Font (đã đăng ký runtime ở AppDelegate.registerPixelFonts).
    static let head = "Press Start 2P"
    static let body = "VT323"

    // Hình học
    static let borderThin: CGFloat = 2
    static let borderThick: CGFloat = 3
    static let shadow: CGFloat = 5
    static let shadowSm: CGFloat = 3

    // Màu nền chung (hex từ app_theme.dart)
    static let grass   = Color(hex: 0x5DA130)
    static let leaf    = Color(hex: 0x6FB83C)
    static let red     = Color(hex: 0xC0432F)
    static let yellow  = Color(hex: 0xE8B844)
    static let green   = Color(hex: 0x6FB83C)

    struct Tokens {
        let background: Color
        let panel: Color
        let inset: Color
        let outline: Color
        let shadow: Color
        let textPrimary: Color
        let textSecondary: Color
        let textMuted: Color
        let scanline: Color
    }

    // "Daytime meadow" — parchment kem, viền nâu.
    static let light = Tokens(
        background: Color(hex: 0xCFE0A8),
        panel:      Color(hex: 0xEAD9B0),
        inset:      Color(hex: 0xDCC79A),
        outline:    Color(hex: 0x2A1E16),
        shadow:     Color(hex: 0x2A1E16),
        textPrimary: Color(hex: 0x2A1E16),
        textSecondary: Color(hex: 0x5A4030),
        textMuted:  Color(hex: 0x917A5E),
        scanline:   Color(hex: 0x2A1E16).opacity(0.04)
    )

    // "Forest night" — panel rêu, nền xanh tối.
    static let dark = Tokens(
        background: Color(hex: 0x1A2418),
        panel:      Color(hex: 0x243524),
        inset:      Color(hex: 0x152014),
        outline:    Color(hex: 0x0E1A0C),
        shadow:     Color(hex: 0x0A140A),
        textPrimary: Color(hex: 0xF0E8CE),
        textSecondary: Color(hex: 0xC4D2A8),
        textMuted:  Color(hex: 0x7E9070),
        scanline:   Color.black.opacity(0.10)
    )

    static func tokens(for scheme: ColorScheme) -> Tokens {
        scheme == .dark ? dark : light
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - Pixel building blocks

/// Panel pixel: fill phẳng + viền vuông cứng + bóng offset cứng (không blur).
/// Bóng được vẽ như một khối đặc lệch xuống dưới-phải, chừa chỗ bằng padding.
struct PixelPanel<Content: View>: View {
    var fill: Color
    var border: Color
    var shadow: Color
    var borderWidth: CGFloat = Pixel.borderThick
    var shadowOffset: CGFloat = Pixel.shadow
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Bóng cứng: khối đặc lệch.
            Rectangle()
                .fill(shadow)
                .padding(.leading, shadowOffset)
                .padding(.top, shadowOffset)
            // Mặt panel.
            content()
                .background(fill)
                .overlay(
                    Rectangle().strokeBorder(border, lineWidth: borderWidth)
                )
                .padding(.trailing, shadowOffset)
                .padding(.bottom, shadowOffset)
        }
    }
}

/// Window dots kiểu pixel: khối vuông màu + viền đen (không tròn).
struct PixelWindowDots: View {
    let outline: Color
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            dot(Pixel.red, action: onClose)
            dot(Pixel.yellow, action: nil)
            dot(Pixel.green, action: nil)
        }
    }

    @ViewBuilder
    private func dot(_ color: Color, action: (() -> Void)?) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: 13, height: 13)
            .overlay(Rectangle().strokeBorder(outline, lineWidth: 2))
            .contentShape(Rectangle())
            .onTapGesture { action?() }
    }
}

/// Scanline overlay — kẻ ngang mờ 1px mỗi 3px, tạo cảm giác màn hình CRT.
struct PixelScanlines: View {
    let color: Color
    var body: some View {
        GeometryReader { geo in
            Path { path in
                var y: CGFloat = 0
                while y < geo.size.height {
                    path.addRect(CGRect(x: 0, y: y, width: geo.size.width, height: 1))
                    y += 3
                }
            }
            .fill(color)
        }
        .allowsHitTesting(false)
    }
}

extension Font {
    static func pixelHead(_ size: CGFloat) -> Font { .custom(Pixel.head, size: size) }
    static func pixelBody(_ size: CGFloat) -> Font { .custom(Pixel.body, size: size) }
}

// MARK: - Window

class ClipboardHistoryWindow: NSPanel {
    static var shared: ClipboardHistoryWindow?

    init(entries: [ClipboardEntry], onSelect: @escaping (ClipboardEntry) -> Void) {
        let contentView = NSHostingView(rootView: ClipboardHistoryView(
            entries: entries,
            onSelect: onSelect,
            onClose: {
                ClipboardHistoryWindow.shared?.orderOut(nil)
                ClipboardHistoryWindow.shared = nil
                NSApp.hide(nil)
            }
        ))

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 480),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.contentView = contentView
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
        self.orderOut(nil)
        if ClipboardHistoryWindow.shared === self {
            ClipboardHistoryWindow.shared = nil
        }
        NSApp.hide(nil)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func showWindow() {
        let mouseLocation = NSEvent.mouseLocation
        let screens = NSScreen.screens
        let activeScreen = screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main

        if let screen = activeScreen {
            var origin = mouseLocation
            origin.x -= 190
            origin.y -= 240

            let screenFrame = screen.visibleFrame
            if origin.x < screenFrame.minX { origin.x = screenFrame.minX }
            if origin.x + 380 > screenFrame.maxX { origin.x = screenFrame.maxX - 380 }
            if origin.y < screenFrame.minY { origin.y = screenFrame.minY }
            if origin.y + 480 > screenFrame.maxY { origin.y = screenFrame.maxY - 480 }

            self.setFrameOrigin(origin)
        }

        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - SwiftUI View

struct ClipboardHistoryView: View {
    @State var entries: [ClipboardEntry]
    let onSelect: (ClipboardEntry) -> Void
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var searchText = ""
    @State private var selectedIndex = 0
    @State private var isHoveringIndex: Int? = nil
    @FocusState private var isFocused: Bool

    private var t: Pixel.Tokens { Pixel.tokens(for: colorScheme) }

    var filteredEntries: [ClipboardEntry] {
        if searchText.isEmpty {
            return entries
        }
        return entries.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }

    private func deleteEntry(_ entry: ClipboardEntry) {
        ClipboardManager.shared.removeEntry(id: entry.id)
        entries.removeAll { $0.id == entry.id }
        if entries.isEmpty { onClose(); return }
        if selectedIndex >= filteredEntries.count {
            selectedIndex = max(0, filteredEntries.count - 1)
        }
    }

    var body: some View {
        PixelPanel(fill: t.panel, border: t.outline, shadow: t.shadow) {
            VStack(spacing: 0) {
                header
                searchBar
                Rectangle().fill(t.outline).frame(height: Pixel.borderThin)
                listOrEmpty
                Rectangle().fill(t.outline).frame(height: Pixel.borderThin)
                footer
            }
        }
        .frame(width: 380, height: 480)
        .overlay(PixelScanlines(color: t.scanline))
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onKeyPress(.upArrow) {
            if !filteredEntries.isEmpty {
                selectedIndex = (selectedIndex - 1 + filteredEntries.count) % filteredEntries.count
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if !filteredEntries.isEmpty {
                selectedIndex = (selectedIndex + 1) % filteredEntries.count
            }
            return .handled
        }
        .onKeyPress(.tab) {
            if !filteredEntries.isEmpty {
                selectedIndex = (selectedIndex + 1) % filteredEntries.count
            }
            return .handled
        }
        .onKeyPress(.return) {
            if !filteredEntries.isEmpty { onSelect(filteredEntries[selectedIndex]) }
            return .handled
        }
        .onKeyPress(.escape) { onClose(); return .handled }
        .onKeyPress(.delete) {
            if searchText.isEmpty, !filteredEntries.isEmpty {
                deleteEntry(filteredEntries[selectedIndex]); return .handled
            }
            return .ignored
        }
        .onKeyPress(.deleteForward) {
            if !filteredEntries.isEmpty {
                deleteEntry(filteredEntries[selectedIndex]); return .handled
            }
            return .ignored
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "123456789")) { keyPress in
            if let num = Int(keyPress.characters), num >= 1 && num <= filteredEntries.count {
                onSelect(filteredEntries[num - 1]); return .handled
            }
            return .ignored
        }
        .onChange(of: searchText) { selectedIndex = 0 }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 9) {
            PixelWindowDots(outline: t.outline, onClose: onClose)

            // Khối icon clipboard vuông.
            Rectangle()
                .fill(Pixel.leaf)
                .frame(width: 18, height: 18)
                .overlay(Rectangle().strokeBorder(t.outline, lineWidth: 2))

            Text("CLIPBOARD")
                .font(.pixelHead(9))
                .foregroundColor(t.textPrimary)
                .lineLimit(1)

            Spacer()

            // Nút "Xoá tất cả" pixel.
            Button(action: {
                ClipboardManager.shared.clearHistory()
                onClose()
            }) {
                Text("XOÁ HẾT")
                    .font(.pixelHead(7))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Pixel.red)
                    .overlay(Rectangle().strokeBorder(t.outline, lineWidth: 2))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }

    // MARK: Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(t.textMuted)

            TextField("", text: $searchText)
                .textFieldStyle(.plain)
                .font(.pixelBody(17))
                .foregroundColor(t.textPrimary)
                .overlay(
                    Group {
                        if searchText.isEmpty {
                            Text("TÌM KIẾM...")
                                .font(.pixelBody(17))
                                .foregroundColor(t.textMuted)
                                .allowsHitTesting(false)
                        }
                    },
                    alignment: .leading
                )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(t.inset)
        .overlay(Rectangle().strokeBorder(t.outline, lineWidth: Pixel.borderThin))
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    // MARK: List

    @ViewBuilder
    private var listOrEmpty: some View {
        if filteredEntries.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "tray")
                    .font(.system(size: 26))
                    .foregroundColor(t.textMuted)
                Text(entries.isEmpty ? "LỊCH SỬ TRỐNG" : "KHÔNG TÌM THẤY")
                    .font(.pixelHead(8))
                    .foregroundColor(t.textMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(0..<filteredEntries.count, id: \.self) { index in
                            let entry = filteredEntries[index]
                            ClipboardItemRow(
                                index: index,
                                entry: entry,
                                isSelected: index == selectedIndex,
                                isHovered: isHoveringIndex == index,
                                tokens: t,
                                onHover: { hovering in
                                    if hovering { isHoveringIndex = index }
                                    else if isHoveringIndex == index { isHoveringIndex = nil }
                                },
                                onTap: { onSelect(entry) },
                                onDelete: { deleteEntry(entry) }
                            )
                            .id(index)

                            if index < filteredEntries.count - 1 {
                                Rectangle()
                                    .fill(t.outline.opacity(0.35))
                                    .frame(height: 1)
                                    .padding(.leading, 50)
                            }
                        }
                    }
                }
                .onChange(of: selectedIndex) { _, newValue in
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Text("\(entries.count) MỤC")
                .font(.pixelHead(7))
                .foregroundColor(t.textMuted)
            Spacer()
            Text("↑↓/TAB CHỌN • ENTER DÁN • DEL XOÁ • ESC ĐÓNG")
                .font(.pixelHead(7))
                .foregroundColor(t.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

// MARK: - Row

struct ClipboardItemRow: View {
    let index: Int
    let entry: ClipboardEntry
    let isSelected: Bool
    let isHovered: Bool
    let tokens: Pixel.Tokens
    let onHover: (Bool) -> Void
    let onTap: () -> Void
    let onDelete: () -> Void

    private var previewText: String {
        let singleLine = entry.text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if singleLine.count > 50 { return String(singleLine.prefix(47)) + "..." }
        return singleLine
    }

    private func timeAgo(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 10 { return "Vừa xong" }
        if seconds < 60 { return "\(seconds) giây trước" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) phút trước" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) giờ trước" }
        let days = hours / 24
        if days == 1 { return "Hôm qua" }
        return "\(days) ngày trước"
    }

    var body: some View {
        HStack(spacing: 11) {
            // Icon vuông: thumbnail ảnh hoặc khối chữ.
            ZStack {
                if entry.isImage, let path = entry.imagePath,
                   let nsImage = NSImage(contentsOfFile: path) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 28, height: 28)
                        .clipped()
                        .overlay(Rectangle().strokeBorder(tokens.outline, lineWidth: 2))
                } else {
                    Rectangle()
                        .fill(tokens.inset)
                        .frame(width: 28, height: 28)
                        .overlay(Rectangle().strokeBorder(tokens.outline, lineWidth: 2))
                    Image(systemName: "doc.text")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Pixel.leaf)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(previewText)
                    .font(.pixelBody(17))
                    .foregroundColor(isSelected ? .white : tokens.textPrimary)
                    .lineLimit(1)

                Text("\(entry.appName.uppercased()) • \(timeAgo(from: entry.timestamp))")
                    .font(.pixelHead(6))
                    .foregroundColor(isSelected ? .white.opacity(0.85) : tokens.textMuted)
                    .lineLimit(1)
            }

            Spacer()

            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 16, height: 16)
                        .background(Pixel.red)
                        .overlay(Rectangle().strokeBorder(tokens.outline, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }

            // Badge số dán nhanh — khối vuông pixel.
            if index < 9 {
                Text("\(index + 1)")
                    .font(.pixelHead(7))
                    .foregroundColor(isSelected ? .white : tokens.textSecondary)
                    .frame(width: 17, height: 17)
                    .background(isSelected ? Pixel.grass : tokens.inset)
                    .overlay(Rectangle().strokeBorder(tokens.outline, lineWidth: 1.5))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            isSelected ? Pixel.grass.opacity(0.9)
                       : (isHovered ? tokens.outline.opacity(0.08) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { onHover($0) }
        .onTapGesture { onTap() }
    }
}
