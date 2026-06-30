// KeyCodeMap.swift
// ----------------
// CGEvent cho ta "keyCode" (mã phím vật lý, vd phím A = 0). Nhưng engine làm việc
// với Character ('a', 'b'...). File này dịch keyCode -> ký tự, có xét Shift để
// ra chữ hoa.
//
// Dịch "chuẩn" theo layout thật đã chuyển sang KeyboardLayout.swift (UCKeyTranslate).
// File này GIỜ đóng vai FALLBACK: bảng tĩnh US QWERTY dùng khi UCKeyTranslate không
// cho kết quả, CỘNG với keyCode của các phím đặc biệt (delete/space/return/tab/esc)
// và hàm isWordBreak mà EventTapController luôn cần.

import CoreGraphics

enum KeyCodeMap {

    /// keyCode -> chữ thường (US QWERTY). Chỉ gồm chữ cái + số (đủ cho Telex/VNI).
    private static let base: [Int64: Character] = [
        0: "a", 11: "b", 8: "c", 2: "d", 14: "e", 3: "f", 5: "g", 4: "h",
        34: "i", 38: "j", 40: "k", 37: "l", 46: "m", 45: "n", 31: "o", 35: "p",
        12: "q", 15: "r", 1: "s", 17: "t", 32: "u", 9: "v", 13: "w", 7: "x",
        16: "y", 6: "z",
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5",
        22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
    ]

    /// keyCode của các phím điều khiển ta quan tâm.
    static let delete: Int64 = 51      // Backspace
    static let space: Int64  = 49
    static let `return`: Int64 = 36
    static let tab: Int64    = 48
    static let escape: Int64 = 53

    /// Trả về Character cho keyCode, áp dụng Shift để ra chữ hoa.
    /// nil nếu là phím ta không xử lý (mũi tên, ký hiệu...).
    static func character(for keyCode: Int64, shift: Bool) -> Character? {
        guard let ch = base[keyCode] else { return nil }
        if shift && ch.isLetter {
            return Character(ch.uppercased())
        }
        return ch
    }

    /// keyCode này có phải phím "ngắt âm tiết" không (space, return, tab, esc)?
    static func isWordBreak(_ keyCode: Int64) -> Bool {
        keyCode == space || keyCode == `return` || keyCode == tab || keyCode == escape
    }

    /// Ký tự tương ứng phím ngắt từ (để tự gõ lại sau khi bung macro).
    /// space -> " ", return -> "\n", tab -> "\t". esc không có ký tự -> " ".
    static func wordBreakCharacter(for keyCode: Int64) -> Character {
        switch keyCode {
        case space:    return " "
        case `return`: return "\n"
        case tab:      return "\t"
        default:       return " "
        }
    }
}
