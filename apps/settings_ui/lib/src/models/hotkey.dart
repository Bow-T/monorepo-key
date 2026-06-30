// hotkey.dart
// -----------
// Mô hình phím tắt bật/tắt bộ gõ. Phải lưu dạng MÁY ĐỌC ĐƯỢC để bộ gõ Swift so
// khớp: keyCode vật lý macOS + tập modifier. Lớp này cũng lo việc:
//   - dịch phím Flutter (LogicalKeyboardKey) -> keyCode macOS,
//   - dựng chuỗi hiển thị (vd "⌃⌥ Space").
//
// keyCode ở đây là "macOS virtual keycode" (giống KeyCodeMap.swift), KHÔNG phải
// mã của Flutter. Đó là không gian mã mà cả hai phía thống nhất.

import 'package:flutter/services.dart';

/// Một modifier có thể gắn vào phím tắt.
enum HotkeyModifier {
  control('control', '⌃'),
  option('option', '⌥'),
  shift('shift', '⇧'),
  command('command', '⌘');

  const HotkeyModifier(this.json, this.symbol);
  final String json;
  final String symbol;

  static HotkeyModifier? fromJson(String v) {
    for (final m in HotkeyModifier.values) {
      if (m.json == v) return m;
    }
    return null;
  }
}

class Hotkey {
  const Hotkey({required this.keyCode, required this.modifiers});

  /// Mã phím vật lý macOS (vd Space = 49). 0 = chưa đặt phím chính.
  final int keyCode;

  /// Tập modifier yêu cầu.
  final Set<HotkeyModifier> modifiers;

  static const Hotkey defaultToggle = Hotkey(
    keyCode: 49, // Space
    modifiers: {HotkeyModifier.control, HotkeyModifier.option},
  );

  bool get isValid => keyCode != 0 && modifiers.isNotEmpty;

  /// Chuỗi hiển thị: ký hiệu modifier (đúng thứ tự ⌃⌥⇧⌘) + tên phím chính.
  String get display {
    const order = [
      HotkeyModifier.control,
      HotkeyModifier.option,
      HotkeyModifier.shift,
      HotkeyModifier.command,
    ];
    final mods = order.where(modifiers.contains).map((m) => m.symbol).join();
    final key = _keyName(keyCode);
    if (mods.isEmpty) return key;
    return '$mods $key';
  }

  // ── JSON (khớp BowConfig.decode phía Swift) ──────────────────────────────
  Map<String, dynamic> toJson() => {
        'hotkeyKeyCode': keyCode,
        'hotkeyModifiers': modifiers.map((m) => m.json).toList(),
        'toggleHotkey': display, // chuỗi hiển thị, để tiện debug/đọc file
      };

  factory Hotkey.fromJson(Map<String, dynamic> j) {
    final code = j['hotkeyKeyCode'];
    final mods = j['hotkeyModifiers'];
    if (code is! int || mods is! List) return defaultToggle;
    final set = mods
        .map((e) => HotkeyModifier.fromJson(e.toString()))
        .whereType<HotkeyModifier>()
        .toSet();
    final hk = Hotkey(keyCode: code, modifiers: set);
    return hk.isValid ? hk : defaultToggle;
  }

  // ── Bắt phím từ Flutter ──────────────────────────────────────────────────

