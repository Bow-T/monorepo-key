// PixelMenuWindow.swift
// ---------------------
// MENU pixel-art dùng chung — thay cho NSMenu mặc định (nền trắng bo góc, font hệ
// thống) vốn lạc phong cách. Dựng bằng NSPanel borderless + SwiftUI, tái dùng hệ
// design `Pixel` (PixelPanel/PixelScanlines/PixelWindowDots) giống SymbolPicker &
// AIResultWindow. Hiện tại con trỏ; đóng khi click ra ngoài / Esc.
//
// Hỗ trợ 3 loại dòng:
//   • .item     — mục bấm được (có icon SF Symbol tuỳ chọn, checkmark tuỳ chọn)
//   • .separator— đường kẻ ngang
//   • .header   — nhãn nhóm (không bấm được)
// Mục có `submenu` sẽ mở một PixelMenuWindow con ngay bên cạnh (menu lồng).
//
// Dùng: PixelMenuWindow.present(title:, items:) — mỗi item mang action đóng gói.
// Action tự đóng toàn bộ menu trước khi chạy (giống NSMenu).

import SwiftUI
import AppKit

// MARK: - Mô tả dòng menu

/// Một dòng trong menu pixel. Dùng factory `.item/.header/.separator` cho gọn.
struct PixelMenuItem: Identifiable {
    let id = UUID()
    enum Kind { case item, header, separator }
    var kind: Kind
    var title: String
    var symbol: String?          // tên SF Symbol (nil = không icon)
    var checked: Bool            // hiện dấu ✓ bên phải
    var enabled: Bool
    var submenu: [PixelMenuItem]?// nếu có -> mục mở menu con
    var action: (() -> Void)?    // hành động khi bấm (nil cho header/separator/submenu)

    static func item(_ title: String,
                     symbol: String? = nil,
                     checked: Bool = false,
                     enabled: Bool = true,
                     action: @escaping () -> Void) -> PixelMenuItem {
        PixelMenuItem(kind: .item, title: title, symbol: symbol, checked: checked,
                      enabled: enabled, submenu: nil, action: action)
    }

    static func submenu(_ title: String,
                        symbol: String? = nil,
                        items: [PixelMenuItem]) -> PixelMenuItem {
        PixelMenuItem(kind: .item, title: title, symbol: symbol, checked: false,
                      enabled: true, submenu: items, action: nil)
    }

    static func header(_ title: String) -> PixelMenuItem {
        PixelMenuItem(kind: .header, title: title, symbol: nil, checked: false,
                      enabled: false, submenu: nil, action: nil)
    }

    static var separator: PixelMenuItem {
        PixelMenuItem(kind: .separator, title: "", symbol: nil, checked: false,
                      enabled: false, submenu: nil, action: nil)
    }
}

// MARK: - Window

final class PixelMenuWindow: NSPanel {
    /// Ngăn xếp menu đang mở (menu gốc + các menu con). Đóng tất cả cùng lúc.
    private static var stack: [PixelMenuWindow] = []

    private var isSubmenu = false

    /// Mở menu gốc tại con trỏ. Đóng menu đang mở (nếu có) trước.
    @MainActor
    static func present(title: String, items: [PixelMenuItem]) {
        closeAll(restoreFocus: false)
        let win = PixelMenuWindow(title: title, items: items, isSubmenu: false)
        stack.append(win)
        win.showAtCursor()
    }

    /// Mở menu gốc ngay dưới icon status bar (menu bar). Nếu không có status item
    /// (hiếm) thì rơi về mở tại con trỏ.
    @MainActor
    static func presentBelowStatusItem(title: String, items: [PixelMenuItem],
                                       statusItem: NSStatusItem?) {
        closeAll(restoreFocus: false)
        let win = PixelMenuWindow(title: title, items: items, isSubmenu: false)
        stack.append(win)
        if let button = statusItem?.button, let btnWindow = button.window {
            // Frame của nút trên màn hình -> đặt menu ngay dưới, canh phải cho gọn.
            let rectInWindow = button.convert(button.bounds, to: nil)
            let onScreen = btnWindow.convertToScreen(rectInWindow)
            win.show(below: onScreen)
        } else {
            win.showAtCursor()
        }
    }

    /// Mở menu con cạnh một dòng. `parentDepth` = số menu được giữ lại phía trên nó
    /// (menu gốc = 0 -> submenu là phần tử thứ 1). Đóng mọi menu sâu hơn parent trước
    /// khi mở, để chuyển giữa các submenu cùng cấp không chồng chất.
    @MainActor
    fileprivate static func presentSubmenu(title: String, items: [PixelMenuItem],
                                           near rect: NSRect, parentDepth: Int) {
        let keep = parentDepth + 1
        while stack.count > keep { stack.removeLast().orderOutSelf() }
        let win = PixelMenuWindow(title: title, items: items, isSubmenu: true)
        stack.append(win)
        win.show(near: rect)
    }

