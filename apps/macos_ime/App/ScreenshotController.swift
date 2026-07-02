// ScreenshotController.swift
// --------------------------
// Điều phối tính năng CHỤP MÀN HÌNH:
//
//   1. Phím tắt (mặc định ⌃⇧S) -> kiểm tra quyền Ghi màn hình (Screen Recording).
//   2. Chụp "đóng băng" màn hình chứa con trỏ chuột bằng ScreenCaptureKit.
//   3. Hiện overlay chọn vùng + vẽ chú thích (ScreenshotOverlayView).
//   4. Kết thúc: COPY ảnh vào clipboard (lịch sử Clipboard tự bắt), COPY TEXT
//      (OCR tiếng Việt qua Vision), hoặc LƯU ra file PNG.
//
// Quyền Ghi màn hình là quyền TCC RIÊNG (ngoài Accessibility/Input Monitoring),
// chỉ cần cho tính năng này — thiếu quyền thì bộ gõ vẫn chạy bình thường.

import AppKit
import ScreenCaptureKit
import SwiftUI

@MainActor
final class ScreenshotController {

    private var overlayWindow: NSWindow?

    /// App đang focus TRƯỚC khi mở overlay — để trả lại focus khi đóng (giống
    /// hành vi của cửa sổ lịch sử Clipboard) mà vẫn hiện được toast của ta.
    private var previousApp: NSRunningApplication?

    /// Bắt đầu phiên chụp. Nhấn phím tắt lần nữa khi overlay đang mở -> huỷ.
    func beginCapture() {
        if overlayWindow != nil {
            dismiss()
            return
        }

        guard Permissions.hasScreenRecording() else {
            // Prompt hệ thống chỉ hiện MỘT LẦN cho mỗi app; kèm alert hướng dẫn
            // cho các lần sau (phải bật thủ công trong System Settings).
            Permissions.requestScreenRecording()
            showPermissionAlert()
            return
        }

        // Chụp màn hình chứa con trỏ chuột, TRƯỚC khi hiện overlay (freeze-frame).
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
                ?? NSScreen.main,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return }

        let displayID = CGDirectDisplayID(number.uint32Value)
        let frame = screen.frame
        let scale = screen.backingScaleFactor

