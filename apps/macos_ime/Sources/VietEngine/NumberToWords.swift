// NumberToWords.swift
// -------------------
// ĐỌC SỐ THÀNH CHỮ tiếng Việt: 123 -> "một trăm hai mươi ba".
//
// Dùng cho: biến đổi vùng bôi đen (bôi "1500000" -> đọc thành chữ) + tiện ích hoá
// đơn/hợp đồng. Thuần logic -> test được.
//
// Quy tắc chính tả số tiếng Việt được xử lý:
//   • mười / mươi:  10 = "mười", 20 = "hai mươi" (số hàng chục >1 dùng "mươi").
//   • linh / lẻ:    105 = "một trăm linh năm" (hàng chục = 0 mà có hàng đơn vị).
//   • mốt:          21 = "hai mươi mốt" (đơn vị =1 sau "mươi", KHÔNG sau "mười").
//   • lăm:          15 = "mười lăm", 25 = "hai mươi lăm" (đơn vị =5 sau chục).
//   • Nhóm 3 chữ số: nghìn / triệu / tỷ; tỷ lặp cho số cực lớn.
//
// Hỗ trợ số nguyên âm ("âm ..."), số 0 ("không"). Số thập phân: đọc phần nguyên +
// "phẩy" + từng chữ số phần lẻ (1.5 -> "một phẩy năm").

import Foundation

public enum NumberToWords {

    private static let digits = ["không", "một", "hai", "ba", "bốn",
                                 "năm", "sáu", "bảy", "tám", "chín"]
    /// Đơn vị nhóm 3 chữ số: "", nghìn, triệu, tỷ (tỷ lặp cho nhóm cao hơn).
    private static let groupUnits = ["", "nghìn", "triệu", "tỷ"]

    /// Đọc một CHUỖI số (có thể kèm dấu '-', '.', khoảng trắng, dấu phân nhóm ',').
    /// Trả nil nếu không phải số hợp lệ. Vd convert("1.500.000")… -> xem chuẩn hoá dưới.
    public static func convert(_ text: String) -> String? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        var negative = false
        if s.hasPrefix("-") {
            negative = true
            s.removeFirst()
        }

        // Bỏ dấu phân nhóm hàng nghìn kiểu ',' (1,500,000). Dấu '.' coi là THẬP PHÂN
        // nếu chỉ xuất hiện 1 lần và có chữ số hai bên; nhiều '.' -> phân nhóm (bỏ).
        s = s.replacingOccurrences(of: ",", with: "")
        let dotCount = s.filter { $0 == "." }.count
        var integerPart = s
        var fractionPart: String? = nil
        if dotCount == 1, let range = s.range(of: ".") {
            let before = String(s[s.startIndex..<range.lowerBound])
            let after = String(s[range.upperBound..<s.endIndex])
            if !before.isEmpty && !after.isEmpty {
                integerPart = before
                fractionPart = after
            } else {
                return nil
            }
        } else if dotCount > 1 {
            integerPart = s.replacingOccurrences(of: ".", with: "")  // phân nhóm
        }

        // Chỉ chấp nhận chữ số ở phần nguyên & phần lẻ.
        guard integerPart.allSatisfy({ $0.isNumber }),
              (fractionPart?.allSatisfy { $0.isNumber } ?? true) else {
            return nil
        }
        guard !integerPart.isEmpty else { return nil }

        var words = readInteger(integerPart)
        if let frac = fractionPart, !frac.isEmpty {
            // Đọc từng chữ số phần thập phân.
            let fracWords = frac.compactMap { $0.wholeNumberValue }.map { digits[$0] }
            words += " phẩy " + fracWords.joined(separator: " ")
        }
        if negative && !(integerPart.allSatisfy { $0 == "0" } && fractionPart == nil) {
            words = "âm " + words
        }
        return words
    }

    // MARK: - Đọc phần nguyên

    /// Đọc chuỗi chữ số nguyên (đã sạch) thành chữ. "0" -> "không".
    private static func readInteger(_ digitsStr: String) -> String {
        // Bỏ số 0 ở đầu (trừ khi toàn 0).
        let trimmed = String(digitsStr.drop { $0 == "0" })
        if trimmed.isEmpty { return "không" }

        // Chia thành các nhóm 3 chữ số từ phải sang.
        var groups: [String] = []
        var chars = Array(trimmed)
        while !chars.isEmpty {
            let take = min(3, chars.count)
            groups.insert(String(chars.suffix(take)), at: 0)
            chars.removeLast(take)
        }

        let groupCount = groups.count
        var parts: [String] = []
        for (i, group) in groups.enumerated() {
            let value = Int(group) ?? 0
            let unitIndex = groupCount - 1 - i
            if value == 0 {
                // Nhóm rỗng: bỏ qua (đơn vị vẫn tính qua vị trí).
                continue
            }
            // Nhóm KHÔNG phải nhóm đầu tiên và <100 cần "không trăm"/"linh" để rõ.
            let isLeadingGroup = parts.isEmpty
            let groupWords = readThreeDigits(value, forceFullHundred: !isLeadingGroup)
            let unit = unitName(unitIndex)
            parts.append(unit.isEmpty ? groupWords : "\(groupWords) \(unit)")
        }
        return parts.joined(separator: " ")
    }

    /// Tên đơn vị nhóm theo chỉ số (0=đơn vị, 1=nghìn, 2=triệu, 3=tỷ, 4=nghìn tỷ...).
    private static func unitName(_ index: Int) -> String {
        if index < groupUnits.count { return groupUnits[index] }
        // index >= 4: lặp tỷ. 4 -> "nghìn tỷ", 5 -> "triệu tỷ", 6 -> "tỷ tỷ"...
        let over = index - 3
        let base = groupUnits[over % 3 + 1]  // nghìn/triệu/tỷ theo chu kỳ
        let tyCount = 1 + over / 3
        return base + String(repeating: " tỷ", count: tyCount)
    }

    /// Đọc một số 1..999. `forceFullHundred` = luôn đọc hàng trăm (kể cả 0 -> "không trăm")
    /// và dùng "linh" cho hàng chục 0 — dùng cho nhóm không phải nhóm đầu.
    private static func readThreeDigits(_ n: Int, forceFullHundred: Bool) -> String {
        let hundreds = n / 100
        let tens = (n % 100) / 10
        let units = n % 10
        var words: [String] = []

        if hundreds > 0 {
            words.append("\(digits[hundreds]) trăm")
        } else if forceFullHundred {
            words.append("không trăm")
        }

        if tens == 0 {
            if units > 0 && (hundreds > 0 || forceFullHundred) {
                words.append("linh")
                words.append(digits[units])
            } else if units > 0 {
                words.append(digits[units])
            }
        } else if tens == 1 {
            words.append("mười")
            if units == 5 {
                words.append("lăm")
            } else if units > 0 {
                words.append(digits[units])
            }
        } else {
            words.append("\(digits[tens]) mươi")
            if units == 1 {
                words.append("mốt")
            } else if units == 5 {
                words.append("lăm")
            } else if units > 0 {
                words.append(digits[units])
            }
        }
        return words.joined(separator: " ")
    }
}