    /// Đóng các menu con sâu hơn mức `depth` (khi hover sang mục không có submenu
    /// trong menu ở mức đó). Giữ lại các menu ở mức <= depth.
    @MainActor
    fileprivate static func closeSubmenus(deeperThan depth: Int) {
        let keep = depth + 1
        while stack.count > keep { stack.removeLast().orderOutSelf() }
    }

    /// Đóng toàn bộ ngăn xếp menu. `restoreFocus` = trả focus về app trước.
    @MainActor
    static func closeAll(restoreFocus: Bool) {
        guard !stack.isEmpty else { return }
        for w in stack { w.orderOutSelf() }
        stack.removeAll()
        if restoreFocus { NSApp.hide(nil) }
    }

    private init(title: String, items: [PixelMenuItem], isSubmenu: Bool) {
        self.isSubmenu = isSubmenu
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let content = NSHostingView(rootView: PixelMenuView(
            title: title,
            items: items,
            onRun: { action in
                // Đóng cả menu trước rồi chạy hành động (giống NSMenu).
                PixelMenuWindow.closeAll(restoreFocus: false)
                action()
            },
            onSubmenu: { subTitle, subItems, rowRect in
                PixelMenuWindow.presentSubmenu(title: subTitle, items: subItems, near: rowRect,
                                               parentDepth: isSubmenu ? 1 : 0)
            },
            onCloseSubmenus: {
                PixelMenuWindow.closeSubmenus(deeperThan: isSubmenu ? 1 : 0)
            },
            onClose: { PixelMenuWindow.closeAll(restoreFocus: true) }
        ))
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
        // Cửa sổ tự co theo nội dung SwiftUI.
        content.setFrameSize(content.fittingSize)
        setContentSize(content.fittingSize)
    }

