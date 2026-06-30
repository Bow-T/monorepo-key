// viet_table.h
// ------------
// Bảng tra (chữ gốc + mark + tone) -> ký tự Unicode dựng sẵn — bản C++ của
// VietTable.swift. Trả về char32_t (code point) cho tổ hợp, hoặc 0 nếu tổ hợp
// không hợp lệ trong tiếng Việt (caller giữ nguyên ký tự gốc).

#pragma once

#include "viet_model.h"

namespace bowkey {

class VietTable {
public:
    // Ký tự tiếng Việt dựng sẵn cho (base + mark + tone). Giữ hoa/thường theo base.
    // Trả 0 nếu không phải nguyên âm/tổ hợp hợp lệ.
    static char32_t Compose(char32_t base, Mark mark, Tone tone);
};

}  // namespace bowkey
