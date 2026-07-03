// NumberFormatter+Grouping.swift
// ------------------------------
// ĐỊNH DẠNG SỐ có/không dấu phân nhóm hàng nghìn (kiểu Việt Nam dùng dấu '.').
//   • group:   "1500000"   -> "1.500.000"
//   • ungroup: "1.500.000" -> "1500000"
//
// Giữ nguyên dấu âm và phần thập phân (phần thập phân KHÔNG chèn dấu phân nhóm).
// Phần thập phân dùng dấu ',' theo quy ước VN khi ĐÃ nhóm (1234.5 -> "1.234,5");
// khi bỏ nhóm thì trả về dạng máy đọc được (dùng '.'). Thuần logic -> test được.

import Foundation

public enum NumberGrouping {

    /// Thêm dấu phân nhóm hàng nghìn. Trả nil nếu không phải số hợp lệ.
    /// "1500000" -> "1.500.000"; "1234.5" -> "1.234,5"; "-1000" -> "-1.000".
    public static func group(_ text: String) -> String? {
        guard let parsed = parse(text) else { return nil }
        let grouped = insertGroups(parsed.integer)
        var out = parsed.negative ? "-\(grouped)" : grouped
        if let frac = parsed.fraction {
            out += ",\(frac)"   // dấu thập phân kiểu VN
        }
        return out
    }

    /// Bỏ dấu phân nhóm, trả số "trần" máy đọc được (dùng '.' cho thập phân).
    /// "1.500.000" -> "1500000"; "1.234,5" -> "1234.5"; "-1.000" -> "-1000".
    public static func ungroup(_ text: String) -> String? {
        guard let parsed = parse(text) else { return nil }
        var out = parsed.negative ? "-\(parsed.integer)" : parsed.integer
        if let frac = parsed.fraction {
            out += ".\(frac)"
        }
        return out
    }

    // MARK: - Phân tích

    private struct Parsed {
        let negative: Bool
        let integer: String     // chỉ chữ số, đã bỏ 0 đầu thừa (tối thiểu "0")
        let fraction: String?   // chỉ chữ số, hoặc nil
    }

    /// Chuẩn hoá đầu vào: chấp nhận dấu phân nhóm '.' hoặc ',' và dấu thập phân
    /// còn lại. Quy tắc: dấu XUẤT HIỆN CUỐI CÙNG mà theo sau là 1-2… chữ số và chỉ
    /// xuất hiện 1 lần được coi là THẬP PHÂN; các dấu còn lại là phân nhóm (bỏ).
    private static func parse(_ text: String) -> Parsed? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        var negative = false
        if s.hasPrefix("-") { negative = true; s.removeFirst() }
        guard !s.isEmpty else { return nil }

        // Chỉ cho phép chữ số + '.' + ','.
        guard s.allSatisfy({ $0.isNumber || $0 == "." || $0 == "," }) else { return nil }

        // Xác định dấu thập phân: nếu có ',' -> ',' là thập phân (kiểu VN), '.' là nhóm.
        // Nếu chỉ có '.' và xuất hiện ĐÚNG 1 lần với <=? -> coi '.' là thập phân KHI
        // phần sau không dài kiểu nhóm 3. Đơn giản & an toàn: ',' luôn là thập phân;
        // '.' là thập phân chỉ khi là dấu duy nhất và không phải bội số nhóm-3.
        var integerRaw = s
        var fraction: String? = nil

        if let commaIdx = s.lastIndex(of: ",") {
            integerRaw = String(s[s.startIndex..<commaIdx]).replacingOccurrences(of: ".", with: "")
            let fr = String(s[s.index(after: commaIdx)..<s.endIndex])
            guard fr.allSatisfy({ $0.isNumber }), !fr.isEmpty else { return nil }
            fraction = fr
        } else {
            let dotCount = s.filter { $0 == "." }.count
            if dotCount == 1, let dotIdx = s.firstIndex(of: ".") {
                let after = String(s[s.index(after: dotIdx)..<s.endIndex])
                let before = String(s[s.startIndex..<dotIdx])
                // '.' là THẬP PHÂN nếu phần sau KHÔNG đúng 3 chữ số, hoặc phần trước rỗng.
                // (123.456 mơ hồ -> ưu tiên coi là nhóm; 12.5 -> thập phân.)
                if !after.isEmpty, before.isEmpty {
                    return nil
                } else if after.count != 3 {
                    guard after.allSatisfy({ $0.isNumber }), !after.isEmpty else { return nil }
                    integerRaw = before
                    fraction = after
                } else {
                    integerRaw = s.replacingOccurrences(of: ".", with: "")  // nhóm
                }
            } else {
                integerRaw = s.replacingOccurrences(of: ".", with: "")      // nhiều '.' -> nhóm
            }
        }

        guard integerRaw.allSatisfy({ $0.isNumber }), !integerRaw.isEmpty else { return nil }
        // Bỏ 0 đầu thừa (giữ tối thiểu "0").
        let normalized = String(integerRaw.drop { $0 == "0" })
        let integer = normalized.isEmpty ? "0" : normalized
        return Parsed(negative: negative, integer: integer, fraction: fraction)
    }

    /// Chèn dấu '.' mỗi 3 chữ số từ phải sang. "1500000" -> "1.500.000".
    private static func insertGroups(_ digits: String) -> String {
        let chars = Array(digits)
        var out = ""
        for (i, c) in chars.enumerated() {
            if i > 0 && (chars.count - i) % 3 == 0 { out.append(".") }
            out.append(c)
        }
        return out
    }
}
