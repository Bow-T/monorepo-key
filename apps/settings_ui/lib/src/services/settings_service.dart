// settings_service.dart
// ---------------------
// Đọc/ghi cấu hình bộ gõ ra ĐĨA, ở một vị trí mà bộ gõ nền tảng cũng đọc được:
//
//     macOS  : ~/Library/Application Support/BowGo/settings.json
//     Windows: %APPDATA%\BowGo\settings.json   (khớp text service TSF)
//
// Đây là "đường dây" thật giữa UI Flutter và bộ gõ (Swift trên macOS, DLL TSF
// trên Windows): UI ghi file, bộ gõ đọc file (và theo dõi thay đổi). Cả hai
// tiến trình đều truy cập được mà không cần quyền đặc biệt.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/settings.dart';
import 'bow_paths.dart';

class SettingsService extends ChangeNotifier {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  BowSettings _value = const BowSettings();
  BowSettings get value => _value;

  File? _file;

  /// Đường dẫn file cấu hình (hiển thị cho người dùng trong UI để minh bạch).
  String get path => _file?.path ?? '(chưa khởi tạo)';

  /// Khởi tạo: xác định đường dẫn, đọc file nếu đã có.
  Future<void> load() async {
    // Thư mục dùng chung theo nền tảng (macOS: Application Support/BowGo;
    // Windows: %APPDATA%\BowGo) — xem [BowPaths].
    _file = await BowPaths.sharedFile('settings.json');

    if (_file!.existsSync()) {
      try {
        final raw = jsonDecode(_file!.readAsStringSync()) as Map<String, dynamic>;
        _value = BowSettings.fromJson(raw);
      } catch (_) {
        // File hỏng -> giữ mặc định, sẽ ghi đè ở lần lưu sau.
      }
    } else {
      // Lần đầu: tạo file với mặc định để Swift có cái mà đọc.
      await _write();
    }
    notifyListeners();
  }

  /// Hook tuỳ chọn khi cấu hình đổi (ngoài notifyListeners) — dùng cho tầng
  /// chạy nền Windows đăng ký lại phím tắt toàn cục. Tránh import vòng: bên
  /// runtime tự gán callback này, service không biết về runtime.
  Future<void> Function(BowSettings next)? onChanged;

  /// Cập nhật một phần cấu hình rồi ghi xuống đĩa ngay (auto-save).
  Future<void> update(BowSettings next) async {
    _value = next;
    notifyListeners();
    await _write();
    if (onChanged != null) await onChanged!(next);
  }

  Future<void> _write() async {
    final f = _file;
    if (f == null) return;
    // `perApp` do bộ gõ Swift quản lý và có thể đã đổi trên đĩa kể từ lần đọc cuối.
    // Đọc lại bản mới nhất từ file để KHÔNG ghi đè mất bộ nhớ per-app của Swift.
    var out = _value;
    if (f.existsSync()) {
      try {
        final disk = BowSettings.fromJson(
          jsonDecode(f.readAsStringSync()) as Map<String, dynamic>,
        );
        out = _value.copyWith(perApp: disk.perApp);
      } catch (_) {
        // File hỏng -> ghi bản trong bộ nhớ.
      }
    }
    const encoder = JsonEncoder.withIndent('  ');
    await f.writeAsString(encoder.convert(out.toJson()));
  }
}
