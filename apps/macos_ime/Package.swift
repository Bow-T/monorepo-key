// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "monorepo-key",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "BowGo", targets: ["BowGoApp"]),
    ],
    targets: [
        // ENGINE thuần: chỉ chứa logic gõ tiếng Việt, KHÔNG import AppKit/CGEvent.
        // Nhờ vậy có thể test toàn bộ bằng `swift test` trong terminal.
        .target(
            name: "VietEngine"
        ),
        // Bộ test cho engine: gõ "tieengs" -> "tiếng" có đúng không?
        .testTarget(
            name: "VietEngineTests",
            dependencies: ["VietEngine"]
        ),
        // APP macOS: CGEvent tap + menu bar. Link engine vào.
        // Nguồn nằm ở App/ (ngoài Sources/) nên khai báo path tường minh.
        .executableTarget(
            name: "BowGoApp",
            dependencies: ["VietEngine"],
            path: "App"
        ),
    ]
)