        Task { @MainActor [weak self] in
            do {
                let image = try await Self.captureDisplay(
                    displayID,
                    pixelWidth: Int(frame.width * scale),
                    pixelHeight: Int(frame.height * scale)
                )
                self?.presentOverlay(screenshot: image, screenFrame: frame)
            } catch {
                NSLog("[Screenshot] Chụp màn hình thất bại: \(error)")
                ToastHUD.show("CHỤP MÀN HÌNH THẤT BẠI")
            }
        }
    }

    /// Chụp một display ra CGImage full-resolution. `nonisolated` để mọi object
    /// ScreenCaptureKit (không Sendable) sống trọn trong hàm; chỉ CGImage
    /// (Sendable) băng qua actor.
    private nonisolated static func captureDisplay(
        _ displayID: CGDirectDisplayID, pixelWidth: Int, pixelHeight: Int
    ) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        )
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw NSError(domain: "BowGo.Screenshot", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Không tìm thấy màn hình để chụp",
            ])
        }
        let config = SCStreamConfiguration()
        config.width = pixelWidth
        config.height = pixelHeight
        config.showsCursor = false
        config.captureResolution = .best
        let filter = SCContentFilter(display: display, excludingWindows: [])
        return try await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: config
        )
    }

    // MARK: - Overlay

    private func presentOverlay(screenshot: CGImage, screenFrame: NSRect) {
        previousApp = NSWorkspace.shared.frontmostApplication
        // Tỉ lệ pixel-ảnh / điểm-view tính từ ảnh THẬT trả về (không giả định 2x).
        let imageScale = CGFloat(screenshot.width) / screenFrame.width

        let view = ScreenshotOverlayView(
            screenshot: screenshot,
            viewSize: screenFrame.size,
            onAction: { [weak self] action, sel, annotations in
                self?.finish(action: action, screenshot: screenshot,
                             selection: sel, annotations: annotations, scale: imageScale)
            },
            onCancel: { [weak self] in self?.dismiss() }
        )

        let window = ScreenshotOverlayWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = CrosshairHostingView(rootView: view)
        window.setFrame(screenFrame, display: true)
        window.level = .screenSaver
        window.isOpaque = true
        window.hasShadow = false
        window.backgroundColor = .black
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        overlayWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func dismiss() {
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        // Trả focus cho app trước đó (không NSApp.hide để toast còn hiện được).
        if let app = previousApp, app.isTerminated == false {
            app.activate()
        } else {
            NSApp.hide(nil)
        }
        previousApp = nil
    }

    // MARK: - Kết thúc phiên chụp

    private func finish(action: ScreenshotAction, screenshot: CGImage,
                        selection: CGRect, annotations: [Annotation], scale: CGFloat) {
        // Toạ độ view (điểm) -> pixel ảnh. Gốc trên-trái ở CẢ HAI hệ (CGImage
        // cropping cũng tính từ góc trên-trái) nên không cần lật trục ở bước này.
        let pixelRect = CGRect(
            x: selection.minX * scale, y: selection.minY * scale,
            width: selection.width * scale, height: selection.height * scale
        ).integral
        guard let crop = screenshot.cropping(to: pixelRect) else {
            dismiss()
            return
        }

        switch action {
        case .ocr:
            // Mở cửa sổ bôi-đen-chữ kiểu Preview (Live Text) trên vùng vừa chọn —
            // trỏ vào chữ để copy đúng đoạn cần. Đóng overlay nhưng GIỮ previousApp
            // để trả focus sau khi cửa sổ Live Text đóng.
            overlayWindow?.orderOut(nil)
            overlayWindow = nil
            let prev = previousApp
            previousApp = nil
            let image = NSImage(cgImage: crop, size: selection.size)
            LiveTextWindow.present(image: image) {
                if let app = prev, app.isTerminated == false {
                    app.activate()
                } else {
                    NSApp.hide(nil)
                }
            }

        case .copy:
            let image = ScreenshotRenderer.render(
                crop: crop, annotations: annotations, selection: selection, scale: scale
            )
            dismiss()
            guard let image else { return }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([image])
            // Lịch sử Clipboard (nếu bật) tự bắt ảnh này qua vòng poll pasteboard.
            ToastHUD.show("ĐÃ COPY ẢNH VÀO CLIPBOARD")

        case .save:
            let image = ScreenshotRenderer.render(
                crop: crop, annotations: annotations, selection: selection, scale: scale
            )
            overlayWindow?.orderOut(nil)
            overlayWindow = nil
            guard let image else { return }
            saveToFile(image)
        }
    }

    private func saveToFile(_ image: NSImage) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd 'lúc' HH.mm.ss"
        panel.nameFieldStringValue = "Chụp màn hình \(stamp.string(from: Date())).png"
        panel.level = .modalPanel
        NSApp.activate(ignoringOtherApps: true)

        let saved: Bool
        if panel.runModal() == .OK, let url = panel.url,
           let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            saved = (try? png.write(to: url)) != nil
        } else {
            saved = false
        }

        if let app = previousApp, app.isTerminated == false {
            app.activate()
        } else {
            NSApp.hide(nil)
        }
        previousApp = nil
        if saved { ToastHUD.show("ĐÃ LƯU ẢNH") }
    }

    // MARK: - Quyền

    private func showPermissionAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Cần quyền Ghi màn hình"
        alert.informativeText = """
        Tính năng chụp màn hình cần quyền "Screen Recording" (Ghi màn hình) — \
        quyền riêng, ngoài 2 quyền gõ phím đã cấp.

          1. Bấm "Mở System Settings" rồi BẬT Bow Go trong danh sách.
          2. macOS sẽ đề nghị mở lại app — chọn "Quit & Reopen".
          3. Nhấn lại phím tắt chụp màn hình.
        """
        alert.addButton(withTitle: "Mở System Settings")
        alert.addButton(withTitle: "Để sau")
        alert.alertStyle = .informational
        if alert.runModal() == .alertFirstButtonReturn {
            Permissions.openSettings(.screenRecording)
        }
    }

}

// MARK: - Toast HUD dùng chung

/// HUD nhỏ giữa-dưới màn hình, tự biến mất — xác nhận đã copy/lưu xong.
/// Dùng chung cho chụp màn hình + OCR ảnh trong lịch sử Clipboard.
@MainActor
enum ToastHUD {
    private static var panel: NSPanel?

