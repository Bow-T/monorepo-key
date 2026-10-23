// engine.cpp
// ----------
// Cài đặt bộ não. Port 1-1 từ Engine.swift; xem file đó (và bản Dart) làm spec.
// Mọi nhánh logic ở đây phải khớp để vượt cùng bộ ca test chuẩn.

#include "engine.h"

#include "viet_table.h"

namespace bowgo {

namespace {

char32_t ToLower(char32_t c) {
    return (c >= U'A' && c <= U'Z') ? (c + 32) : c;
}

bool IsAsciiLetter(char32_t c) {
    char32_t l = ToLower(c);
    return l >= U'a' && l <= U'z';
}

bool IsAsciiDigit(char32_t c) { return c >= U'0' && c <= U'9'; }

bool IsVietVowel(char32_t base) {
    char32_t l = ToLower(base);
    return l == U'a' || l == U'e' || l == U'i' || l == U'o' || l == U'u' || l == U'y';
}

}  // namespace

VietEngine::VietEngine(InputMethod method, ToneStyle tone_style)
    : method_(method), tone_style_(tone_style) {}

void VietEngine::ResetSyllable() {
    letters_.clear();
    tone_ = Tone::None;
}

void VietEngine::Clear() {
    ResetSyllable();
    raw_keys_.clear();
}

std::optional<std::u32string> VietEngine::Process(char32_t ch) {
    // Ghi phím thô TRƯỚC khi xử lý (nếu nó thuộc về âm tiết). Ngắt từ tự reset.
    bool will_be_word_break;
    if (IsAsciiLetter(ch)) {
        will_be_word_break = false;
    } else {
        bool is_vni_tone_key =
            (method_ == InputMethod::Vni) && IsAsciiDigit(ch) && !letters_.empty();
        will_be_word_break = !is_vni_tone_key;
    }
    if (!will_be_word_break) {
        raw_keys_.push_back(ch);
    }
    return Step(ch);
}

std::optional<std::u32string> VietEngine::Step(char32_t ch) {
    // 1) Ký tự ngắt từ -> chốt âm tiết. Ngoại lệ: chữ số trong VNI là phím-dấu.
    if (!IsAsciiLetter(ch)) {
        bool is_vni_tone_key =
            (method_ == InputMethod::Vni) && IsAsciiDigit(ch) && !letters_.empty();
        if (!is_vni_tone_key) {
            ResetSyllable();
            raw_keys_.clear();
            return std::nullopt;
        }
    }

    // 2) Thử coi ch là phím-dấu.
    switch (ApplyAsDiacritic(ch)) {
        case DiacriticResult::Applied:
            return Render();
        case DiacriticResult::Cancelled:
            // GÕ LẠI ĐỂ BỎ DẤU: dấu đã gỡ; ký tự phím-dấu hiện như chữ thường.
            letters_.push_back({ch, Mark::None});
            return Render();
        case DiacriticResult::NotDiacritic:
            break;
    }

    // 3) Không phải phím-dấu -> nối như chữ thường.
    letters_.push_back({ch, Mark::None});
    PropagateUoHorn();
    return Render();
}

std::optional<std::u32string> VietEngine::Backspace() {
    if (raw_keys_.empty()) return std::nullopt;
    raw_keys_.pop_back();

    ResetSyllable();
    std::vector<char32_t> keys = raw_keys_;
    raw_keys_.clear();
    std::u32string current;
    for (char32_t key : keys) {
        raw_keys_.push_back(key);
        auto r = Step(key);
        current = r.value_or(U"");
    }
    return current;
}

// MARK: - Áp dụng phím-dấu

// Tổ hợp PHỤ ÂM ĐẦU không tồn tại trong tiếng Việt (có trong tiếng Anh/thuật ngữ:
// blue, brown, clear, drop, flag, print, string, swift...). Tiếng Việt KHÔNG có âm
// tiết nào bắt đầu bằng các cụm này, nên khi âm tiết đang gõ mở đầu bằng một trong số
// đó, ta CHẮC CHẮN người dùng đang gõ từ phi-Việt -> KHÔNG coi phím nào là phím-dấu
// (tránh "clear"->"clẻa", "printf"->"prìnt"). Cũng là cách nhận diện sớm để không
// phá lệnh terminal.
// LƯU Ý: KHÔNG đưa cụm chứa 'w' (sw, tw, wr) vào đây — trong Telex 'w' là phím gõ
// tắt: "tw"->tư, "sw"->sư, "w"->ư. Chặn chúng sẽ phá tính năng gõ tắt. Từ tiếng Anh
// như "swift"/"twin" để cơ chế tự-khôi-phục-tiếng-Anh xử lý khi chốt từ.
// (Khớp Engine.swift `nonVietInitialClusters`.)
static constexpr char32_t kNonVietInitialClusters[][2] = {
    {U'b', U'l'}, {U'b', U'r'}, {U'c', U'l'}, {U'c', U'r'}, {U'd', U'r'}, {U'f', U'l'},
    {U'f', U'r'}, {U'g', U'l'}, {U'g', U'r'}, {U'p', U'l'}, {U'p', U'r'},
    {U's', U'c'}, {U's', U'k'}, {U's', U'l'}, {U's', U'm'}, {U's', U'n'}, {U's', U'p'},
    {U's', U't'},
};

// Âm tiết hiện tại có mở đầu bằng tổ hợp phụ âm đầu phi-Việt không, KHI xét thêm
// phím `ch` sắp gõ? Hai trường hợp:
//   • Đã có >=2 chữ và 2 chữ GỐC đầu là cụm phi-Việt (vd đã gõ "st" của "strings").
//   • Mới có ĐÚNG 1 phụ âm, và phụ âm đó + `ch` tạo cụm phi-Việt — cần xét sớm vì
//     phím thứ 2 có thể chính là phím-dấu, sẽ bị áp NGAY nếu không chặn trước.
bool VietEngine::StartsWithNonVietCluster(char32_t ch) const {
    if (letters_.empty()) return false;
    const char32_t a = ToLower(letters_[0].base);
    const char32_t b = ToLower(letters_.size() >= 2 ? letters_[1].base : ch);
    for (const auto& cluster : kNonVietInitialClusters) {
        if (cluster[0] == a && cluster[1] == b) return true;
    }
    return false;
}

VietEngine::DiacriticResult VietEngine::ApplyAsDiacritic(char32_t ch) {
    // Âm tiết mở đầu bằng tổ hợp phụ âm phi-Việt (str, cl, pr...) -> đây là từ tiếng
    // Anh/lệnh, không phải tiếng Việt. Giữ mọi phím nguyên bản.
    if (StartsWithNonVietCluster(ch)) return DiacriticResult::NotDiacritic;
    return method_ == InputMethod::Telex ? ApplyTelex(ch) : ApplyVni(ch);
}

VietEngine::DiacriticResult VietEngine::ApplyTelex(char32_t ch) {
    char32_t lower = ToLower(ch);
    switch (lower) {
        case U's': return SetTone(Tone::Acute);
        case U'f': return SetTone(Tone::Grave);
        case U'r': return SetTone(Tone::Hook);
        case U'x': return SetTone(Tone::Tilde);
        case U'j': return SetTone(Tone::Dot);
        case U'z': return SetTone(Tone::None);  // xoá dấu thanh

        case U'a':
        case U'e':
        case U'o':
            return ApplyCircumflexRepeat(lower);

        case U'w': {
            // Xử lý ww -> w: nếu phím trước là w và không có nguyên âm trước w đó
            // thì chữ 'ư' (do w gõ tắt tạo ra) trở về chữ 'w' thô (ww->w, www->ww).
            const size_t raw_len = raw_keys_.size();
            const bool is_consecutive_w =
                raw_len >= 2 && ToLower(raw_keys_[raw_len - 2]) == U'w';
            if (is_consecutive_w) {
                const char32_t before = raw_len >= 3 ? ToLower(raw_keys_[raw_len - 3]) : 0;
                const bool has_vowel_before_prev_w =
                    before == U'u' || before == U'o' || before == U'a';
                if (!has_vowel_before_prev_w && !letters_.empty() &&
                    letters_.back().mark == Mark::Horn &&
                    ToLower(letters_.back().base) == U'u') {
                    letters_.back().base = ch;
                    letters_.back().mark = Mark::None;
                    return DiacriticResult::Applied;
                }
            }
            return ApplyHornOrBreve();
        }
        case U'd':
            if (!letters_.empty() && ToLower(letters_.back().base) == U'd') {
                if (letters_.back().mark == Mark::Dyet) {
                    return RemoveMarkOnLast();  // đ rồi gõ 'd' nữa -> bỏ gạch (ddd -> dd)
                }
                if (letters_.back().mark == Mark::None) {
                    return SetMarkOnLast(Mark::Dyet);  // dd -> đ
                }
            }
            return DiacriticResult::NotDiacritic;

        default:
            return DiacriticResult::NotDiacritic;
    }
}

// Lặp nguyên âm a/e/o trong Telex: tạo mũ (aa->â) hoặc KÉO DÀI nguyên âm.
// CHU KỲ MŨ tính theo SỐ LẦN gõ nguyên âm đó trong "run" cuối (đếm cả khi có
// phím-thanh xen giữa — vd "casa" == "caas" == cấ). Dấu thanh "ăn theo", không
// phá chu kỳ:
//   lần 2 gõ -> tạo mũ (aa->â, asa->ấ, these->thế)
//   lần 3 gõ -> gỡ mũ (aaa->aa, asaa->áaa)
//   lần >=4  -> kéo dài thô, KHÔNG tạo lại mũ (aaaa->aaa, ojooo->ọoo)
VietEngine::DiacriticResult VietEngine::ApplyCircumflexRepeat(char32_t lower) {
    if (letters_.empty() || ToLower(letters_.back().base) != lower) {
        return DiacriticResult::NotDiacritic;  // 'a/e/o' đơn -> nối như chữ thường
    }

    const int press_count = TrailingVowelPressCount(lower);

    if (letters_.back().mark == Mark::Circumflex) {
        return RemoveMarkOnLast();  // â/ê/ô + gõ thêm -> gỡ mũ (chu kỳ lần 3)
    }
    if (letters_.back().mark == Mark::None) {
        if (press_count == 2 &&
            VietTable::Compose(letters_.back().base, Mark::Circumflex, Tone::None) != 0) {
            return SetMarkOnLast(Mark::Circumflex);  // aa -> â
        }
        return DiacriticResult::NotDiacritic;  // kéo dài thô (aaaa->aaa, áaa...)
    }
    return DiacriticResult::NotDiacritic;
}

// Đếm số lần phím nguyên âm `lower` được gõ trong "run" nguyên âm cuối của
// raw_keys_ — bỏ qua phím-thanh (s f r x j z) xen giữa, dừng khi gặp nguyên âm
// KHÁC hoặc phụ âm. Vd "casa" -> 2; "asaa" -> 3.
int VietEngine::TrailingVowelPressCount(char32_t lower) const {
    int n = 0;
    for (auto it = raw_keys_.rbegin(); it != raw_keys_.rend(); ++it) {
        char32_t k = ToLower(*it);
        if (k == lower) { ++n; continue; }
        if (k == U's' || k == U'f' || k == U'r' || k == U'x' || k == U'j' || k == U'z') {
            continue;  // phím-thanh không phá run
        }
        break;  // nguyên âm khác / phụ âm -> dừng
    }
    return n;
}

VietEngine::DiacriticResult VietEngine::ApplyVni(char32_t ch) {
    switch (ch) {
        case U'1': return SetTone(Tone::Acute);
        case U'2': return SetTone(Tone::Grave);
        case U'3': return SetTone(Tone::Hook);
        case U'4': return SetTone(Tone::Tilde);
        case U'5': return SetTone(Tone::Dot);
        case U'0': return SetTone(Tone::None);
        case U'6': return SetMarkOnNucleus(Mark::Circumflex)
                              .value_or(DiacriticResult::NotDiacritic);  // â/ê/ô
        case U'7': return ApplyHornVni();                                // ơ/ư/ươ/ưa
        case U'8': return SetMarkOnNucleus(Mark::Breve)
                              .value_or(DiacriticResult::NotDiacritic);  // ă
        case U'9': return SetMarkOrToggle(Mark::Dyet);                   // đ (lên 'd' đầu)
        default:   return DiacriticResult::NotDiacritic;
    }
}

// Tìm CỤM NGUYÊN ÂM (nucleus) của âm tiết: quét NGƯỢC từ cuối, BỎ QUA phụ âm cuối,
// lấy run nguyên âm liền nhau. Trả (start, end) chỉ số trong letters_, hoặc nullopt
// nếu âm tiết chưa có nguyên âm.
//
// Đây là chìa khoá để dấu/biến âm đặt ĐÚNG kể cả khi người dùng gõ phím-dấu SAU phụ
// âm cuối — vd "đuoc" rồi gõ "w" vẫn móc được cụm "uo" -> "đươc".
std::optional<std::pair<int, int>> VietEngine::VowelNucleusRange() const {
    int end = static_cast<int>(letters_.size()) - 1;
    while (end >= 0 && !IsVietVowel(letters_[end].base)) --end;
    if (end < 0) return std::nullopt;
    int start = end;
    while (start - 1 >= 0 && IsVietVowel(letters_[start - 1].base)) --start;
    return std::make_pair(start, end);
}

// w trong Telex: a->ă, o->ơ, u->ư (móc/trăng đặt lên CỤM NGUYÊN ÂM, không chỉ chữ
// cuối — nên "đuoc"+w -> "đươc"). Nếu không áp được -> gõ tắt -> 'ư'.
VietEngine::DiacriticResult VietEngine::ApplyHornOrBreve() {
    auto r = ApplyHornToNucleus(/*allow_breve=*/true);
    return r ? *r : InsertStandaloneW();
}

// 7 trong VNI: o->ơ, u->ư (KHÔNG có trăng 'ă', KHÔNG có gõ tắt ->'ư').
VietEngine::DiacriticResult VietEngine::ApplyHornVni() {
    return ApplyHornToNucleus(/*allow_breve=*/false).value_or(DiacriticResult::NotDiacritic);
}

// LÕI CHUNG đặt móc (và tuỳ chọn trăng) lên CỤM NGUYÊN ÂM. Trả nullopt nếu không áp
// được (caller tự fallback: Telex -> 'ư', VNI -> giữ thô). Tìm cụm qua
// VowelNucleusRange nên hoạt động kể cả khi phím-móc gõ SAU phụ âm cuối.
std::optional<VietEngine::DiacriticResult> VietEngine::ApplyHornToNucleus(bool allow_breve) {
    auto range = VowelNucleusRange();
    if (!range) return std::nullopt;
    const int v_start = range->first;
    const int v_end = range->second;

    // Cụm 2+ nguyên âm bắt đầu bằng "uo"/"ua" -> luật ươ/ưa riêng.
    if (v_end - v_start >= 1) {
        const char32_t a = ToLower(letters_[v_start].base);
        const char32_t b = ToLower(letters_[v_start + 1].base);
        const bool is_part_of_qu = v_start >= 1 && ToLower(letters_[v_start - 1].base) == U'q';

        // "uo" -> "ươ": móc CẢ HAI nguyên âm.
        if (a == U'u' && b == U'o' && !is_part_of_qu) {
            // "thuo": LUÔN móc 'o', và móc THÊM 'u' nếu có phụ âm cuối sau cụm
            // (thương). Không có phụ âm cuối thì chỉ móc 'o' (thuở).
            const bool is_thuo = v_start >= 2 &&
                                 ToLower(letters_[v_start - 2].base) == U't' &&
                                 ToLower(letters_[v_start - 1].base) == U'h';
            if (is_thuo) {
                if (letters_[v_start + 1].mark == Mark::Horn) {
                    letters_[v_start].mark = Mark::None;
                    letters_[v_start + 1].mark = Mark::None;
                    return DiacriticResult::Cancelled;
                }
                letters_[v_start + 1].mark = Mark::Horn;
                const bool has_final = v_end < static_cast<int>(letters_.size()) - 1;
                if (has_final) letters_[v_start].mark = Mark::Horn;
                return DiacriticResult::Applied;
            }
            // Gõ lại khi đã là "ươ" -> bỏ móc cả hai.
            if (letters_[v_start].mark == Mark::Horn && letters_[v_start + 1].mark == Mark::Horn) {
                letters_[v_start].mark = Mark::None;
                letters_[v_start + 1].mark = Mark::None;
                return DiacriticResult::Cancelled;
            }
            letters_[v_start].mark = Mark::Horn;
            letters_[v_start + 1].mark = Mark::Horn;
            return DiacriticResult::Applied;
        }

        // "ua" -> "ưa": chỉ móc 'u'.
        if (a == U'u' && b == U'a' && !is_part_of_qu) {
            if (letters_[v_start].mark == Mark::Horn) {
                letters_[v_start].mark = Mark::None;
                return DiacriticResult::Cancelled;
            }
            letters_[v_start].mark = Mark::Horn;
            return DiacriticResult::Applied;
        }
    }

    // Một nguyên âm trong cụm nhận móc/trăng: ưu tiên nguyên âm hợp GẦN CUỐI cụm.
    // BỎ 'u' sau 'q' (và 'i' sau 'g') — bán phụ âm của phụ âm đầu (qua7 KHÔNG thành qưa).
    int target_start = v_start;
    if (v_start >= 1) {
        const char32_t semivowel = ToLower(letters_[v_start].base);
        const char32_t prev = ToLower(letters_[v_start - 1].base);
        if ((semivowel == U'u' && prev == U'q') || (semivowel == U'i' && prev == U'g')) {
            target_start = v_start + 1;
        }
    }
    if (target_start > v_end) return std::nullopt;
    auto target = HornBreveTargetIndex(target_start, v_end, allow_breve);
    if (!target) return std::nullopt;
    switch (ToLower(letters_[*target].base)) {
        case U'a':
            return letters_[*target].mark == Mark::Breve ? RemoveMarkAt(*target)
                                                         : SetMarkAt(Mark::Breve, *target);
        case U'o':
        case U'u':
            return letters_[*target].mark == Mark::Horn ? RemoveMarkAt(*target)
                                                        : SetMarkAt(Mark::Horn, *target);
        default:
            return std::nullopt;
    }
}

// Chọn nguyên âm trong cụm [start..end] nhận móc/trăng đơn: nguyên âm phù hợp GẦN
// CUỐI cụm nhất. Telex (allow_breve) nhận a/o/u; VNI '7' chỉ nhận o/u.
std::optional<int> VietEngine::HornBreveTargetIndex(int start, int end, bool allow_breve) const {
    for (int i = end; i >= start; --i) {
        const char32_t l = ToLower(letters_[i].base);
        if (l == U'o' || l == U'u' || (allow_breve && l == U'a')) return i;
    }
    return std::nullopt;
}

// Đặt MŨ (â/ê/ô) hoặc TRĂNG (ă) của VNI lên CỤM NGUYÊN ÂM (không chỉ chữ cuối) — nên
// gõ "6"/"8" SAU phụ âm cuối / sau bán nguyên âm 'i' vẫn đúng: "muoi"+6 -> "muôi",
// "tang"+8 -> "tăng". Toggle: chữ đích đã mang đúng mark -> gỡ + số thô. Trả nullopt
// nếu cụm không có nguyên âm nào áp được.
std::optional<VietEngine::DiacriticResult> VietEngine::SetMarkOnNucleus(Mark mark) {
    auto range = VowelNucleusRange();
    if (!range) return std::nullopt;
    int start = range->first;
    const int end = range->second;

    // Bỏ 'u' sau 'q' / 'i' sau 'g' — bán phụ âm của phụ âm đầu, không nhận mũ/trăng.
    if (start >= 1) {
        const char32_t semivowel = ToLower(letters_[start].base);
        const char32_t prev = ToLower(letters_[start - 1].base);
        if ((semivowel == U'u' && prev == U'q') || (semivowel == U'i' && prev == U'g')) {
            start = start + 1;
        }
    }
    if (start > end) return std::nullopt;

    // Tìm nguyên âm GẦN CUỐI cụm nhận được mark.
    for (int i = end; i >= start; --i) {
        if (VietTable::Compose(letters_[i].base, mark, Tone::None) == 0) continue;
        if (letters_[i].mark == mark) return RemoveMarkAt(i);  // trùng -> gỡ + số thô
        return SetMarkAt(mark, i);
    }
    return std::nullopt;
}

// GÕ TẮT 'w' -> 'ư': khi 'w' không áp được móc/trăng cho cụm nguyên âm (âm tiết chưa
// có nguyên âm, hoặc cụm không có a/o/u), 'w' tự tạo nguyên âm 'ư'.
// Ví dụ: "tw"->tư, "mwf"->mừ, "w"->ư. Cách gõ tắt Telex phổ biến.
// Ngoại lệ: nếu chữ NGAY TRƯỚC thuộc nhóm không-ghép-được thì 'w' giữ thô.
// (Nhóm chữ không ghép 'w': w e y f j k z.)
VietEngine::DiacriticResult VietEngine::InsertStandaloneW() {
    if (!letters_.empty()) {
        char32_t prev = ToLower(letters_.back().base);
        if (prev == U'w' || prev == U'e' || prev == U'y' || prev == U'f' ||
            prev == U'j' || prev == U'k' || prev == U'z') {
            return DiacriticResult::NotDiacritic;
        }
    }
    // Chèn 'u' mang móc -> hiển thị 'ư'.
    letters_.push_back({U'u', Mark::Horn});
    return DiacriticResult::Applied;
}

// Lan móc trên cụm "uo" -> "ươ" khi gặp âm đóng {n,c,i,m,p,t} đứng ngay sau.
// Tiếng Việt không có âm tiết chứa "ưo"/"uơ" trần — luôn là "ươ". Chỉ kích hoạt
// khi ĐÚNG MỘT trong u/o đang có móc (để không đụng "huow"->hươ đang gõ dở).
void VietEngine::PropagateUoHorn() {
    const size_t n = letters_.size();
    if (n < 3) return;
    char32_t closer = ToLower(letters_[n - 1].base);
    if (closer != U'n' && closer != U'c' && closer != U'i' && closer != U'm' &&
        closer != U'p' && closer != U't') {
        return;
    }
    if (ToLower(letters_[n - 3].base) != U'u' || ToLower(letters_[n - 2].base) != U'o') {
        return;
    }
    bool u_horn = letters_[n - 3].mark == Mark::Horn;
    bool o_horn = letters_[n - 2].mark == Mark::Horn;
    if (u_horn != o_horn) {
        letters_[n - 3].mark = Mark::Horn;
        letters_[n - 2].mark = Mark::Horn;
    }
}

// MARK: - Thao tác trên âm tiết

bool VietEngine::HasVowel() const {
    for (const Letter& l : letters_) {
        if (IsVietVowel(l.base)) return true;
    }
    return false;
}

VietEngine::DiacriticResult VietEngine::SetTone(Tone tone) {
    // Dấu thanh chỉ hợp lệ khi âm tiết đã có ít nhất một nguyên âm (xem comment
    // trong Engine.swift: tránh "tre"->"tẻ", "trên"->"tển").
    if (!HasVowel()) return DiacriticResult::NotDiacritic;

    if (tone_ == tone && tone != Tone::None) {
        tone_ = Tone::None;  // gõ trùng dấu -> gỡ dấu, trả ký tự thô
        return DiacriticResult::Cancelled;
    }
    tone_ = tone;
    return DiacriticResult::Applied;
}

VietEngine::DiacriticResult VietEngine::SetMarkOnLast(Mark mark) {
    if (letters_.empty()) return DiacriticResult::NotDiacritic;
    Letter& last = letters_.back();
    if (VietTable::Compose(last.base, mark, Tone::None) == 0) {
        return DiacriticResult::NotDiacritic;  // tổ hợp không hợp lệ
    }
    last.mark = mark;
    return DiacriticResult::Applied;
}

// Như SetMarkOnLast nhưng nếu chữ cuối ĐÃ mang đúng biến âm đó thì GỠ ra và trả
// ký tự thô — dùng cho VNI khi gõ lại số-biến-âm trùng để hủy (a6->â, a66->a6;
// d9->đ, d99->d9). Cơ chế toggle: gỡ dấu rồi chèn phím thô.
VietEngine::DiacriticResult VietEngine::SetMarkOrToggle(Mark mark) {
    if (letters_.empty()) return DiacriticResult::NotDiacritic;
    if (letters_.back().mark == mark) {
        return RemoveMarkOnLast();  // gõ lại số-biến-âm trùng -> gỡ + ký tự số thô
    }
    return SetMarkOnLast(mark);
}

VietEngine::DiacriticResult VietEngine::RemoveMarkOnLast() {
    if (letters_.empty()) return DiacriticResult::NotDiacritic;
    letters_.back().mark = Mark::None;
    return DiacriticResult::Cancelled;
}

// Đặt dấu biến âm cho chữ tại VỊ TRÍ bất kỳ (không chỉ chữ cuối) — cần khi móc/trăng
// đặt lên nguyên âm nằm TRƯỚC phụ âm cuối (vd "muon"+w -> 'o' móc).
VietEngine::DiacriticResult VietEngine::SetMarkAt(Mark mark, int index) {
    if (index < 0 || index >= static_cast<int>(letters_.size())) {
        return DiacriticResult::NotDiacritic;
    }
    if (VietTable::Compose(letters_[index].base, mark, Tone::None) == 0) {
        return DiacriticResult::NotDiacritic;
    }
    letters_[index].mark = mark;
    return DiacriticResult::Applied;
}

// Gỡ dấu biến âm tại vị trí bất kỳ (gõ lại trùng móc/trăng để hủy).
VietEngine::DiacriticResult VietEngine::RemoveMarkAt(int index) {
    if (index < 0 || index >= static_cast<int>(letters_.size())) {
        return DiacriticResult::NotDiacritic;
    }
    letters_[index].mark = Mark::None;
    return DiacriticResult::Cancelled;
}

// MARK: - Render

std::u32string VietEngine::Render() const {
    const int tone_index = ToneTargetIndex();
    std::u32string out;
    for (int i = 0; i < static_cast<int>(letters_.size()); ++i) {
        Tone tone = (i == tone_index) ? tone_ : Tone::None;
        char32_t composed = VietTable::Compose(letters_[i].base, letters_[i].mark, tone);
        out.push_back(composed != 0 ? composed : letters_[i].base);
    }
    return out;
}

int VietEngine::ToneTargetIndex() const {
    // Luật 1: ưu tiên nguyên âm có dấu biến âm (â ê ô ơ ư ă) — lấy chỉ số CUỐI.
    for (int i = static_cast<int>(letters_.size()) - 1; i >= 0; --i) {
        Mark m = letters_[i].mark;
        if (m == Mark::Circumflex || m == Mark::Breve || m == Mark::Horn) {
            return i;
        }
    }

    // Tập chỉ số nguyên âm.
    std::vector<int> vowel_idx;
    for (int i = 0; i < static_cast<int>(letters_.size()); ++i) {
        if (IsVietVowel(letters_[i].base)) vowel_idx.push_back(i);
    }

    // KÉO DÀI NGUYÊN ÂM: gộp các nguyên âm TRÙNG nhau liên tiếp về một đại diện
    // (giữ ký tự ĐẦU — dấu thuộc về nguyên âm gốc). Nhờ vậy "oiii" tính như "oi"
    // khi đặt dấu (chòiiii, không phải choìiii); diphthong thật (oa, uy, ươ) không
    // bị ảnh hưởng vì các chữ khác nhau.
    if (vowel_idx.size() >= 2) {
        std::vector<int> collapsed;
        for (int idx : vowel_idx) {
            if (!collapsed.empty() &&
                ToLower(letters_[collapsed.back()].base) == ToLower(letters_[idx].base)) {
                continue;  // cùng nguyên âm với cái trước -> bỏ (kéo dài)
            }
            collapsed.push_back(idx);
        }
        vowel_idx = collapsed;
    }

    // "qu"/"gi": loại nguyên âm đầu nếu nó là 'u' sau 'q' hoặc 'i' sau 'g', và còn
    // nguyên âm khác phía sau.
    if (vowel_idx.size() >= 2) {
        int first = vowel_idx.front();
        char32_t first_base = ToLower(letters_[first].base);
        char32_t prev_base = first > 0 ? ToLower(letters_[first - 1].base) : U' ';
        if ((first_base == U'i' && prev_base == U'g') ||
            (first_base == U'u' && prev_base == U'q')) {
            vowel_idx.erase(vowel_idx.begin());
        }
    }

    if (vowel_idx.empty()) return -1;
    int start = vowel_idx.front();
    int end = vowel_idx.back();
    int count = static_cast<int>(vowel_idx.size());

    // Có phụ âm sau cụm nguyên âm?
    bool has_final_consonant =
        (end + 1 < static_cast<int>(letters_.size())) &&
        !IsVietVowel(letters_[end + 1].base);

    // Luật 2: có phụ âm cuối -> nguyên âm cuối của cụm.
    if (has_final_consonant) return end;

    // Cụm nguyên âm hở:
    if (count == 1) {
        return start;  // luật 4
    }
    if (count == 2) {
        if (tone_style_ == ToneStyle::Old) return start;
        char32_t a = ToLower(letters_[start].base);
        char32_t b = ToLower(letters_[end].base);
        bool open_tail =
            (a == U'o' && (b == U'a' || b == U'e')) || (a == U'u' && b == U'y');
        return open_tail ? end : start;
    }
    // luật 3: 3 nguyên âm -> nguyên âm giữa.
    return vowel_idx[1];
}

}  // namespace bowgo
