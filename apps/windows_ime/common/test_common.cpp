// test_common.cpp
// ---------------
// Test tầng common (đa nền, chạy trên macOS/Linux/Windows):
//   - text_codec: chuyển mã UTF-8/16/32.
//   - bow_config: đọc settings.json (khoá thiếu, JSON hỏng, tiếng Việt, \uXXXX).
//   - ime_controller: mirror hành vi EventTapController (gõ thay, backspace
//     đồng bộ, macro / khôi phục tiếng Anh / tự sửa lỗi khi ngắt từ).
// In số ca pass/fail; exit code != 0 nếu có ca fail.

#include <iostream>
#include <string>

#include "bow_config.h"
#include "ime_controller.h"
#include "text_codec.h"

using namespace bowgo;

namespace {

int g_pass = 0;
int g_fail = 0;

void Check(bool ok, const std::string& msg) {
    if (ok) {
        ++g_pass;
    } else {
        ++g_fail;
        std::cout << "  FAIL: " << msg << "\n";
    }
}

void CheckStr(const std::u32string& got, const std::u32string& want,
              const std::string& msg) {
    if (got == want) {
        ++g_pass;
    } else {
        ++g_fail;
        std::cout << "  FAIL: " << msg << " = \"" << U32ToUtf8(got) << "\" (muốn \""
                  << U32ToUtf8(want) << "\")\n";
    }
}

// Gõ một dãy phím ASCII qua controller, trả action CUỐI cùng.
KeyAction Type(ImeController& c, const char* keys) {
    KeyAction last;
    for (const char* p = keys; *p; ++p) last = c.HandleChar(*p);
    return last;
}

}  // namespace

