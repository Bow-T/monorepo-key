// StickerCatalogTests.swift
// -------------------------
// Kiểm tra danh mục sticker: mỗi slug KHỚP một file .png thật trong assets/emojis
// (bắt lỗi gõ sai tên -> ô hiện "?"), không trùng, nhãn không rỗng.

import Testing
import Foundation
@testable import VietEngine

@Suite("Danh mục sticker")
struct StickerCatalogTests {

    /// Thư mục assets/emojis suy từ vị trí file test (lùi tới gốc monorepo).
    private var emojiDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // VietEngineTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // macos_ime
            .deletingLastPathComponent()   // apps
            .deletingLastPathComponent()   // <root>
            .appendingPathComponent("assets/emojis")
    }

    @Test("Có sticker và mỗi mục có nhãn")
    func nonEmpty() {
        #expect(StickerCatalog.count > 0)
        for s in StickerCatalog.all {
            #expect(!s.slug.isEmpty)
            #expect(!s.label.isEmpty)
        }
    }

    @Test("Không trùng slug")
    func noDuplicateSlugs() {
        let slugs = StickerCatalog.all.map { $0.slug }
        #expect(Set(slugs).count == slugs.count)
    }

    @Test("Mỗi slug khớp một file .png thật trong assets/emojis")
    func everySlugHasFile() {
        let dir = emojiDir
        for s in StickerCatalog.all {
            let path = dir.appendingPathComponent(s.fileName).path
            #expect(FileManager.default.fileExists(atPath: path),
                    "thiếu file cho sticker \(s.slug): \(path)")
        }
    }

    @Test("fileName = slug + .png")
    func fileNameFormat() {
        #expect(StickerCatalog.Sticker(slug: "crying-face", label: "Khóc").fileName == "crying-face.png")
    }
}
