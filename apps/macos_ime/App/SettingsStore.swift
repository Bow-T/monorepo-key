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

/// Một cặp tự-sửa-lỗi: gõ ra `wrong` -> tự thay bằng `right` khi chốt từ.
struct AutoCorrectPair: Equatable {
    var wrong: String
    var right: String
}

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

    /// Khởi động cùng hệ thống (đăng ký login item qua SMAppService). Mặc định bật —
    /// bộ gõ nên sẵn sàng ngay khi đăng nhập máy.
    var launchAtLogin: Bool = true

    /// Smart Switch: tự nhớ bật/tắt theo từng app (bundle id).
    var smartSwitch: Bool = false

    /// Trạng thái đã nhớ cho từng app: bundleId -> enabled. Chỉ dùng khi smartSwitch.
    var perApp: [String: Bool] = [:]

    /// Bật/tắt gõ tắt (macro). Mặc định bật.
    var macroEnabled: Bool = true

    /// Tự khôi phục tiếng Anh: từ biến dạng & không hợp lệ tiếng Việt -> trả phím
    /// thô khi chốt từ. Mặc định tắt (heuristic, không từ điển).
    var autoRestoreEnglish: Bool = false

    /// Tự sửa lỗi gõ nhanh: khi chốt từ, sửa dấu thanh đặt sai vị trí hoặc lỗi gõ
    /// nhanh phổ biến ("giừo"->"giờ", "nhièu"->"nhiều"). Mặc định tắt (từ điển tĩnh).
    var autoCorrect: Bool = false

    /// Danh sách cặp (sai -> đúng) do người dùng cấu hình cho tự-sửa-lỗi.
    /// JSON: "autoCorrectPairs": [ {"wrong":"giừo","right":"giờ"}, ... ]
    /// Lần đầu (khoá vắng mặt) sẽ được gieo bằng bộ mặc định built-in.
    var autoCorrectPairs: [AutoCorrectPair] = []

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

    /// Cấu hình chụp màn hình (chọn vùng -> vẽ chú thích -> copy clipboard/OCR).
    /// Mặc định ⌃⇧S. Cần quyền Ghi màn hình (Screen Recording) riêng.
    var screenshotEnabled: Bool = true
    var screenshotHotkeyKeyCode: Int64 = 1 // S
    var screenshotHotkeyModifiers: Set<String> = ["control", "shift"]

    /// Biến đổi văn bản đã bôi đen (bỏ dấu / IN HOA / chuyển mã…). Phím tắt bật
    /// popup chọn thao tác tại vị trí con trỏ. Mặc định ⌃⇧T (T = Transform).
    var textTransformEnabled: Bool = true
    var textTransformHotkeyKeyCode: Int64 = 17 // T
    var textTransformHotkeyModifiers: Set<String> = ["control", "shift"]

    /// Gõ tắt emoji theo shortcode (:cry: -> 😢). Bung khi gõ dấu ':' đóng.
    /// Mặc định TẮT để không ảnh hưởng người không dùng emoji.
    var emojiShortcutsEnabled: Bool = false

    /// Bảng gõ nhanh ký tự đặc biệt & emoji (picker). Phím tắt (mặc định ⌃⇧K)
    /// mở overlay chọn ký tự tại con trỏ. Mặc định bật.
    var symbolPickerEnabled: Bool = true
    var symbolPickerHotkeyKeyCode: Int64 = 40 // K
    var symbolPickerHotkeyModifiers: Set<String> = ["control", "shift"]

    /// Undo ngay sau khi bung gõ tắt/emoji/tự-sửa: nhấn Backspace lập tức để khôi
    /// phục chuỗi gốc (vd "vn " -> "Việt Nam ", Backspace -> "vn "). Mặc định bật.
    var undoExpansionEnabled: Bool = true

    /// Bảng dán sticker (emoji ảnh). Phím tắt (mặc định ⌃⇧J) mở overlay chọn sticker
    /// để dán ẢNH vào ô đang gõ. Mặc định bật.
    var stickerPickerEnabled: Bool = true
    var stickerPickerHotkeyKeyCode: Int64 = 38 // J
    var stickerPickerHotkeyModifiers: Set<String> = ["control", "shift"]

    /// Đếm từ/ký tự vùng bôi đen -> hiện toast. Phím tắt (mặc định ⌃⇧C). Mặc định bật.
    var countSelectionEnabled: Bool = true
    var countSelectionHotkeyKeyCode: Int64 = 8 // C
    var countSelectionHotkeyModifiers: Set<String> = ["control", "shift"]

    /// Trợ lý AI trên vùng bôi đen (dịch / tóm tắt / sửa ngữ pháp / hỏi tự do).
    /// Phím tắt (mặc định ⌃⇧G) mở popup chọn thao tác. API key lưu Keychain — KHÔNG
    /// vào file này. `aiProvider` = "claude"|"openai"; model tuỳ chỉnh mỗi hãng.
    /// Mặc định TẮT (cần người dùng nhập API key trước khi dùng). (G = Gợi ý AI;
    /// tránh keyCode 0 vốn là quy ước "chỉ-modifier".)
    var aiEnabled: Bool = false
    var aiHotkeyKeyCode: Int64 = 5 // G
    var aiHotkeyModifiers: Set<String> = ["control", "shift"]
    var aiProvider: String = "claude"
    var aiClaudeModel: String = "claude-opus-4-8"
    var aiOpenAIModel: String = "gpt-4o"

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
        if let ll = obj["launchAtLogin"] as? Bool { cfg.launchAtLogin = ll }
        if let s = obj["smartSwitch"] as? Bool { cfg.smartSwitch = s }
        if let p = obj["perApp"] as? [String: Bool] { cfg.perApp = p }
        if let me = obj["macroEnabled"] as? Bool { cfg.macroEnabled = me }
        if let ar = obj["autoRestoreEnglish"] as? Bool { cfg.autoRestoreEnglish = ar }
        if let ac = obj["autoCorrect"] as? Bool { cfg.autoCorrect = ac }
        if let pairs = obj["autoCorrectPairs"] as? [[String: Any]] {
            cfg.autoCorrectPairs = pairs.compactMap { item in
                guard let w = item["wrong"] as? String, !w.isEmpty,
                      let r = item["right"] as? String, !r.isEmpty else { return nil }
                return AutoCorrectPair(wrong: w, right: r)
            }
        } else {
            // Khoá vắng mặt -> gieo bộ mặc định built-in để người dùng thấy & sửa.
            cfg.autoCorrectPairs = AutoCorrectDictionary.defaultPairs()
                .map { AutoCorrectPair(wrong: $0.wrong, right: $0.right) }
        }
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
        if let se = obj["screenshotEnabled"] as? Bool { cfg.screenshotEnabled = se }
        if let sk = obj["screenshotHotkeyKeyCode"] as? Int { cfg.screenshotHotkeyKeyCode = Int64(sk) }
        if let smods = obj["screenshotHotkeyModifiers"] as? [String] {
            cfg.screenshotHotkeyModifiers = Set(smods)
        }
        if let tte = obj["textTransformEnabled"] as? Bool { cfg.textTransformEnabled = tte }
        if let ttk = obj["textTransformHotkeyKeyCode"] as? Int { cfg.textTransformHotkeyKeyCode = Int64(ttk) }
        if let ttmods = obj["textTransformHotkeyModifiers"] as? [String] {
            cfg.textTransformHotkeyModifiers = Set(ttmods)
        }
        if let em = obj["emojiShortcutsEnabled"] as? Bool { cfg.emojiShortcutsEnabled = em }
        if let sp = obj["symbolPickerEnabled"] as? Bool { cfg.symbolPickerEnabled = sp }
        if let spk = obj["symbolPickerHotkeyKeyCode"] as? Int { cfg.symbolPickerHotkeyKeyCode = Int64(spk) }
        if let spm = obj["symbolPickerHotkeyModifiers"] as? [String] {
            cfg.symbolPickerHotkeyModifiers = Set(spm)
        }
        if let ue = obj["undoExpansionEnabled"] as? Bool { cfg.undoExpansionEnabled = ue }
        if let st = obj["stickerPickerEnabled"] as? Bool { cfg.stickerPickerEnabled = st }
        if let stk = obj["stickerPickerHotkeyKeyCode"] as? Int { cfg.stickerPickerHotkeyKeyCode = Int64(stk) }
        if let stm = obj["stickerPickerHotkeyModifiers"] as? [String] {
            cfg.stickerPickerHotkeyModifiers = Set(stm)
        }
        if let ce = obj["countSelectionEnabled"] as? Bool { cfg.countSelectionEnabled = ce }
        if let cck = obj["countSelectionHotkeyKeyCode"] as? Int { cfg.countSelectionHotkeyKeyCode = Int64(cck) }
        if let ccm = obj["countSelectionHotkeyModifiers"] as? [String] {
            cfg.countSelectionHotkeyModifiers = Set(ccm)
        }
        if let ai = obj["aiEnabled"] as? Bool { cfg.aiEnabled = ai }
        if let aik = obj["aiHotkeyKeyCode"] as? Int { cfg.aiHotkeyKeyCode = Int64(aik) }
        if let aim = obj["aiHotkeyModifiers"] as? [String] { cfg.aiHotkeyModifiers = Set(aim) }
        if let ap = obj["aiProvider"] as? String, ap == "claude" || ap == "openai" {
            cfg.aiProvider = ap
        }
        if let cm = obj["aiClaudeModel"] as? String, !cm.isEmpty { cfg.aiClaudeModel = cm }
        if let om = obj["aiOpenAIModel"] as? String, !om.isEmpty { cfg.aiOpenAIModel = om }
        return cfg
    }

    private static func parseMacroType(_ s: String?) -> MacroSnippetType {
        switch s {
        case "date":      return .date
        case "time":      return .time
        case "dateTime":  return .dateTime
        case "random":    return .random
        case "counter":   return .counter
        case "clipboard": return .clipboard
        case "calc":      return .calc
        default:          return .staticText
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

    /// Đang theo dõi file chưa — false khi lúc mở file chưa tồn tại (lần chạy đầu),
    /// health check dựa vào đây để thử lại.
    var isWatching: Bool { source != nil }

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
        if let data = try? Data(contentsOf: url) {
            if let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                obj = parsed
            } else {
                // App Cài đặt ghi nguyên tử (tạm + rename) nên file không parse được là
                // HỎNG thật (sửa tay sai…). Cất sang .bak thay vì ghi đè mất dữ liệu,
                // rồi ghi file mới — nếu không mọi lần ghi sau đều bị bỏ mãi.
                let backup = url.appendingPathExtension("bak")
                try? FileManager.default.removeItem(at: backup)
                try? FileManager.default.moveItem(at: url, to: backup)
                NSLog("[Settings] settings.json hỏng, đã cất sang \(backup.lastPathComponent).")
            }
        } else {
            // Lần chạy đầu: thư mục BowGo có thể chưa tồn tại -> ghi sẽ hỏng im lặng.
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
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

    /// Cập nhật cờ `autoCorrect` (khi bật/tắt tự sửa lỗi qua menu). Giữ nguyên khoá khác.
    func writeAutoCorrect(_ enabled: Bool) {
        update { obj in
            if (obj["autoCorrect"] as? Bool) == enabled { return false }
            obj["autoCorrect"] = enabled
            return true
        }
    }

    /// Cập nhật cờ `launchAtLogin` (khi bật/tắt khởi động cùng hệ thống qua menu).
    func writeLaunchAtLogin(_ enabled: Bool) {
        update { obj in
            if (obj["launchAtLogin"] as? Bool) == enabled { return false }
            obj["launchAtLogin"] = enabled
            return true
        }
    }

    /// Gieo giá trị `launchAtLogin` MẶC ĐỊNH (bật) vào file nếu khoá chưa tồn tại
    /// (lần chạy đầu) — để app UI Flutter thấy đúng trạng thái.
    func seedLaunchAtLoginIfAbsent(default defaultValue: Bool = true) {
        update { obj in
            guard obj["launchAtLogin"] == nil else { return false }
            obj["launchAtLogin"] = defaultValue
            return true
        }
    }

    /// Gieo bộ cặp tự-sửa MẶC ĐỊNH vào file NẾU khoá chưa tồn tại (lần chạy đầu).
    /// Nhờ vậy app UI Flutter thấy được danh sách để người dùng xem & sửa.
    func seedAutoCorrectPairsIfAbsent() {
        update { obj in
            guard obj["autoCorrectPairs"] == nil else { return false }  // đã có -> giữ nguyên
            obj["autoCorrectPairs"] = AutoCorrectDictionary.defaultPairs()
                .map { ["wrong": $0.wrong, "right": $0.right] }
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

    func writeEmojiShortcutsEnabled(_ enabled: Bool) {
        update { obj in
            if (obj["emojiShortcutsEnabled"] as? Bool) == enabled { return false }
            obj["emojiShortcutsEnabled"] = enabled
            return true
        }
    }

    func writeUndoExpansionEnabled(_ enabled: Bool) {
        update { obj in
            if (obj["undoExpansionEnabled"] as? Bool) == enabled { return false }
            obj["undoExpansionEnabled"] = enabled
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
        let watchedFD = open(url.path, O_EVTONLY)
        guard watchedFD >= 0 else { return }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: watchedFD,
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
        // Đóng ĐÚNG fd của source này. Cancel handler chạy bất đồng bộ, lúc đó
        // fd đọc qua `self` đã là fd mới của lần startWatching() kế tiếp — đóng nhầm nó thì
        // watcher chết sau lần bộ gõ tự ghi file đầu tiên (⌃⇧, Smart Switch…).
        src.setCancelHandler { close(watchedFD) }
        source = src
        src.resume()
    }

    func stopWatching() {
        source?.cancel()
        source = nil
    }
}
