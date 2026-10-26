// ScreenshotOverlayLifecycleTests.swift
// -------------------------------------
// "Bấm chụp màn hình lại ra ảnh chụp CŨ": NSApp.hide tới lúc overlay đang là key
// (panel của Bow Go mất key tự đóng bằng hide) -> overlay mất key GIỮA lúc hide, bị
// gỡ ngay lúc đó nhưng AppKit vẫn ghi nó vào danh sách hiện-lại-khi-unhide. Mỗi lần
// app được kích hoạt sau đó (mỗi lần chụp), overlay mồ côi mang ảnh cũ tự hiện lại.
//
// Test này MỞ CỬA SỔ THẬT (overlay toàn màn hình chừng 1 giây) và kích hoạt app test,
// nên cần phiên đồ hoạ. Dùng XCTest đồng bộ (không phải swift-testing) vì phải tự
// bơm sự kiện AppKit trên main thread — trong async main của swift-testing, bơm
// nextEvent làm run loop chính dừng và tiến trình test thoát ngang.

import AppKit
import XCTest
@testable import BowGoApp

private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var _open = false
    var isOpen: Bool { lock.lock(); defer { lock.unlock() }; return _open }
    func open() { lock.lock(); _open = true; lock.unlock() }
}

private func solidImage() -> CGImage {
    let ctx = CGContext(data: nil, width: 64, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 1, green: 0, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 40))
    return ctx.makeImage()!
}

@MainActor
final class ScreenshotOverlayLifecycleTests: XCTestCase {

    private static let launched: Void = {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
    }()

    override func setUp() async throws {
        try XCTSkipIf(NSScreen.screens.isEmpty, "cần màn hình (phiên đồ hoạ)")
        _ = Self.launched
    }

    private var overlays: [NSWindow] { NSApp.windows.filter { $0.level == .screenSaver } }
    private var overlayVisible: Bool { overlays.contains { $0.isVisible } }
    private var overlayKey: Bool { overlays.contains { $0.isKeyWindow } }

    /// Bơm sự kiện AppKit (kích hoạt app, đổi key…) + main queue tới khi `condition` đúng.
    private func pump(_ seconds: TimeInterval, until condition: () -> Bool = { false }) {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline {
            if let event = NSApp.nextEvent(matching: .any, until: Date().addingTimeInterval(0.01),
                                           inMode: .default, dequeue: true) {
                NSApp.sendEvent(event)
            }
        }
    }

    private func makeController(gate: Gate? = nil) -> ScreenshotController {
        ScreenshotController(
            capture: { _, _, _ in
                while let gate, !gate.isOpen { try await Task.sleep(for: .milliseconds(10)) }
                return solidImage()
            },
            hasPermission: { true }
        )
    }

    /// Dọn: bấm phím tắt lần nữa khi overlay đang hiện = huỷ phiên.
    private func cleanUp(_ controller: ScreenshotController) {
        if overlayVisible { controller.beginCapture() }
        NSApp.unhide(nil)
        pump(2) { !overlayVisible }
    }

    /// App bị NSApp.hide lúc overlay đang key -> kích hoạt lại KHÔNG được hiện overlay cũ.
    func testHideWhileOverlayKeyDoesNotResurrectOldOverlay() throws {
        let controller = makeController()
        defer { cleanUp(controller) }
        controller.beginCapture()
        pump(3) { overlayKey }
        try XCTSkipUnless(overlayKey, "app test không được kích hoạt (đang gõ ở app khác?) — không tái hiện được")

        NSApp.hide(nil)   // như panel mất key tự đóng bằng hide
        pump(0.3)
        NSApp.activate(ignoringOtherApps: true)
        pump(0.6)

        XCTAssertFalse(overlayVisible, "overlay đã gỡ hiện lại sau khi kích hoạt = ảnh chụp cũ ở lần chụp sau")
    }

    /// Sau khi bị hide lúc đang key, bấm chụp lại phải ra ĐÚNG MỘT overlay MỚI —
    /// không phải overlay cũ hiện lại, cũng không bị hiểu là "bấm lần nữa = huỷ".
    func testCaptureAfterHideWhileKeyShowsExactlyOneFreshOverlay() throws {
        let controller = makeController()
        defer { cleanUp(controller) }
        controller.beginCapture()
        pump(3) { overlayKey }
        try XCTSkipUnless(overlayKey, "app test không được kích hoạt (đang gõ ở app khác?) — không tái hiện được")
        let old = overlays.first

        NSApp.hide(nil)
        pump(0.3)
        controller.beginCapture()
        pump(3) { overlayKey }

        XCTAssertEqual(overlays.filter { $0.isVisible }.count, 1, "overlay cũ mồ côi hiện cùng overlay mới")
        XCTAssertFalse(overlays.contains { $0 === old && $0.isVisible }, "đang hiện lại CHÍNH overlay cũ (ảnh cũ)")
    }

    /// Menu pixel mở ra trong lúc chờ ảnh (ScreenCaptureKit chậm): overlay giật key ->
    /// 0.15s sau menu tự đóng bằng NSApp.hide. Overlay vừa hiện phải còn nguyên, menu
    /// phải được đóng. (Lịch sử clipboard / bảng ký hiệu hide ĐỒNG BỘ trước khi overlay
    /// activate nên không tái hiện được lỗi này.)
    func testMenuOpenedDuringCaptureDoesNotHideOverlay() throws {
        let gate = Gate()
        let controller = makeController(gate: gate)
        defer { cleanUp(controller) }
        controller.beginCapture()   // chờ gate

        PixelMenuWindow.present(title: "TEST", items: [.item("Một mục") {}])
        pump(0.3)
        gate.open()

        pump(3) { overlayKey }
        try XCTSkipUnless(overlayKey, "app test không được kích hoạt (đang gõ ở app khác?) — không tái hiện được")
        pump(0.6)

        XCTAssertTrue(overlayVisible, "menu đóng bằng NSApp.hide giấu luôn overlay vừa hiện")
        XCTAssertFalse(NSApp.isHidden)
        XCTAssertFalse(NSApp.windows.contains { $0 is PixelMenuWindow && $0.isVisible }, "menu chưa được đóng")
    }
}