int main() {
    // ── text_codec ───────────────────────────────────────────────────────────
    {
        CheckStr(Utf8ToU32(u8"Tiếng Việt"), U"Tiếng Việt", "utf8->u32 tiếng Việt");
        Check(U32ToUtf8(U"đường phố") == u8"đường phố", "u32->utf8 khứ hồi");
        Check(U32ToUtf16(U"tiếng") == u"tiếng", "u32->utf16 BMP");
        // Ngoài BMP (emoji) -> surrogate pair.
        std::u32string emoji(1, static_cast<char32_t>(0x1F600));
        std::u16string utf16 = U32ToUtf16(emoji);
        Check(utf16.size() == 2 && utf16[0] == 0xD83D && utf16[1] == 0xDE00,
              "u32->utf16 surrogate pair");
        // Byte hỏng -> U+FFFD, không crash.
        Check(!Utf8ToU32("\x80\xFFhi").empty(), "utf8 hỏng không crash");
    }

    // ── bow_config ───────────────────────────────────────────────────────────
    {
        // JSON đầy đủ, có tiếng Việt + escape \uXXXX.
        auto cfg = ParseBowConfig(u8R"({
            "enabled": false,
            "method": "vni",
            "toneStyle": "old",
            "hotkeyKeyCode": 49,
            "hotkeyModifiers": ["control", "option"],
            "macroEnabled": true,
            "macros": [
                {"keyword": "vn", "content": "Việt Nam", "type": "staticText"},
                {"keyword": "esc", "content": "\u00e0 \ud83d\ude00", "type": "staticText"},
                {"keyword": "d", "content": "dd/MM/yyyy", "type": "date"}
            ],
            "autoRestoreEnglish": true,
            "autoCorrect": true,
            "autoCorrectPairs": [{"wrong": "giừo", "right": "giờ"}],
            "launchAtLogin": true,
            "perApp": {"com.example": true}
        })");
        Check(cfg.has_value(), "parse JSON đầy đủ");
        if (cfg) {
            Check(!cfg->enabled, "enabled=false");
            Check(cfg->method == InputMethod::Vni, "method=vni");
            Check(cfg->tone_style == ToneStyle::Old, "toneStyle=old");
            Check(cfg->hotkey_key_code == 49, "hotkeyKeyCode=49");
            Check(cfg->hotkey_modifiers ==
                      std::set<std::string>({"control", "option"}),
                  "hotkeyModifiers");
            Check(cfg->macros.size() == 3, "3 macro");
            if (cfg->macros.size() == 3) {
                CheckStr(cfg->macros[0].content, U"Việt Nam", "macro content Việt");
                CheckStr(cfg->macros[1].content, U"\u00e0 \U0001F600", "macro content escape+emoji");
                Check(cfg->macros[2].type == MacroSnippetType::Date, "macro type date");
            }
            Check(cfg->auto_restore_english, "autoRestoreEnglish=true");
            Check(cfg->auto_correct && cfg->has_auto_correct_pairs &&
                      cfg->auto_correct_pairs.size() == 1,
                  "autoCorrectPairs 1 cặp");
        }

        // Khoá thiếu -> mặc định (khớp SettingsStore.swift).
        auto defaults = ParseBowConfig("{}");
        Check(defaults.has_value(), "parse {} được");
        if (defaults) {
            Check(defaults->enabled, "mặc định enabled=true");
            Check(defaults->method == InputMethod::Telex, "mặc định telex");
            Check(defaults->tone_style == ToneStyle::Modern, "mặc định modern");
            Check(defaults->hotkey_modifiers ==
                      std::set<std::string>({"control", "shift"}),
                  "mặc định hotkey ⌃⇧");
            Check(defaults->macro_enabled, "mặc định macroEnabled=true");
            Check(!defaults->auto_correct, "mặc định autoCorrect=false");
            Check(!defaults->has_auto_correct_pairs, "mặc định không có pairs");
        }

        // JSON hỏng -> nullopt (caller giữ cấu hình cũ).
        Check(!ParseBowConfig("{").has_value(), "JSON hỏng -> nullopt");
        Check(!ParseBowConfig("").has_value(), "chuỗi rỗng -> nullopt");
        Check(!ParseBowConfig("[1,2]{").has_value(), "rác sau JSON -> nullopt");
        // Kiểu sai từng khoá -> giữ mặc định, không crash.
        auto weird = ParseBowConfig(R"({"enabled": "yes", "macros": 5})");
        Check(weird.has_value() && weird->enabled && weird->macros.empty(),
              "kiểu sai -> mặc định");
    }

    // ── ime_controller: gõ thay cơ bản ───────────────────────────────────────
    {
        ImeController c;
        BowConfig cfg;
        c.Apply(cfg);

        // Mỗi ký tự: nuốt + gõ thay; backspaces = độ dài hiển thị trước đó.
        KeyAction a = c.HandleChar(U't');
        Check(a.kind == KeyAction::Kind::Replace && a.backspaces == 0, "t: replace 0");
        CheckStr(a.text, U"t", "t hiển thị");
        a = Type(c, "ieengs");
        Check(a.kind == KeyAction::Kind::Replace, "tieengs: replace");
        CheckStr(a.text, U"tiếng", "tieengs -> tiếng");
        Check(a.backspaces == 5, "backspaces = 5 (thay 'tiếng' cũ 5 ký tự)");
        Check(c.HasPendingSyllable(), "đang gõ dở");

        // Backspace: nuốt + đồng bộ màn = engine (lùi 1 PHÍM thô, không phải 1 ký tự).
        a = c.HandleBackspace();
        Check(a.kind == KeyAction::Kind::Replace && a.backspaces == 5,
              "backspace: replace 5");
        CheckStr(a.text, U"tiêng", "backspace 's' -> tiêng");

        // Ngắt từ không có gì để sửa -> PassThrough + chốt từ.
        Check(!c.WordBreakNeedsEdit(BreakKey::Space), "space không cần sửa");
        a = c.HandleWordBreak(BreakKey::Space);
        Check(a.kind == KeyAction::Kind::PassThrough, "space pass-through");
        Check(!c.HasPendingSyllable(), "đã chốt từ");

        // Engine rỗng -> backspace pass-through.
        a = c.HandleBackspace();
        Check(a.kind == KeyAction::Kind::PassThrough, "backspace khi rỗng: pass");

        // Ký tự ngoài âm tiết (dấu chấm) -> pass + chốt.
        Type(c, "abc");
        a = c.HandleChar(U'.');
        Check(a.kind == KeyAction::Kind::PassThrough && !c.HasPendingSyllable(),
              "'.' chốt từ, pass");
    }

    // ── ime_controller: gõ tắt (macro) ───────────────────────────────────────
    {
        ImeController c;
        BowConfig cfg;
        MacroDefinition vn;
        vn.keyword = U"vn";
        vn.content = U"Việt Nam";
        cfg.macros.push_back(vn);
        c.Apply(cfg);

        Type(c, "vn");
        Check(c.WordBreakNeedsEdit(BreakKey::Space), "vn+space cần sửa");
        Check(c.WordBreakNeedsEdit(BreakKey::Space), "hỏi 2 lần không đổi trạng thái");
        KeyAction a = c.HandleWordBreak(BreakKey::Space);
        Check(a.kind == KeyAction::Kind::Replace && a.backspaces == 2 &&
                  !a.resend_original_key,
              "space: nuốt, thay 2 ký tự");
        CheckStr(a.text, U"Việt Nam ", "vn+space -> 'Việt Nam '");

        // Enter: sửa văn bản rồi GỬI LẠI phím (không chèn '\n').
        Type(c, "vn");
        Check(c.WordBreakNeedsEdit(BreakKey::Enter), "vn+enter cần sửa");
        a = c.HandleWordBreak(BreakKey::Enter);
        Check(a.kind == KeyAction::Kind::Replace && a.resend_original_key,
              "enter: thay + gửi lại phím");
        CheckStr(a.text, U"Việt Nam", "vn+enter -> 'Việt Nam' (không kèm \\n)");

        // Esc KHÔNG bung macro (khớp macOS: macro chỉ với space/return/tab).
        Type(c, "vn");
        Check(!c.WordBreakNeedsEdit(BreakKey::Escape), "esc không bung macro");
        a = c.HandleWordBreak(BreakKey::Escape);
        Check(a.kind == KeyAction::Kind::PassThrough, "esc pass-through");

        // Từ không phải keyword -> pass.
        Type(c, "vx");
        Check(!c.WordBreakNeedsEdit(BreakKey::Space), "vx không phải macro");

        // Backspace giữa chừng làm mất khớp macro (word_raw_keys bị bỏ).
        Type(c, "vn");
        c.HandleBackspace();
        Type(c, "n");
        Check(!c.WordBreakNeedsEdit(BreakKey::Space),
              "sau backspace không còn khớp macro");

        // macroEnabled=false -> không bung dù có định nghĩa.
        cfg.macro_enabled = false;
        c.Apply(cfg);
        Type(c, "vn");
        Check(!c.WordBreakNeedsEdit(BreakKey::Space), "tắt macro -> không bung");
    }

    // ── ime_controller: tự khôi phục tiếng Anh ──────────────────────────────
    {
        ImeController c;
        BowConfig cfg;
        cfg.auto_restore_english = true;
        c.Apply(cfg);

        KeyAction a = Type(c, "waht");
        Check(a.kind == KeyAction::Kind::Replace, "waht: đang bị biến dạng");
        Check(c.WordBreakNeedsEdit(BreakKey::Space), "waht cần khôi phục");
        a = c.HandleWordBreak(BreakKey::Space);
        CheckStr(a.text, U"waht ", "khôi phục 'waht '");

        // Từ tiếng Việt hợp lệ -> giữ nguyên.
        Type(c, "tieengs");
        Check(!c.WordBreakNeedsEdit(BreakKey::Space), "tiếng -> giữ");
        c.HandleWordBreak(BreakKey::Space);

        // ASCII thuần -> giữ nguyên.
        Type(c, "test");
        Check(!c.WordBreakNeedsEdit(BreakKey::Space), "test ascii -> giữ");
        c.HandleWordBreak(BreakKey::Space);
    }

    // ── ime_controller: tự sửa lỗi gõ nhanh (cặp người dùng) ─────────────────
    {
        ImeController c;
        BowConfig cfg;
        cfg.auto_correct = true;
        cfg.has_auto_correct_pairs = true;
        cfg.auto_correct_pairs.push_back({U"tét", U"tết"});
        c.Apply(cfg);

        Type(c, "test");  // t-e-s-t: 's' là dấu sắc -> "tét"
        Check(c.WordBreakNeedsEdit(BreakKey::Space), "tét cần sửa (cặp người dùng)");
        KeyAction a = c.HandleWordBreak(BreakKey::Space);
        CheckStr(a.text, U"tết ", "tét -> 'tết '");

        // Không có cặp người dùng -> Shared() không sửa "tét" (từ thật).
        BowConfig plain;
        plain.auto_correct = true;
        c.Apply(plain);
        Type(c, "test");
        Check(!c.WordBreakNeedsEdit(BreakKey::Space), "tét giữ nguyên với dict gốc");
    }

    // ── ime_controller: bật/tắt ──────────────────────────────────────────────
    {
        ImeController c;
        BowConfig cfg;
        c.Apply(cfg);
        Check(c.enabled(), "mặc định bật");
        Check(!c.ToggleEnabled(), "toggle -> tắt");
        Check(c.ToggleEnabled(), "toggle -> bật lại");
        cfg.enabled = false;
        c.Apply(cfg);
        Check(!c.enabled(), "config tắt -> tắt");
    }

    std::cout << "\n" << g_pass << " pass, " << g_fail << " fail.\n";
    return g_fail == 0 ? 0 : 1;
}
