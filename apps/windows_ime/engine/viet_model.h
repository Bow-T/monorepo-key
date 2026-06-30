// viet_model.h
// ------------
// Mô hình hoá tiếng Việt cho bộ gõ — bản C++ của VietModel.swift.
// Một nguyên âm tiếng Việt = (chữ cái gốc) + (dấu biến âm/mark) + (dấu thanh/tone).
//
// Engine làm việc trên ký tự Unicode dạng char32_t (UTF-32) để mỗi nguyên âm có
// dấu (â, ế, ữ...) là MỘT code point, dễ xử lý hơn UTF-8/UTF-16.

#pragma once

namespace bowgo {

// Dấu thanh (5 dấu + thanh ngang). Thứ tự khớp index trong bảng tra.
enum class Tone {
    None = 0,   // ngang  (a)
    Acute,      // sắc    (á)
    Grave,      // huyền  (à)
    Hook,       // hỏi    (ả)
    Tilde,      // ngã    (ã)
    Dot,        // nặng   (ạ)
};

// Dấu biến âm gắn vào chữ cái (mũ, móc, trăng, gạch đ).
enum class Mark {
    None = 0,
    Circumflex,  // dấu mũ:    a->â, e->ê, o->ô
    Breve,       // dấu trăng: a->ă
    Horn,        // dấu móc:   o->ơ, u->ư
    Dyet,        // gạch ngang d->đ
};

// Phương thức gõ.
enum class InputMethod {
    Telex,
    Vni,
};

// Kiểu đặt dấu thanh: modern (hoà, quý) vs old (hòa, qúy).
enum class ToneStyle {
    Modern,
    Old,
};

}  // namespace bowgo
