// Engine.swift
// ------------
// Bộ não của bộ gõ. Phần gõ âm tiết (Telex/VNI, đặt dấu, gõ lại bỏ dấu, backspace)
// nằm ở core Rust packages/viet_core, gọi qua C ABI (module CVietCore). Lớp này giữ
// API Swift cũ và thêm phần cấp TỪ chỉ bản macOS có: macro, tự sửa lỗi gõ nhanh,
// tự khôi phục tiếng Anh.
//
// Core phải được build trước `swift build`/`swift test`: bash scripts/build-core.sh

import CVietCore
import Foundation

public final class VietEngine {
    private let core: OpaquePointer

    /// Kiểu đặt dấu thanh:
    /// - `modern`: hoà, quý, khoẻ (đuôi mở oa/oe/uy đặt dấu lên nguyên âm sau).
    /// - `old`:    hòa, qúy, khỏe (đặt dấu lên nguyên âm trước).
    /// Đây là tuỳ chọn người dùng (các bộ gõ phổ biến đều có), mặc định modern.
    public enum ToneStyle { case modern, old }

    /// Kho macro/gõ tắt (tuỳ chọn). Nếu nil -> không có macro.
    private let macros: MacroStore?

    /// Tự khôi phục tiếng Anh: nếu chuỗi đã gõ bị biến dạng và KHÔNG phải âm tiết
    /// tiếng Việt hợp lệ thì khôi phục phím thô khi chốt từ. Mặc định tắt.
    private let autoRestoreEnglish: Bool

    /// Tự sửa lỗi gõ nhanh: khi chốt từ, nếu từ vừa gõ khớp một lỗi phổ biến hoặc
    /// dấu thanh đặt sai vị trí thì tự sửa về từ đúng. Mặc định tắt. Xem `AutoCorrect`.
    private let autoCorrect: Bool

    public init(method: InputMethod = .telex,
                toneStyle: ToneStyle = .modern,
                macros: MacroStore? = nil,
                autoRestoreEnglish: Bool = false,
                autoCorrect: Bool = false) {
        self.macros = macros
        self.autoRestoreEnglish = autoRestoreEnglish
        self.autoCorrect = autoCorrect
        core = bow_engine_new(method == .vni ? BOW_METHOD_VNI : BOW_METHOD_TELEX,
                              toneStyle == .old ? BOW_TONE_OLD : BOW_TONE_MODERN)
    }

    deinit { bow_engine_free(core) }

    /// Phím thô của CẢ TỪ đang gõ (qua nhiều âm tiết), chỉ gồm chữ cái/chữ số.
    /// Reset khi gặp phím ngắt từ. Dùng để khớp macro/gõ tắt theo phím thô ASCII.
    private var wordRawKeys: [Character] = []

    /// Tổng số ký tự HIỂN THỊ của từ đang gõ (cộng dồn qua các âm tiết đã chốt +
    /// âm tiết hiện tại). Cần để biết phải xoá bao nhiêu ký tự khi bung macro.
    private var committedWordLength = 0   // độ dài các âm tiết đã chốt trong từ

    /// Kết quả xử lý một phím khi BẬT macro (API mới, không phá `process` cũ).
    public enum KeyResult: Equatable {
        /// Phím thuộc âm tiết -> chuỗi hiển thị mới của âm tiết hiện tại.
        case syllable(String)
        /// Phím ngắt từ thường -> caller xuất `breakChar` nguyên bản, bắt đầu từ mới.
        case wordBreak(Character)
        /// Macro khớp -> caller XOÁ `deleteCount` ký tự đã hiển thị (cả từ khoá),
        /// rồi CHÈN `insert` + `breakChar`. (breakChar là phím ngắt vừa gõ.)
        case macro(deleteCount: Int, insert: String, breakChar: Character)
        /// Tự sửa lỗi gõ nhanh: từ vừa gõ (`deleteCount` ký tự hiển thị) được thay bằng
        /// `insert` (từ đúng), rồi CHÈN `breakChar`. Giống macro nhưng lý do khác nhau.
        case autoCorrect(deleteCount: Int, insert: String, breakChar: Character)
    }

    /// Nhận một ký tự người dùng gõ, trả về chuỗi văn bản hiện tại của âm tiết
    /// (cái mà ô nhập liệu nên hiển thị cho âm tiết đang gõ).
    ///
    /// Trả về `nil` nghĩa là: ký tự này KHÔNG thuộc âm tiết (vd khoảng trắng) —
    /// caller nên xuất ký tự đó nguyên bản và bắt đầu âm tiết mới.
    public func process(_ ch: Character) -> String? {
        bow_engine_process(core, Self.scalar(ch)) ? render() : nil
    }

    /// API mới CÓ MACRO: xử lý một phím và phân biệt rõ 3 tình huống (xem `KeyResult`).
    ///
    /// Khác `process`: khi gặp phím ngắt từ, nếu `wordRawKeys` khớp một macro thì
    /// trả `.macro(...)` để caller xoá từ khoá và chèn nội dung. Nếu không có macro
    /// (hoặc không khớp) thì hành vi gõ tiếng Việt y hệt `process`.
    public func processKey(_ ch: Character) -> KeyResult {
        if bow_engine_is_word_char(core, Self.scalar(ch)) {
            // Phím thuộc từ: cập nhật cả buffer âm tiết (core) lẫn buffer từ.
            wordRawKeys.append(ch)
            return .syllable(process(ch) ?? "")
        }

        // Phím NGẮT TỪ. Trước khi chốt, thử khớp macro theo phím thô của cả từ.
        if let macros, !wordRawKeys.isEmpty {
            let keyword = String(wordRawKeys)
            if let content = macros.expand(keyword: keyword) {
                let deleteCount = currentWordDisplayLength()
                resetWord()
                return .macro(deleteCount: deleteCount, insert: content, breakChar: ch)
            }
        }

        // Tự sửa lỗi gõ nhanh trên từ vừa gõ (chỉ xét âm tiết hiện tại — từ đơn).
        // Chỉ chạy khi âm tiết chưa được khôi phục tiếng Anh (ưu tiên cao hơn ở caller).
        if autoCorrect, committedWordLength == 0 {
            let display = render()
            if !display.isEmpty, let result = AutoCorrect.correctWord(display) {
                resetWord()
                return .autoCorrect(deleteCount: display.count,
                                    insert: result.corrected,
                                    breakChar: ch)
            }
        }

        resetWord()
        return .wordBreak(ch)
    }

