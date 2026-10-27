// engine.cpp
// ----------
// Lớp bọc core Rust: chuyển char32_t / UTF-8 qua lại với C ABI của viet_core.

#include "engine.h"

#include "viet_core.h"

namespace bowgo {

void VietEngine::CoreDeleter::operator()(BowEngine* core) const { bow_engine_free(core); }

VietEngine::VietEngine(InputMethod method, ToneStyle tone_style)
    : core_(bow_engine_new(method == InputMethod::Vni ? BOW_METHOD_VNI : BOW_METHOD_TELEX,
                           tone_style == ToneStyle::Old ? BOW_TONE_OLD : BOW_TONE_MODERN)) {}

std::optional<std::u32string> VietEngine::Process(char32_t ch) {
    if (!bow_engine_process(core_.get(), static_cast<uint32_t>(ch))) return std::nullopt;
    return Text();
}

std::optional<std::u32string> VietEngine::Backspace() {
    if (!bow_engine_backspace(core_.get())) return std::nullopt;
    return Text();
}

void VietEngine::Clear() { bow_engine_clear(core_.get()); }

// Core trả UTF-8 hợp lệ (String của Rust) -> giải mã thẳng sang UTF-32.
std::u32string VietEngine::Text() const {
    size_t len = 0;
    const uint8_t* s = bow_engine_text(core_.get(), &len);
    std::u32string out;
    for (size_t i = 0; i < len;) {
        uint8_t c = s[i];
        int extra = c < 0x80 ? 0 : c < 0xE0 ? 1 : c < 0xF0 ? 2 : 3;
        char32_t cp = extra == 0 ? c : c & (0x3F >> extra);
        for (int k = 1; k <= extra; ++k) cp = (cp << 6) | (s[i + k] & 0x3F);
        out.push_back(cp);
        i += 1 + extra;
    }
    return out;
}

}  // namespace bowgo
