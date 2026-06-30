// viet_syllable.cpp
// -----------------
// Cài đặt kiểm tra âm tiết tiếng Việt + tự khôi phục tiếng Anh (bản C++).
// Port 1:1 từ VietSyllable.swift; phải cho kết quả giống hệt bản Swift/Dart.

#include "viet_syllable.h"

#include <unordered_map>
#include <unordered_set>

namespace bowkey {

namespace {

char32_t ToLower(char32_t c) {
    return (c >= U'A' && c <= U'Z') ? (c + 32) : c;
}

bool IsAsciiLetter(char32_t c) {
    char32_t l = ToLower(c);
    return l >= U'a' && l <= U'z';
}

// Chữ cái tiếng Việt cơ bản (a-z + nguyên âm mũ/móc/trăng + đ).
bool IsVietLetter(char32_t c) {
    if (c >= U'a' && c <= U'z') return true;
    static const std::u32string extra = U"ăâđêôơư";
    return extra.find(ToLower(c)) != std::u32string::npos;
}

// Bỏ dấu thanh, giữ mũ/móc/trăng.
const std::unordered_map<char32_t, char32_t>& ToneStripMap() {
    static const std::unordered_map<char32_t, char32_t> m = [] {
        std::unordered_map<char32_t, char32_t> map;
        auto add = [&](char32_t keep, const std::u32string& toned) {
            for (char32_t ch : toned) map[ch] = keep;
        };
        add(U'a', U"áàảãạ");  add(U'ă', U"ắằẳẵặ");  add(U'â', U"ấầẩẫậ");
        add(U'e', U"éèẻẽẹ");  add(U'ê', U"ếềểễệ");
        add(U'i', U"íìỉĩị");
        add(U'o', U"óòỏõọ");  add(U'ô', U"ốồổỗộ");  add(U'ơ', U"ớờởỡợ");
        add(U'u', U"úùủũụ");  add(U'ư', U"ứừửữự");
        add(U'y', U"ýỳỷỹỵ");
        return map;
    }();
    return m;
}

const std::vector<std::u32string>& Initials() {
    static const std::vector<std::u32string> v = {
        U"ngh", U"ng", U"nh", U"ch", U"gh", U"gi", U"kh", U"ph", U"th", U"tr", U"qu",
        U"b", U"c", U"d", U"đ", U"g", U"h", U"k", U"l", U"m", U"n", U"p", U"q", U"r",
        U"s", U"t", U"v", U"x",
    };
    return v;
}

const std::vector<std::u32string>& Finals() {
    static const std::vector<std::u32string> v = {
        U"ch", U"nh", U"ng", U"c", U"m", U"n", U"p", U"t",
    };
    return v;
}

const std::unordered_set<std::u32string>& Nuclei() {
    static const std::unordered_set<std::u32string> s = {
        U"a", U"ă", U"â", U"e", U"ê", U"i", U"o", U"ô", U"ơ", U"u", U"ư", U"y",
        U"ai", U"ao", U"au", U"ay", U"âu", U"ây",
        U"eo", U"êu",
        U"ia", U"iê", U"iu", U"yê", U"yêu", U"iêu",
        U"oa", U"oă", U"oe", U"oo", U"oi", U"ôi", U"ơi",
        U"ua", U"uâ", U"uê", U"uô", U"uơ", U"ui", U"ưi", U"uy", U"ưa", U"ươ", U"ưu", U"ôô",
        U"oai", U"oay", U"oao", U"uây", U"uôi", U"ươi",
        U"uya", U"uyê", U"uyu",
    };
    return s;
}

std::u32string Lowercase(const std::u32string& s) {
    std::u32string out;
    out.reserve(s.size());
    for (char32_t c : s) out.push_back(ToLower(c));
    return out;
}

// Khớp tiền tố dài nhất trong danh sách (đã sắp dài trước).
const std::u32string* MatchPrefix(const std::u32string& s,
                                  const std::vector<std::u32string>& list) {
    for (const auto& cand : list) {
        if (s.size() >= cand.size() && s.compare(0, cand.size(), cand) == 0) return &cand;
    }
    return nullptr;
}

const std::u32string* MatchSuffix(const std::u32string& s,
                                  const std::vector<std::u32string>& list) {
    for (const auto& cand : list) {
        if (s.size() >= cand.size() &&
            s.compare(s.size() - cand.size(), cand.size(), cand) == 0) {
            return &cand;
        }
    }
    return nullptr;
}

const std::u32string& MarkedVowels() {
    static const std::u32string marked =
        U"ăâđêôơưĂÂĐÊÔƠƯ"
        U"ÁÀẢÃẠẮẰẲẴẶẤẦẨẪẬÉÈẺẼẸẾỀỂỄỆÍÌỈĨỊÓÒỎÕỌỐỒỔỖỘỚỜỞỠỢÚÙỦŨỤỨỪỬỮỰÝỲỶỸỴ";
    return marked;
}

bool HasVietnameseDiacritic(const std::u32string& word) {
    const auto& strip = ToneStripMap();
    const auto& marked = MarkedVowels();
    for (char32_t ch : word) {
        if (strip.count(ch)) return true;
        if (marked.find(ch) != std::u32string::npos) return true;
    }
    return false;
}

// Một ký tự có phải "chữ" (cho việc tách từ): ASCII a-z, nguyên âm có dấu thanh,
// hoặc nguyên âm mũ/móc/trăng/đ (cả hoa lẫn thường).
bool IsWordChar(char32_t c) {
    if (IsAsciiLetter(c)) return true;
    if (ToneStripMap().count(c)) return true;
    return MarkedVowels().find(c) != std::u32string::npos;
}

}  // namespace

bool VietSyllable::IsValidToneless(const std::u32string& rawSyllable) {
    std::u32string s = Lowercase(rawSyllable);
    if (s.empty()) return false;
    for (char32_t ch : s) {
        if (!IsVietLetter(ch)) return false;
    }

    std::u32string rest = s;
    if (const auto* initial = MatchPrefix(rest, Initials())) {
        rest = rest.substr(initial->size());
    }
    if (rest.empty()) return false;  // chỉ có phụ âm

    std::u32string nucleus = rest;
    if (const auto* fin = MatchSuffix(rest, Finals())) {
        nucleus = rest.substr(0, rest.size() - fin->size());
    }
    if (nucleus.empty()) return false;

    return Nuclei().count(nucleus) > 0;
}

std::u32string VietSyllable::StripTone(const std::u32string& display) {
    const auto& strip = ToneStripMap();
    std::u32string out;
    out.reserve(display.size());
    for (char32_t ch : display) {
        auto it = strip.find(ch);
        out.push_back(it != strip.end() ? it->second : ch);
    }
    return out;
}

bool VietSyllable::IsValidDisplay(const std::u32string& display) {
    return IsValidToneless(StripTone(display));
}

bool VietSyllable::IsMisspelled(const std::u32string& word) {
    if (!HasVietnameseDiacritic(word)) return false;
    return !IsValidDisplay(word);
}

std::vector<VietSyllable::MisspelledWord> VietSyllable::MisspelledWords(
    const std::u32string& text) {
    std::vector<MisspelledWord> result;
    size_t i = 0;
    while (i < text.size()) {
        if (!IsWordChar(text[i])) {
            ++i;
            continue;
        }
        size_t j = i;
        while (j < text.size() && IsWordChar(text[j])) {
            ++j;
        }
        std::u32string word = text.substr(i, j - i);
        if (IsMisspelled(word)) result.push_back({word, i, j});
        i = j;
    }
    return result;
}

std::optional<std::u32string> EnglishRestoreKeys(const std::u32string& rawKeys,
                                                 const std::u32string& display) {
    if (rawKeys.empty()) return std::nullopt;
    if (Lowercase(display) == Lowercase(rawKeys)) return std::nullopt;  // không biến dạng
    if (VietSyllable::IsValidDisplay(display)) return std::nullopt;     // vẫn hợp lệ VN
    return rawKeys;
}

}  // namespace bowkey
