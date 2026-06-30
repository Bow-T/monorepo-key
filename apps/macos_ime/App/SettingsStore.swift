// SettingsStore.swift
// -------------------
// Đọc cấu hình do app UI (Flutter) ghi ra, và THEO DÕI file để áp dụng ngay khi
// người dùng đổi cài đặt trong UI — không cần khởi động lại bộ gõ.
//
// File dùng chung (cùng đường dẫn phía Flutter ghi):
//     ~/Library/Application Support/BowKey/settings.json
//
// Hợp đồng JSON phải KHỚP với apps/settings_ui/lib/src/models/settings.dart:
//     { "enabled": Bool, "method": "telex"|"vni",
//       "toneStyle": "modern"|"old", "toggleHotkey": String }

import Foundation
import VietEngine

/// Ảnh chụp cấu hình bộ gõ đọc từ đĩa.
struct BowConfig: Equatable {
    var enabled: Bool = true
    var method: InputMethod = .telex
    var toneStyle: VietEngine.ToneStyle = .modern

    /// Phím tắt bật/tắt — dạng máy đọc được để event tap so khớp.
    ///   - hotkeyKeyCode: mã phím vật lý macOS (vd Space = 49).
    ///   - hotkeyModifiers: tập modifier yêu cầu ("control","option","shift","command").
    /// Mặc định ⌃⌥ Space (giữ tương thích bản trước).
    var hotkeyKeyCode: Int64 = 49
    var hotkeyModifiers: Set<String> = ["control", "option"]

    static func decode(_ data: Data) -> BowConfig? {
        guard
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        var cfg = BowConfig()
        if let e = obj["enabled"] as? Bool { cfg.enabled = e }
        if let m = obj["method"] as? String { cfg.method = m == "vni" ? .vni : .telex }
        if let t = obj["toneStyle"] as? String { cfg.toneStyle = t == "old" ? .old : .modern }
        if let k = obj["hotkeyKeyCode"] as? Int { cfg.hotkeyKeyCode = Int64(k) }
        if let mods = obj["hotkeyModifiers"] as? [String] {
            cfg.hotkeyModifiers = Set(mods)
        }
        return cfg
    }
}

/// Đọc file cấu hình + theo dõi thay đổi, gọi `onChange` mỗi khi file cập nhật.
final class SettingsStore {

    /// Đường dẫn file dùng chung với app UI Flutter.
    static var fileURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("BowKey", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1

    /// Callback khi cấu hình thay đổi (chạy trên main queue).
    var onChange: ((BowConfig) -> Void)?

    /// Đọc cấu hình hiện tại (nil nếu chưa có file / lỗi).
    func read() -> BowConfig? {
        guard let data = try? Data(contentsOf: Self.fileURL) else { return nil }
        return BowConfig.decode(data)
    }

    /// Cập nhật cờ `enabled` trong file (khi người dùng dùng phím tắt bật/tắt) để
    /// app UI Flutter phản ánh đúng. Giữ nguyên các khoá khác đang có trong file.
    /// Tự bỏ qua sự kiện watch do chính ta ghi (so khớp nội dung) để khỏi vòng lặp.
    func writeEnabled(_ enabled: Bool) {
        let url = Self.fileURL
        var obj: [String: Any] = [:]
        if let data = try? Data(contentsOf: url),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            obj = parsed
        }
        if (obj["enabled"] as? Bool) == enabled { return } // không đổi -> khỏi ghi
        obj["enabled"] = enabled
        guard let out = try? JSONSerialization.data(
            withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]
        ) else { return }
        try? out.write(to: url, options: .atomic)
    }

    /// Bắt đầu theo dõi file. Khi UI ghi đè file, ta đọc lại và báo onChange.
    func startWatching() {
        stopWatching()

        let url = Self.fileURL
        // Mở để theo dõi. Nếu file chưa tồn tại thì chờ — sẽ thử lại khi áp dụng.
        fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = src.data
            // Nhiều trình soạn (kể cả Flutter) ghi theo kiểu thay file -> ta phải
            // mở theo dõi lại trên inode mới.
            if flags.contains(.delete) || flags.contains(.rename) {
                self.startWatching()
            }
            if let cfg = self.read() {
                self.onChange?(cfg)
            }
        }
        src.setCancelHandler { [weak self] in
            if let fd = self?.fd, fd >= 0 { close(fd) }
            self?.fd = -1
        }
        source = src
        src.resume()
    }

    func stopWatching() {
        source?.cancel()
        source = nil
    }
}
