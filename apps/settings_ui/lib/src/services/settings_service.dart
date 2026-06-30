// settings_service.dart
// ---------------------
// Đọc/ghi cấu hình bộ gõ ra ĐĨA, ở một vị trí mà app Swift macOS cũng đọc được:
//
//     ~/Library/Application Support/BowKey/settings.json
//
// Đây là "đường dây" thật giữa UI Flutter và bộ gõ Swift: UI ghi file, bộ gõ đọc
// file (và theo dõi thay đổi). Dùng Application Support vì cả hai tiến trình đều
// truy cập được mà không cần quyền đặc biệt.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/settings.dart';

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
    final dir = await getApplicationSupportDirectory();
    // getApplicationSupportDirectory() trả về .../Application Support/<bundleId>.
    // Ta cố định một thư mục "BowKey" dùng chung để Swift biết chỗ tìm.
    final shared = Directory('${dir.parent.path}/BowKey');
    if (!shared.existsSync()) {
      shared.createSync(recursive: true);
    }
    _file = File('${shared.path}/settings.json');

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

  /// Cập nhật một phần cấu hình rồi ghi xuống đĩa ngay (auto-save).
  Future<void> update(BowSettings next) async {
    _value = next;
    notifyListeners();
    await _write();
  }

  Future<void> _write() async {
    final f = _file;
    if (f == null) return;
    const encoder = JsonEncoder.withIndent('  ');
    await f.writeAsString(encoder.convert(_value.toJson()));
  }
}