  /// Dựng Hotkey từ một sự kiện phím Flutter (khi người dùng "thu" phím tắt).
  /// Trả null nếu phím chính chưa được hỗ trợ ánh xạ sang keyCode macOS.
  static Hotkey? fromKeyEvent(KeyEvent event) {
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;

    final mods = <HotkeyModifier>{};
    if (pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight)) {
      mods.add(HotkeyModifier.control);
    }
    if (pressed.contains(LogicalKeyboardKey.altLeft) ||
        pressed.contains(LogicalKeyboardKey.altRight)) {
      mods.add(HotkeyModifier.option);
    }
    if (pressed.contains(LogicalKeyboardKey.shiftLeft) ||
        pressed.contains(LogicalKeyboardKey.shiftRight)) {
      mods.add(HotkeyModifier.shift);
    }
    if (pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight)) {
      mods.add(HotkeyModifier.command);
    }

    final code = _macKeyCode(event.logicalKey);
    if (code == null) return null; // phím chính chưa hỗ trợ
    return Hotkey(keyCode: code, modifiers: mods);
  }

  /// Phím chính này có phải chỉ là một modifier không? (không tính là "phím chính")
  static bool isModifierKey(LogicalKeyboardKey key) {
    return {
      LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.controlRight,
      LogicalKeyboardKey.altLeft, LogicalKeyboardKey.altRight,
      LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.shiftRight,
      LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.metaRight,
    }.contains(key);
  }

  // ── Bảng ánh xạ LogicalKeyboardKey -> keyCode macOS ──────────────────────
  // Khớp KeyCodeMap.swift. Chỉ gồm phím hay dùng làm phím tắt.
  static int? _macKeyCode(LogicalKeyboardKey key) => _toMac[key.keyId];

  static String _keyName(int code) => _names[code] ?? 'Key#$code';

  static final Map<int, int> _toMac = {
    LogicalKeyboardKey.space.keyId: 49,
    LogicalKeyboardKey.keyA.keyId: 0,
    LogicalKeyboardKey.keyS.keyId: 1,
    LogicalKeyboardKey.keyD.keyId: 2,
    LogicalKeyboardKey.keyF.keyId: 3,
    LogicalKeyboardKey.keyH.keyId: 4,
    LogicalKeyboardKey.keyG.keyId: 5,
    LogicalKeyboardKey.keyZ.keyId: 6,
    LogicalKeyboardKey.keyX.keyId: 7,
    LogicalKeyboardKey.keyC.keyId: 8,
    LogicalKeyboardKey.keyV.keyId: 9,
    LogicalKeyboardKey.keyB.keyId: 11,
    LogicalKeyboardKey.keyQ.keyId: 12,
    LogicalKeyboardKey.keyW.keyId: 13,
    LogicalKeyboardKey.keyE.keyId: 14,
    LogicalKeyboardKey.keyR.keyId: 15,
    LogicalKeyboardKey.keyY.keyId: 16,
    LogicalKeyboardKey.keyT.keyId: 17,
    LogicalKeyboardKey.keyO.keyId: 31,
    LogicalKeyboardKey.keyU.keyId: 32,
    LogicalKeyboardKey.keyI.keyId: 34,
    LogicalKeyboardKey.keyP.keyId: 35,
    LogicalKeyboardKey.keyL.keyId: 37,
    LogicalKeyboardKey.keyJ.keyId: 38,
    LogicalKeyboardKey.keyK.keyId: 40,
    LogicalKeyboardKey.keyN.keyId: 45,
    LogicalKeyboardKey.keyM.keyId: 46,
    LogicalKeyboardKey.digit1.keyId: 18,
    LogicalKeyboardKey.digit2.keyId: 19,
    LogicalKeyboardKey.digit3.keyId: 20,
    LogicalKeyboardKey.digit4.keyId: 21,
    LogicalKeyboardKey.digit5.keyId: 23,
    LogicalKeyboardKey.digit6.keyId: 22,
    LogicalKeyboardKey.digit7.keyId: 26,
    LogicalKeyboardKey.digit8.keyId: 28,
    LogicalKeyboardKey.digit9.keyId: 25,
    LogicalKeyboardKey.digit0.keyId: 29,
  };

  // keyCode macOS -> tên hiển thị.
  static const Map<int, String> _names = {
    49: 'Space',
    0: 'A', 1: 'S', 2: 'D', 3: 'F', 4: 'H', 5: 'G', 6: 'Z', 7: 'X', 8: 'C',
    9: 'V', 11: 'B', 12: 'Q', 13: 'W', 14: 'E', 15: 'R', 16: 'Y', 17: 'T',
    31: 'O', 32: 'U', 34: 'I', 35: 'P', 37: 'L', 38: 'J', 40: 'K', 45: 'N',
    46: 'M',
    18: '1', 19: '2', 20: '3', 21: '4', 23: '5', 22: '6', 26: '7', 28: '8',
    25: '9', 29: '0',
  };
}
