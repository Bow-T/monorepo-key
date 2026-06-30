// engine.h
// --------
// Bộ não bộ gõ — bản C++ của Engine.swift. Nhận từng ký tự (char32_t) người dùng
// gõ, trả về chuỗi hiển thị (std::u32string) của âm tiết hiện tại, hoặc báo "ngắt
// từ" để caller xuất ký tự nguyên bản.
//
// Đây là phần SPEC CHUNG: phải cho kết quả GIỐNG HỆT engine Dart/Swift trên cùng
// bộ ca test chuẩn (golden cases).

#pragma once

#include <optional>
#include <string>
#include <vector>

#include "viet_model.h"

namespace bowkey {

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
    struct Letter {
        char32_t base;
        Mark mark = Mark::None;
    };

    enum class DiacriticResult {
        Applied,       // đã áp dấu/biến âm
        Cancelled,     // gõ lại trùng -> đã gỡ dấu; trả ký tự thô cho caller
        NotDiacritic,  // không phải phím-dấu -> nối như chữ thường
    };

    InputMethod method_;
    ToneStyle tone_style_;

    std::vector<Letter> letters_;
    Tone tone_ = Tone::None;
    std::vector<char32_t> raw_keys_;  // lịch sử phím thô, để replay

    std::optional<std::u32string> Step(char32_t ch);
    void ResetSyllable();

    DiacriticResult ApplyAsDiacritic(char32_t ch);
    DiacriticResult ApplyTelex(char32_t ch);
    DiacriticResult ApplyVni(char32_t ch);
    DiacriticResult ApplyHornOrBreve();

    DiacriticResult SetTone(Tone tone);
    DiacriticResult SetMarkOnLast(Mark mark);
    DiacriticResult RemoveMarkOnLast();

    bool HasVowel() const;
    std::u32string Render() const;
    int ToneTargetIndex() const;
};

}  // namespace bowkey
