// Test ô thu phím tắt: modifier đã nhả không được dính vào tổ hợp sau, phím A
// (keyCode 0 trùng mã "chỉ-modifier") bị từ chối, và tổ hợp chỉ-modifier chỉ
// nhận ở ô bật/tắt bộ gõ.

import 'package:bow_settings/src/models/hotkey.dart';
import 'package:bow_settings/src/theme/app_theme.dart';
import 'package:bow_settings/src/widgets/hotkey_recorder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<List<Hotkey>> pumpRecorder(WidgetTester tester, {bool allowModifierOnly = false}) async {
    final saved = <Hotkey>[];
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: HotkeyRecorder(
          hotkey: Hotkey.defaultToggle,
          allowModifierOnly: allowModifierOnly,
          onChanged: saved.add,
        ),
      ),
    ));
    await tester.tap(find.byType(HotkeyRecorder));
    await tester.pump();
    return saved;
  }

  testWidgets('chạm ⌘ rồi nhả, sau đó ⌃K -> lưu ⌃K (không dính ⌘)', (tester) async {
    final saved = await pumpRecorder(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(saved, hasLength(1));
    expect(saved.single.modifiers, {HotkeyModifier.control});
    expect(saved.single.keyCode, 40); // 'K'
  });

  testWidgets('⌃⇧A bị từ chối (keyCode 0 trùng mã chỉ-modifier)', (tester) async {
    final saved = await pumpRecorder(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(saved, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape); // thoát thu
  });

  Future<void> pressCtrlShift(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  }

  testWidgets('⌃⇧ chỉ-modifier bị bỏ qua ở ô phím tắt tính năng', (tester) async {
    final saved = await pumpRecorder(tester);
    await pressCtrlShift(tester);
    expect(saved, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape); // thoát thu
  });

  testWidgets('lỡ bấm phím chữ trước, rồi ⌃⇧ -> vẫn thu được chỉ-modifier', (tester) async {
    final saved = await pumpRecorder(tester, allowModifierOnly: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB); // không modifier -> bị bỏ qua
    await pressCtrlShift(tester);
    expect(saved, hasLength(1));
    expect(saved.single.isModifierOnly, isTrue);
  });

  testWidgets('để ô thu mở quá 60s -> tự huỷ thu', (tester) async {
    final saved = await pumpRecorder(tester);
    expect(find.text('GIỮ PHÍM…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 61));
    expect(find.text('GIỮ PHÍM…'), findsNothing);
    expect(saved, isEmpty);
  });

  testWidgets('⌃⇧ chỉ-modifier được nhận ở ô bật/tắt bộ gõ', (tester) async {
    final saved = await pumpRecorder(tester, allowModifierOnly: true);
    await pressCtrlShift(tester);
    expect(saved, hasLength(1));
    expect(saved.single.isModifierOnly, isTrue);
  });
}
