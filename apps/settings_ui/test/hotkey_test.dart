// Test model Hotkey — đặc biệt phím tắt CHỈ-MODIFIER (vd Ctrl+Shift) và việc
// serialize/parse khớp contract JSON với Swift.

import 'package:flutter_test/flutter_test.dart';
import 'package:bow_settings/src/models/hotkey.dart';

void main() {
  group('Hotkey chỉ-modifier (Ctrl+Shift)', () {
    const ctrlShift = Hotkey(
      keyCode: 0,
      modifiers: {HotkeyModifier.control, HotkeyModifier.shift},
    );

    test('default là Ctrl+Shift chỉ-modifier', () {
      expect(Hotkey.defaultToggle.keyCode, 0);
      expect(Hotkey.defaultToggle.modifiers,
          {HotkeyModifier.control, HotkeyModifier.shift});
      expect(Hotkey.defaultToggle.isModifierOnly, isTrue);
    });

    test('hợp lệ khi có >=2 modifier; không hợp lệ nếu chỉ 1', () {
      expect(ctrlShift.isValid, isTrue);
      const onlyShift = Hotkey(keyCode: 0, modifiers: {HotkeyModifier.shift});
      expect(onlyShift.isValid, isFalse); // 1 modifier -> không nuốt nhầm
    });

    test('display chỉ hiện ký hiệu modifier (không phím chính)', () {
      expect(ctrlShift.display, '⌃⇧');
    });

    test('serialize/parse giữ nguyên (keyCode 0)', () {
      final json = ctrlShift.toJson();
      expect(json['hotkeyKeyCode'], 0);
      expect(json['hotkeyModifiers'], containsAll(['control', 'shift']));
      final parsed = Hotkey.fromJson(json);
      expect(parsed.keyCode, 0);
      expect(parsed.modifiers, ctrlShift.modifiers);
    });
  });

  group('Hotkey có phím chính (vẫn hoạt động)', () {
    const ctrlOptSpace = Hotkey(
      keyCode: 49,
      modifiers: {HotkeyModifier.control, HotkeyModifier.option},
    );

    test('hợp lệ với >=1 modifier + phím chính', () {
      expect(ctrlOptSpace.isValid, isTrue);
      expect(ctrlOptSpace.isModifierOnly, isFalse);
    });

    test('display gồm modifier + tên phím', () {
      expect(ctrlOptSpace.display, '⌃⌥ Space');
    });
  });
}
