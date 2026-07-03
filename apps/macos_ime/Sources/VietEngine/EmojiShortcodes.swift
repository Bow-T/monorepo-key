// EmojiShortcodes.swift
// ---------------------
// GÕ TẮT EMOJI theo shortcode kiểu Slack/Discord: gõ `:cry:` + phím ngắt từ ->
// thay bằng 😢. Tái dùng TOÀN BỘ đường bung của macro (xem Macro.swift): mỗi
// shortcode là một `MacroDefinition` tĩnh với keyword là chuỗi `:tên:`.
//
// Vì sao là macro tĩnh mà không phải cơ chế riêng?
//   • Keyword khớp theo CHUỖI PHÍM THÔ ASCII (`:`, chữ cái) — trùng khít cách
//     macro đã khớp `wordRawKeys`. Ký tự `:` cũng là phím thô nên nằm sẵn trong
//     buffer. Không cần thêm logic khớp/nuốt phím nào.
//   • Bung ở PHÍM NGẮT TỪ (space/enter/tab) — đúng hành vi người dùng mong đợi.
//
// Danh sách gọn, phủ các emoji hay dùng. Người dùng vẫn có thể tự thêm macro
// emoji riêng (keyword tuỳ ý) qua Cài đặt nếu muốn nhiều hơn.

import Foundation

public enum EmojiShortcodes {

    /// Bảng shortcode -> emoji. Keyword để dạng `:tên:` cho quen (Slack/GitHub).
    /// Giữ chữ thường; người dùng gõ y hệt.
    public static let table: [String: String] = [
        // Mặt cười / cảm xúc
        ":smile:": "😄", ":grin:": "😁", ":joy:": "😂", ":rofl:": "🤣",
        ":sweat_smile:": "😅", ":wink:": "😉", ":blush:": "😊", ":yum:": "😋",
        ":sunglasses:": "😎", ":heart_eyes:": "😍", ":kissing_heart:": "😘",
        ":thinking:": "🤔", ":neutral:": "😐", ":unamused:": "😒",
        ":sweat:": "😓", ":pensive:": "😔", ":confused:": "😕",
        ":cry:": "😢", ":sob:": "😭", ":angry:": "😠", ":rage:": "😡",
        ":scream:": "😱", ":fearful:": "😨", ":disappointed:": "😞",
        ":sleepy:": "😪", ":sleeping:": "😴", ":mask:": "😷",
        ":dizzy_face:": "😵", ":shush:": "🤫", ":hugs:": "🤗",
        ":smirk:": "😏", ":upside_down:": "🙃", ":money_mouth:": "🤑",
        ":nerd:": "🤓", ":star_struck:": "🤩", ":partying:": "🥳",
        ":pleading:": "🥺", ":melting:": "🫠", ":skull:": "💀",

        // Cử chỉ / bàn tay
        ":thumbsup:": "👍", ":+1:": "👍", ":thumbsdown:": "👎", ":-1:": "👎",
        ":ok_hand:": "👌", ":clap:": "👏", ":wave:": "👋", ":raised_hands:": "🙌",
        ":pray:": "🙏", ":muscle:": "💪", ":point_up:": "☝️",
        ":point_right:": "👉", ":point_left:": "👈", ":point_down:": "👇",
        ":fist:": "✊", ":punch:": "👊", ":v:": "✌️", ":metal:": "🤘",
        ":handshake:": "🤝", ":writing:": "✍️", ":folded_hands:": "🙏",

        // Trái tim / biểu tượng
        ":heart:": "❤️", ":orange_heart:": "🧡", ":yellow_heart:": "💛",
        ":green_heart:": "💚", ":blue_heart:": "💙", ":purple_heart:": "💜",
        ":black_heart:": "🖤", ":broken_heart:": "💔", ":sparkling_heart:": "💖",
        ":two_hearts:": "💕", ":fire:": "🔥", ":sparkles:": "✨", ":star:": "⭐",
        ":star2:": "🌟", ":boom:": "💥", ":zap:": "⚡", ":100:": "💯",
        ":tada:": "🎉", ":confetti:": "🎊", ":gift:": "🎁", ":balloon:": "🎈",
        ":check:": "✅", ":x:": "❌", ":warning:": "⚠️", ":question:": "❓",
        ":exclamation:": "❗", ":bulb:": "💡", ":bell:": "🔔",

        // Vật / hoạt động / đồ ăn
        ":rocket:": "🚀", ":coffee:": "☕", ":beer:": "🍺", ":pizza:": "🍕",
        ":cake:": "🎂", ":hamburger:": "🍔", ":sushi:": "🍣", ":rice:": "🍚",
        ":apple:": "🍎", ":banana:": "🍌", ":eyes:": "👀", ":brain:": "🧠",
        ":computer:": "💻", ":phone:": "📱", ":email:": "📧", ":calendar:": "📅",
        ":clock:": "🕐", ":hourglass:": "⏳", ":pushpin:": "📌", ":memo:": "📝",
        ":books:": "📚", ":bug:": "🐛", ":lock:": "🔒", ":key:": "🔑",
        ":link:": "🔗", ":mag:": "🔍", ":wrench:": "🔧", ":hammer:": "🔨",

        // Thiên nhiên / con vật
        ":sun:": "☀️", ":moon:": "🌙", ":rainbow:": "🌈", ":snowflake:": "❄️",
        ":cloud:": "☁️", ":umbrella:": "☔", ":dog:": "🐶", ":cat:": "🐱",
        ":mouse:": "🐭", ":rabbit:": "🐰", ":bear:": "🐻", ":panda:": "🐼",
        ":unicorn:": "🦄", ":dragon:": "🐉", ":butterfly:": "🦋",
        ":seedling:": "🌱", ":rose:": "🌹", ":sunflower:": "🌻", ":palm:": "🌴",

        // Ký hiệu tiện dụng khi gõ tiếng Việt
        ":vn:": "🇻🇳", ":flag_vn:": "🇻🇳", ":100point:": "💯",
    ]

