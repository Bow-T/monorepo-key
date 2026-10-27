// swift-tools-version: 6.0
import PackageDescription

// Core gõ Rust (packages/viet_core). Build trước khi `swift build`/`swift test`:
//   bash scripts/build-core.sh   (cargo build + buộc link lại khi core đổi)
let vietCoreLibDir = Context.packageDirectory + "/../../packages/viet_core/target/release"

let package = Package(
    name: "monorepo-key",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "BowGo", targets: ["BowGoApp"]),
    ],
    targets: [
        // C ABI của core Rust (header + link "viet_core").
        .systemLibrary(
            name: "CVietCore"
        ),
        // ENGINE thuần: chỉ chứa logic gõ tiếng Việt, KHÔNG import AppKit/CGEvent.
        // Nhờ vậy có thể test toàn bộ bằng `swift test` trong terminal.
        .target(
            name: "VietEngine",
            dependencies: ["CVietCore"],
            linkerSettings: [.unsafeFlags(["-L", vietCoreLibDir])]
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
        // Test phần THUẦN của tầng App (đồng bộ settings.json, cờ dò nền…) qua
        // `@testable import BowGoApp`. Không đụng event tap; riêng
        // ScreenshotOverlayLifecycleTests mở cửa sổ thật (cần phiên đồ hoạ).
        .testTarget(
            name: "BowGoAppTests",
            dependencies: ["BowGoApp"]
        ),
    ]
)
