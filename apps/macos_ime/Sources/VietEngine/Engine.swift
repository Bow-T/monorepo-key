// Engine.swift
// ------------
// Bộ não của bộ gõ. Nhận từng phím người dùng nhấn và quyết định:
//   - giữ nguyên ký tự đó, HAY
//   - biến đổi "từ đang gõ" thành dạng có dấu tiếng Việt.
//
// MÔ HÌNH XỬ LÝ (đơn giản hoá để học):
//   Engine giữ một "buffer" = từ đang gõ dở (vd: đã gõ "tieeng").
//   Mỗi phím mới tới, engine thử xem nó có phải phím-dấu của Telex không:
//     - 's' -> sắc, 'f' -> huyền, 'r' -> hỏi, 'x' -> ngã, 'j' -> nặng, 'z' -> xoá dấu
//     - 'aa'->â, 'ee'->ê, 'oo'->ô, 'aw'->ă, 'ow'->ơ, 'uw'->ư, 'dd'->đ, 'w'->ơ/ư
//   Nếu là phím-dấu áp được -> sửa buffer. Nếu không -> nối ký tự vào buffer.
//
//   Khi gặp khoảng trắng / dấu câu / phím không phải chữ -> "chốt từ", reset buffer.
//
// LƯU Ý: đây là bản TỐI GIẢN để bạn học cơ chế. Bộ gõ thật còn xử lý
// đặt dấu thanh đúng vị trí theo quy tắc chính tả, gõ lại để bỏ dấu, undo, v.v.
// Ta sẽ nâng cấp dần.

/// Một âm tiết đang được gõ, mô tả theo (các ký tự) + (mark) + (tone).
struct Syllable {
    /// Các "khối chữ cái" theo thứ tự gõ. Mỗi khối là 1 chữ cái gốc + mark riêng.
    /// Ví dụ "tieeng": t, i, e(circumflex), n, g  -> nhưng để đơn giản ta lưu phẳng.
    var letters: [Letter] = []
    var tone: Tone = .none

    struct Letter {
        var base: Character
        var mark: Mark = .none
    }

    var isEmpty: Bool { letters.isEmpty }

    mutating func reset() {
        letters.removeAll()
        tone = .none
    }
}

public final class VietEngine {
    private var syllable = Syllable()
    private let method: InputMethod

    /// Kiểu đặt dấu thanh:
    /// - `modern`: hoà, quý, khoẻ (đuôi mở oa/oe/uy đặt dấu lên nguyên âm sau).
    /// - `old`:    hòa, qúy, khỏe (đặt dấu lên nguyên âm trước).
    /// Đây là tuỳ chọn người dùng (các bộ gõ phổ biến đều có), mặc định modern.
    public enum ToneStyle { case modern, old }
    private let toneStyle: ToneStyle

    /// Kho macro/gõ tắt (tuỳ chọn). Nếu nil -> không có macro.
    private let macros: MacroStore?

    /// Tự khôi phục tiếng Anh: nếu chuỗi đã gõ bị biến dạng và KHÔNG phải âm tiết
    /// tiếng Việt hợp lệ thì khôi phục phím thô khi chốt từ. Mặc định tắt.
    private let autoRestoreEnglish: Bool

    public init(method: InputMethod = .telex,
                toneStyle: ToneStyle = .modern,
                macros: MacroStore? = nil,
                autoRestoreEnglish: Bool = false) {
        self.method = method
        self.toneStyle = toneStyle
        self.macros = macros
        self.autoRestoreEnglish = autoRestoreEnglish
    }

    // MARK: - Buffer phím thô (giữ lịch sử phím gốc người dùng gõ)

