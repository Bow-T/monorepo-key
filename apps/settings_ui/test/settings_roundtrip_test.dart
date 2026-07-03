// Test round-trip JSON của BowSettings — nền tảng cho tính năng Sao lưu/Khôi phục:
// toJson() rồi fromJson() phải cho lại CÙNG cấu hình. Nếu một khoá bị bỏ sót ở
// một trong hai chiều, backup sẽ mất dữ liệu — test này bắt lỗi đó.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:bow_settings/src/models/settings.dart';

void main() {
  group('BowSettings round-trip', () {
    test('mặc định: toJson -> fromJson giữ nguyên', () {
      const original = BowSettings();
      final back = BowSettings.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );
      _expectEqual(back, original);
    });

    test('cấu hình đã tuỳ biến mọi trường: giữ nguyên qua round-trip', () {
      final original = const BowSettings().copyWith(
        enabled: false,
        method: InputMethod.vni,
        toneStyle: ToneStyle.old,
        launchAtLogin: false,
        smartSwitch: true,
        autoRestoreEnglish: true,
        autoCorrect: true,
        autoCorrectPairs: const [
          AutoCorrectPair(wrong: 'giừo', right: 'giờ'),
          AutoCorrectPair(wrong: 'nhièu', right: 'nhiều'),
        ],
        macroEnabled: false,
        macros: const [
          MacroEntry(keyword: 'vn', content: 'Việt Nam'),
          MacroEntry(keyword: 'td', content: 'dd/MM/yyyy', type: 'date'),
        ],
        clipboardHistoryEnabled: false,
        clipboardHistoryLimit: 80,
        screenshotEnabled: false,
        textTransformEnabled: false,
        emojiShortcutsEnabled: true,
        symbolPickerEnabled: false,
        undoExpansionEnabled: false,
        stickerPickerEnabled: false,
      );

      final back = BowSettings.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );
      _expectEqual(back, original);
    });

    test('perApp bị loại khi xuất (bộ nhớ riêng máy)', () {
      // Mô phỏng đúng cái _exportAllSettings làm: toJson()..remove('perApp').
      final json = const BowSettings().toJson()..remove('perApp');
      expect(json.containsKey('perApp'), isFalse);
      // Nhập lại không có perApp -> về map rỗng, không lỗi.
      final back = BowSettings.fromJson(json);
      expect(back.perApp, isEmpty);
    });
  });
}

/// So sánh hai BowSettings ở mức trường quan trọng (không có == tự sinh).
void _expectEqual(BowSettings a, BowSettings b) {
  expect(a.enabled, b.enabled);
  expect(a.method, b.method);
  expect(a.toneStyle, b.toneStyle);
  expect(a.hotkey.keyCode, b.hotkey.keyCode);
  expect(a.hotkey.modifiers, b.hotkey.modifiers);
  expect(a.launchAtLogin, b.launchAtLogin);
  expect(a.smartSwitch, b.smartSwitch);
  expect(a.autoRestoreEnglish, b.autoRestoreEnglish);
  expect(a.autoCorrect, b.autoCorrect);
  expect(a.autoCorrectPairs.length, b.autoCorrectPairs.length);
  for (var i = 0; i < a.autoCorrectPairs.length; i++) {
    expect(a.autoCorrectPairs[i].wrong, b.autoCorrectPairs[i].wrong);
    expect(a.autoCorrectPairs[i].right, b.autoCorrectPairs[i].right);
  }
  expect(a.macroEnabled, b.macroEnabled);
  expect(a.macros.length, b.macros.length);
  for (var i = 0; i < a.macros.length; i++) {
    expect(a.macros[i].keyword, b.macros[i].keyword);
    expect(a.macros[i].content, b.macros[i].content);
    expect(a.macros[i].type, b.macros[i].type);
  }
  expect(a.clipboardHistoryEnabled, b.clipboardHistoryEnabled);
  expect(a.clipboardHistoryLimit, b.clipboardHistoryLimit);
  expect(a.clipboardHistoryHotkey.keyCode, b.clipboardHistoryHotkey.keyCode);
  expect(a.screenshotEnabled, b.screenshotEnabled);
  expect(a.screenshotHotkey.keyCode, b.screenshotHotkey.keyCode);
  expect(a.textTransformEnabled, b.textTransformEnabled);
  expect(a.textTransformHotkey.keyCode, b.textTransformHotkey.keyCode);
  expect(a.emojiShortcutsEnabled, b.emojiShortcutsEnabled);
  expect(a.symbolPickerEnabled, b.symbolPickerEnabled);
  expect(a.symbolPickerHotkey.keyCode, b.symbolPickerHotkey.keyCode);
  expect(a.undoExpansionEnabled, b.undoExpansionEnabled);
  expect(a.stickerPickerEnabled, b.stickerPickerEnabled);
  expect(a.stickerPickerHotkey.keyCode, b.stickerPickerHotkey.keyCode);
}
