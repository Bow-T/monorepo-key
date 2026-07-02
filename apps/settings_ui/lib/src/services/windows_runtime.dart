// windows_runtime.dart
// --------------------
// "Tầng chạy nền" cho app đồng hành trên Windows — gộp những việc mà bộ gõ
// Swift làm trên macOS nhưng Windows cần app Flutter tự lo:
//   • Icon khay hệ thống (tray) với menu chuột phải.
//   • Ẩn cửa sổ xuống khay khi đóng (không thoát app).
//   • Phím tắt TOÀN CỤC: mở lịch sử clipboard, chụp màn hình.
//   • Chạy ClipboardHistoryService nền.
//
// ⚠️ CHỈ kích hoạt trên Windows. Trên macOS mọi thứ này do bộ gõ Swift đảm
// nhiệm, nên [maybeStart] thoát ngay nếu không phải Windows — an toàn để gọi
// vô điều kiện từ main().

import 'dart:io';

import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../models/hotkey.dart';
import 'clipboard_history_service.dart';
import 'screenshot_service.dart';
import 'settings_service.dart';

/// Điều hướng khi mở overlay clipboard / hiện cửa sổ chính — main() cung cấp.
typedef ShowOverlay = void Function();

class WindowsRuntime with TrayListener, WindowListener {
  WindowsRuntime._();
  static final WindowsRuntime instance = WindowsRuntime._();

  bool _started = false;
  ShowOverlay? _onShowClipboard;
  ShowOverlay? _onShowMainWindow;

  /// Gọi từ main() SAU runApp. No-op nếu không phải Windows.
  /// [onShowClipboard]: hiện overlay lịch sử clipboard.
  /// [onShowMainWindow]: đưa cửa sổ cài đặt trở lại (từ tray).
  Future<void> maybeStart({
    required ShowOverlay onShowClipboard,
    required ShowOverlay onShowMainWindow,
  }) async {
    if (!Platform.isWindows || _started) return;
    _started = true;
    _onShowClipboard = onShowClipboard;
    _onShowMainWindow = onShowMainWindow;

    // Đóng cửa sổ -> ẩn xuống khay thay vì thoát.
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);

    await _setupTray();
    trayManager.addListener(this);

    await _registerHotkeys();
    await _startClipboard();

    // Đổi cấu hình (bật/tắt, đổi phím tắt, đổi giới hạn) -> áp lại tức thì.
    SettingsService.instance.onChanged = (next) async {
      ClipboardHistoryService.instance.limit = next.clipboardHistoryLimit;
      if (next.clipboardHistoryEnabled) {
        await ClipboardHistoryService.instance
            .start(limit: next.clipboardHistoryLimit);
      } else {
        ClipboardHistoryService.instance.stop();
      }
      await reloadHotkeys();
    };
  }

  Future<void> _setupTray() async {
    // Icon khay: đặt file .ico kèm app (assets/tray/bowgo.ico). Nếu chưa có,
    // tray_manager vẫn tạo mục khay (icon rỗng) — không chặn luồng.
    try {
      await trayManager.setIcon('assets/tray/bowgo.ico');
    } catch (_) {/* thiếu icon -> bỏ qua */}
    await trayManager.setToolTip('Bow Go');
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'open', label: 'Mở cài đặt Bow Go'),
      MenuItem(key: 'clipboard', label: 'Lịch sử clipboard'),
      MenuItem(key: 'screenshot', label: 'Chụp màn hình'),
      MenuItem.separator(),
      MenuItem(key: 'exit', label: 'Thoát'),
    ]));
  }

  Future<void> _registerHotkeys() async {
    await hotKeyManager.unregisterAll();
    final s = SettingsService.instance.value;

    if (s.clipboardHistoryEnabled) {
      final hk = _toHotKey(s.clipboardHistoryHotkey);
      if (hk != null) {
        await hotKeyManager.register(hk,
            keyDownHandler: (_) => _onShowClipboard?.call());
      }
    }
    if (s.screenshotEnabled) {
      final hk = _toHotKey(s.screenshotHotkey);
      if (hk != null) {
        await hotKeyManager.register(hk,
            keyDownHandler: (_) => ScreenshotService.instance.captureRegion());
      }
    }
  }

  /// Đăng ký lại phím tắt khi người dùng đổi cấu hình (gọi từ SettingsService).
  Future<void> reloadHotkeys() async {
    if (!_started) return;
    await _registerHotkeys();
  }

  Future<void> _startClipboard() async {
    final s = SettingsService.instance.value;
    if (s.clipboardHistoryEnabled) {
      await ClipboardHistoryService.instance
          .start(limit: s.clipboardHistoryLimit);
    }
  }

  // ── Ánh xạ Hotkey (model) -> HotKey (plugin) ────────────────────────────────

  HotKey? _toHotKey(Hotkey hk) {
    // keyCode 0 = chỉ-modifier (⌃⇧ kiểu macOS) — hotkey_manager toàn cục cần
    // một phím THẬT, nên bỏ qua (giống giới hạn của preserved key bên TSF).
    final key = Hotkey.logicalFromMacKeyCode(hk.keyCode);
    if (key == null) return null;
    final mods = <HotKeyModifier>[
      if (hk.modifiers.contains(HotkeyModifier.control)) HotKeyModifier.control,
      if (hk.modifiers.contains(HotkeyModifier.shift)) HotKeyModifier.shift,
      if (hk.modifiers.contains(HotkeyModifier.option)) HotKeyModifier.alt,
      if (hk.modifiers.contains(HotkeyModifier.command)) HotKeyModifier.meta,
    ];
    if (mods.isEmpty) return null; // phím tắt toàn cục cần ít nhất 1 modifier
    return HotKey(key: key, modifiers: mods, scope: HotKeyScope.system);
  }

  // ── TrayListener ────────────────────────────────────────────────────────────

  @override
  void onTrayIconMouseDown() {
    _onShowMainWindow?.call();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'open':
        _onShowMainWindow?.call();
        break;
      case 'clipboard':
        _onShowClipboard?.call();
        break;
      case 'screenshot':
        ScreenshotService.instance.captureRegion();
        break;
      case 'exit':
        _quit();
        break;
    }
  }

  Future<void> _quit() async {
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  // ── WindowListener ──────────────────────────────────────────────────────────

  @override
  void onWindowClose() async {
    // Đóng -> ẩn xuống khay (giữ app chạy nền cho clipboard/hotkey).
    if (await windowManager.isPreventClose()) {
      await windowManager.hide();
      await windowManager.setSkipTaskbar(true);
    }
  }
}