    @objc private func handleResignKey() {
        // Menu cha mất key khi mở/đóng menu con là bình thường -> CHỈ đóng toàn bộ
        // khi thực sự không còn menu nào là key (click ra ngoài). Trễ nhỏ để menu
        // con vừa mở kịp trở thành key (tránh đóng nhầm giữa lúc chuyển submenu).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let anyKey = PixelMenuWindow.stack.contains { $0.isKeyWindow }
            if !anyKey { PixelMenuWindow.closeAll(restoreFocus: true) }
        }
    }

    private func orderOutSelf() {
        NotificationCenter.default.removeObserver(self)
        orderOut(nil)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Đặt menu gốc quanh con trỏ, kẹp trong màn hình.
    private func showAtCursor() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let size = frame.size
        if let f = screen?.visibleFrame {
            // Neo góc trên-trái menu tại con trỏ (như menu ngữ cảnh macOS).
            var origin = NSPoint(x: mouse.x, y: mouse.y - size.height)
            if origin.x + size.width > f.maxX { origin.x = f.maxX - size.width }
            if origin.x < f.minX { origin.x = f.minX }
            if origin.y < f.minY { origin.y = f.minY }
            if origin.y + size.height > f.maxY { origin.y = f.maxY - size.height }
            setFrameOrigin(origin)
        }
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Đặt menu ngay DƯỚI icon status bar (rect nút theo toạ độ màn hình).
    private func show(below rect: NSRect) {
        let screen = NSScreen.screens.first { NSMouseInRect(NSPoint(x: rect.midX, y: rect.midY), $0.frame, false) } ?? NSScreen.main
        let size = frame.size
        var origin = NSPoint(x: rect.maxX - size.width, y: rect.minY - size.height + 2)
        if let f = screen?.visibleFrame {
            if origin.x < f.minX { origin.x = f.minX }
            if origin.x + size.width > f.maxX { origin.x = f.maxX - size.width }
            if origin.y < f.minY { origin.y = f.minY }
        }
        setFrameOrigin(origin)
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Đặt menu con cạnh phải của dòng cha (rect theo toạ độ màn hình).
    private func show(near rect: NSRect) {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let size = frame.size
        if let f = screen?.visibleFrame {
            var origin = NSPoint(x: rect.maxX - 4, y: rect.maxY - size.height)
            // Không đủ chỗ bên phải -> lật sang trái dòng cha.
            if origin.x + size.width > f.maxX { origin.x = rect.minX - size.width + 4 }
            if origin.x < f.minX { origin.x = f.minX }
            if origin.y < f.minY { origin.y = f.minY }
            if origin.y + size.height > f.maxY { origin.y = f.maxY - size.height }
            setFrameOrigin(origin)
        }
        makeKeyAndOrderFront(nil)
    }
}

// MARK: - View

struct PixelMenuView: View {
    let title: String
    let items: [PixelMenuItem]
    let onRun: (@escaping () -> Void) -> Void
    /// (title, items, rowRectMànHình) khi hover/bấm một mục có submenu.
    let onSubmenu: (String, [PixelMenuItem], NSRect) -> Void
    /// Đóng các menu con sâu hơn (khi hover sang mục không có submenu).
    var onCloseSubmenus: () -> Void = {}
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering: UUID? = nil
    /// Rect (toạ độ theo cửa sổ chứa, gốc trên-trái) của từng dòng — để đặt submenu.
    @State private var rowRects: [UUID: CGRect] = [:]
    /// Dòng đang mở submenu — tránh mở lại liên tục khi hover lặp.
    @State private var openedSubmenuFor: UUID? = nil

    private var t: Pixel.Tokens { Pixel.tokens(for: colorScheme) }

    /// Cửa sổ NSPanel chứa view này (để đổi toạ độ dòng -> màn hình). Lấy qua accessor.
    @State private var hostWindow: NSWindow? = nil

    var body: some View {
        PixelPanel(fill: t.panel, border: t.outline, shadow: t.shadow) {
            VStack(spacing: 0) {
                header
                Rectangle().fill(t.outline).frame(height: Pixel.borderThin)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { row($0) }
                }
                .padding(6)
            }
        }
        .fixedSize()
        .background(WindowAccessor { hostWindow = $0 })
        .overlay(PixelScanlines(color: t.scanline))
        .onKeyPress(.escape) { onClose(); return .handled }
    }

    private var header: some View {
        HStack(spacing: 8) {
            PixelWindowDots(outline: t.outline, onClose: onClose)
            Spacer(minLength: 12)
            Text(title.uppercased())
                .font(.pixelHead(9))
                .foregroundColor(t.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 12)
            Color.clear.frame(width: 47, height: 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func row(_ item: PixelMenuItem) -> some View {
        switch item.kind {
        case .separator:
            Rectangle()
                .fill(t.outline.opacity(0.25))
                .frame(height: Pixel.borderThin)
                .padding(.vertical, 5)
                .padding(.horizontal, 4)
        case .header:
            Text(item.title.uppercased())
                .font(.pixelHead(7))
                .foregroundColor(t.textMuted)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)
        case .item:
            itemRow(item)
        }
    }

    private func itemRow(_ item: PixelMenuItem) -> some View {
        let isHover = hovering == item.id
        let hasSub = item.submenu != nil
        // Rect của dòng theo toạ độ màn hình — cập nhật liên tục để mở submenu đúng chỗ.
        return HStack(spacing: 9) {
            // Icon SF Symbol (nếu có) — canh cột đều.
            if let sym = item.symbol {
                Image(systemName: sym)
                    .font(.system(size: 12))
                    .frame(width: 16)
                    .foregroundColor(isHover ? t.textPrimary : t.textSecondary)
            } else {
                Color.clear.frame(width: 16, height: 1)
            }
            Text(item.title)
                .font(.pixelBody(17))
                .foregroundColor(item.enabled ? (isHover ? t.textPrimary : t.textSecondary)
                                              : t.textMuted)
                .lineLimit(1)
            Spacer(minLength: 18)
            if item.checked {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Pixel.grass)
            }
            if hasSub {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(isHover ? t.textPrimary : t.textMuted)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(minWidth: 220, alignment: .leading)
        .background(isHover ? t.inset : Color.clear)
        .overlay(
            Rectangle().strokeBorder(
                isHover ? Pixel.grass : Color.clear,
                lineWidth: Pixel.borderThin
            )
        )
        .contentShape(Rectangle())
        // Ghi lại rect của dòng (toạ độ màn hình) để mở submenu cạnh nó.
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { rowRects[item.id] = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { rowRects[item.id] = $1 }
            }
        )
        .onHover { inside in
            if inside {
                hovering = item.id
                // Hover vào dòng có submenu -> mở menu con MỘT LẦN (như menu macOS).
                // Hover sang dòng khác (submenu khác nil) -> đóng submenu đang mở.
                if let sub = item.submenu, let rect = rowRects[item.id] {
                    if openedSubmenuFor != item.id {
                        openedSubmenuFor = item.id
                        onSubmenu(item.title, sub, screenRect(from: rect))
                    }
                } else {
                    openedSubmenuFor = nil
                    onCloseSubmenus()
                }
            } else if hovering == item.id {
                hovering = nil
            }
        }
        .onTapGesture {
            guard item.enabled else { return }
            if let action = item.action {
                onRun(action)
            } else if let sub = item.submenu, let rect = rowRects[item.id] {
                // Mục submenu không có action -> tap cũng mở menu con.
                openedSubmenuFor = item.id
                onSubmenu(item.title, sub, screenRect(from: rect))
            }
        }
    }

    /// Đổi frame SwiftUI (gốc trên-trái, theo cửa sổ chứa) sang rect màn hình
    /// (gốc dưới-trái) để định vị NSPanel con cạnh dòng. Dùng CHÍNH cửa sổ chứa
    /// view này (menu cha), không phải keyWindow — menu con vừa mở có thể đã chiếm key.
    private func screenRect(from f: CGRect) -> NSRect {
        guard let win = hostWindow else { return .zero }
        let wf = win.frame
        let x = wf.minX + f.minX
        let yTop = wf.maxY - f.minY
        return NSRect(x: x, y: yTop - f.height, width: f.width, height: f.height)
    }
}

/// Lấy tham chiếu NSWindow thật của một view SwiftUI (để đổi toạ độ chính xác).
private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { onResolve(v.window) }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onResolve(nsView.window) }
    }
}
