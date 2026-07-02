// screenshot_service.dart
// -----------------------
// Chụp màn hình (chọn vùng) cho tính năng đồng hành trên Windows — bản Flutter
// rút gọn của ScreenshotController.swift (macOS). Dùng plugin screen_capturer:
// chọn vùng -> lưu PNG vào thư mục dùng chung + copy vào clipboard.
//
// Ghi chú: bản macOS có thêm chú thích (vẽ/mũi tên/chữ) + OCR tiếng Việt. Bản
// Windows đầu tiên tập trung phần chụp + copy; chú thích/OCR để lộ trình sau
// (screen_capturer chỉ chụp, không kèm trình chú thích).

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:screen_capturer/screen_capturer.dart';

import 'bow_paths.dart';

class ScreenshotService {
  ScreenshotService._();
  static final ScreenshotService instance = ScreenshotService._();

  /// Chụp một vùng do người dùng chọn. Trả đường dẫn PNG đã lưu, hoặc null nếu
  /// huỷ/thất bại. Ảnh cũng được copy vào clipboard (copyToClipboard: true).
  Future<String?> captureRegion() async {
    if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) return null;
    final dir = await BowPaths.sharedDir();
    final name = 'shot_${DateTime.now().millisecondsSinceEpoch}.png';
    final path = '${dir.path}${Platform.pathSeparator}screenshots'
        '${Platform.pathSeparator}$name';
    // Bảo đảm thư mục con tồn tại.
    final shotsDir = Directory(
        '${dir.path}${Platform.pathSeparator}screenshots');
    if (!shotsDir.existsSync()) shotsDir.createSync(recursive: true);

    try {
      final CapturedData? data = await screenCapturer.capture(
        mode: CaptureMode.region,
        imagePath: path,
        copyToClipboard: true,
      );
      if (data == null) return null; // người dùng huỷ
      return File(path).existsSync() ? path : null;
    } catch (e) {
      debugPrint('Chụp màn hình thất bại: $e');
      return null;
    }
  }
}