    /// Đúng dãy phím người dùng đã gõ cho âm tiết hiện tại (vd "tieengs").
    /// Giữ buffer này để có thể DỰNG LẠI (replay) âm tiết — cần cho backspace, ESC.
    private var rawKeys: [Character] = []

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
    }

    /// Nhận một ký tự người dùng gõ, trả về chuỗi văn bản hiện tại của âm tiết
    /// (cái mà ô nhập liệu nên hiển thị cho âm tiết đang gõ).
    ///
    /// Trả về `nil` nghĩa là: ký tự này KHÔNG thuộc âm tiết (vd khoảng trắng) —
    /// caller nên xuất ký tự đó nguyên bản và bắt đầu âm tiết mới.
    public func process(_ ch: Character) -> String? {
        // Ghi lại phím thô TRƯỚC khi xử lý (nếu nó thuộc về âm tiết).
        // Ký tự ngắt từ sẽ tự reset bên dưới nên không cần ghi.
        let willBeWordBreak: Bool = {
            if ch.isLetter { return false }
            let isVNIToneKey = (method == .vni) && ch.isNumber && !syllable.isEmpty
            return !isVNIToneKey
        }()
        if !willBeWordBreak {
            rawKeys.append(ch)
        }
        return step(ch)
    }

    /// API mới CÓ MACRO: xử lý một phím và phân biệt rõ 3 tình huống (xem `KeyResult`).
    ///
    /// Khác `process`: khi gặp phím ngắt từ, nếu `wordRawKeys` khớp một macro thì
    /// trả `.macro(...)` để caller xoá từ khoá và chèn nội dung. Nếu không có macro
    /// (hoặc không khớp) thì hành vi gõ tiếng Việt y hệt `process`.
    public func processKey(_ ch: Character) -> KeyResult {
        let isWordChar = ch.isLetter || ((method == .vni) && ch.isNumber && !syllable.isEmpty)

        if isWordChar {
            // Phím thuộc từ: cập nhật cả buffer âm tiết lẫn buffer từ.
            rawKeys.append(ch)
            wordRawKeys.append(ch)
            let rendered = step(ch) ?? ""
            return .syllable(rendered)
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
        syllable.reset()
        rawKeys.removeAll()
        wordRawKeys.removeAll()
        committedWordLength = 0
    }

    /// Một bước xử lý thuần (không đụng rawKeys) — để replay dùng lại được.
    private func step(_ ch: Character) -> String? {
        // 1) Ký tự ngắt từ (space, dấu câu...) -> chốt âm tiết.
        //    Ngoại lệ: với VNI, các CHỮ SỐ là phím-dấu, không phải ngắt từ —
        //    cho chúng đi tiếp tới applyAsDiacritic khi đang có âm tiết dở.
        if !ch.isLetter {
            let isVNIToneKey = (method == .vni) && ch.isNumber && !syllable.isEmpty
            if !isVNIToneKey {
                syllable.reset()
                rawKeys.removeAll()   // chốt âm tiết -> buffer thô bắt đầu lại
                return nil
            }
        }

        // 2) Thử coi ch là phím-dấu của phương thức gõ.
        switch applyAsDiacritic(ch) {
        case .applied:
            return render()

        case .cancelled:
            // GÕ LẠI ĐỂ BỎ DẤU: vd "hoaf" rồi gõ "f" nữa.
            // Dấu đã bị gỡ. Ký tự phím-dấu lúc này hiện ra như chữ
            // thường -> "hoa" + "f" = "hoaf". Nối ký tự thô rồi render.
            syllable.letters.append(.init(base: ch))
            return render()

        case .notDiacritic:
            break  // rơi xuống bước 3
        }

        // 3) Không phải phím-dấu -> nối như một chữ cái thường.
        syllable.letters.append(.init(base: ch))
        propagateUoHorn()
        return render()
    }

    /// Reset thủ công (gọi khi con trỏ nhảy chỗ khác, click chuột, v.v.)
    public func clear() {
        syllable.reset()
        rawKeys.removeAll()
    }

    /// Xử lý phím Backspace: xoá 1 phím thô cuối rồi DỰNG LẠI âm tiết từ đầu.
    ///
    /// Vì sao dựng lại thay vì "tháo dấu"? Vì một ký tự hiển thị có thể do nhiều phím
    /// tạo nên (vd "ế" = e+e+s). Xoá 1 phím thô rồi replay luôn cho kết quả ĐÚNG mà
    /// không cần logic đảo ngược phức tạp — đây là mẹo gọn của cách giữ buffer thô.
    ///
    /// Trả về chuỗi hiển thị mới của âm tiết (rỗng nếu đã hết), hoặc `nil` nếu không
    /// còn gì trong buffer (caller cứ để Backspace đi qua như bình thường).
    @discardableResult
    public func backspace() -> String? {
        guard !rawKeys.isEmpty else { return nil }
        rawKeys.removeLast()
        // Dựng lại từ đầu.
        syllable.reset()
        let keys = rawKeys
        rawKeys.removeAll()           // step() không tự ghi rawKeys; ta ghi lại bên dưới
        var current = ""
        for key in keys {
            rawKeys.append(key)
            current = step(key) ?? ""
        }
        return current
    }

    // MARK: - Áp dụng phím-dấu

    /// Kết quả khi thử coi một ký tự là phím-dấu.
    private enum DiacriticResult {
        case applied        // đã áp dấu/biến âm vào âm tiết
        case cancelled      // gõ lại trùng dấu -> đã GỠ dấu; trả ký tự thô cho caller
        case notDiacritic   // không phải phím-dấu -> nối như chữ thường
    }

    /// Thử coi `ch` là phím-dấu của phương thức gõ hiện tại.
    private func applyAsDiacritic(_ ch: Character) -> DiacriticResult {
        switch method {
        case .telex: return applyTelex(ch)
        case .vni:   return applyVNI(ch)
        }
    }

    private func applyTelex(_ ch: Character) -> DiacriticResult {
        let lower = Character(ch.lowercased())
        switch lower {
        // Dấu thanh
        case "s": return setTone(.acute)
        case "f": return setTone(.grave)
        case "r": return setTone(.hook)
        case "x": return setTone(.tilde)
        case "j": return setTone(.dot)
        case "z": return setTone(.none)   // xoá dấu thanh

        // Dấu biến âm bằng cách lặp chữ: aa, ee, oo
        case "a", "e", "o":
            return applyCircumflexRepeat(lower, raw: ch)

        // w: ă/ơ/ư tuỳ chữ cái cuối; dd -> đ
        case "w":
            // Xử lý ww -> w: nếu phím trước là w và không có nguyên âm trước w đó
            let rawLen = rawKeys.count
            let isConsecutiveW = rawLen >= 2 && Character(rawKeys[rawLen - 2].lowercased()) == "w"
            if isConsecutiveW {
                let hasVowelBeforePrevW = rawLen >= 3 && "uoa".contains(Character(rawKeys[rawLen - 3].lowercased()))
                if !hasVowelBeforePrevW {
                    if var last = syllable.letters.last, last.mark == .horn, "uU".contains(last.base) {
                        last.base = ch
                        last.mark = .none
                        syllable.letters[syllable.letters.count - 1] = last
                        return .applied
                    }
                } else {
                    return .notDiacritic
                }
            }
            return applyHornOrBreve()
        case "d":
            if let last = syllable.letters.last,
               Character(last.base.lowercased()) == "d" {
                if last.mark == .dyet {
                    return removeMarkOnLast()   // đ rồi gõ 'd' nữa -> bỏ gạch (ddd -> dd)
                }
                if last.mark == .none {
                    return setMarkOnLast(.dyet) // dd -> đ
                }
            }
            return .notDiacritic

        default:
            return .notDiacritic
        }
    }

    /// Lặp nguyên âm a/e/o trong Telex: tạo mũ (aa->â) hoặc KÉO DÀI nguyên âm.
    ///
    /// CHU KỲ MŨ tính theo SỐ LẦN gõ nguyên âm đó trong "run" cuối (đếm cả khi có
    /// phím-thanh xen giữa — vd "casa" == "caas" == cấ). Dấu thanh đi kèm "ăn theo",
    /// KHÔNG phá chu kỳ; vị trí dấu do toneTargetIndex() quyết định:
    ///   lần 2 gõ  -> tạo mũ:   aa->â,  asa->ấ,  these->thế
    ///   lần 3 gõ  -> gỡ mũ:    aaa->aa, asaa->áaa, nhesee->nhéee
    ///   lần ≥4    -> kéo dài thô (KHÔNG tạo lại mũ): aaaa->aaa, ojooo->ọoo
    ///
    /// Riêng họ 'o' khi nguyên âm đã mang dấu thanh vẫn chạy đủ chu kỳ Telex cũ
    /// (ọ+o->ộ, ộ+o->ọo) — đây là hành vi "legacy o-family" của Telex/PHTV.
    private func applyCircumflexRepeat(_ lower: Character, raw ch: Character) -> DiacriticResult {
        guard let last = syllable.letters.last,
              Character(last.base.lowercased()) == lower else {
            return .notDiacritic   // 'a/e/o' đơn -> để bước 3 nối như chữ thường
        }

        // Đếm số lần gõ nguyên âm này trong "run" cuối (gồm cả lần đang gõ).
        // Đếm trên rawKeys để bắt được cả phím-thanh xen giữa (casa, asaa...).
        let pressCount = trailingVowelPressCount(lower)

        if last.mark == .circumflex {
            // Đang là â/ê/ô -> gõ thêm nguyên âm đó: GỠ mũ (chu kỳ lần 3).
            return removeMarkOnLast()
        }

        if last.mark == .none {
            // pressCount == 2 (lần thứ 2 trong run) -> tạo mũ.
            // pressCount >= 3 (đã qua chu kỳ gỡ mũ) -> chỉ kéo dài thô.
            if pressCount == 2, VietTable.compose(base: last.base, mark: .circumflex, tone: .none) != nil {
                return setMarkOnLast(.circumflex)
            }
            return .notDiacritic        // kéo dài thô (aaaa->aaa, áaa...)
        }
        return .notDiacritic
    }

    /// Đếm số lần phím nguyên âm `lower` được gõ trong "run" nguyên âm cuối của
    /// rawKeys — bỏ qua các phím-thanh (s f r x j z) xen giữa, dừng khi gặp một
    /// nguyên âm KHÁC hoặc phụ âm. Vd "casa" -> 'a' đếm 2 lần; "asaa" -> 3 lần.
    private func trailingVowelPressCount(_ lower: Character) -> Int {
        let toneKeys: Set<Character> = ["s", "f", "r", "x", "j", "z"]
        var n = 0
        for key in rawKeys.reversed() {
            let k = Character(key.lowercased())
            if k == lower { n += 1; continue }
            if toneKeys.contains(k) { continue }   // phím-thanh không phá run
            break                                  // nguyên âm khác / phụ âm -> dừng
        }
        return n
    }

    private func applyVNI(_ ch: Character) -> DiacriticResult {
        switch ch {
        case "1": return setTone(.acute)
        case "2": return setTone(.grave)
        case "3": return setTone(.hook)
        case "4": return setTone(.tilde)
        case "5": return setTone(.dot)
        case "0": return setTone(.none)
        case "6": return setMarkOrToggle(.circumflex)  // â/ê/ô
        case "7": return applyHornVNI()                // VNI horn: ơ/ư/ươ/ưa
        case "8": return setMarkOrToggle(.breve)       // ă
        case "9": return setMarkOrToggle(.dyet)        // đ
        default:  return .notDiacritic
        }
    }

    /// w trong Telex: a->ă, o->ơ, u->ư.
    /// Trường hợp đặc biệt: cụm "uo" -> "ươ" — móc CẢ HAI nguyên âm,
    /// vì "ươ" là một nguyên âm đôi (nướng, được, thương).
    private func applyHornOrBreve() -> DiacriticResult {
        let n = syllable.letters.count

        // "uo" + w -> "ươ": áp móc cho cả u và o.
        if n >= 2,
           Character(syllable.letters[n - 2].base.lowercased()) == "u",
           Character(syllable.letters[n - 1].base.lowercased()) == "o" {
            let isPartOfQu = n >= 3 && Character(syllable.letters[n - 3].base.lowercased()) == "q"
            if !isPartOfQu {
                let isThuo = n >= 4 &&
                    Character(syllable.letters[n - 4].base.lowercased()) == "t" &&
                    Character(syllable.letters[n - 3].base.lowercased()) == "h"
                if isThuo {
                    if syllable.letters[n - 1].mark == .horn {
                        syllable.letters[n - 1].mark = .none
                        return .cancelled
                    }
                    syllable.letters[n - 1].mark = .horn
                    return .applied
                }

                // Gõ lại w khi đã là "ươ" -> bỏ móc cả hai.
                if syllable.letters[n - 1].mark == .horn && syllable.letters[n - 2].mark == .horn {
                    syllable.letters[n - 2].mark = .none
                    syllable.letters[n - 1].mark = .none
                    return .cancelled
                }
                syllable.letters[n - 2].mark = .horn
                syllable.letters[n - 1].mark = .horn
                return .applied
            }
        }

        // "ua" + w -> "ưa": áp móc cho u.
        if n >= 2,
           Character(syllable.letters[n - 2].base.lowercased()) == "u",
           Character(syllable.letters[n - 1].base.lowercased()) == "a" {
            let isPartOfQu = n >= 3 && Character(syllable.letters[n - 3].base.lowercased()) == "q"
            if !isPartOfQu {
                // Gõ lại w khi đã là "ưa" -> bỏ móc u.
                if syllable.letters[n - 2].mark == .horn {
                    syllable.letters[n - 2].mark = .none
                    return .cancelled
                }
                syllable.letters[n - 2].mark = .horn
                return .applied
            }
        }

        if let last = syllable.letters.last {
            switch Character(last.base.lowercased()) {
            case "a":
                return last.mark == .breve ? removeMarkOnLast() : setMarkOnLast(.breve)
            case "o", "u":
                return last.mark == .horn ? removeMarkOnLast() : setMarkOnLast(.horn)
            default:
                break
            }
        }

        // GÕ TẮT 'w' -> 'ư': khi 'w' không áp được móc/trăng cho chữ cuối (chữ cuối
        // không phải a/o/u, hoặc âm tiết chưa có nguyên âm), 'w' tự tạo nguyên âm 'ư'.
        // Ví dụ: "tw"->tư, "mwf"->mừ, "w"->ư. Đây là cách gõ tắt Telex phổ biến.
        // Ngoại lệ: nếu chữ NGAY TRƯỚC thuộc nhóm không-ghép-được thì 'w' giữ thô.
        // (Nhóm chữ không ghép 'w': w e y f j k z.)
        if let prev = syllable.letters.last.map({ Character($0.base.lowercased()) }) {
            let standaloneWBad: Set<Character> = ["w", "e", "y", "f", "j", "k", "z"]
            if standaloneWBad.contains(prev) { return .notDiacritic }
        }
        // Chèn 'u' mang móc -> hiển thị 'ư'.
        syllable.letters.append(.init(base: "u", mark: .horn))
        return .applied
    }

    /// 7 trong VNI: o->ơ, u->ư.
    /// Trường hợp đặc biệt: cụm "uo" -> "ươ" — móc CẢ HAI nguyên âm,
    /// và cụm "ua" -> "ưa" — móc u.
    private func applyHornVNI() -> DiacriticResult {
        let n = syllable.letters.count

        // "uo" + 7 -> "ươ": áp móc cho cả u và o.
        if n >= 2,
           Character(syllable.letters[n - 2].base.lowercased()) == "u",
           Character(syllable.letters[n - 1].base.lowercased()) == "o" {
            let isPartOfQu = n >= 3 && Character(syllable.letters[n - 3].base.lowercased()) == "q"
            if !isPartOfQu {
                let isThuo = n >= 4 &&
                    Character(syllable.letters[n - 4].base.lowercased()) == "t" &&
                    Character(syllable.letters[n - 3].base.lowercased()) == "h"
                if isThuo {
                    if syllable.letters[n - 1].mark == .horn {
                        syllable.letters[n - 1].mark = .none
                        return .cancelled
                    }
                    syllable.letters[n - 1].mark = .horn
                    return .applied
                }

                if syllable.letters[n - 1].mark == .horn && syllable.letters[n - 2].mark == .horn {
                    syllable.letters[n - 2].mark = .none
                    syllable.letters[n - 1].mark = .none
                    return .cancelled
                }
                syllable.letters[n - 2].mark = .horn
                syllable.letters[n - 1].mark = .horn
                return .applied
            }
        }

        // "ua" + 7 -> "ưa": áp móc cho u.
        if n >= 2,
           Character(syllable.letters[n - 2].base.lowercased()) == "u",
           Character(syllable.letters[n - 1].base.lowercased()) == "a" {
            let isPartOfQu = n >= 3 && Character(syllable.letters[n - 3].base.lowercased()) == "q"
            if !isPartOfQu {
                if syllable.letters[n - 2].mark == .horn {
                    syllable.letters[n - 2].mark = .none
                    return .cancelled
                }
                syllable.letters[n - 2].mark = .horn
                return .applied
            }
        }

        if let last = syllable.letters.last {
            switch Character(last.base.lowercased()) {
            case "o", "u":
                return last.mark == .horn ? removeMarkOnLast() : setMarkOnLast(.horn)
            default:
                break
            }
        }

        return .notDiacritic
    }

    /// Lan móc trên cụm "uo" -> "ươ" khi gặp âm đóng đứng ngay sau.
    ///
    /// Tiếng Việt không có âm tiết chứa "ưo"/"uơ" trần — luôn là "ươ". Khi người
    /// dùng gõ tắt (vd "tw"->tư, rồi "o","n"), ta có "tưon"; lúc này cần đồng bộ
    /// móc cho cả u và o thành "tươn". Chỉ kích hoạt khi âm đóng kế tiếp thuộc
    /// {n, c, i, m, p, t} (âm đóng hợp lệ của cụm "ươ") và ĐÚNG MỘT trong u/o đang
    /// có móc — để không đụng vào "huow"->hươ đang gõ dở (chưa có âm đóng).
    private func propagateUoHorn() {
        let n = syllable.letters.count
        guard n >= 3 else { return }
        let closers: Set<Character> = ["n", "c", "i", "m", "p", "t"]
        guard closers.contains(Character(syllable.letters[n - 1].base.lowercased())) else { return }
        guard Character(syllable.letters[n - 3].base.lowercased()) == "u",
              Character(syllable.letters[n - 2].base.lowercased()) == "o" else { return }
        let uHorn = syllable.letters[n - 3].mark == .horn
        let oHorn = syllable.letters[n - 2].mark == .horn
        if uHorn != oHorn {
            syllable.letters[n - 3].mark = .horn
            syllable.letters[n - 2].mark = .horn
        }
    }

    // MARK: - Thao tác trên âm tiết

    /// Âm tiết hiện tại đã chứa ít nhất một nguyên âm chưa?
    private var hasVowel: Bool { syllable.letters.contains { $0.base.isVietVowel } }

    private func setTone(_ tone: Tone) -> DiacriticResult {
        // Dấu thanh chỉ hợp lệ khi âm tiết ĐÃ CÓ ÍT NHẤT MỘT NGUYÊN ÂM.
        // Nếu không, phím-dấu (s f r x j z) chỉ là phụ âm thường — ví dụ chữ 'r'
        // trong "tre"/"trên", chữ 's' trong "sai", 'x' trong "xin".
        // Không có guard này, gõ "tre" sẽ thành "tẻ" và "trên" thành "tển" vì 'r'
        // bị nuốt làm dấu hỏi dù âm tiết mới chỉ có phụ âm 't'.
        guard hasVowel else { return .notDiacritic }

        // GÕ LẠI ĐỂ BỎ/ĐỔI DẤU THANH:
        if syllable.tone == tone && tone != .none {
            // Gõ đúng dấu đang có -> GỠ dấu, trả ký tự thô (hoá + s -> hoas).
            syllable.tone = .none
            return .cancelled
        }
        // Khác dấu (hoặc 'z' xoá dấu) -> đặt/thay dấu mới.
        syllable.tone = tone
        return .applied
    }

    private func setMarkOnLast(_ mark: Mark) -> DiacriticResult {
        guard var last = syllable.letters.last else { return .notDiacritic }
        // Kiểm tra mark có hợp lệ cho chữ cái này không (tra bảng).
        guard VietTable.compose(base: last.base, mark: mark, tone: .none) != nil else {
            return .notDiacritic
        }
        last.mark = mark
        syllable.letters[syllable.letters.count - 1] = last
        return .applied
    }

    /// Gỡ dấu biến âm của chữ cái cuối (dùng khi gõ lại trùng biến âm: aa+a, ow+w...).
    private func removeMarkOnLast() -> DiacriticResult {
        guard var last = syllable.letters.last else { return .notDiacritic }
        last.mark = .none
        syllable.letters[syllable.letters.count - 1] = last
        return .cancelled
    }

    /// Như `setMarkOnLast` nhưng nếu chữ cuối ĐÃ mang đúng biến âm đó thì GỠ ra
    /// và trả ký tự thô — dùng cho VNI khi gõ lại số-biến-âm trùng để hủy.
    /// Ví dụ a6→â, a66→a6 (mũ bị gỡ, số '6' hiện ra); d9→đ, d99→d9.
    /// Cơ chế toggle: gõ lại số-biến-âm trùng thì gỡ dấu rồi chèn phím thô.
    private func setMarkOrToggle(_ mark: Mark) -> DiacriticResult {
        if let last = syllable.letters.last, last.mark == mark {
            return removeMarkOnLast()   // gõ lại số-biến-âm trùng -> gỡ + ký tự số thô
        }
        return setMarkOnLast(mark)
    }

    // MARK: - Render

    /// Dựng chuỗi hiển thị của âm tiết, đặt dấu thanh lên nguyên âm phù hợp.
    private func render() -> String {
        let toneIndex = toneTargetIndex()
        var out = ""
        for (i, letter) in syllable.letters.enumerated() {
            let tone: Tone = (i == toneIndex) ? syllable.tone : .none
            if let composed = VietTable.compose(base: letter.base, mark: letter.mark, tone: tone) {
                out.append(composed)
            } else {
                out.append(letter.base)
            }
        }
        return out
    }

    /// Chọn nguyên âm để đặt dấu thanh — theo QUY TẮC CHÍNH TẢ tiếng Việt.
    ///
    /// Vị trí dấu thanh KHÔNG cố định mà phụ thuộc vào "cụm nguyên âm" và việc
    /// có phụ âm cuối hay không.
    /// Ta rút gọn thành các luật ưu tiên, xét trên cụm nguyên âm [start...end]:
    ///
    ///   1. Nguyên âm nào MANG DẤU biến âm (â ê ô ơ ư ă) thì dấu thanh đặt lên đó.
    ///      vd: tiếng (ê), được (ơ), nướng (ơ).
    ///   2. Nếu cụm có phụ âm cuối -> dấu đặt lên nguyên âm CUỐI của cụm.
    ///      vd: toán (lên a), nguyễn — (xét luật 1 trước).
    ///   3. Cụm nguyên âm hở (không phụ âm cuối):
    ///        - 2 nguyên âm: đặt lên nguyên âm ĐẦU, TRỪ các đuôi mở
    ///          "oa/oe/uy" thì đặt lên nguyên âm SAU (hoà, quý, khoẻ).
    ///        - 3 nguyên âm (oai, uây, uyê...): đặt lên nguyên âm GIỮA.
    ///   4. 1 nguyên âm: đặt lên chính nó.
    ///
    /// Đây là phiên bản "modern orthography" (hoà, quý). Chế độ "old" (hòa)
    /// bật/tắt được qua toneStyle — chỗ để bạn mở rộng sau.
    private func toneTargetIndex() -> Int {
        // Luật 1: ưu tiên nguyên âm có dấu biến âm.
        if let marked = syllable.letters.lastIndex(where: {
            $0.mark == .circumflex || $0.mark == .breve || $0.mark == .horn
        }) {
            return marked
        }

        // Tìm cụm nguyên âm liên tiếp [start...end].
        var vowelIdx = syllable.letters.indices.filter { syllable.letters[$0].base.isVietVowel }

        // KÉO DÀI NGUYÊN ÂM: gộp các nguyên âm TRÙNG nhau liên tiếp về một đại diện
        // (giữ ký tự ĐẦU của chuỗi trùng — dấu thuộc về nguyên âm gốc). Nhờ vậy
        // "oiii" được tính như "oi" khi đặt dấu (chòiiii, không phải choìiii), còn
        // diphthong thật (oa, uy, ươ) không bị ảnh hưởng vì chữ khác nhau.
        if vowelIdx.count >= 2 {
            var collapsed: [Int] = []
            for idx in vowelIdx {
                if let prev = collapsed.last,
                   Character(syllable.letters[prev].base.lowercased())
                     == Character(syllable.letters[idx].base.lowercased()) {
                    continue   // cùng nguyên âm với cái trước -> bỏ (kéo dài)
                }
                collapsed.append(idx)
            }
            vowelIdx = collapsed
        }

        // "qu" và "gi": chữ 'u' sau 'q' và chữ 'i' sau 'g' KHÔNG phải nguyên âm chính
        // mà là một phần của phụ âm đầu. Loại nó khỏi cụm tính dấu — NHƯNG chỉ khi
        // cụm còn nguyên âm khác phía sau (vd "quà"->dấu lên a, "già"->lên a). Nếu nó
        // là nguyên âm DUY NHẤT thì giữ lại để nhận dấu ("gì", "qù").
        // Quy tắc chính tả: "gi"/"qu" — 'i'/'u' là bán phụ âm của phụ âm đầu.
        if vowelIdx.count >= 2, let first = vowelIdx.first {
            let firstBase = Character(syllable.letters[first].base.lowercased())
            let prevBase = first > 0
                ? Character(syllable.letters[first - 1].base.lowercased())
                : Character(" ")
            if (firstBase == "i" && prevBase == "g") || (firstBase == "u" && prevBase == "q") {
                vowelIdx.removeFirst()
            }
        }

        guard let start = vowelIdx.first, let end = vowelIdx.last else { return -1 }
        let count = vowelIdx.count

        // Có phụ âm sau cụm nguyên âm không? (chữ cái không phải nguyên âm, đứng sau `end`)
        let hasFinalConsonant = (end + 1 < syllable.letters.count)
            && !syllable.letters[end + 1].base.isVietVowel

        // Luật 2: có phụ âm cuối -> dấu lên nguyên âm cuối của cụm.
        if hasFinalConsonant {
            return end
        }

        // Cụm nguyên âm hở:
        switch count {
        case 1:
            return start                         // luật 4
        case 2:
            // luật 3: mặc định lên nguyên âm đầu, trừ "oa/oe/uy" -> lên sau.
            // Ở chế độ "old", các đuôi mở này vẫn đặt dấu lên nguyên âm đầu (hòa, qúy).
            if toneStyle == .old { return start }
            let a = Character(syllable.letters[start].base.lowercased())
            let b = Character(syllable.letters[end].base.lowercased())
            let openTail = (a == "o" && (b == "a" || b == "e")) || (a == "u" && b == "y")
            return openTail ? end : start
        default:
            // luật 3: 3 nguyên âm -> nguyên âm giữa.
            return vowelIdx[1]
        }
    }
}

private extension Character {
    var isVietVowel: Bool {
        "aeiouy".contains(Character(self.lowercased()))
    }
}
