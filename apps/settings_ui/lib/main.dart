// main.dart
// ---------
// Điểm vào app cài đặt Bow Go (Flutter). Dựng theme pixel, nạp cấu hình từ đĩa
// rồi mở màn hình cài đặt.
//
// Trên WINDOWS, app còn kiêm "app đồng hành": chạy nền dưới khay hệ thống, giữ
// phím tắt toàn cục (mở lịch sử clipboard / chụp màn hình) — những việc mà bộ
// gõ Swift làm trên macOS. Xem [WindowsRuntime].

import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'src/pages/clipboard_history_overlay.dart';
import 'src/pages/onboarding_screen.dart';
import 'src/pages/settings_page.dart';
import 'src/services/permission_status_service.dart';
import 'src/services/settings_service.dart';
import 'src/services/windows_runtime.dart';
import 'src/theme/app_theme.dart';

/// Khoá điều hướng toàn cục — để WindowsRuntime (ngoài cây widget) mở overlay
/// clipboard / đưa cửa sổ chính lên mà không cần BuildContext.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Windows: khởi tạo window_manager trước khi hiện cửa sổ (để ẩn-xuống-khay).
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(920, 640),
      center: true,
      title: 'Bow Go — Cài đặt',
    );
    unawaited(windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    }));
  }

  await SettingsService.instance.load();
  await PermissionStatusService.instance.start();
  runApp(const BowSettingsApp());

  // Windows: bật app đồng hành (tray + hotkey + clipboard nền). No-op nơi khác.
  await WindowsRuntime.instance.maybeStart(
    onShowClipboard: _showClipboardOverlay,
    onShowMainWindow: _showMainWindow,
  );
}

/// Đưa cửa sổ chính trở lại (từ tray / bấm icon khay).
Future<void> _showMainWindow() async {
  if (!Platform.isWindows) return;
  await windowManager.setSkipTaskbar(false);
  await windowManager.show();
  await windowManager.focus();
}

/// Hiện overlay lịch sử clipboard (đẩy một route toàn màn hình lên trên).
void _showClipboardOverlay() {
  final nav = rootNavigatorKey.currentState;
  if (nav == null) return;
  _showMainWindow();
  nav.push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => ClipboardHistoryOverlay(onClose: () => nav.maybePop()),
  ));
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

class _BowSettingsAppState extends State<BowSettingsApp>
    with WidgetsBindingObserver {
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
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Người dùng thường bật quyền trong System Settings rồi Alt-Tab về app này.
    // Ngay khi app được focus lại, kiểm tra quyền tức thì — không đợi vòng poll —
    // để dòng trạng thái đổi sang ✓ ngay, không còn cảm giác "cấp xong mà chưa
    // hiện".
    if (state == AppLifecycleState.resumed) {
      PermissionStatusService.instance.refresh();
    }
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
      navigatorKey: rootNavigatorKey,
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
