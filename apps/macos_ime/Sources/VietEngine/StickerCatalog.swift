// StickerCatalog.swift
// --------------------
// DANH MỤC STICKER (emoji ẢNH PNG) cho bảng dán sticker. Chỉ DỮ LIỆU thuần (tên file
// + nhãn tiếng Việt) -> test được; tầng App lo nạp ảnh từ bundle & dán.
//
// Ảnh nằm ở assets/emojis/<slug>.png (256×256). `slug` khớp CLDR short name viết
// gạch nối, vd "crying-face". Nhãn tiếng Việt để hiển thị tooltip/tìm kiếm sau này.

import Foundation

public enum StickerCatalog {

    /// Một sticker: slug (tên file, không đuôi) + nhãn tiếng Việt.
    public struct Sticker: Equatable, Sendable {
        public let slug: String     // "crying-face" -> file "crying-face.png"
        public let label: String    // "Mặt khóc"
        public init(slug: String, label: String) {
            self.slug = slug
            self.label = label
        }
        public var fileName: String { "\(slug).png" }
    }

    /// Toàn bộ sticker theo thứ tự hiển thị. Slug PHẢI khớp tên file trong
    /// assets/emojis. Nhãn tiếng Việt để tooltip/tìm kiếm.
    public static let all: [Sticker] = [
        Sticker(slug: "slightly-smiling-face",        label: "Cười nhẹ"),
        Sticker(slug: "beaming-face-with-smiling-eyes", label: "Cười tươi"),
        Sticker(slug: "smiling-face-with-heart-eyes", label: "Mắt trái tim"),
        Sticker(slug: "smiling-cat-with-heart-eyes",  label: "Mèo mắt tim"),
        Sticker(slug: "zipper-mouth-face",            label: "Khoá miệng"),
        Sticker(slug: "face-exhaling",                label: "Thở hắt ra"),
        Sticker(slug: "slightly-frowning-face",       label: "Hơi nhăn"),
        Sticker(slug: "worried-face",                 label: "Lo lắng"),
        Sticker(slug: "pensive-face",                 label: "Trầm ngâm"),
        Sticker(slug: "confounded-face",              label: "Bối rối"),
        Sticker(slug: "anxious-face-with-sweat",      label: "Lo toát mồ hôi"),
        Sticker(slug: "fearful-face",                 label: "Sợ hãi"),
        Sticker(slug: "weary-face",                   label: "Rã rời"),
        Sticker(slug: "tired-face",                   label: "Mệt mỏi"),
        Sticker(slug: "crying-face",                  label: "Khóc"),
        Sticker(slug: "loudly-crying-face",           label: "Khóc oà"),
        Sticker(slug: "enraged-face",                 label: "Giận dữ"),
        Sticker(slug: "face-with-thermometer",        label: "Sốt (ốm)"),
    ]

    /// Số lượng sticker.
    public static var count: Int { all.count }
}
