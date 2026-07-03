// Calculator.swift
// ----------------
// MÁY TÍNH BIỂU THỨC nhỏ cho macro `calc`: gõ tắt một biểu thức số học rồi bung ra
// KẾT QUẢ (vd "5*3+2" -> "17", "(2+3)/4" -> "1.25").
//
// Hỗ trợ: + - * / và dấu ngoặc ( ), số thập phân, số âm. Ưu tiên toán tử chuẩn
// (* / trước + -). Thuần logic -> test được; không phụ thuộc gì ngoài Foundation.
//
// Cách cài: shunting-yard đơn giản -> tính hậu tố (RPN). Trả nil nếu biểu thức sai.

import Foundation

public enum Calculator {

    /// Tính biểu thức, trả CHUỖI kết quả (số nguyên không có ".0"); nil nếu lỗi.
    /// Vd: eval("5*3+2") == "17"; eval("10/4") == "2.5"; eval("1/0") == nil.
    public static func eval(_ expression: String) -> String? {
        guard let value = evaluate(expression), value.isFinite else { return nil }
        return format(value)
    }

    /// Tính ra Double (nil nếu sai cú pháp hoặc chia 0).
    public static func evaluate(_ expression: String) -> Double? {
        guard let tokens = tokenize(expression) else { return nil }
        guard let rpn = toRPN(tokens) else { return nil }
        return evalRPN(rpn)
    }

    // MARK: - Token

    private enum Token: Equatable {
        case number(Double)
        case op(Character)          // + - * /
        case lparen
        case rparen
    }

    /// Tách chuỗi thành token. Xử lý số âm (dấu '-' đầu biểu thức hoặc sau '(' / toán tử).
    private static func tokenize(_ s: String) -> [Token]? {
        var tokens: [Token] = []
        let chars = Array(s)
        var i = 0

        func lastMeaningfulAllowsUnary() -> Bool {
            // Dấu '-' là NGẮT ÂM khi đứng đầu, sau '(' hoặc sau một toán tử.
            guard let last = tokens.last else { return true }
            switch last {
            case .op, .lparen: return true
            default: return false
            }
        }

        while i < chars.count {
            let c = chars[i]
            if c == " " || c == "\t" { i += 1; continue }

            if c.isNumber || c == "." {
                var num = ""
                while i < chars.count, chars[i].isNumber || chars[i] == "." {
                    num.append(chars[i]); i += 1
                }
                guard let d = Double(num) else { return nil }
                tokens.append(.number(d))
                continue
            }

            switch c {
            case "+", "*", "/":
                tokens.append(.op(c)); i += 1
            case "-":
                if lastMeaningfulAllowsUnary() {
                    // Số âm: gộp dấu '-' vào số kế tiếp.
                    i += 1
                    var num = ""
                    while i < chars.count, chars[i].isNumber || chars[i] == "." {
                        num.append(chars[i]); i += 1
                    }
                    guard let d = Double(num) else { return nil }
                    tokens.append(.number(-d))
                } else {
                    tokens.append(.op("-")); i += 1
                }
            case "(":
                tokens.append(.lparen); i += 1
            case ")":
                tokens.append(.rparen); i += 1
            default:
                return nil   // ký tự lạ -> không phải biểu thức
            }
        }
        return tokens.isEmpty ? nil : tokens
    }

    // MARK: - Shunting-yard -> RPN

    private static func precedence(_ op: Character) -> Int {
        (op == "*" || op == "/") ? 2 : 1
    }

    private static func toRPN(_ tokens: [Token]) -> [Token]? {
        var output: [Token] = []
        var ops: [Token] = []

        for token in tokens {
            switch token {
            case .number:
                output.append(token)
            case .op(let o):
                while case .op(let top)? = ops.last, precedence(top) >= precedence(o) {
                    output.append(ops.removeLast())
                }
                ops.append(token)
            case .lparen:
                ops.append(token)
            case .rparen:
                var foundLParen = false
                while let top = ops.last {
                    if top == .lparen { ops.removeLast(); foundLParen = true; break }
                    output.append(ops.removeLast())
                }
                if !foundLParen { return nil }   // ngoặc lệch
            }
        }
        while let top = ops.popLast() {
            if top == .lparen { return nil }     // ngoặc lệch
            output.append(top)
        }
        return output
    }

    // MARK: - Tính RPN

    private static func evalRPN(_ rpn: [Token]) -> Double? {
        var stack: [Double] = []
        for token in rpn {
            switch token {
            case .number(let d):
                stack.append(d)
            case .op(let o):
                guard stack.count >= 2 else { return nil }
                let b = stack.removeLast()
                let a = stack.removeLast()
                switch o {
                case "+": stack.append(a + b)
                case "-": stack.append(a - b)
                case "*": stack.append(a * b)
                case "/":
                    guard b != 0 else { return nil }   // chia 0
                    stack.append(a / b)
                default: return nil
                }
            default:
                return nil
            }
        }
        return stack.count == 1 ? stack[0] : nil
    }

    // MARK: - Định dạng kết quả

    /// Số nguyên -> không có phần thập phân; số lẻ -> tối đa 6 chữ số sau dấu chấm,
    /// bỏ số 0 thừa. Vd 17.0 -> "17"; 2.5 -> "2.5"; 1/3 -> "0.333333".
    private static func format(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1e15 {
            return String(Int(value))
        }
        var s = String(format: "%.6f", value)
        // Bỏ số 0 thừa ở cuối phần thập phân.
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}
