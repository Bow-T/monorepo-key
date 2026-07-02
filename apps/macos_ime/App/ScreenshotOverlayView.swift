// ScreenshotOverlayView.swift
// ---------------------------
// Overlay toàn màn hình cho tính năng CHỤP MÀN HÌNH: hiển thị ảnh màn hình đã
// "đóng băng", người dùng kéo chuột chọn vùng, sau đó vẽ chú thích (bút, mũi tên,
// khung, chữ) rồi chọn hành động: COPY ảnh / COPY TEXT (OCR) / LƯU file.
//
// Phong cách pixel art dùng chung design tokens với ClipboardHistoryWindow
// (enum Pixel). Phím: kéo chuột = chọn vùng, Enter = copy, Esc = thoát.

import AppKit
import SwiftUI

// MARK: - Mô hình chú thích

/// Công cụ vẽ trên vùng đã chọn.
enum AnnotationTool: Equatable {
    case pen    // bút vẽ tự do
    case arrow  // mũi tên
    case rect   // khung chữ nhật
    case text   // chèn chữ
}

/// Bảng màu chú thích — cố định vài màu pixel, để phía render (NSColor) và phía
/// view (Color) luôn khớp nhau.
enum AnnotationColor: CaseIterable, Equatable {
    case red, yellow, green, black, white

    private var hex: UInt32 {
        switch self {
        case .red:    return 0xC0432F  // Pixel.red
        case .yellow: return 0xE8B844  // Pixel.yellow
        case .green:  return 0x5DA130  // Pixel.grass
        case .black:  return 0x1A1A1A
        case .white:  return 0xF5F0E0
        }
    }

    var color: Color { Color(hex: hex) }

    var nsColor: NSColor {
        NSColor(
            red:   CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue:  CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Một nét chú thích đã vẽ. Toạ độ theo HỆ VIEW của overlay (điểm, gốc trên-trái);
/// phía render sẽ đổi sang toạ độ pixel của ảnh.
struct Annotation {
    var tool: AnnotationTool
    var color: AnnotationColor
    var points: [CGPoint] = []   // pen: polyline; arrow/rect: [đầu, cuối]
    var text: String = ""        // tool .text
    var origin: CGPoint = .zero  // tool .text: góc trên-trái của chữ
}

/// Hành động kết thúc phiên chụp.
enum ScreenshotAction {
    case copy  // copy ảnh (kèm chú thích) vào clipboard
    case ocr   // nhận dạng chữ trong vùng chọn rồi copy text
    case save  // lưu ảnh (kèm chú thích) ra file
}

/// Cỡ chữ (điểm) của chú thích chữ — dùng chung giữa Canvas preview và renderer.
let screenshotTextSize: CGFloat = 24

// MARK: - View

struct ScreenshotOverlayView: View {
    let screenshot: CGImage
    let viewSize: CGSize
    let onAction: (ScreenshotAction, CGRect, [Annotation]) -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    @State private var dragOrigin: CGPoint?
    @State private var selection: CGRect?
    @State private var locked = false  // đã chốt vùng chọn -> sang chế độ chú thích
    @State private var tool: AnnotationTool?
    @State private var color: AnnotationColor = .red
    @State private var annotations: [Annotation] = []
    @State private var draft: Annotation?      // nét đang kéo dở
    @State private var textDraft: CGPoint?     // vị trí ô nhập chữ đang mở
    @State private var textInput = ""
    @State private var toolbarSize = CGSize(width: 640, height: 44)

    @FocusState private var keyFocus: Bool
    @FocusState private var textFocus: Bool

    private var t: Pixel.Tokens { Pixel.tokens(for: colorScheme) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(decorative: screenshot, scale: CGFloat(screenshot.width) / viewSize.width)
                .resizable()
                .frame(width: viewSize.width, height: viewSize.height)

            dimming

            if let sel = selection {
                selectionBorder(sel)
                sizeLabel(sel)
            }

            annotationCanvas

            if let p = textDraft {
                textEditor(at: p)
            }

            if locked, selection != nil {
                toolbar
                    .offset(x: toolbarOffset.x, y: toolbarOffset.y)
            }

            if !locked {
                hintBar
            }
        }
        .frame(width: viewSize.width, height: viewSize.height)
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .focusable()
        .focusEffectDisabled()
        .focused($keyFocus)
        .onAppear { keyFocus = true }
        .onKeyPress(.escape) {
            onCancel()
            return .handled
        }
        .onKeyPress(.return) {
            guard locked, let sel = selection else { return .ignored }
            commitTextDraft()
            onAction(.copy, sel, annotations)
            return .handled
        }
    }

    // MARK: Chọn vùng & vẽ

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                if !locked {
                    let origin = dragOrigin ?? v.startLocation
                    dragOrigin = origin
                    selection = Self.rect(from: origin, to: v.location)
                    return
                }
                guard let sel = selection, let tool else { return }
                switch tool {
                case .pen:
                    var d = draft ?? Annotation(tool: .pen, color: color)
                    d.points.append(Self.clamp(v.location, to: sel))
                    draft = d
                case .arrow, .rect:
                    draft = Annotation(
                        tool: tool, color: color,
                        points: [Self.clamp(v.startLocation, to: sel),
                                 Self.clamp(v.location, to: sel)]
                    )
                case .text:
                    break
                }
            }
            .onEnded { v in
                if !locked {
                    dragOrigin = nil
                    if let sel = selection, sel.width >= 8, sel.height >= 8 {
                        locked = true
                    } else {
                        selection = nil  // kéo quá nhỏ -> coi như chưa chọn
                    }
                    return
                }
                guard let sel = selection, let tool else { return }
                switch tool {
                case .pen, .arrow, .rect:
                    if let d = draft, d.points.count >= 2 { annotations.append(d) }
                    draft = nil
                case .text:
                    // Click đặt điểm nhập chữ (chốt ô đang nhập dở nếu có).
                    commitTextDraft()
                    textDraft = Self.clamp(v.location, to: sel)
                    textInput = ""
                    textFocus = true
                }
            }
    }

