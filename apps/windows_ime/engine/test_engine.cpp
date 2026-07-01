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
#include <optional>
#include <string>

#include "auto_correct.h"
#include "engine.h"
#include "macro.h"
#include "text_converter.h"
#include "viet_syllable.h"

using namespace bowgo;

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

    // ── Kéo dài nguyên âm + chu kỳ mũ ─────────────────────────────────────
    // Chu kỳ mũ theo số lần gõ nguyên âm, KHÔNG tạo lại mũ sau khi đã gỡ.
    Check("aaa", "aa"); Check("aaaa", "aaa");
    Check("eee", "ee"); Check("ooo", "oo"); Check("cooo", "coo"); Check("theee", "thee");
    Check("these", "thế");            // 1 e thừa sau thé -> tạo mũ -> thế
    Check("baasm", "bấm");            // mũ trước thanh -> giữ mũ
    // Đặt dấu thanh khi nguyên âm bị kéo dài: dấu ở nguyên âm GỐC, không trôi.
    Check("choifiii", "chòiiii"); Check("choiiiif", "chòiiii");

    // ── Âm tiết hợp lệ + khôi phục tiếng Anh + chính tả ───────────────────
    auto checkEq = [](bool got, bool want, const std::string& msg) {
        if (got == want) ++g_pass;
        else { ++g_fail; std::cout << "  FAIL: " << msg << "\n"; }
    };
    checkEq(VietSyllable::IsValidToneless(U"tiêng"), true, "tiêng hợp lệ");
    checkEq(VietSyllable::IsValidToneless(U"nghiêng"), true, "nghiêng hợp lệ");
    checkEq(VietSyllable::IsValidToneless(U"terminal"), false, "terminal không hợp lệ");
    checkEq(VietSyllable::IsValidToneless(U"the"), true, "the trùng cấu trúc VN");
    checkEq(VietSyllable::IsValidDisplay(U"tiếng"), true, "tiếng display hợp lệ");
    checkEq(VietSyllable::IsValidDisplay(U"terminäl"), false, "terminäl không hợp lệ");
    checkEq(VietSyllable::StripTone(U"tiếng") == U"tiêng", true, "stripTone tiếng");
    checkEq(VietSyllable::IsMisspelled(U"tểrn"), true, "tểrn sai chính tả");
    checkEq(VietSyllable::IsMisspelled(U"tiếng"), false, "tiếng đúng");
    checkEq(VietSyllable::IsMisspelled(U"terminal"), false, "ascii không đánh dấu sai");
    {
        auto bad = VietSyllable::MisspelledWords(U"Tôi viết tểrn rồi");
        checkEq(bad.size() == 1 && bad[0].word == U"tểrn", true, "tìm từ sai trong câu");
    }
    // Tự khôi phục tiếng Anh
    auto restore = [](const char* keys) -> std::optional<std::u32string> {
        VietEngine e;
        std::u32string disp;
        for (char32_t ch : U8(keys)) disp = e.Process(ch).value_or(U"");
        return EnglishRestoreKeys(U8(keys), disp);
    };
    checkEq(restore("waht").has_value() && restore("waht").value() == U"waht", true,
            "waht -> khôi phục");
    checkEq(!restore("tieengs").has_value(), true, "tiếng -> giữ");
    checkEq(!restore("test").has_value(), true, "test ascii -> giữ");

    // ── Công cụ chuyển mã ─────────────────────────────────────────────────
    auto checkStr = [](const std::u32string& got, const std::u32string& want,
                       const std::string& msg) {
        if (got == want) ++g_pass;
        else { ++g_fail; std::cout << "  FAIL: " << msg << " = \"" << ToU8(got) << "\"\n"; }
    };
    checkStr(TextConverter::RemoveDiacritics(U"Tiếng Việt"), U"Tieng Viet", "bỏ dấu");
    checkStr(TextConverter::RemoveDiacritics(U"đường"), U"duong", "bỏ dấu đường");
    checkStr(TextConverter::ChangeCase(U"Tiếng Việt", LetterCase::AllUpper), U"TIẾNG VIỆT",
             "hoa hết");
    checkStr(TextConverter::ChangeCase(U"Tiếng Việt", LetterCase::AllLower), U"tiếng việt",
             "thường hết");
    checkStr(TextConverter::ChangeCase(U"nguyễn văn an", LetterCase::CapitalizeWords),
             U"Nguyễn Văn An", "hoa mỗi từ");
    // TCVN3 / VNI round-trip
    for (const std::u32string s : {U"tiếng việt", U"đường phố", U"phở bò"}) {
        auto tcvn = TextConverter::Convert(s, CodeTable::Unicode, CodeTable::Tcvn3);
        checkStr(TextConverter::Convert(tcvn, CodeTable::Tcvn3, CodeTable::Unicode), s,
                 "TCVN khứ hồi");
    }
    for (const std::u32string s : {std::u32string(U"Tiếng Việt"), std::u32string(U"đường phố")}) {
        auto vni = TextConverter::Convert(s, CodeTable::Unicode, CodeTable::VniWindows);
        checkStr(TextConverter::Convert(vni, CodeTable::VniWindows, CodeTable::Unicode), s,
                 "VNI khứ hồi");
    }
    checkStr(TextConverter::Convert(U"đ", CodeTable::Unicode, CodeTable::VniWindows), U"ñ",
             "đ -> ñ (VNI)");

    // ── Macro ─────────────────────────────────────────────────────────────
    {
        MacroStore store({{U"vn", U"Việt Nam"}, {U"kb", U"không biết"}});
        checkStr(store.Expand(U"vn").value_or(U"?"), U"Việt Nam", "macro vn");
        checkEq(!store.Expand(U"xx").has_value(), true, "macro không khớp");

        MacroEnvironment env;
        env.now = [] { return MacroClock{2026, 6, 30, 9, 5, 7}; };
        MacroStore dyn({{U"td", U"dd/MM/yyyy", MacroSnippetType::Date},
                        {U"tg", U"HH:mm:ss", MacroSnippetType::Time}}, env);
        checkStr(dyn.Expand(U"td").value_or(U"?"), U"30/06/2026", "macro ngày");
        checkStr(dyn.Expand(U"tg").value_or(U"?"), U"09:05:07", "macro giờ");

        MacroStore cnt({{U"no", U"#", MacroSnippetType::Counter}});
        checkStr(cnt.Expand(U"no").value_or(U"?"), U"#1", "counter 1");
        checkStr(cnt.Expand(U"no").value_or(U"?"), U"#2", "counter 2");

        MacroEnvironment renv;
        renv.randomIndex = [](int) { return 1; };
        MacroStore rnd({{U"rr", U"a, b, c", MacroSnippetType::Random}}, renv);
        checkStr(rnd.Expand(U"rr").value_or(U"?"), U"b", "random index 1");
    }

    // ── Tự sửa lỗi gõ nhanh (auto-correct) ────────────────────────────────
    // Helper: kiểm tra RepositionTone(u32(keys)) == u32(expect).
    auto checkReposition = [](const std::string& in, const std::string& expect) {
        auto got = AutoCorrect::RepositionTone(U8(in));
        std::u32string want = U8(expect);
        if (got.has_value() && got.value() == want) ++g_pass;
        else {
            ++g_fail;
            std::cout << "  FAIL: repositionTone(\"" << in << "\") = \""
                      << (got.has_value() ? ToU8(got.value()) : std::string("nil"))
                      << "\"  (mong đợi \"" << expect << "\")\n";
        }
    };
    auto checkRepositionNil = [](const std::string& in) {
        auto got = AutoCorrect::RepositionTone(U8(in));
        if (!got.has_value()) ++g_pass;
        else {
            ++g_fail;
            std::cout << "  FAIL: repositionTone(\"" << in << "\") = \""
                      << ToU8(got.value()) << "\"  (mong đợi nil)\n";
        }
    };
    // Lớp 1: dời dấu thanh về đúng vị trí.
    checkReposition("hòa", "hoà");   // dấu ở 'o' (cũ) -> 'a' (modern)
    checkReposition("qúy", "quý");   // dấu lên 'y'
    checkReposition("khỏe", "khoẻ");
    // Đã đúng vị trí -> trả chính nó (không đổi).
    checkReposition("tiếng", "tiếng");
    checkReposition("giờ", "giờ");
    checkReposition("hoà", "hoà");
    // Không có dấu thanh -> nil.
    checkRepositionNil("hoa");
    checkRepositionNil("tieng");

    // Lớp 2: từ điển (override + tự sinh).
    {
        const auto& dict = AutoCorrectDictionary::Shared();
        auto checkLookup = [&](const std::string& in, const std::string& expect) {
            auto got = dict.Lookup(U8(in));
            std::u32string want = U8(expect);
            if (got.has_value() && got.value() == want) ++g_pass;
            else {
                ++g_fail;
                std::cout << "  FAIL: lookup(\"" << in << "\") = \""
                          << (got.has_value() ? ToU8(got.value()) : std::string("nil"))
                          << "\"  (mong đợi \"" << expect << "\")\n";
            }
        };
        auto checkLookupNil = [&](const std::string& in) {
            auto got = dict.Lookup(U8(in));
            if (!got.has_value()) ++g_pass;
            else {
                ++g_fail;
                std::cout << "  FAIL: lookup(\"" << in << "\") = \""
                          << ToU8(got.value()) << "\"  (mong đợi nil)\n";
            }
        };
        // Override kinh điển.
        checkLookup("giừo", "giờ");
        checkLookup("nhièu", "nhiều");
        checkLookup("ngừoi", "người");
        checkLookup("đựoc", "được");
        // Biến thể tự sinh: dấu rơi nhầm nguyên âm.
        checkLookup("nhiêù", "nhiều");
        // Từ đúng -> KHÔNG bị "sửa".
        checkLookupNil("giờ");
        checkLookupNil("nhiều");
        checkLookupNil("người");
        checkLookupNil("được");
        // Biến thể trùng một TỪ ĐÚNG khác -> KHÔNG được "sửa" (không phá từ thật).
        // "dậy" sinh biến thể "dạy" nhưng "dạy" là từ đúng (dạy học) -> loại khỏi bảng.
        checkLookupNil("dạy");
        // Nhưng typo thật của "dậy" (dấu nặng ở 'y' thay vì 'â') vẫn phải sửa được.
        checkLookup("dâỵ", "dậy");
        // Giữ kiểu hoa của chữ đầu.
        checkLookup("Giừo", "Giờ");
        checkLookup("Nhièu", "Nhiều");
    }

    // IsRealWord: phân biệt từ đúng vs typo dấu-sai-chỗ.
    checkEq(AutoCorrect::IsRealWord(U"dạy"), true, "dạy là từ thật");
    checkEq(AutoCorrect::IsRealWord(U"nhiêù"), false, "nhiêù dấu sai chỗ");

    // An toàn: correctWord không đụng ASCII / từ đúng.
    auto checkCorrectNil = [](const std::string& in) {
        if (!AutoCorrect::CorrectWord(U8(in)).has_value()) ++g_pass;
        else {
            ++g_fail;
            std::cout << "  FAIL: correctWord(\"" << in << "\") kỳ vọng nil\n";
        }
    };
    auto checkCorrect = [](const std::string& in, const std::string& expect,
                           AutoCorrectResult::Reason reason) {
        auto got = AutoCorrect::CorrectWord(U8(in));
        std::u32string want = U8(expect);
        if (got.has_value() && got.value().corrected == want && got.value().reason == reason)
            ++g_pass;
        else {
            ++g_fail;
            std::cout << "  FAIL: correctWord(\"" << in << "\") = \""
                      << (got.has_value() ? ToU8(got.value().corrected) : std::string("nil"))
                      << "\"  (mong đợi \"" << expect << "\")\n";
        }
    };
    checkCorrectNil("hello");
    checkCorrectNil("the");
    checkCorrectNil("Github");
    // Từ ASCII chứa nguyên âm thường (a/e/o/u/i/y) — có trong bảng ngược nhưng
    // KHÔNG mang dấu -> guard an toàn phải bỏ qua, không auto-correct.
    checkCorrectNil("bay");
    checkCorrectNil("cay");
    checkCorrectNil("tiếng");   // từ tiếng Việt đúng
    checkCorrectNil("giờ");
    checkCorrectNil("người");
    // correctWord điều phối 2 lớp.
    checkCorrect("hòa", "hoà", AutoCorrectResult::Reason::ToneReposition);
    checkCorrect("giừo", "giờ", AutoCorrectResult::Reason::Dictionary);
    checkCorrect("nhièu", "nhiều", AutoCorrectResult::Reason::Dictionary);

    std::cout << "\n" << g_pass << " pass, " << g_fail << " fail.\n";
    return g_fail == 0 ? 0 : 1;
}