    /// Bộ `MacroDefinition` tĩnh để nạp vào MacroStore. Tất cả là staticText.
    public static func definitions() -> [MacroDefinition] {
        table.map { MacroDefinition(keyword: $0.key, content: $0.value, type: .staticText) }
    }

    /// Ký tự có được phép nằm giữa hai dấu ':' của shortcode không.
    /// Cho chữ/số ASCII + '_', '+', '-' (khớp keyword như ":+1:", ":heart_eyes:").
    public static func isShortcodeChar(_ ch: Character) -> Bool {
        ch.isLetter || ch.isNumber || ch == "_" || ch == "+" || ch == "-"
    }
}

/// MÁY TRẠNG THÁI theo dõi shortcode `:code:` đang gõ dở, TÁCH khỏi tầng sự kiện
/// để test được. Chỉ giữ `buffer` (dấu ':' mở + phần code ĐÃ HIỂN THỊ). Bộ điều
/// khiển gọi các hàm dưới đây và tự lo đồng bộ màn hình (Backspace + gõ emoji).
///
/// Bất biến: `buffer.count` = số ký tự đang hiển thị kể từ dấu ':' mở, nên đó
/// chính là số Backspace cần khi bung emoji.
public struct EmojiShortcodeMatcher {
    /// Buffer hiện tại (rỗng = không có shortcode nào đang mở). Đọc để biết số
    /// Backspace khi bung.
    public private(set) var buffer = ""

    public init() {}

    /// Xoá trạng thái (gọi khi Backspace, ngắt từ, click chuột, đổi app…).
    public mutating func reset() { buffer = "" }

    /// Vừa gõ dấu ':'. Nếu nó ĐÓNG một shortcode hợp lệ -> trả emoji, số ký tự cần
    /// xoá, và `shortcode` GỐC (":code:" — để undo khôi phục lại); buffer reset. Nếu
    /// không -> mở buffer mới (":") và trả nil. Gọi cho MỌI dấu ':' (kể cả ':' đầu).
    public mutating func onColon() -> (emoji: String, deleteCount: Int, shortcode: String)? {
        if buffer.count >= 2, buffer.hasPrefix(":") {
            let shortcode = buffer + ":"
            if let emoji = EmojiShortcodes.table[shortcode] {
                let deleteCount = buffer.count
                buffer = ""
                return (emoji, deleteCount, shortcode)
            }
        }
        // Không khớp -> ':' này là dấu mở mới.
        buffer = ":"
        return nil
    }

    /// Vừa hiển thị một ký tự KHÔNG phải ':' (engine đã render). `renderedSelf` =
    /// engine gõ ra đúng 1 ký tự thô (không biến đổi tiếng Việt) hay không. Nếu
    /// đang mở buffer mà ký tự hợp lệ & không bị biến đổi -> nối; ngược lại huỷ.
    public mutating func onCharacter(_ ch: Character, renderedSelf: Bool) {
        guard !buffer.isEmpty else { return }
        if renderedSelf, EmojiShortcodes.isShortcodeChar(ch) {
            buffer.append(ch)
            if buffer.count > 32 { buffer = "" }   // chặn phình vô hạn
        } else {
            buffer = ""
        }
    }
}
