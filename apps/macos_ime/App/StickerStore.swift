// StickerStore.swift
// ------------------
// Nạp ảnh sticker (emoji PNG) từ bundle app, có cache. Dữ liệu danh mục ở
// `StickerCatalog` (engine); đây lo phần I/O ảnh phụ thuộc AppKit.
//
// Vị trí ảnh trong app đã build: Contents/Resources/emojis/<slug>.png (build-app.sh
// copy từ assets/emojis). Khi chạy DEV (swift run, chưa đóng .app) không có bundle
// resources -> thử đường nguồn assets/emojis theo #filePath để vẫn xem được.

import AppKit
import VietEngine

/// Chỉ dùng từ MainActor (SwiftUI view + AppDelegate) -> cache an toàn concurrency.
@MainActor
enum StickerStore {

    /// Cache ảnh đã nạp theo slug (tránh đọc đĩa lặp lại mỗi lần mở picker).
    private static var cache: [String: NSImage] = [:]

    /// Nạp ảnh cho một sticker (nil nếu không tìm thấy file).
    static func image(for sticker: StickerCatalog.Sticker) -> NSImage? {
        if let cached = cache[sticker.slug] { return cached }
        guard let url = url(for: sticker.fileName),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        cache[sticker.slug] = image
        return image
    }

    /// Tìm URL file ảnh: ưu tiên bundle (Resources/emojis), lùi về nguồn assets (dev).
    private static func url(for fileName: String) -> URL? {
        // 1) Trong bundle: Resources/emojis/<file>.
        if let resDir = Bundle.main.resourceURL {
            let bundled = resDir.appendingPathComponent("emojis").appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        }
        // 2) DEV fallback: <repo>/assets/emojis/<file>, suy từ vị trí file nguồn.
        //    StickerStore.swift ở apps/macos_ime/App -> lùi 3 cấp tới gốc monorepo.
        let src = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // App
            .deletingLastPathComponent()   // macos_ime
            .deletingLastPathComponent()   // apps
            .deletingLastPathComponent()   // <root>
            .appendingPathComponent("assets/emojis")
            .appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: src.path) { return src }
        return nil
    }
}
