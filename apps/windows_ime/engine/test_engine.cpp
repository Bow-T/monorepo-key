// test_engine.cpp
// ---------------
// Bộ ca test chuẩn cho engine C++ — port 1-1 từ VietEngineTests.swift. Phải khớp
// HỆT bản Dart/Swift. KHÔNG cần Windows: biên dịch bằng clang/g++ trên macOS/Linux:
//
//   c++ -std=c++17 engine.cpp viet_table.cpp test_engine.cpp -o test_engine
//   ./test_engine
//
// In ra số ca pass/fail; exit code != 0 nếu có ca fail.

#include <cstdint>
#include <iostream>
#include <string>

#include "engine.h"

using namespace bowkey;

namespace {

int g_pass = 0;
int g_fail = 0;

// Chuyển UTF-8 (chuỗi nguồn) -> u32string để so sánh với kết quả engine.
std::u32string U8(const std::string& s) {
    std::u32string out;
    size_t i = 0;
    while (i < s.size()) {
        unsigned char c = static_cast<unsigned char>(s[i]);
        char32_t cp = 0;
        int extra = 0;
        if (c < 0x80) { cp = c; extra = 0; }
        else if ((c >> 5) == 0x6) { cp = c & 0x1F; extra = 1; }
        else if ((c >> 4) == 0xE) { cp = c & 0x0F; extra = 2; }
        else if ((c >> 3) == 0x1E) { cp = c & 0x07; extra = 3; }
        else { cp = c; extra = 0; }
        for (int k = 0; k < extra && i + 1 < s.size(); ++k) {
            ++i;
            cp = (cp << 6) | (static_cast<unsigned char>(s[i]) & 0x3F);
        }
        out.push_back(cp);
        ++i;
    }
    return out;
}

// In u32string ra UTF-8 để thông báo lỗi đọc được.
std::string ToU8(const std::u32string& s) {
    std::string out;
    for (char32_t cp : s) {
        if (cp < 0x80) {
            out.push_back(static_cast<char>(cp));
        } else if (cp < 0x800) {
            out.push_back(static_cast<char>(0xC0 | (cp >> 6)));
            out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
        } else if (cp < 0x10000) {
            out.push_back(static_cast<char>(0xE0 | (cp >> 12)));
            out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
            out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
        } else {
            out.push_back(static_cast<char>(0xF0 | (cp >> 18)));
            out.push_back(static_cast<char>(0x80 | ((cp >> 12) & 0x3F)));
            out.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
            out.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
        }
    }
    return out;
}

// Gõ lần lượt từng ký tự (UTF-8 nguồn, thường chỉ ASCII) qua engine; trả âm tiết cuối.
std::u32string Type(const std::string& keys,
                    InputMethod method = InputMethod::Telex,
                    ToneStyle tone_style = ToneStyle::Modern) {
    VietEngine engine(method, tone_style);
    std::u32string current;
    std::u32string ukeys = U8(keys);
    for (char32_t ch : ukeys) {
        auto r = engine.Process(ch);
        current = r.value_or(U"");
    }
    return current;
}

std::u32string TypeThenBackspace(const std::string& keys, int n,
                                 InputMethod method = InputMethod::Telex) {
    VietEngine engine(method);
    std::u32string current;
    for (char32_t ch : U8(keys)) current = engine.Process(ch).value_or(U"");
    for (int i = 0; i < n; ++i) current = engine.Backspace().value_or(U"");
    return current;
}

// So sánh: kết quả gõ `keys` có bằng `expect` (UTF-8) không.
void Check(const std::string& keys, const std::string& expect,
           InputMethod method = InputMethod::Telex,
           ToneStyle tone_style = ToneStyle::Modern) {
    std::u32string got = Type(keys, method, tone_style);
    std::u32string want = U8(expect);
    if (got == want) {
        ++g_pass;
    } else {
        ++g_fail;
        std::cout << "  FAIL: type(\"" << keys << "\") = \"" << ToU8(got)
                  << "\"  (mong đợi \"" << expect << "\")\n";
    }
}

void CheckBack(const std::string& keys, int n, const std::string& expect,
               InputMethod method = InputMethod::Telex) {
    std::u32string got = TypeThenBackspace(keys, n, method);
    std::u32string want = U8(expect);
    if (got == want) {
        ++g_pass;
    } else {
        ++g_fail;
        std::cout << "  FAIL: backspace(\"" << keys << "\", " << n << ") = \""
                  << ToU8(got) << "\"  (mong đợi \"" << expect << "\")\n";
    }
}

}  // namespace

