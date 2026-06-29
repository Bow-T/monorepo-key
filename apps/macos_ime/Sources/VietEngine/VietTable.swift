// VietTable.swift
// ---------------
// Bảng tra: (chữ cái gốc, dấu biến âm, dấu thanh) -> ký tự Unicode tiếng Việt.
//
// Vì sao cần bảng này? Vì tiếng Việt có sẵn các ký tự dựng sẵn (precomposed) trong
// Unicode như "ế", "ữ", "ặ". Engine suy nghĩ theo (gốc + mark + tone) rồi tra ra
// ký tự cuối cùng để "gõ ra màn hình".
//
// Cách đọc bảng: với mỗi nguyên âm có dấu, ta liệt kê 6 biến thể theo 6 thanh,
// theo đúng thứ tự enum Tone: [none, acute, grave, hook, tilde, dot].

enum VietTable {

    /// Trả về ký tự tiếng Việt dựng sẵn cho tổ hợp (base + mark + tone).
    /// Nếu không phải nguyên âm hợp lệ -> trả về nil (engine sẽ giữ nguyên ký tự gốc).
    static func compose(base: Character, mark: Mark, tone: Tone) -> Character? {
        let isUpper = base.isUppercase
        let lower = Character(base.lowercased())

        guard let variants = lower.toneVariants(mark: mark) else { return nil }
        let result = variants[tone.index]
        return isUpper ? Character(result.uppercased()) : result
    }
}

private extension Tone {
    /// Vị trí của thanh trong mảng 6 biến thể.
    var index: Int {
        switch self {
        case .none:  return 0
        case .acute: return 1
        case .grave: return 2
        case .hook:  return 3
        case .tilde: return 4
        case .dot:   return 5
        }
    }
}

private extension Character {
    /// Trả mảng 6 biến thể theo thanh [ngang, sắc, huyền, hỏi, ngã, nặng]
    /// cho chữ cái gốc (đã lowercase) với dấu biến âm `mark`.
    /// Trả nil nếu tổ hợp không hợp lệ trong tiếng Việt.
    func toneVariants(mark: Mark) -> [Character]? {
        switch (self, mark) {
        // --- a ---
        case ("a", .none):       return chars("a á à ả ã ạ")
        case ("a", .circumflex): return chars("â ấ ầ ẩ ẫ ậ")
        case ("a", .breve):      return chars("ă ắ ằ ẳ ẵ ặ")
        // --- e ---
        case ("e", .none):       return chars("e é è ẻ ẽ ẹ")
        case ("e", .circumflex): return chars("ê ế ề ể ễ ệ")
        // --- i ---
        case ("i", .none):       return chars("i í ì ỉ ĩ ị")
        // --- o ---
        case ("o", .none):       return chars("o ó ò ỏ õ ọ")
        case ("o", .circumflex): return chars("ô ố ồ ổ ỗ ộ")
        case ("o", .horn):       return chars("ơ ớ ờ ở ỡ ợ")
        // --- u ---
        case ("u", .none):       return chars("u ú ù ủ ũ ụ")
        case ("u", .horn):       return chars("ư ứ ừ ử ữ ự")
        // --- y ---
        case ("y", .none):       return chars("y ý ỳ ỷ ỹ ỵ")
        // --- đ (phụ âm, không mang dấu thanh; lặp 6 lần cho khớp định dạng) ---
        case ("d", .dyet):       return chars("đ đ đ đ đ đ")
        default:
            return nil
        }
    }
}

/// Helper: tách chuỗi "á à ả" thành mảng Character.
private func chars(_ s: String) -> [Character] {
    s.split(separator: " ").map { Character(String($0)) }
}
