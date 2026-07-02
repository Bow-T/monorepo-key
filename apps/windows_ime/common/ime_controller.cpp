// ime_controller.cpp — xem ime_controller.h.

#include "ime_controller.h"

#include "../engine/viet_syllable.h"

namespace bowgo {

namespace {
bool IsAsciiAlnum(char32_t ch) {
    return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') ||
           (ch >= '0' && ch <= '9');
}
}  // namespace

ImeController::ImeController() : engine_(InputMethod::Telex, ToneStyle::Modern) {}

void ImeController::Apply(const BowConfig& config) {
    enabled_ = config.enabled;
    method_ = config.method;
    tone_style_ = config.tone_style;
    auto_restore_english_ = config.auto_restore_english;
    auto_correct_ = config.auto_correct;

    // Kho macro: chỉ dựng khi bật VÀ có định nghĩa (khớp rebuildMacroStore Swift).
    if (config.macro_enabled && !config.macros.empty()) {
        macro_store_ = std::make_unique<MacroStore>(config.macros);
    } else {
        macro_store_.reset();
    }

    // Từ điển tự-sửa: có cặp người dùng -> dựng bản riêng (từ đúng dựng sẵn +
    // overrides gốc + cặp người dùng đè lên trên); không -> dùng Shared().
    if (config.has_auto_correct_pairs) {
        auto overrides = AutoCorrectDictionary::Overrides();
        for (const auto& p : config.auto_correct_pairs) {
            overrides.emplace_back(p.wrong, p.right);
        }
        user_dict_ = std::make_unique<AutoCorrectDictionary>(
            AutoCorrectDictionary::Words(), overrides);
    } else {
        user_dict_.reset();
    }

    engine_ = VietEngine(method_, tone_style_);
    ResetSyllable();
}

void ImeController::SetEnabled(bool on) {
    enabled_ = on;
    ResetSyllable();
}

bool ImeController::ToggleEnabled() {
    SetEnabled(!enabled_);
    return enabled_;
}

void ImeController::ResetSyllable() {
    engine_.Clear();
    committed_length_ = 0;
    word_raw_keys_.clear();
    current_display_.clear();
}

KeyAction ImeController::HandleChar(char32_t ch) {
    // Ghi phím thô của từ (cho macro + khôi phục tiếng Anh). Chỉ chữ/số ASCII.
    if ((macro_store_ || auto_restore_english_) && IsAsciiAlnum(ch)) {
        word_raw_keys_.push_back(ch);
    }

    auto rendered = engine_.Process(ch);
    if (!rendered.has_value()) {
        // Engine bảo đây là ngắt từ (ký tự ngoài âm tiết) -> chốt, cho đi qua.
        committed_length_ = 0;
        word_raw_keys_.clear();
        current_display_.clear();
        return KeyAction::Pass();
    }

    // LUÔN nuốt phím gốc + gõ thay (xem bất biến ở đầu header).
    int backspaces = committed_length_;
    committed_length_ = static_cast<int>(rendered->size());
    current_display_ = *rendered;
    return KeyAction::MakeReplace(backspaces, std::move(*rendered));
}

KeyAction ImeController::HandleBackspace() {
    auto rebuilt = engine_.Backspace();
    if (rebuilt.has_value()) {
        // Nuốt Backspace gốc, tự đồng bộ màn hình = engine. `word_raw_keys_`
        // không còn khớp phần đã xoá -> bỏ (macro/khôi-phục tính lại từ phím kế).
        int backspaces = committed_length_;
        committed_length_ = static_cast<int>(rebuilt->size());
        current_display_ = *rebuilt;
        word_raw_keys_.clear();
        return KeyAction::MakeReplace(backspaces, std::move(*rebuilt));
    }
    // Engine rỗng -> Backspace bình thường.
    committed_length_ = 0;
    current_display_.clear();
    word_raw_keys_.clear();
    return KeyAction::Pass();
}

bool ImeController::WouldTransform(bool macro_capable) const {
    if (macro_capable && macro_store_ && !word_raw_keys_.empty() &&
        macro_store_->Has(word_raw_keys_)) {
        return true;
    }
    if (auto_restore_english_ && !word_raw_keys_.empty() &&
        EnglishRestoreKeys(word_raw_keys_, current_display_).has_value()) {
        return true;
    }
    if (auto_correct_ && !current_display_.empty()) {
        const AutoCorrectDictionary& dict =
            user_dict_ ? *user_dict_ : AutoCorrectDictionary::Shared();
        if (AutoCorrect::CorrectWord(current_display_, dict).has_value()) return true;
    }
    return false;
}

std::optional<std::u32string> ImeController::TakeTransform(bool macro_capable) {
    // GÕ TẮT: khớp macro theo phím thô của cả từ.
    if (macro_capable && macro_store_ && !word_raw_keys_.empty()) {
        if (auto content = macro_store_->Expand(word_raw_keys_)) return content;
    }
    // TỰ KHÔI PHỤC TIẾNG ANH: từ bị biến dạng, không phải âm tiết Việt hợp lệ.
    if (auto_restore_english_ && !word_raw_keys_.empty()) {
        if (auto raw = EnglishRestoreKeys(word_raw_keys_, current_display_)) return raw;
    }
    // TỰ SỬA LỖI GÕ NHANH (chạy SAU khôi-phục để không tranh chỗ từ tiếng Anh).
    if (auto_correct_ && !current_display_.empty()) {
        const AutoCorrectDictionary& dict =
            user_dict_ ? *user_dict_ : AutoCorrectDictionary::Shared();
        if (auto result = AutoCorrect::CorrectWord(current_display_, dict)) {
            return result->corrected;
        }
    }
    return std::nullopt;
}

bool ImeController::WordBreakNeedsEdit(BreakKey key) const {
    return WouldTransform(key != BreakKey::Escape);
}

KeyAction ImeController::HandleWordBreak(BreakKey key) {
    auto replacement = TakeTransform(key != BreakKey::Escape);
    if (!replacement.has_value()) {
        ResetSyllable();
        return KeyAction::Pass();
    }

    int backspaces = committed_length_;
    ResetSyllable();

    if (key == BreakKey::Space) {
        // Space chèn được như văn bản thường -> gộp luôn vào chuỗi thay,
        // nuốt hẳn phím gốc (một lần sửa duy nhất, không phải gửi lại phím).
        return KeyAction::MakeReplace(backspaces, *replacement + U" ");
    }
    // Enter/Tab/Esc: sửa văn bản xong phải GỬI LẠI phím gốc để ứng dụng nhận
    // đúng hành vi thật của phím (Enter gửi form, Tab nhảy ô...).
    return KeyAction::MakeReplace(backspaces, std::move(*replacement),
                                  /*resend=*/true);
}

}  // namespace bowgo
