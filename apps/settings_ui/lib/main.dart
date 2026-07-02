// main.dart
// ---------
// Điểm vào app cài đặt Bow Go (Flutter, macOS). Dựng theme pixel, nạp cấu hình
// từ đĩa rồi mở màn hình cài đặt.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'src/pages/onboarding_screen.dart';
import 'src/pages/settings_page.dart';
import 'src/services/permission_status_service.dart';
import 'src/services/settings_service.dart';
import 'src/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsService.instance.load();
  await PermissionStatusService.instance.start();
  runApp(const BowSettingsApp());
}

/// Cho phép cuộn bằng cả chuột/trackpad LẪN kéo-chuột-trái trên desktop.
/// Mặc định Flutter chỉ cuộn bằng trackpad trên macOS; thêm touch + mouse
/// để thanh công cụ (sidebar) và nội dung luôn kéo cuộn được.
class _DragScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

class BowSettingsApp extends StatefulWidget {
  const BowSettingsApp({super.key});

  @override
  State<BowSettingsApp> createState() => _BowSettingsAppState();
}

class _BowSettingsAppState extends State<BowSettingsApp> {
  ThemeMode _mode = ThemeMode.dark;

  /// Đã rời màn onboarding để vào app chưa (bấm "Bắt đầu" / "Để sau").
  bool _enteredApp = false;

  @override
  void initState() {
    super.initState();
    // Nếu mở app mà đã đủ quyền (hoặc chưa rõ trạng thái) thì vào thẳng settings.
    // Chỉ hiện onboarding khi BIẾT CHẮC còn thiếu quyền.
    final st = PermissionStatusService.instance.value;
    _enteredApp = !(st.known && !st.ready);
  }

  void _toggleTheme() {
    setState(() {
      _mode = _mode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bow Go — Cài đặt',
      debugShowCheckedModeBanner: false,
      scrollBehavior: _DragScrollBehavior(),
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _mode,
      // Snap theme — không fade (đúng tinh thần pixel).
      themeAnimationDuration: const Duration(milliseconds: 1),
      home: _enteredApp
          ? SettingsPage(onToggleTheme: _toggleTheme)
          : OnboardingScreen(
              onContinue: () => setState(() => _enteredApp = true),
            ),
    );
  }
}