int main() {
    // ── Telex cơ bản ──────────────────────────────────────────────────────
    Check("as", "á"); Check("af", "à"); Check("ar", "ả");
    Check("ax", "ã"); Check("aj", "ạ");
    Check("aa", "â"); Check("ee", "ê"); Check("oo", "ô");
    Check("aw", "ă"); Check("ow", "ơ"); Check("uw", "ư");
    Check("dd", "đ");
    Check("ees", "ế"); Check("oof", "ồ"); Check("uwx", "ữ");
    Check("tieengs", "tiếng"); Check("ddaays", "đấy"); Check("Vieetj", "Việt");
    Check("asz", "a");

    // ── Quy tắc đặt dấu (modern) ──────────────────────────────────────────
    Check("muaf", "mùa"); Check("biaf", "bìa");
    Check("hoaf", "hoà"); Check("khoer", "khoẻ"); Check("quys", "quý");
    Check("toans", "toán"); Check("hoangf", "hoàng");
    Check("tieengs", "tiếng"); Check("nuowngs", "nướng"); Check("dduwowcj", "được");
    Check("ngoaif", "ngoài");
    Check("quaf", "quà"); Check("quas", "quá"); Check("quans", "quán");
    Check("giaf", "già"); Check("gias", "giá"); Check("giof", "giò");
    Check("giups", "giúp"); Check("giuwxa", "giữa");
    Check("gif", "gì"); Check("gir", "gỉ");

    // ── Chế độ đặt dấu cũ ─────────────────────────────────────────────────
    Check("hoaf", "hòa", InputMethod::Telex, ToneStyle::Old);
    Check("thuyf", "thùy", InputMethod::Telex, ToneStyle::Old);
    Check("khoer", "khỏe", InputMethod::Telex, ToneStyle::Old);
    Check("quys", "quý"); Check("quys", "quý", InputMethod::Telex, ToneStyle::Old);
    Check("toans", "toán", InputMethod::Telex, ToneStyle::Old);
    Check("tieengs", "tiếng", InputMethod::Telex, ToneStyle::Old);

    // ── Phụ âm-dấu sau phụ âm đầu (chưa có nguyên âm) ──────────────────────
    Check("tre", "tre"); Check("tres", "tré"); Check("treen", "trên");
    Check("trong", "trong"); Check("truowcs", "trước");
    Check("gra", "gra"); Check("xra", "xra"); Check("strong", "strong");
    Check("sai", "sai"); Check("xin", "xin"); Check("rum", "rum");
    Check("fan", "fan"); Check("zap", "zap");

    // ── Gõ tắt 'w' ────────────────────────────────────────────────────────
    Check("w", "ư"); Check("tw", "tư"); Check("cw", "cư"); Check("qw", "qư");
    Check("mwf", "mừ"); Check("dwfng", "dừng"); Check("mwfng", "mừng");
    Check("wf", "ừ");
    Check("huwong", "hương"); Check("huwongs", "hướng"); Check("tuwong", "tương");
    Check("thuwong", "thương"); Check("nuwocs", "nước");
    Check("uw", "ư"); Check("huowng", "hương"); Check("huow", "hươ");

    // ── Gõ lại để bỏ/đổi dấu ──────────────────────────────────────────────
    Check("hoaf", "hoà"); Check("hoaff", "hoaf"); Check("ass", "as");
    Check("hoafs", "hoá"); Check("asx", "ã");
    Check("aaa", "aa"); Check("oww", "ow"); Check("ddd", "dd");
    Check("asz", "a"); Check("azz", "a");

    // ── Backspace ─────────────────────────────────────────────────────────
    CheckBack("tieengs", 1, "tiêng");
    CheckBack("tieengs", 2, "tiên");
    CheckBack("aas", 1, "â");
    CheckBack("aas", 2, "a");
    CheckBack("as", 2, "");

    // ── VNI cơ bản ────────────────────────────────────────────────────────
    Check("a1", "á", InputMethod::Vni); Check("a2", "à", InputMethod::Vni);
    Check("a6", "â", InputMethod::Vni); Check("o7", "ơ", InputMethod::Vni);
    Check("a8", "ă", InputMethod::Vni); Check("d9", "đ", InputMethod::Vni);
    Check("tie61ng", "tiếng", InputMethod::Vni);
    // Toggle số-biến-âm trùng -> huỷ + số thô
    Check("a66", "a6", InputMethod::Vni); Check("o77", "o7", InputMethod::Vni);
    Check("a88", "a8", InputMethod::Vni); Check("d99", "d9", InputMethod::Vni);
    Check("a16", "ấ", InputMethod::Vni); Check("a61", "ấ", InputMethod::Vni);

    std::cout << "\n" << g_pass << " pass, " << g_fail << " fail.\n";
    return g_fail == 0 ? 0 : 1;
}