    static func show(_ message: String) {
        panel?.orderOut(nil)

        let host = NSHostingView(rootView: ScreenshotToastView(message: message))
        host.frame.size = host.fittingSize

        let toast = NSPanel(
            contentRect: NSRect(origin: .zero, size: host.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        toast.contentView = host
        toast.level = .statusBar
        toast.backgroundColor = .clear
        toast.isOpaque = false
        toast.hasShadow = false
        toast.ignoresMouseEvents = true
        toast.hidesOnDeactivate = false

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let f = screen?.visibleFrame {
            toast.setFrameOrigin(NSPoint(
                x: f.midX - host.fittingSize.width / 2,
                y: f.minY + 60
            ))
        }

        toast.orderFrontRegardless()
        panel = toast

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            guard panel === toast else { return }
            toast.orderOut(nil)
            panel = nil
        }
    }
}

// MARK: - Cửa sổ overlay

/// Cửa sổ borderless phải tự nhận key để bắt Esc/Enter + gõ chữ chú thích.
private final class ScreenshotOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// HostingView đổi con trỏ thành crosshair trong lúc chọn vùng.
private final class CrosshairHostingView<Content: View>: NSHostingView<Content> {
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .crosshair)
    }
}

// MARK: - Toast view

private struct ScreenshotToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.pixelHead(8))
            .foregroundColor(Color(hex: 0xF0E8CE))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(hex: 0x243524))
            .overlay(Rectangle().strokeBorder(Color(hex: 0x0E1A0C), lineWidth: 2))
            .fixedSize()
    }
}

// MARK: - Render ảnh cuối (crop + chú thích)

enum ScreenshotRenderer {

    /// Vẽ chú thích lên ảnh đã crop, trả về NSImage kích thước pixel gốc.
    /// Toạ độ chú thích ở hệ VIEW (điểm, gốc trên-trái) -> đổi sang hệ CG của ảnh
    /// (pixel, gốc dưới-trái): dời theo góc vùng chọn, nhân `scale`, lật trục y.
    static func render(crop: CGImage, annotations: [Annotation],
                       selection: CGRect, scale: CGFloat) -> NSImage? {
        let w = crop.width
        let h = crop.height
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = NSSize(width: w, height: h)  // 1 điểm = 1 pixel

        guard let gctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gctx
        defer { NSGraphicsContext.restoreGraphicsState() }

        let ctx = gctx.cgContext
        ctx.interpolationQuality = .high
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))

        // Điểm view -> pixel CG (lật y).
        func px(_ p: CGPoint) -> CGPoint {
            CGPoint(x: (p.x - selection.minX) * scale,
                    y: (selection.maxY - p.y) * scale)
        }

        ctx.setLineWidth(3 * scale)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        for a in annotations {
            ctx.setStrokeColor(a.color.nsColor.cgColor)
            switch a.tool {
            case .pen:
                guard a.points.count >= 2 else { continue }
                ctx.beginPath()
                ctx.move(to: px(a.points[0]))
                for p in a.points.dropFirst() { ctx.addLine(to: px(p)) }
                ctx.strokePath()

            case .arrow:
                guard a.points.count == 2 else { continue }
                let s = px(a.points[0])
                let e = px(a.points[1])
                let angle = atan2(e.y - s.y, e.x - s.x)
                let len = 14 * scale
                ctx.beginPath()
                ctx.move(to: s)
                ctx.addLine(to: e)
                for delta in [CGFloat.pi * 5 / 6, -CGFloat.pi * 5 / 6] {
                    ctx.move(to: e)
                    ctx.addLine(to: CGPoint(x: e.x + len * cos(angle + delta),
                                            y: e.y + len * sin(angle + delta)))
                }
                ctx.strokePath()

            case .rect:
                guard a.points.count == 2 else { continue }
                let p1 = px(a.points[0])
                let p2 = px(a.points[1])
                ctx.stroke(CGRect(x: min(p1.x, p2.x), y: min(p1.y, p2.y),
                                  width: abs(p1.x - p2.x), height: abs(p1.y - p2.y)))

            case .text:
                let font = NSFont(name: Pixel.body, size: screenshotTextSize * scale)
                    ?? NSFont.systemFont(ofSize: screenshotTextSize * scale, weight: .medium)
                let attr = NSAttributedString(string: a.text, attributes: [
                    .font: font,
                    .foregroundColor: a.color.nsColor,
                ])
                // origin là góc TRÊN-trái của chữ -> draw(at:) cần góc DƯỚI-trái.
                let top = px(a.origin)
                attr.draw(at: NSPoint(x: top.x, y: top.y - attr.size().height))
            }
        }

        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
