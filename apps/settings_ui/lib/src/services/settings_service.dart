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

  /// Ảnh chụp (JSON) các khoá mà tiến trình bộ gõ Swift CŨNG ghi, tại thời điểm
  /// đọc file gần nhất. Dùng để phân biệt "UI vừa sửa khoá này" với "UI chưa đụng
  /// tới, giá trị trên đĩa mới hơn". Nhờ vậy khi ghi đè, ta chỉ đè các khoá UI
  /// thực sự đổi, còn lại lấy bản mới nhất trên đĩa -> KHÔNG xoá dữ liệu (như
  /// autoCorrectPairs/macros do Swift seed hoặc bản UI khác vừa lưu). Xem [_write].
  Map<String, dynamic> _sharedSnapshot = const {};

  /// Các khoá do NHIỀU tiến trình cùng ghi (UI Flutter + bộ gõ Swift). Với những
  /// khoá này phải merge theo snapshot thay vì đè thẳng từ bộ nhớ.
  static const List<String> _sharedKeys = ['perApp', 'autoCorrectPairs', 'macros'];

  /// Trích các khoá dùng chung từ một map JSON (để so sánh/merge).
  Map<String, dynamic> _sharedFrom(Map<String, dynamic> json) => {
        for (final k in _sharedKeys)
          if (json.containsKey(k)) k: json[k],
      };

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
        _sharedSnapshot = _sharedFrom(raw); // ghi nhớ bản đĩa để merge khi ghi
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

    // Bắt đầu từ JSON của bản trong bộ nhớ (chứa các thay đổi UI vừa làm).
    final outJson = _value.toJson();

    // Các khoá dùng chung (perApp, autoCorrectPairs, macros) do bộ gõ Swift CŨNG
    // ghi và có thể đã đổi trên đĩa kể từ lần ta đọc. Nếu đè thẳng bản bộ nhớ
    // (có thể đang cũ/rỗng) sẽ XOÁ MẤT dữ liệu tiến trình kia vừa lưu — đây từng
    // là nguyên nhân mất hết autoCorrectPairs/macros. Nên với từng khoá dùng
    // chung: nếu UI KHÔNG đổi nó (giá trị bộ nhớ vẫn khớp snapshot lúc đọc) thì
    // GIỮ bản mới nhất trên đĩa; chỉ khi UI thực sự đổi mới đè bằng bản bộ nhớ.
    if (f.existsSync()) {
      try {
        final diskRaw = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        for (final k in _sharedKeys) {
          final memVal = outJson[k];
          final snapVal = _sharedSnapshot[k];
          final uiChanged = !_jsonEq(memVal, snapVal);
          if (!uiChanged && diskRaw.containsKey(k)) {
            outJson[k] = diskRaw[k]; // UI chưa đụng -> tôn trọng bản đĩa mới hơn
          }
        }
      } catch (_) {
        // File hỏng -> ghi bản trong bộ nhớ (đã gồm thay đổi UI).
      }
    }

    const encoder = JsonEncoder.withIndent('  ');
    await f.writeAsString(encoder.convert(outJson));
    // Cập nhật snapshot theo đúng nội dung vừa ghi để lần lưu kế tiếp so đúng.
    _sharedSnapshot = _sharedFrom(outJson);
  }

  /// So sánh hai giá trị JSON (khoá dùng chung) qua chuỗi hoá — model không có
  /// operator == nên so bằng JSON là cách chắc chắn và đủ nhanh cho danh sách nhỏ.
  bool _jsonEq(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);
}
