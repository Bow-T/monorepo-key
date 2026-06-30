// widget_test.dart
// ----------------
// Smoke test: app cài đặt dựng được và hiển thị tiêu đề "BOW GO".

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bow_settings/src/pages/settings_page.dart';
import 'package:bow_settings/src/theme/app_theme.dart';

void main() {
  testWidgets('Màn hình cài đặt hiển thị tiêu đề Bow Go', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: SettingsPage(onToggleTheme: () {}),
      ),
    );

    expect(find.text('BOW GO'), findsOneWidget);
    expect(find.text('TELEX'), findsWidgets);
  });
}