    /// Làm mờ phần NGOÀI vùng chọn (fill even-odd để "đục lỗ" vùng chọn).
    private var dimming: some View {
        Path { p in
            p.addRect(CGRect(origin: .zero, size: viewSize))
            if let sel = selection { p.addRect(sel) }
        }
        .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))
        .allowsHitTesting(false)
    }

    private func selectionBorder(_ sel: CGRect) -> some View {
        Rectangle()
            .strokeBorder(Color.white, lineWidth: 2)
            .background(Rectangle().strokeBorder(Color.black.opacity(0.6), lineWidth: 1).padding(-1))
            .frame(width: sel.width, height: sel.height)
            .offset(x: sel.minX, y: sel.minY)
            .allowsHitTesting(false)
    }

    private func sizeLabel(_ sel: CGRect) -> some View {
        let above = sel.minY > 26
        return Text("\(Int(sel.width))×\(Int(sel.height))")
            .font(.pixelHead(8))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.75))
            .offset(x: sel.minX, y: above ? sel.minY - 24 : sel.minY + 4)
            .allowsHitTesting(false)
    }

    /// Vẽ preview các chú thích (đã chốt + nét đang kéo), cắt theo vùng chọn.
    private var annotationCanvas: some View {
        Canvas { ctx, _ in
            if let sel = selection { ctx.clip(to: Path(sel)) }
            for a in annotations { Self.draw(a, in: &ctx) }
            if let d = draft { Self.draw(d, in: &ctx) }
        }
        .frame(width: viewSize.width, height: viewSize.height)
        .allowsHitTesting(false)
    }

    private static func draw(_ a: Annotation, in ctx: inout GraphicsContext) {
        let stroke = StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
        switch a.tool {
        case .pen:
            guard a.points.count >= 2 else { return }
            var p = Path()
            p.move(to: a.points[0])
            for pt in a.points.dropFirst() { p.addLine(to: pt) }
            ctx.stroke(p, with: .color(a.color.color), style: stroke)
        case .arrow:
            guard a.points.count == 2 else { return }
            ctx.stroke(arrowPath(from: a.points[0], to: a.points[1]),
                       with: .color(a.color.color), style: stroke)
        case .rect:
            guard a.points.count == 2 else { return }
            ctx.stroke(Path(rect(from: a.points[0], to: a.points[1])),
                       with: .color(a.color.color), style: stroke)
        case .text:
            ctx.draw(
                Text(a.text).font(.pixelBody(screenshotTextSize)).foregroundColor(a.color.color),
                at: a.origin, anchor: .topLeading
            )
        }
    }

    /// Đường mũi tên: thân + 2 cạnh đầu mũi. Dùng chung công thức với renderer.
    static func arrowPath(from s: CGPoint, to e: CGPoint) -> Path {
        var p = Path()
        p.move(to: s)
        p.addLine(to: e)
        let angle = atan2(e.y - s.y, e.x - s.x)
        let len: CGFloat = 14
        for delta in [CGFloat.pi * 5 / 6, -CGFloat.pi * 5 / 6] {
            p.move(to: e)
            p.addLine(to: CGPoint(x: e.x + len * cos(angle + delta),
                                  y: e.y + len * sin(angle + delta)))
        }
        return p
    }

    // MARK: Nhập chữ

    private func textEditor(at p: CGPoint) -> some View {
        TextField("", text: $textInput)
            .textFieldStyle(.plain)
            .font(.pixelBody(screenshotTextSize))
            .foregroundColor(color.color)
            .frame(width: max(240, (selection?.maxX ?? 240) - p.x))
            .background(Color.black.opacity(0.25))
            .overlay(Rectangle().strokeBorder(color.color.opacity(0.6), lineWidth: 1))
            .focused($textFocus)
            .onSubmit { commitTextDraft() }
            .onExitCommand {
                textDraft = nil
                textInput = ""
                keyFocus = true
            }
            .offset(x: p.x, y: p.y)
    }

    private func commitTextDraft() {
        if let p = textDraft {
            let s = textInput.trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty {
                annotations.append(Annotation(tool: .text, color: color, text: s, origin: p))
            }
        }
        textDraft = nil
        textInput = ""
        keyFocus = true
    }

    // MARK: Toolbar

    private var toolbarOffset: CGPoint {
        guard let sel = selection else { return .zero }
        let x = min(max(8, sel.minX), max(8, viewSize.width - toolbarSize.width - 8))
        var y = sel.maxY + 10
        if y + toolbarSize.height > viewSize.height - 8 {
            y = max(8, sel.minY - toolbarSize.height - 10)
        }
        return CGPoint(x: x, y: y)
    }

    private var toolbar: some View {
        HStack(spacing: 5) {
            toolButton("scribble", .pen, help: "Bút vẽ")
            toolButton("arrow.up.right", .arrow, help: "Mũi tên")
            toolButton("rectangle", .rect, help: "Khung")
            toolButton("textformat", .text, help: "Chữ")

            toolbarDivider

            ForEach(AnnotationColor.allCases, id: \.self) { c in
                colorButton(c)
            }

            toolbarDivider

            iconButton("arrow.uturn.backward", help: "Hoàn tác nét vẽ") {
                if draft != nil { draft = nil } else if !annotations.isEmpty { annotations.removeLast() }
            }
            iconButton("arrow.counterclockwise", help: "Chọn lại vùng") {
                textDraft = nil
                textInput = ""
                draft = nil
                annotations.removeAll()
                selection = nil
                locked = false
                tool = nil
                keyFocus = true
            }

            toolbarDivider

            labelButton("COPY TEXT", icon: "text.viewfinder", fill: t.inset, fg: t.textPrimary) {
                guard let sel = selection else { return }
                onAction(.ocr, sel, annotations)
            }
            labelButton("LƯU", icon: "square.and.arrow.down", fill: t.inset, fg: t.textPrimary) {
                guard let sel = selection else { return }
                commitTextDraft()
                onAction(.save, sel, annotations)
            }
            labelButton("COPY", icon: "doc.on.doc", fill: Pixel.grass, fg: .white) {
                guard let sel = selection else { return }
                commitTextDraft()
                onAction(.copy, sel, annotations)
            }

            iconButton("xmark", help: "Đóng (Esc)") { onCancel() }
        }
        .padding(6)
        .background(t.panel)
        .overlay(Rectangle().strokeBorder(t.outline, lineWidth: 2))
        .background(
            GeometryReader { g in
                Color.clear
                    .onAppear { toolbarSize = g.size }
                    .onChange(of: g.size) { _, new in toolbarSize = new }
            }
        )
    }

    private var toolbarDivider: some View {
        Rectangle().fill(t.outline.opacity(0.4)).frame(width: 2, height: 20)
    }

    private func toolButton(_ icon: String, _ value: AnnotationTool, help: String) -> some View {
        let active = tool == value
        return Button {
            tool = active ? nil : value
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(active ? .white : t.textPrimary)
                .frame(width: 28, height: 28)
                .background(active ? Pixel.grass : t.inset)
                .overlay(Rectangle().strokeBorder(t.outline, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func colorButton(_ value: AnnotationColor) -> some View {
        Button {
            color = value
        } label: {
            Rectangle()
                .fill(value.color)
                .frame(width: 16, height: 16)
                .overlay(Rectangle().strokeBorder(t.outline, lineWidth: 2))
                .overlay(
                    Rectangle().strokeBorder(Color.white, lineWidth: color == value ? 2 : 0).padding(2)
                )
        }
        .buttonStyle(.plain)
    }

    private func iconButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(t.textPrimary)
                .frame(width: 28, height: 28)
                .background(t.inset)
                .overlay(Rectangle().strokeBorder(t.outline, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func labelButton(_ title: String, icon: String, fill: Color, fg: Color,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10, weight: .bold))
                Text(title).font(.pixelHead(7))
            }
            .foregroundColor(fg)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(fill)
            .overlay(Rectangle().strokeBorder(t.outline, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private var hintBar: some View {
        Text("KÉO CHUỘT ĐỂ CHỌN VÙNG • ESC THOÁT")
            .font(.pixelHead(8))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.75))
            .overlay(Rectangle().strokeBorder(Color.white.opacity(0.4), lineWidth: 1))
            .offset(x: viewSize.width / 2 - 150, y: 14)
            .allowsHitTesting(false)
    }

    // MARK: Tiện ích hình học

    static func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    static func clamp(_ p: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(x: min(max(p.x, rect.minX), rect.maxX),
                y: min(max(p.y, rect.minY), rect.maxY))
    }
}
