// SettingsStore.swift
// -------------------
// Đọc cấu hình do app UI (Flutter) ghi ra, và THEO DÕI file để áp dụng ngay khi
// người dùng đổi cài đặt trong UI — không cần khởi động lại bộ gõ.
// File dùng chung (cùng đường dẫn phía Flutter ghi):
//     ~/Library/Application Support/BowGo/settings.json
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
    ///   - hotkeyKeyCode: mã phím vật lý macOS (vd Space = 49). 0 = chỉ-modifier.
    ///   - hotkeyModifiers: tập modifier yêu cầu ("control","option","shift","command").
    /// Mặc định ⌃⇧ (Control+Shift, chỉ-modifier — giống Unikey).
    var hotkeyKeyCode: Int64 = 0
    var hotkeyModifiers: Set<String> = ["control", "shift"]

    /// Smart Switch: tự nhớ bật/tắt theo từng app (bundle id).
    var smartSwitch: Bool = false

    /// Trạng thái đã nhớ cho từng app: bundleId -> enabled. Chỉ dùng khi smartSwitch.
    var perApp: [String: Bool] = [:]

    /// Bật/tắt gõ tắt (macro). Mặc định bật.
    var macroEnabled: Bool = true

    /// Tự khôi phục tiếng Anh: từ biến dạng & không hợp lệ tiếng Việt -> trả phím
    /// thô khi chốt từ. Mặc định tắt (heuristic, không từ điển).
    var autoRestoreEnglish: Bool = false

    /// Định nghĩa macro: từ khoá thô -> nội dung. Loại tĩnh.
    /// JSON: "macros": [ {"keyword":"vn","content":"Việt Nam"}, ... ]
    var macros: [MacroDefinition] = []

    /// SỬA LỖI GÕ ĐÔI TRÌNH DUYỆT: ở ô có autocomplete (thanh địa chỉ/tìm kiếm
    /// Chromium — Edge/Chrome/Brave/Cốc Cốc, Spotlight), Backspace tổng hợp bị
    /// highlight gợi ý nuốt -> ký tự cũ không xoá được -> nhân đôi ("d"+"o"->"ddo").
    /// Khi bật, ta gửi trước một ký tự rỗng để phá highlight rồi mới Backspace.
    /// Mặc định BẬT — áp cho MỌI app trừ danh sách loại trừ.
    var fixBrowserDoubleType: Bool = true

    /// Danh sách bundle id KHÔNG áp mẹo phá-highlight (app báo lỗi/không tương thích).
    /// Người dùng có thể thêm nếu một app hiếm chèn nhầm ký tự rỗng. Mặc định trống.
    var browserFixExcludedApps: Set<String> = []

    /// Cấu hình lịch sử Clipboard.
    var clipboardHistoryEnabled: Bool = true
    var clipboardHistoryLimit: Int = 40
    var clipboardHistoryHotkeyKeyCode: Int64 = 9 // V
    var clipboardHistoryHotkeyModifiers: Set<String> = ["control"]

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
        if let s = obj["smartSwitch"] as? Bool { cfg.smartSwitch = s }
        if let p = obj["perApp"] as? [String: Bool] { cfg.perApp = p }
        if let me = obj["macroEnabled"] as? Bool { cfg.macroEnabled = me }
        if let ar = obj["autoRestoreEnglish"] as? Bool { cfg.autoRestoreEnglish = ar }
        if let arr = obj["macros"] as? [[String: Any]] {
            cfg.macros = arr.compactMap { item in
                guard let kw = item["keyword"] as? String, !kw.isEmpty,
                      let content = item["content"] as? String else { return nil }
                let type = parseMacroType(item["type"] as? String)
                return MacroDefinition(keyword: kw, content: content, type: type)
            }
        }
        if let fb = obj["fixBrowserDoubleType"] as? Bool { cfg.fixBrowserDoubleType = fb }
        if let ex = obj["browserFixExcludedApps"] as? [String] { cfg.browserFixExcludedApps = Set(ex) }
        if let che = obj["clipboardHistoryEnabled"] as? Bool { cfg.clipboardHistoryEnabled = che }
        if let chl = obj["clipboardHistoryLimit"] as? Int { cfg.clipboardHistoryLimit = chl }
        if let chk = obj["clipboardHistoryHotkeyKeyCode"] as? Int { cfg.clipboardHistoryHotkeyKeyCode = Int64(chk) }
        if let chmods = obj["clipboardHistoryHotkeyModifiers"] as? [String] {
            cfg.clipboardHistoryHotkeyModifiers = Set(chmods)
        }
        return cfg
    }

    private static func parseMacroType(_ s: String?) -> MacroSnippetType {
        switch s {
        case "date":     return .date
        case "time":     return .time
        case "dateTime": return .dateTime
        case "random":   return .random
        case "counter":  return .counter
        default:         return .staticText
        }
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
            .appendingPathComponent("BowGo", isDirectory: true)
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

    /// Đọc-sửa-ghi file JSON, giữ nguyên các khoá khác. `mutate` trả về false nếu
    /// không có gì đổi (để khỏi ghi thừa -> tránh kích hoạt watch vô ích).
    private func update(_ mutate: (inout [String: Any]) -> Bool) {
        let url = Self.fileURL
        var obj: [String: Any] = [:]
        if let data = try? Data(contentsOf: url),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            obj = parsed
        }
        guard mutate(&obj) else { return }
        guard let out = try? JSONSerialization.data(
            withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]
        ) else { return }
        try? out.write(to: url, options: .atomic)
    }

    /// Cập nhật cờ `enabled` trong file (khi bật/tắt qua phím tắt/menu) để app UI
    /// Flutter phản ánh đúng. Giữ nguyên các khoá khác.
    func writeEnabled(_ enabled: Bool) {
        update { obj in
            if (obj["enabled"] as? Bool) == enabled { return false }
            obj["enabled"] = enabled
            return true
        }
    }

    /// Cập nhật cờ `autoRestoreEnglish` (khi bật/tắt qua menu). Giữ nguyên khoá khác.
    func writeAutoRestoreEnglish(_ enabled: Bool) {
        update { obj in
            if (obj["autoRestoreEnglish"] as? Bool) == enabled { return false }
            obj["autoRestoreEnglish"] = enabled
            return true
        }
    }

    /// Cập nhật cờ `macroEnabled` (khi bật/tắt gõ tắt qua menu). Giữ nguyên khoá khác.
    func writeMacroEnabled(_ enabled: Bool) {
        update { obj in
            if (obj["macroEnabled"] as? Bool) == enabled { return false }
            obj["macroEnabled"] = enabled
            return true
        }
    }

    /// Ghi nhớ trạng thái bật/tắt cho một app (Smart Switch). Giữ nguyên khoá khác.
    func writePerApp(bundleId: String, enabled: Bool) {
        update { obj in
            var map = (obj["perApp"] as? [String: Bool]) ?? [:]
            if map[bundleId] == enabled { return false }
            map[bundleId] = enabled
            obj["perApp"] = map
            return true
        }
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
