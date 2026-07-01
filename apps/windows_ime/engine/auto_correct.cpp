// auto_correct.cpp
// ----------------
// Cài đặt tự-sửa lỗi gõ nhanh. Port 1-1 từ AutoCorrect.swift + AutoCorrectDictionary.swift.
// Phải cho KẾT QUẢ GIỐNG bản Swift trên cùng bộ ca test chuẩn (golden cases).

#include "auto_correct.h"

#include <set>
#include <unordered_set>

#include "viet_syllable.h"
#include "viet_table.h"

namespace bowgo {

namespace {

char32_t ToLower(char32_t c) {
    return (c >= U'A' && c <= U'Z') ? (c + 32) : c;
}

char32_t ToUpper(char32_t c) {
    return (c >= U'a' && c <= U'z') ? (c - 32) : c;
}

bool IsAsciiLetter(char32_t c) {
    char32_t l = ToLower(c);
    return l >= U'a' && l <= U'z';
}

bool IsVowelLetter(char32_t base) {
    char32_t l = ToLower(base);
    return l == U'a' || l == U'e' || l == U'i' || l == U'o' || l == U'u' || l == U'y';
}

std::u32string Lowercase(const std::u32string& s) {
    std::u32string out;
    out.reserve(s.size());
    for (char32_t c : s) out.push_back(ToLower(c));
    return out;
}

// ── Bảng ngược của VietTable: ký tự dựng sẵn -> (chữ gốc, dấu biến âm, dấu thanh).
// Vd 'ế' -> ('e', Circumflex, Acute); 'ự' -> ('u', Horn, Dot); 'đ' -> ('d', Dyet, None).
struct Parts {
    char32_t base;
    Mark mark;
    Tone tone;
};

// Xây dựng bảng ngược từ chính VietTable để LUÔN đồng bộ với bảng gõ.
const std::unordered_map<char32_t, Parts>& CharDecomposeMap() {
    static const std::unordered_map<char32_t, Parts> m = [] {
        std::unordered_map<char32_t, Parts> map;
        const std::vector<std::pair<char32_t, std::vector<Mark>>> bases = {
            {U'a', {Mark::None, Mark::Circumflex, Mark::Breve}},
            {U'e', {Mark::None, Mark::Circumflex}},
            {U'i', {Mark::None}},
            {U'o', {Mark::None, Mark::Circumflex, Mark::Horn}},
            {U'u', {Mark::None, Mark::Horn}},
            {U'y', {Mark::None}},
        };
        const std::vector<Tone> tones = {Tone::None,  Tone::Acute, Tone::Grave,
                                         Tone::Hook,  Tone::Tilde, Tone::Dot};
        for (const auto& [base, marks] : bases) {
            for (Mark mark : marks) {
                for (Tone tone : tones) {
                    char32_t ch = VietTable::Compose(base, mark, tone);
                    if (ch == 0) continue;
                    // Chỉ ghi nếu chưa có (none-mark ưu tiên cho ký tự gốc a/e/...).
                    if (map.find(ch) == map.end()) {
                        map[ch] = Parts{base, mark, tone};
                    }
                    // Bản HOA: ký tự Việt hoa không lệch +/-32 so với thường ->
                    // dựng qua Compose thay vì cộng/trừ code point.
                    char32_t up_ch = VietTable::Compose(ToUpper(base), mark, tone);
                    if (up_ch != 0 && up_ch != ch && map.find(up_ch) == map.end()) {
                        map[up_ch] = Parts{ToUpper(base), mark, tone};
                    }
                }
            }
        }
        // đ (không mang dấu thanh).
        char32_t d = VietTable::Compose(U'd', Mark::Dyet, Tone::None);
        if (d != 0) {
            map[d] = Parts{U'd', Mark::Dyet, Tone::None};
            char32_t d_up = VietTable::Compose(U'D', Mark::Dyet, Tone::None);
            if (d_up != 0) map[d_up] = Parts{U'D', Mark::Dyet, Tone::None};
        }
        return map;
    }();
    return m;
}

}  // namespace

// ── Decomposed ────────────────────────────────────────────────────────────

std::u32string Decomposed::Toneless() const {
    std::u32string s;
    for (const Letter& l : letters) {
        char32_t c = VietTable::Compose(l.base, l.mark, Tone::None);
        s.push_back(c != 0 ? c : l.base);
    }
    return s;
}

std::u32string Decomposed::Render(int tone_at) const {
    std::u32string out;
    for (int i = 0; i < static_cast<int>(letters.size()); ++i) {
        Tone t = (i == tone_at) ? tone : Tone::None;
        char32_t c = VietTable::Compose(letters[i].base, letters[i].mark, t);
        out.push_back(c != 0 ? c : letters[i].base);
    }
    return out;
}

std::optional<Decomposed> Decomposed::Parse(const std::u32string& word) {
    const auto& char_map = CharDecomposeMap();
    std::vector<Letter> letters;
    Tone tone = Tone::None;
    for (char32_t ch : word) {
        auto it = char_map.find(ch);
        if (it != char_map.end()) {
            letters.push_back(Letter{it->second.base, it->second.mark});
            if (it->second.tone != Tone::None) tone = it->second.tone;
        } else if (IsAsciiLetter(ch)) {
            letters.push_back(Letter{ch, Mark::None});
        } else {
            return std::nullopt;  // ký tự lạ -> không phân rã được
        }
    }
    if (letters.empty()) return std::nullopt;
    Decomposed d;
    d.letters = std::move(letters);
    d.tone = tone;
    return d;
}

// ── ToneRules ─────────────────────────────────────────────────────────────

// Chọn vị trí đặt dấu thanh cho một dãy chữ cái — theo quy tắc chính tả "modern":
//   1. Nguyên âm mang dấu biến âm (â ê ô ơ ư ă) -> dấu lên đó (chỉ số cuối).
//   2. Có phụ âm cuối -> nguyên âm cuối của cụm.
//   3. Cụm hở: 2 nguyên âm -> đầu, trừ "oa/oe/uy" -> sau; 3 nguyên âm -> giữa.
//   4. 1 nguyên âm -> chính nó.
int ToneRules::TargetIndex(const std::vector<Decomposed::Letter>& letters) {
    // Luật 1: nguyên âm có dấu biến âm — lấy chỉ số CUỐI.
    for (int i = static_cast<int>(letters.size()) - 1; i >= 0; --i) {
        Mark m = letters[i].mark;
        if (m == Mark::Circumflex || m == Mark::Breve || m == Mark::Horn) {
            return i;
        }
    }

    std::vector<int> vowel_idx;
    for (int i = 0; i < static_cast<int>(letters.size()); ++i) {
        if (IsVowelLetter(letters[i].base)) vowel_idx.push_back(i);
    }

    // Gộp nguyên âm trùng liên tiếp (kéo dài) về một đại diện đầu.
    if (vowel_idx.size() >= 2) {
        std::vector<int> collapsed;
        for (int idx : vowel_idx) {
            if (!collapsed.empty() &&
                ToLower(letters[collapsed.back()].base) == ToLower(letters[idx].base)) {
                continue;
            }
            collapsed.push_back(idx);
        }
        vowel_idx = collapsed;
    }

    // "gi"/"qu": 'i'/'u' là bán phụ âm đầu, loại khỏi cụm nếu còn nguyên âm khác.
    if (vowel_idx.size() >= 2) {
        int first = vowel_idx.front();
        char32_t first_base = ToLower(letters[first].base);
        char32_t prev_base = first > 0 ? ToLower(letters[first - 1].base) : U' ';
        if ((first_base == U'i' && prev_base == U'g') ||
            (first_base == U'u' && prev_base == U'q')) {
            vowel_idx.erase(vowel_idx.begin());
        }
    }

    if (vowel_idx.empty()) return -1;
    int start = vowel_idx.front();
    int end = vowel_idx.back();
    int count = static_cast<int>(vowel_idx.size());

    bool has_final_consonant =
        (end + 1 < static_cast<int>(letters.size())) &&
        !IsVowelLetter(letters[end + 1].base);
    if (has_final_consonant) return end;

    switch (count) {
        case 1:
            return start;
        case 2: {
            char32_t a = ToLower(letters[start].base);
            char32_t b = ToLower(letters[end].base);
            bool open_tail =
                (a == U'o' && (b == U'a' || b == U'e')) || (a == U'u' && b == U'y');
            return open_tail ? end : start;
        }
        default:
            return vowel_idx[1];
    }
}

// ── AutoCorrect (lớp 1 + điều phối) ───────────────────────────────────────

// Chuỗi có chứa ký tự MANG DẤU tiếng Việt (dấu thanh HOẶC mũ/móc/trăng/đ) không?
// LƯU Ý: chữ thường a/e/o/u/i/y KHÔNG tính là "có dấu" — nếu tính, mọi từ ASCII
// (kể cả "hello", "bay") sẽ lọt qua guard an toàn và bị auto-correct đụng nhầm.
bool AutoCorrect::ContainsVietnameseDiacritic(const std::u32string& word) {
    const auto& char_map = CharDecomposeMap();
    for (char32_t ch : word) {
        auto it = char_map.find(ch);
        if (it != char_map.end() &&
            (it->second.tone != Tone::None || it->second.mark != Mark::None)) {
            return true;
        }
    }
    return false;
}

// Một chuỗi có phải TỪ ĐÚNG thật không (để không "sửa" nhầm nó)?
// = vần hợp lệ VÀ dấu thanh nằm ĐÚNG vị trí chuẩn chính tả. Chỉ true cho từ
// gõ chuẩn (dạy, tay, mây), false cho typo dấu-sai-chỗ (nhiêù, cuời) dù vần
// của chúng có thể hợp lệ.
bool AutoCorrect::IsRealWord(const std::u32string& word) {
    if (!VietSyllable::IsValidDisplay(word)) return false;
    auto dec = Decomposed::Parse(word);
    if (!dec) return false;
    // Không mang dấu thanh -> coi là "đúng" (không phải lỗi dấu-sai-chỗ).
    if (dec->tone == Tone::None) return true;
    // Vị trí dấu thanh THỰC TẾ trong chuỗi.
    const auto& char_map = CharDecomposeMap();
    int real_idx = -1;
    for (int i = 0; i < static_cast<int>(word.size()); ++i) {
        auto it = char_map.find(word[i]);
        if (it != char_map.end() && it->second.tone != Tone::None) real_idx = i;
    }
    // Đúng từ khi dấu đặt ĐÚNG vị trí chuẩn.
    return real_idx == ToneRules::TargetIndex(dec->letters);
}

// Phân rã từ thành (chữ cái + mark) + (một dấu thanh), rồi dựng lại với dấu thanh
// đặt đúng vị trí theo quy tắc chính tả. Trả nullopt nếu không áp dụng được.
std::optional<std::u32string> AutoCorrect::RepositionTone(const std::u32string& word) {
    auto decomposed = Decomposed::Parse(word);
    if (!decomposed) return std::nullopt;
    // Không có dấu thanh -> không có gì để dời.
    if (decomposed->tone == Tone::None) return std::nullopt;
    // Cấu trúc phải là âm tiết tiếng Việt hợp lệ (đã bỏ thanh).
    if (!VietSyllable::IsValidToneless(decomposed->Toneless())) return std::nullopt;

    int target = ToneRules::TargetIndex(decomposed->letters);
    if (target < 0) return std::nullopt;

    // Dựng lại: dấu thanh CHỈ đặt lên `target`.
    return decomposed->Render(target);
}

std::optional<AutoCorrectResult> AutoCorrect::CorrectWord(const std::u32string& word) {
    if (word.empty()) return std::nullopt;
    // An toàn: chỉ xét từ có dấu tiếng Việt. Bỏ qua ASCII thuần (Anh/tên riêng).
    if (!ContainsVietnameseDiacritic(word)) return std::nullopt;

    // Lớp 1: dời dấu thanh về đúng vị trí.
    if (auto repositioned = RepositionTone(word); repositioned && *repositioned != word) {
        return AutoCorrectResult{*repositioned, AutoCorrectResult::Reason::ToneReposition};
    }

    // Lớp 2: tra từ điển lỗi phổ biến (khớp không phân biệt hoa/thường).
    if (auto fixed = AutoCorrectDictionary::Shared().Lookup(word); fixed && *fixed != word) {
        return AutoCorrectResult{*fixed, AutoCorrectResult::Reason::Dictionary};
    }

    return std::nullopt;
}

// ── AutoCorrectDictionary (lớp 2) ─────────────────────────────────────────

namespace {

// Biến thể "thiếu dấu biến âm": với mỗi nguyên âm mang mũ/móc/trăng, tạo bản bỏ
// mark đó (giữ nguyên dấu thanh) — mô phỏng gõ nhanh quên dấu mũ.
std::set<std::u32string> MissingMarkVariants(const Decomposed& dec) {
    std::set<std::u32string> out;
    for (int i = 0; i < static_cast<int>(dec.letters.size()); ++i) {
        if (dec.letters[i].mark == Mark::None || dec.letters[i].mark == Mark::Dyet) {
            continue;
        }
        Decomposed copy = dec;
        copy.letters[i].mark = Mark::None;
        int target = ToneRules::TargetIndex(copy.letters);
        if (target < 0) continue;
        out.insert(Lowercase(copy.Render(target)));
    }
    return out;
}

// Sinh các biến thể-lỗi thường gặp của MỘT từ đúng (đã lowercase).
// Các lỗi mô phỏng: gõ nhanh làm dấu thanh rơi nhầm nguyên âm, thiếu dấu mũ/móc.
std::set<std::u32string> Misspellings(const std::u32string& correct) {
    std::set<std::u32string> out;
    auto dec_opt = Decomposed::Parse(correct);
    if (!dec_opt || dec_opt->tone == Tone::None) {
        // Không có dấu thanh: chỉ sinh lỗi thiếu-dấu-mũ (nếu có mũ/móc/trăng).
        if (dec_opt) {
            auto mm = MissingMarkVariants(*dec_opt);
            out.insert(mm.begin(), mm.end());
        }
        return out;
    }
    const Decomposed& dec = *dec_opt;

    // (a) DẤU THANH RƠI NHẦM NGUYÊN ÂM: đặt dấu thanh lên MỖI nguyên âm khác vị trí
    //     đúng. Đây là lỗi gõ nhanh phổ biến nhất ("nhièu", "giừo"...).
    int correct_target = ToneRules::TargetIndex(dec.letters);
    for (int i = 0; i < static_cast<int>(dec.letters.size()); ++i) {
        if (!IsVowelLetter(dec.letters[i].base)) continue;
        if (i == correct_target) continue;
        out.insert(Lowercase(dec.Render(i)));
    }

    // (b) THIẾU DẤU MŨ/MÓC/TRĂNG trên nguyên âm mang dấu thanh.
    auto mm = MissingMarkVariants(dec);
    out.insert(mm.begin(), mm.end());

    return out;
}

// Áp kiểu hoa/thường của `source` lên `target` (theo từng ký tự, phần dư giữ thường).
std::u32string ApplyCasing(const std::u32string& source, const std::u32string& target) {
    std::u32string out;
    for (int i = 0; i < static_cast<int>(target.size()); ++i) {
        char32_t ch = target[i];
        if (i < static_cast<int>(source.size()) && source[i] != ToLower(source[i])) {
            // source[i] là chữ hoa (khác bản thường của nó).
            char32_t up = ToUpper(ch);
            // Ký tự Việt có dấu: dựng bản hoa qua bảng ngược -> Compose.
            const auto& char_map = CharDecomposeMap();
            auto it = char_map.find(ch);
            if (it != char_map.end()) {
                char32_t comp = VietTable::Compose(ToUpper(it->second.base),
                                                   it->second.mark, it->second.tone);
                out.push_back(comp != 0 ? comp : up);
            } else {
                out.push_back(up);
            }
        } else {
            out.push_back(ch);
        }
    }
    return out;
}

}  // namespace

const std::vector<std::u32string>& AutoCorrectDictionary::Words() {
    // DANH SÁCH TỪ ĐÚNG phổ biến. Thêm từ mới vào đây để mở rộng ("tự thêm để trend").
    static const std::vector<std::u32string> words = {
        // đại từ / hư từ hay gặp
        U"giờ", U"giờ", U"giữa", U"giường", U"người", U"được", U"nhiều", U"chiều", U"yêu",
        U"tiền", U"biết", U"việc", U"hiểu", U"chuyện", U"muốn", U"buồn", U"luôn", U"cuộc",
        // động từ / tính từ thường dùng
        U"trường", U"thương", U"hường", U"phường", U"vườn", U"mượn", U"lười", U"cười",
        U"rượu", U"hươu", U"bưởi", U"tưởng", U"thưởng", U"nướng", U"xưởng",
        U"tuổi", U"cuối", U"suối", U"chuối", U"đuối", U"nuôi", U"muối",
        U"khỏe", U"khoẻ", U"hoà", U"hoạ", U"loạ", U"toà", U"xoà", U"goá",
        U"quý", U"quà", U"quả", U"quẻ", U"quỳ", U"thuý", U"tuý",
        // âm tiết mang mũ hay bị quên
        U"mấy", U"thấy", U"đấy", U"cây", U"mây", U"bây", U"gây", U"dậy", U"chạy",
        U"tôi", U"rồi", U"mới", U"với", U"vội", U"đội", U"hỏi", U"gọi", U"nói",
        U"về", U"lễ", U"kể", U"thế", U"để", U"nếu", U"đều", U"kêu", U"nhiêu",
        U"cũng", U"những", U"từng", U"cùng", U"vẫn", U"lần", U"phần", U"gần",
    };
    return words;
}

const std::vector<std::pair<std::u32string, std::u32string>>&
AutoCorrectDictionary::Overrides() {
    // OVERRIDES thủ công — cặp (lỗi -> đúng) đặc thù, ưu tiên cao hơn bản sinh tự động.
    static const std::vector<std::pair<std::u32string, std::u32string>> overrides = {
        {U"giừo", U"giờ"},     // 'ư' + dời chữ -> 'ờ'
        {U"nhièu", U"nhiều"},  // dấu ở 'e' -> ở 'ê'
        {U"ngừoi", U"người"},
        {U"đựoc", U"được"},
        {U"cuộcj", U"cuộc"},
    };
    return overrides;
}

AutoCorrectDictionary::AutoCorrectDictionary(
    const std::vector<std::u32string>& words,
    const std::vector<std::pair<std::u32string, std::u32string>>& overrides) {
    // 1) Sinh biến thể-lỗi từ danh sách từ đúng.
    for (const std::u32string& correct : words) {
        std::u32string key = Lowercase(correct);
        for (const std::u32string& variant : Misspellings(key)) {
            // Không ghi đè nếu variant TRÙNG một từ đúng khác (tránh sửa nhầm từ thật).
            if (variant == key) continue;
            if (table_.find(variant) == table_.end()) table_[variant] = key;
        }
    }
    // Xoá các key mà bản thân nó cũng là một từ đúng (an toàn: đừng "sửa" từ đúng).
    // (a) Trùng một từ trong danh sách `words`.
    std::unordered_set<std::u32string> correct_set;
    for (const std::u32string& w : words) correct_set.insert(Lowercase(w));
    for (auto it = table_.begin(); it != table_.end();) {
        if (correct_set.count(it->first)) {
            it = table_.erase(it);
        } else {
            ++it;
        }
    }
    // (b) Bản thân biến thể đã là một TỪ ĐÚNG (dù không nằm trong `words`). Ví dụ
    //     "dậy" sinh biến thể "dạy" — nhưng "dạy" cũng là từ đúng (dạy học), không
    //     phải lỗi gõ; sửa "dạy"→"dậy" là phá từ đúng. Phân biệt với typo dấu-sai-chỗ
    //     (nhiêù, giừo) bằng: biến thể có VẦN hợp lệ VÀ dấu thanh đặt ĐÚNG vị trí
    //     chuẩn → là từ thật, loại bỏ. (nhiêù có vần "iêu" hợp lệ nhưng dấu ở 'u'
    //     sai vị trí -> KHÔNG bị loại, vẫn sửa được về "nhiều".)
    for (auto it = table_.begin(); it != table_.end();) {
        if (AutoCorrect::IsRealWord(it->first)) {
            it = table_.erase(it);
        } else {
            ++it;
        }
    }

    // 2) Overrides thủ công (ưu tiên cao nhất, ghi đè bản sinh tự động).
    for (const auto& [wrong, right] : overrides) {
        table_[Lowercase(wrong)] = Lowercase(right);
    }
}

const AutoCorrectDictionary& AutoCorrectDictionary::Shared() {
    static const AutoCorrectDictionary shared(Words(), Overrides());
    return shared;
}

std::optional<std::u32string> AutoCorrectDictionary::Lookup(
    const std::u32string& word) const {
    std::u32string key = Lowercase(word);
    auto it = table_.find(key);
    if (it == table_.end()) return std::nullopt;
    return ApplyCasing(word, it->second);
}

}  // namespace bowgo
