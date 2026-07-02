// bow_config.h
// ------------
// Đọc cấu hình bộ gõ từ settings.json DÙNG CHUNG với app cài đặt Flutter —
// bản C++ của SettingsStore.swift (phần đọc). Schema khớp
// apps/settings_ui/lib/src/models/settings.dart.
//
// Vị trí file:
//   - macOS   : ~/Library/Application Support/BowGo/settings.json
//   - Windows : %APPDATA%\BowGo\settings.json
//
// Chỉ chứa các khoá tầng BỘ GÕ cần (phím tắt clipboard/chụp màn hình... thuộc
// app đồng hành, không thuộc text service). Khoá thiếu -> giá trị mặc định,
// GIỐNG hành vi SettingsStore.swift. Parser JSON tự viết, tối giản, chịu lỗi:
// JSON hỏng -> nullopt (giữ cấu hình cũ), khoá lạ -> bỏ qua.
//
// Thuần C++17 đa nền — test được trên macOS/Linux.

#pragma once

#include <optional>
#include <set>
#include <string>
#include <vector>

#include "../engine/macro.h"
#include "../engine/viet_model.h"

namespace bowgo {

struct BowAutoCorrectPair {
    std::u32string wrong;
    std::u32string right;
};

struct BowConfig {
    bool enabled = true;
    InputMethod method = InputMethod::Telex;
    ToneStyle tone_style = ToneStyle::Modern;

    // Phím tắt bật/tắt. key_code 0 = chỉ-modifier (nhấn đúng tập rồi nhả).
    // LƯU Ý: key_code là mã phím macOS (app settings ghi); bên Windows hiện chỉ
    // hỗ trợ dạng chỉ-modifier (mặc định Control+Shift).
    long long hotkey_key_code = 0;
    std::set<std::string> hotkey_modifiers = {"control", "shift"};

    bool macro_enabled = true;
    std::vector<MacroDefinition> macros;

    bool auto_restore_english = false;

    bool auto_correct = false;
    // "autoCorrectPairs" có mặt trong JSON không. Vắng mặt -> dùng từ điển
    // dựng sẵn (AutoCorrectDictionary::Shared), khớp hành vi Swift.
    bool has_auto_correct_pairs = false;
    std::vector<BowAutoCorrectPair> auto_correct_pairs;
};

// Phân tích chuỗi JSON (UTF-8). Trả nullopt nếu JSON hỏng (caller giữ cấu hình cũ).
std::optional<BowConfig> ParseBowConfig(const std::string& json);

// Tiện ích: đọc file rồi ParseBowConfig. Đường dẫn hẹp (UTF-8/POSIX) — dùng cho
// test & macOS/Linux. Trên Windows, tầng TSF tự đọc file bằng API wide rồi gọi
// ParseBowConfig để không vướng ANSI codepage.
std::optional<BowConfig> LoadBowConfig(const std::string& path);

// Đường dẫn settings.json mặc định của nền tảng hiện tại (xem đầu file).
// Trả chuỗi rỗng nếu thiếu biến môi trường cần thiết.
std::string DefaultSettingsPath();

}  // namespace bowgo
