// Test chặn gán phím tắt trùng: tổ hợp đã thuộc tính năng ĐANG BẬT khác thì không
// lưu và báo lỗi; tính năng đang tắt không giữ chỗ.

import 'package:bow_settings/src/models/settings.dart';
import 'package:bow_settings/src/pages/settings_page.dart';
import 'package:bow_settings/src/services/settings_service.dart';
import 'package:bow_settings/src/theme/app_theme.dart';
import 'package:bow_settings/src/widgets/hotkey_recorder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const s = BowSettings();

  group('hotkeyConflict', () {
    test('⌃⇧K cho clipboard trùng bảng ký tự (đang bật)', () {
      expect(hotkeyConflict(s, 'lịch sử clipboard', Hotkey.defaultSymbolPicker), 'bảng ký tự');
    });

    test('gán lại đúng phím của chính tính năng đó: không tính là trùng', () {
      expect(hotkeyConflict(s, 'bảng ký tự', Hotkey.defaultSymbolPicker), isNull);
    });

    test('tính năng đang tắt không giữ chỗ (AI tắt sẵn giữ ⌃⇧G)', () {
      expect(s.aiEnabled, isFalse);
      expect(hotkeyConflict(s, 'lịch sử clipboard', Hotkey.defaultAI), isNull);
      expect(
        hotkeyConflict(s.copyWith(aiEnabled: true), 'lịch sử clipboard', Hotkey.defaultAI),
        'trợ lý AI',
      );
    });

    test('cùng phím chính nhưng khác tập modifier: không trùng', () {
      const ctrlOnlyK = Hotkey(keyCode: 40, modifiers: {HotkeyModifier.control});
      expect(hotkeyConflict(s, 'lịch sử clipboard', ctrlOnlyK), isNull);
    });

    test('phím bật/tắt bộ gõ luôn giữ chỗ', () {
      expect(hotkeyConflict(s, 'chụp màn hình', Hotkey.defaultToggle), 'bật/tắt bộ gõ');
    });
  });

  testWidgets('màn Cài đặt: thu ⌃⇧K cho clipboard -> báo trùng, KHÔNG lưu', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final before = SettingsService.instance.value.clipboardHistoryHotkey;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: SettingsPage(onToggleTheme: () {}),
    ));
    await tester.tap(find.text('PHÍM TẮT'));
    await tester.pump(const Duration(milliseconds: 500)); // trang có animation lặp

    final recorder = find.descendant(
      of: find.ancestor(of: find.text('PHÍM TẮT CLIPBOARD'), matching: find.byType(Row)).first,
      matching: find.byType(HotkeyRecorder),
    );
    await tester.ensureVisible(recorder);
    await tester.tap(recorder);
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(find.textContaining('đã dùng cho bảng ký tự'), findsOneWidget);
    final after = SettingsService.instance.value.clipboardHistoryHotkey;
    expect(after.keyCode, before.keyCode);
    expect(after.modifiers, before.modifiers);
    await tester.pump(const Duration(seconds: 5)); // cho snackbar hết hạn
  });
}
