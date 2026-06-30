// viet_table.cpp
// --------------
// Cài đặt bảng tra. Mỗi nguyên âm (gốc + mark) có 6 biến thể theo 6 thanh, đúng
// thứ tự [none, acute, grave, hook, tilde, dot] — khớp enum Tone và bản Swift.

#include "viet_table.h"

namespace bowgo {

namespace {

// Một hàng 6 biến thể (theo thứ tự Tone). Dùng U"..." literal (char32_t).
struct Row {
    char32_t base;
    Mark mark;
    const char32_t* variants;  // trỏ tới mảng 6 char32_t
};

// Khai báo các hàng. Mỗi mảng 6 ký tự = [ngang, sắc, huyền, hỏi, ngã, nặng].
const char32_t kA[]        = {U'a', U'á', U'à', U'ả', U'ã', U'ạ'};
const char32_t kACirc[]    = {U'â', U'ấ', U'ầ', U'ẩ', U'ẫ', U'ậ'};
const char32_t kABreve[]   = {U'ă', U'ắ', U'ằ', U'ẳ', U'ẵ', U'ặ'};
const char32_t kE[]        = {U'e', U'é', U'è', U'ẻ', U'ẽ', U'ẹ'};
const char32_t kECirc[]    = {U'ê', U'ế', U'ề', U'ể', U'ễ', U'ệ'};
const char32_t kI[]        = {U'i', U'í', U'ì', U'ỉ', U'ĩ', U'ị'};
const char32_t kO[]        = {U'o', U'ó', U'ò', U'ỏ', U'õ', U'ọ'};
const char32_t kOCirc[]    = {U'ô', U'ố', U'ồ', U'ổ', U'ỗ', U'ộ'};
const char32_t kOHorn[]    = {U'ơ', U'ớ', U'ờ', U'ở', U'ỡ', U'ợ'};
const char32_t kU[]        = {U'u', U'ú', U'ù', U'ủ', U'ũ', U'ụ'};
const char32_t kUHorn[]    = {U'ư', U'ứ', U'ừ', U'ử', U'ữ', U'ự'};
const char32_t kY[]        = {U'y', U'ý', U'ỳ', U'ỷ', U'ỹ', U'ỵ'};
// đ là phụ âm, không mang dấu thanh -> lặp 6 lần cho khớp định dạng.
const char32_t kD[]        = {U'đ', U'đ', U'đ', U'đ', U'đ', U'đ'};

const Row kRows[] = {
    {U'a', Mark::None, kA},   {U'a', Mark::Circumflex, kACirc}, {U'a', Mark::Breve, kABreve},
    {U'e', Mark::None, kE},   {U'e', Mark::Circumflex, kECirc},
    {U'i', Mark::None, kI},
    {U'o', Mark::None, kO},   {U'o', Mark::Circumflex, kOCirc}, {U'o', Mark::Horn, kOHorn},
    {U'u', Mark::None, kU},   {U'u', Mark::Horn, kUHorn},
    {U'y', Mark::None, kY},
    {U'd', Mark::Dyet, kD},
};

char32_t ToLower(char32_t c) {
    return (c >= U'A' && c <= U'Z') ? (c + 32) : c;
}

// Đổi nguyên âm thường có dấu sang hoa. Vì char32_t literal hoa/thường lệch nhau
// không theo +/-32, ta tra song song mảng hoa.
const char32_t kA_U[]      = {U'A', U'Á', U'À', U'Ả', U'Ã', U'Ạ'};
const char32_t kACirc_U[]  = {U'Â', U'Ấ', U'Ầ', U'Ẩ', U'Ẫ', U'Ậ'};
const char32_t kABreve_U[] = {U'Ă', U'Ắ', U'Ằ', U'Ẳ', U'Ẵ', U'Ặ'};
const char32_t kE_U[]      = {U'E', U'É', U'È', U'Ẻ', U'Ẽ', U'Ẹ'};
const char32_t kECirc_U[]  = {U'Ê', U'Ế', U'Ề', U'Ể', U'Ễ', U'Ệ'};
const char32_t kI_U[]      = {U'I', U'Í', U'Ì', U'Ỉ', U'Ĩ', U'Ị'};
const char32_t kO_U[]      = {U'O', U'Ó', U'Ò', U'Ỏ', U'Õ', U'Ọ'};
const char32_t kOCirc_U[]  = {U'Ô', U'Ố', U'Ồ', U'Ổ', U'Ỗ', U'Ộ'};
const char32_t kOHorn_U[]  = {U'Ơ', U'Ớ', U'Ờ', U'Ở', U'Ỡ', U'Ợ'};
const char32_t kU_U[]      = {U'U', U'Ú', U'Ù', U'Ủ', U'Ũ', U'Ụ'};
const char32_t kUHorn_U[]  = {U'Ư', U'Ứ', U'Ừ', U'Ử', U'Ữ', U'Ự'};
const char32_t kY_U[]      = {U'Y', U'Ý', U'Ỳ', U'Ỷ', U'Ỹ', U'Ỵ'};
const char32_t kD_U[]      = {U'Đ', U'Đ', U'Đ', U'Đ', U'Đ', U'Đ'};

const char32_t* UpperRowFor(const char32_t* lowerRow) {
    if (lowerRow == kA) return kA_U;
    if (lowerRow == kACirc) return kACirc_U;
    if (lowerRow == kABreve) return kABreve_U;
    if (lowerRow == kE) return kE_U;
    if (lowerRow == kECirc) return kECirc_U;
    if (lowerRow == kI) return kI_U;
    if (lowerRow == kO) return kO_U;
    if (lowerRow == kOCirc) return kOCirc_U;
    if (lowerRow == kOHorn) return kOHorn_U;
    if (lowerRow == kU) return kU_U;
    if (lowerRow == kUHorn) return kUHorn_U;
    if (lowerRow == kY) return kY_U;
    if (lowerRow == kD) return kD_U;
    return nullptr;
}

int ToneIndex(Tone t) { return static_cast<int>(t); }

}  // namespace

char32_t VietTable::Compose(char32_t base, Mark mark, Tone tone) {
    const bool isUpper = (base >= U'A' && base <= U'Z');
    const char32_t lower = ToLower(base);

    for (const Row& row : kRows) {
        if (row.base == lower && row.mark == mark) {
            const char32_t* variants = row.variants;
            if (isUpper) {
                const char32_t* up = UpperRowFor(variants);
                if (up) variants = up;
            }
            return variants[ToneIndex(tone)];
        }
    }
    return 0;  // không hợp lệ
}

}  // namespace bowgo
