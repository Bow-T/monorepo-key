// ime_controller.h
// ----------------
// CONTROLLER bộ gõ dùng chung cho tầng Windows — bản C++ của phần xử lý phím
// trong EventTapController.swift (macOS), TÁCH KHỎI nền tảng để test được trên
// macOS/Linux. Tầng nền tảng (TSF trên Windows) chỉ còn việc:
//   1. Dịch phím vật lý -> ký tự theo layout thật (ToUnicodeEx).
//   2. Gọi đúng Handle* dưới đây.
//   3. Thi hành KeyAction trả về (sửa văn bản qua edit session / cho phím đi qua).
//
// CÁC BẤT BIẾN HỌC TỪ BẢN macOS (đã trả giá bằng bug thật):
//   • LUÔN nuốt phím gốc và gõ-thay với mọi ký tự engine xử lý — kể cả khi engine
//     chỉ nối thêm đúng ký tự đó. Trộn ký tự "đi qua tự nhiên" với ký tự do ta
//     chèn trong cùng một từ từng gây mất chữ ("em chịu á" -> "em chịu ").
//   • Backspace khi đang gõ dở: NUỐT phím gốc và tự đồng bộ màn hình = engine
//     (xoá committed cũ, chèn bản dựng lại) — vì engine có thể lùi nhiều hơn một
//     ký tự hiển thị (ư=u+w, â=a+a...).
//   • Ngắt từ: thử GÕ TẮT (macro) -> TỰ KHÔI PHỤC TIẾNG ANH -> TỰ SỬA LỖI GÕ
//     NHANH, theo đúng thứ tự đó; chỉ macro yêu cầu phím ngắt "có chèn ký tự"
//     (space/enter/tab, không esc).

#pragma once

#include <memory>
#include <optional>
#include <string>

#include "../engine/auto_correct.h"
#include "../engine/engine.h"
#include "../engine/macro.h"
#include "bow_config.h"

namespace bowgo {

// Hành động tầng nền tảng phải thi hành cho MỘT phím người dùng gõ.
struct KeyAction {
    enum class Kind {
        PassThrough,  // không sửa văn bản; để phím gốc đi tiếp cho ứng dụng
        Replace,      // NUỐT phím gốc; xoá `backspaces` ký tự trước con trỏ, chèn `text`
    };
    Kind kind = Kind::PassThrough;
    int backspaces = 0;
    std::u32string text;
    // Chỉ với Replace: sau khi sửa văn bản phải GỬI LẠI phím gốc (Enter/Tab/Esc
    // khi bung macro/sửa từ — hành vi phím phải là thật: Enter gửi form/xuống
    // dòng theo ứng dụng, KHÔNG được chèn '\n' vào văn bản).
    bool resend_original_key = false;

    static KeyAction Pass() { return {}; }
    static KeyAction MakeReplace(int backspaces, std::u32string text,
                                 bool resend = false) {
        KeyAction a;
        a.kind = Kind::Replace;
        a.backspaces = backspaces;
        a.text = std::move(text);
        a.resend_original_key = resend;
        return a;
    }
};

// Phím ngắt từ (space/enter/tab/esc — khớp KeyCodeMap.isWordBreak bên macOS).
enum class BreakKey { Space, Enter, Tab, Escape };

class ImeController {
public:
    ImeController();

    // Áp cấu hình (đọc từ settings.json). Dựng lại engine/macro/từ điển, chốt từ.
    void Apply(const BowConfig& config);

    bool enabled() const { return enabled_; }
    void SetEnabled(bool on);
    // Đảo bật/tắt (phím tắt VI/EN). Trả trạng thái MỚI.
    bool ToggleEnabled();

    // Ký tự in được đã dịch theo layout (chỉ gọi khi enabled, không kèm Ctrl/Alt).
    KeyAction HandleChar(char32_t ch);

    // Phím Backspace.
    KeyAction HandleBackspace();

    // Phím ngắt từ. `WordBreakNeedsEdit` là bước "hỏi trước" KHÔNG đổi trạng
    // thái — cho ITfKeyEventSink::OnTestKeyDown quyết định có nhận phím không.
    bool WordBreakNeedsEdit(BreakKey key) const;
    KeyAction HandleWordBreak(BreakKey key);

    // Đang gõ dở một âm tiết (đã có ký tự do ta chèn trên màn)?
    bool HasPendingSyllable() const { return committed_length_ > 0; }

    // Con trỏ nhảy chỗ (click chuột, đổi focus, phím điều hướng, Ctrl/Alt...):
    // chốt từ đang gõ, KHÔNG sửa văn bản.
    void ResetSyllable();

private:
    // Nội dung thay cho từ hiện tại khi ngắt từ (macro -> khôi phục tiếng Anh ->
    // tự sửa lỗi), KHÔNG kèm ký tự ngắt. nullopt = không có gì để thay.
    // `macro_capable` = phím ngắt có chèn ký tự (space/enter/tab).
    // const = chỉ tra (Has/kiểm tra thuần); bản `Take` mới bung macro thật
    // (Expand có thể tăng counter).
    bool WouldTransform(bool macro_capable) const;
    std::optional<std::u32string> TakeTransform(bool macro_capable);

    bool enabled_ = true;
    InputMethod method_ = InputMethod::Telex;
    ToneStyle tone_style_ = ToneStyle::Modern;
    bool auto_restore_english_ = false;
    bool auto_correct_ = false;

    VietEngine engine_;
    std::unique_ptr<MacroStore> macro_store_;               // null = tắt gõ tắt
    std::unique_ptr<AutoCorrectDictionary> user_dict_;      // null = dùng Shared()

    // "Số ký tự ĐANG hiện trên màn cho âm tiết hiện tại" — số Backspace cần khi
    // gõ thay.
    int committed_length_ = 0;
    // Phím thô (ASCII chữ/số) của CẢ TỪ đang gõ — khớp macro + khôi phục tiếng Anh.
    std::u32string word_raw_keys_;
    // Chuỗi HIỂN THỊ hiện tại của từ (kết quả render cuối).
    std::u32string current_display_;
};

}  // namespace bowgo
