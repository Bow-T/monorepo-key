// KeyboardLayout.swift
// --------------------
// Dịch keyCode (mã phím vật lý) -> ký tự theo LAYOUT BÀN PHÍM THẬT của người dùng,
// bằng UCKeyTranslate (Carbon/HIToolbox). Nhờ vậy bộ gõ đúng cả với Dvorak,
// Colemak, AZERTY... chứ không cứng nhắc US QWERTY.
//
// Vì sao cần: keyCode chỉ là VỊ TRÍ phím vật lý (phím "ở chỗ chữ Q trên QWERTY").
// Người dùng Dvorak đặt layout khác -> cùng keyCode đó cho ra ký tự khác. Bảng tĩnh
// trong KeyCodeMap chỉ đúng cho QWERTY; UCKeyTranslate hỏi đúng layout hiện hành.
//
// Layout có thể đổi giữa chừng (đổi nguồn nhập). Ta cache layout hiện tại và làm mới
// khi nhận thông báo đổi nguồn nhập (kCFNotificationCenter...SelectedKeyboardInputSourceChanged).

import Carbon.HIToolbox
import Foundation

final class KeyboardLayout {

    /// Dữ liệu layout hiện hành ('uchr' của TIS). Cache lại, làm mới khi đổi nguồn.
    private var layoutData: Data?

    /// Trạng thái phím "dead key" giữa các lần gọi (vd '^' chờ nguyên âm). Bộ gõ
    /// tiếng Việt xử lý dấu riêng nên ta KHÔNG muốn macOS gộp dead key — reset mỗi lần.
    private var deadKeyState: UInt32 = 0

    init() {
        refresh()
        // Đăng ký nhận thông báo khi người dùng đổi nguồn nhập/layout.
        let center = CFNotificationCenterGetDistributedCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            center,
            observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let me = Unmanaged<KeyboardLayout>.fromOpaque(observer).takeUnretainedValue()
                me.refresh()
            },
            kTISNotifySelectedKeyboardInputSourceChanged,
            nil,
            .deliverImmediately
        )
    }

    deinit {
        let center = CFNotificationCenterGetDistributedCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterRemoveEveryObserver(center, observer)
    }

    /// Đọc lại layout hiện hành từ Text Input Source.
    func refresh() {
        // Ưu tiên layout đang dùng; nếu nguồn hiện tại không có 'uchr' (vd một số
        // IME), lùi về "keyboard layout input source" để vẫn có bảng phím vật lý.
        let source: TISInputSource? =
            TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
            ?? TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()

        guard let source,
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else {
            layoutData = nil
            return
        }
        let cfData = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue()
        layoutData = cfData as Data
    }

    /// Dịch keyCode -> Character theo layout thật. Trả nil nếu không ra ký tự dùng
    /// được cho bộ gõ (phím chức năng, hoặc layout không dịch được).
    ///
    /// `shift`: có giữ Shift không (để ra chữ hoa / ký tự trên).
    func character(for keyCode: Int64, shift: Bool) -> Character? {
        guard let layoutData else { return nil }

        var result: Character?
        layoutData.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)

            // Cờ modifier cho UCKeyTranslate: chỉ quan tâm Shift (bộ gõ đã loại
            // Cmd/Ctrl/Option ở tầng trên). Định dạng: (modifierKeyState >> 8) & 0xFF.
            let modifierKeyState: UInt32 = shift ? UInt32(shiftKey >> 8) : 0

            var chars = [UniChar](repeating: 0, count: 4)
            var realLength = 0
            var dead: UInt32 = 0

            let status = UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDown),
                modifierKeyState,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), // không gộp dead key
                &dead,
                chars.count,
                &realLength,
                &chars
            )

            guard status == noErr, realLength > 0 else { return }
            let s = String(utf16CodeUnits: chars, count: realLength)
            // Chỉ nhận đúng 1 ký tự "in được" (chữ/số/ký tự cơ bản). Loại điều khiển.
            guard s.count == 1, let c = s.first, !c.isWhitespace,
                  !c.unicodeScalars.contains(where: { $0.value < 0x20 })
            else { return }
            result = c
        }
        return result
    }
}
