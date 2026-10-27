// engine.h
// --------
// Bộ não bộ gõ — lớp bọc C++ quanh core Rust packages/viet_core (C ABI ở
// viet_core.h). Nhận từng ký tự (char32_t) người dùng gõ, trả về chuỗi hiển thị
// (std::u32string) của âm tiết hiện tại, hoặc báo "ngắt từ" để caller xuất ký tự
// nguyên bản. Hành vi gõ do core quyết định, kiểm bằng bộ ca chuẩn dùng chung
// packages/viet_engine/spec/typing_cases.tsv.

#pragma once

#include <memory>
#include <optional>
#include <string>

#include "viet_model.h"

struct BowEngine;

namespace bowgo {

class VietEngine {
public:
    explicit VietEngine(InputMethod method = InputMethod::Telex,
                        ToneStyle tone_style = ToneStyle::Modern);

    // Nhận một ký tự. Trả chuỗi hiển thị của âm tiết, hoặc nullopt nếu ký tự này
    // KHÔNG thuộc âm tiết (ngắt từ) — caller xuất nguyên bản & bắt đầu âm tiết mới.
    std::optional<std::u32string> Process(char32_t ch);

    // Backspace: xoá 1 phím thô cuối rồi dựng lại âm tiết. Trả chuỗi mới (rỗng nếu
    // hết), hoặc nullopt nếu buffer rỗng (caller để Backspace đi qua bình thường).
    std::optional<std::u32string> Backspace();

    // Reset thủ công (con trỏ nhảy chỗ, click chuột...).
    void Clear();

private:
    struct CoreDeleter {
        void operator()(BowEngine* core) const;
    };
    std::unique_ptr<BowEngine, CoreDeleter> core_;

    std::u32string Text() const;
};

}  // namespace bowgo
