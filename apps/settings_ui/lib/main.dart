// main.dart
// ---------
// Điểm vào app cài đặt Bow Key (Flutter, macOS). Dựng theme pixel, nạp cấu hình
// từ đĩa rồi mở màn hình cài đặt.

import 'package:flutter/material.dart';

import 'src/pages/settings_page.dart';
import 'src/services/settings_service.dart';
import 'src/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsService.instance.load();
  runApp(const BowSettingsApp());
}

class BowSettingsApp extends StatefulWidget {
  const BowSettingsApp({super.key});

  @override
  State<BowSettingsApp> createState() => _BowSettingsAppState();
}

class _BowSettingsAppState extends State<BowSettingsApp> {
  ThemeMode _mode = ThemeMode.light;

  void _toggleTheme() {
    setState(() {
      _mode = _mode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bow Key — Cài đặt',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _mode,
      // Snap theme — không fade (đúng tinh thần pixel).
      themeAnimationDuration: const Duration(milliseconds: 1),
      home: SettingsPage(onToggleTheme: _toggleTheme),
    );
  }
}
