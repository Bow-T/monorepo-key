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

    public init(method: InputMethod = .telex, toneStyle: ToneStyle = .modern) {
        self.method = method
        self.toneStyle = toneStyle
    }

    // MARK: - Buffer phím thô (giữ lịch sử phím gốc người dùng gõ)

    /// Đúng dãy phím người dùng đã gõ cho âm tiết hiện tại (vd "tieengs").
    /// Giữ buffer này để có thể DỰNG LẠI (replay) âm tiết — cần cho backspace, ESC.
    private var rawKeys: [Character] = []

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
            if let last = syllable.letters.last,
               Character(last.base.lowercased()) == lower {
                if last.mark == .circumflex {
                    return removeMarkOnLast()        // aa rồi a nữa -> bỏ mũ
                }
                if last.mark == .none {
                    return setMarkOnLast(.circumflex)
                }
            }
            return .notDiacritic  // 'a/e/o' đơn -> để bước 3 nối như chữ thường

        // w: ă/ơ/ư tuỳ chữ cái cuối; dd -> đ
        case "w":
            return applyHornOrBreve()
        case "d":
            if let last = syllable.letters.last,
               Character(last.base.lowercased()) == "d",
               last.mark == .none {
                return setMarkOnLast(.dyet)   // dd -> đ
            }
            return .notDiacritic

        default:
            return .notDiacritic
        }
    }

    private func applyVNI(_ ch: Character) -> DiacriticResult {
        switch ch {
        case "1": return setTone(.acute)
        case "2": return setTone(.grave)
        case "3": return setTone(.hook)
        case "4": return setTone(.tilde)
        case "5": return setTone(.dot)
        case "0": return setTone(.none)
        case "6": return setMarkOnLast(.circumflex)  // â/ê/ô
        case "7": return setMarkOnLast(.horn)        // ơ/ư
        case "8": return setMarkOnLast(.breve)       // ă
        case "9": return setMarkOnLast(.dyet)        // đ
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

        guard let last = syllable.letters.last else { return .notDiacritic }
        switch Character(last.base.lowercased()) {
        case "a":
            return last.mark == .breve ? removeMarkOnLast() : setMarkOnLast(.breve)
        case "o", "u":
            return last.mark == .horn ? removeMarkOnLast() : setMarkOnLast(.horn)
        default:
            return .notDiacritic
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
        let vowelIdx = syllable.letters.indices.filter { syllable.letters[$0].base.isVietVowel }
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