    /// Độ dài (số ký tự) phần đang hiển thị của TỪ hiện tại = các âm tiết đã chốt
    /// + âm tiết đang gõ dở.
    private func currentWordDisplayLength() -> Int {
        committedWordLength + render().count
    }

    /// Kiểm tra TỰ KHÔI PHỤC TIẾNG ANH tại thời điểm chốt từ.
    ///
    /// Trả về chuỗi PHÍM THÔ để khôi phục (caller xoá phần đã hiển thị, gõ lại
    /// chuỗi này) nếu: bật autoRestoreEnglish, engine ĐÃ biến dạng từ, và dạng
    /// biến dạng KHÔNG phải âm tiết tiếng Việt hợp lệ. Ngược lại trả nil (giữ nguyên).
    ///
    /// Quy tắc ưu tiên tiếng Việt: nếu chuỗi hiển thị vẫn là âm tiết tiếng Việt
    /// hợp lệ thì KHÔNG khôi phục (tránh phá từ tiếng Việt thật như "thế", "bạn").
    public func englishRestoreOnWordBreak() -> String? {
        guard autoRestoreEnglish, !wordRawKeys.isEmpty else { return nil }
        return Self.englishRestoreKeys(rawKeys: String(wordRawKeys), display: render())
    }

    /// Quyết định khôi phục (thuần, không trạng thái) — caller tự giữ buffer.
    /// Trả `rawKeys` để khôi phục, hoặc nil nếu nên giữ nguyên dạng tiếng Việt.
    ///   - rawKeys: chuỗi phím thô ASCII của cả từ (vd "terminal").
    ///   - display: chuỗi đang hiển thị (có thể đã bị biến dạng, vd "terminäl").
    public static func englishRestoreKeys(rawKeys: String, display: String) -> String? {
        guard !rawKeys.isEmpty else { return nil }
        // Engine có thực sự biến dạng không? Hiển thị trùng phím thô -> không
        // có gì để khôi phục ("test" giữ "test").
        guard display.lowercased() != rawKeys.lowercased() else { return nil }
        // Hiển thị vẫn là âm tiết tiếng Việt hợp lệ -> giữ (ưu tiên tiếng Việt).
        if VietSyllable.isValidDisplay(display) { return nil }
        // Biến dạng + không hợp lệ tiếng Việt -> khôi phục phím thô.
        return rawKeys
    }

    /// Số ký tự đang hiển thị cho từ hiện tại (caller cần để biết xoá bao nhiêu khi
    /// khôi phục).
    public var currentWordLength: Int { currentWordDisplayLength() }

    /// Reset trạng thái cấp TỪ (gọi khi ngắt từ hoặc bung macro).
    private func resetWord() {
        bow_engine_clear(core)
        wordRawKeys.removeAll()
        committedWordLength = 0
    }

    /// Reset thủ công (gọi khi con trỏ nhảy chỗ khác, click chuột, v.v.)
    public func clear() {
        bow_engine_clear(core)
    }

    /// Xử lý phím Backspace: core xoá 1 phím thô cuối rồi DỰNG LẠI âm tiết từ đầu.
    ///
    /// LƯU Ý: hàm này lùi theo PHÍM THÔ, nên chuỗi hiển thị trả về có thể DÀI BẰNG
    /// chuỗi cũ (chỉ tháo dấu: "tiếng"->"tiêng", "ấ"->"â"). Caller (EventTapController)
    /// PHẢI đồng bộ màn hình theo chuỗi này (xoá `committedLength` cũ, gõ lại chuỗi
    /// mới) — KHÔNG được giả định phím Backspace vật lý xoá đúng số ký tự hiển thị,
    /// nếu không màn hình sẽ lệch engine -> nuốt chữ khi gõ lại.
    ///
    /// Trả về chuỗi hiển thị mới của âm tiết (rỗng nếu đã hết), hoặc `nil` nếu không
    /// còn gì trong buffer (caller cứ để Backspace đi qua như bình thường).
    @discardableResult
    public func backspace() -> String? {
        bow_engine_backspace(core) ? render() : nil
    }

    /// Chuỗi hiển thị của âm tiết đang gõ (rỗng nếu chưa có).
    private func render() -> String {
        var len = 0
        guard let bytes = bow_engine_text(core, &len) else { return "" }
        return String(decoding: UnsafeBufferPointer(start: bytes, count: len), as: UTF8.self)
    }

    /// Phím -> Unicode scalar cho core. Ký tự ghép nhiều scalar (vd "e" + dấu tổ hợp)
    /// được dựng sẵn NFC trước; vẫn nhiều scalar thì coi là phím ngắt từ (U+FFFD).
    private static func scalar(_ ch: Character) -> UInt32 {
        let scalars = String(ch).precomposedStringWithCanonicalMapping.unicodeScalars
        return scalars.count == 1 ? scalars.first!.value : 0xFFFD
    }
}
