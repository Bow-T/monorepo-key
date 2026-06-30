// Macro.swift
// -----------
// GÕ TẮT (macro/snippet): gõ một "từ khoá" ngắn (vd "vn") rồi nhấn phím ngắt từ
// (space, dấu câu) -> bộ gõ thay từ khoá bằng nội dung dài ("Việt Nam").
//
// THIẾT KẾ (đối chiếu PHTV, rút gọn cho engine BowKey):
//   • Khớp theo CHUỖI PHÍM THÔ ASCII người dùng gõ (không theo chữ đã bỏ dấu),
//     để từ khoá không lẫn với bộ gõ tiếng Việt. Vd từ khoá "vn", "btw", "kb".
//   • Bung khi gặp PHÍM NGẮT TỪ (space/dấu câu), không bung giữa chừng.
//   • Nội dung có thể TĨNH ("Việt Nam") hoặc ĐỘNG (ngày/giờ/đếm/ngẫu nhiên) —
//     phần động học từ EngineMacroSnippetRuntime của PHTV.
//
// Lớp này THUẦN LOGIC (không phụ thuộc AppKit) nên test được bằng `swift test`.

import Foundation

/// Loại nội dung macro.
public enum MacroSnippetType: Equatable {
    case staticText            // nội dung cố định
    case date                  // ngày, theo format (mặc định dd/MM/yyyy)
    case time                  // giờ, theo format (mặc định HH:mm:ss)
    case dateTime              // ngày giờ
    case random                // chọn ngẫu nhiên từ danh sách phân tách bởi ','
    case counter               // bộ đếm tăng dần theo prefix
}

/// Một định nghĩa macro: từ khoá -> nội dung.
public struct MacroDefinition: Equatable {
    /// Từ khoá thô (ASCII, không dấu) người dùng gõ để kích hoạt, vd "vn".
    public let keyword: String
    /// Nội dung thay thế (với loại tĩnh) HOẶC format/tham số (với loại động).
    public let content: String
    public let type: MacroSnippetType

    public init(keyword: String, content: String, type: MacroSnippetType = .staticText) {
        self.keyword = keyword
        self.content = content
        self.type = type
    }
}

/// Bộ sinh nội dung động + kho macro. Tách khỏi engine để dễ test & tái dùng.
public final class MacroStore {
    private var byKeyword: [String: MacroDefinition] = [:]
    private var counters: [String: Int] = [:]

    /// Nguồn ngày giờ & ngẫu nhiên — tiêm vào để test xác định (deterministic).
    /// Mặc định dùng đồng hồ thật + random thật.
    public struct Environment {
        public var now: () -> Date
        public var randomIndex: (_ count: Int) -> Int
        public var clipboard: () -> String
        public init(now: @escaping () -> Date = { Date() },
                    randomIndex: @escaping (Int) -> Int = { Int.random(in: 0..<$0) },
                    clipboard: @escaping () -> String = { "" }) {
            self.now = now
            self.randomIndex = randomIndex
            self.clipboard = clipboard
        }
    }
    private let env: Environment

    public init(_ definitions: [MacroDefinition] = [], environment: Environment = Environment()) {
        self.env = environment
        for d in definitions { byKeyword[d.keyword] = d }
    }

    /// Thêm / ghi đè một macro.
    public func set(_ definition: MacroDefinition) {
        byKeyword[definition.keyword] = definition
    }

    /// Xoá toàn bộ macro (và reset bộ đếm).
    public func clear() {
        byKeyword.removeAll()
        counters.removeAll()
    }

    public var isEmpty: Bool { byKeyword.isEmpty }

    /// Tra macro theo từ khoá thô. Trả về nội dung ĐÃ BUNG (đã giải động), hoặc nil.
    public func expand(keyword: String) -> String? {
        guard let def = byKeyword[keyword] else { return nil }
        return render(def)
    }

    // MARK: - Sinh nội dung

    private func render(_ def: MacroDefinition) -> String {
        switch def.type {
        case .staticText: return def.content
        case .date:       return formatDateTime(def.content.isEmpty ? "dd/MM/yyyy" : def.content)
        case .time:       return formatDateTime(def.content.isEmpty ? "HH:mm:ss" : def.content)
        case .dateTime:   return formatDateTime(def.content.isEmpty ? "dd/MM/yyyy HH:mm" : def.content)
        case .random:     return randomValue(from: def.content)
        case .counter:    return counterValue(prefix: def.content)
        }
    }

    /// Bung format ngày giờ kiểu dd/MM/yyyy HH:mm:ss (port từ PHTV).
    /// Token lặp: d/M/y/H/m/s; lặp >=2 -> đệm 0; yyyy -> năm đủ 4 số.
    private func formatDateTime(_ format: String) -> String {
        let tokens: Set<Character> = ["d", "M", "y", "H", "m", "s"]
        let c = Calendar.current.dateComponents(
            [.day, .month, .year, .hour, .minute, .second], from: env.now())
        let day = c.day ?? 0, month = c.month ?? 0, year = c.year ?? 0
        let hour = c.hour ?? 0, minute = c.minute ?? 0, second = c.second ?? 0
        func two(_ v: Int) -> String { String(format: "%02d", v) }

        var out = ""
        var lastChar: Character? = nil
        var repeatCount = 0
        func flush() {
            guard let ch = lastChar, repeatCount > 0 else { return }
            switch ch {
            case "d": out += repeatCount >= 2 ? two(day) : String(day)
            case "M": out += repeatCount >= 2 ? two(month) : String(month)
            case "y": out += repeatCount >= 4 ? String(year) : two(year % 100)
            case "H": out += repeatCount >= 2 ? two(hour) : String(hour)
            case "m": out += repeatCount >= 2 ? two(minute) : String(minute)
            case "s": out += repeatCount >= 2 ? two(second) : String(second)
            default:  out += String(repeating: ch, count: repeatCount)
            }
            repeatCount = 0
        }
        for ch in format {
            if ch == lastChar, tokens.contains(ch) {
                repeatCount += 1
            } else {
                flush(); lastChar = ch; repeatCount = 1
            }
        }
        flush()
        return out
    }

    private func randomValue(from list: String) -> String {
        let items = list.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t")) }
            .filter { !$0.isEmpty }
        guard !items.isEmpty else { return list }
        return items[env.randomIndex(items.count)]
    }

    private func counterValue(prefix: String) -> String {
        let next = (counters[prefix] ?? 0) + 1
        counters[prefix] = next
        return "\(prefix)\(next)"
    }
}
