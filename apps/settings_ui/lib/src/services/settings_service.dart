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
//
// Bộ gõ Swift CŨNG ghi file này (bật/tắt bằng phím tắt hay menu, Smart Switch,
// gieo cặp tự-sửa…). Vì vậy UI:
//   • theo dõi file và nạp lại khi bộ gõ đổi nó (xem [reloadIfChanged]);
//   • khi ghi chỉ đè những khoá UI THỰC SỰ đổi, còn lại giữ bản trên đĩa (xem
//     [_merge]) — kể cả khoá UI không biết (vd fixBrowserDoubleType);
//   • ghi nguyên tử (file tạm + rename) và tuần tự, để bộ gõ không bao giờ đọc
//     trúng file ghi dở.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/settings.dart';
import 'bow_paths.dart';

class SettingsService extends ChangeNotifier {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  /// Bản riêng cho test (singleton dùng file thật trong thư mục BowGo).
  @visibleForTesting
  SettingsService.forTest();

  BowSettings _value = const BowSettings();
  BowSettings get value => _value;

  File? _file;

  /// JSON (đã chuẩn hoá qua model) của cấu hình tại lần đọc/ghi đĩa gần nhất. Dùng
  /// để phân biệt "UI vừa sửa khoá này" với "UI chưa đụng tới, bản trên đĩa mới
  /// hơn" -> KHÔNG đè mất thay đổi bộ gõ vừa ghi (vd ⌃⇧ tắt bộ gõ rồi UI lưu một
  /// cài đặt khác, `enabled` cũ không được bật ngược lại).
  Map<String, dynamic> _base = const {};

  /// Nội dung file lần gần nhất ta đọc/ghi — so với nó để biết bộ gõ vừa ghi.
  String? _lastContent;

  /// Các lần ghi xếp hàng nối tiếp (hai thao tác liên tiếp không ghi chồng nhau).
  Future<void> _writeQueue = Future.value();

  Timer? _pollTimer;

  /// Đường dẫn file cấu hình (hiển thị cho người dùng trong UI để minh bạch).
  String get path => _file?.path ?? '(chưa khởi tạo)';

  /// Khởi tạo: xác định đường dẫn, đọc file nếu đã có, rồi theo dõi thay đổi.
  Future<void> load() async {
    // Thư mục dùng chung theo nền tảng (macOS: Application Support/BowGo;
    // Windows: %APPDATA%\BowGo) — xem [BowPaths].
    await loadFrom(await BowPaths.sharedFile('settings.json'));
    _pollTimer ??= Timer.periodic(
      const Duration(milliseconds: 1500),
      (_) => reloadIfChanged(),
    );
  }

  @visibleForTesting
  Future<void> loadFrom(File file) async {
    _file = file;
    if (file.existsSync()) {
      _reloadFromDisk();
    } else {
      // Lần đầu: tạo file với mặc định để Swift có cái mà đọc.
      await _enqueueWrite();
    }
    _base = _value.toJson();
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
    await _enqueueWrite();
    if (onChanged != null) await onChanged!(_value);
  }

  /// Số lần ghi đang xếp hàng — còn lần ghi chờ thì KHÔNG nạp lại từ đĩa (nạp lúc
  /// đó sẽ đè thay đổi UI chưa kịp ghi).
  int _pendingWrites = 0;

  // Nuốt lỗi trong hàng đợi: một lần ghi hỏng không được làm "chết" mọi lần sau.
  Future<void> _enqueueWrite() {
    _pendingWrites++;
    return _writeQueue = _writeQueue
        .then((_) => _write())
        .catchError((Object e) => debugPrint('[Settings] Ghi settings.json lỗi: $e'))
        .whenComplete(() => _pendingWrites--);
  }

  /// Đọc file -> [_value]. Trả false nếu không đọc/parse được (giữ nguyên bộ nhớ).
  bool _reloadFromDisk() {
    try {
      final content = _file!.readAsStringSync();
      final raw = jsonDecode(content) as Map<String, dynamic>;
      _value = BowSettings.fromJson(raw);
      _base = _value.toJson();
      _lastContent = content;
      return true;
    } catch (_) {
      // File hỏng / đang ghi dở -> giữ bản trong bộ nhớ, lần sau thử lại.
      return false;
    }
  }

  /// Bộ gõ vừa ghi file (nội dung khác lần ta đọc/ghi cuối) -> nạp lại cho UI.
  /// Gọi định kỳ từ [load].
  Future<void> reloadIfChanged() async {
    final f = _file;
    if (f == null || !f.existsSync() || _pendingWrites > 0) return;
    final String content;
    try {
      content = f.readAsStringSync();
    } catch (_) {
      return;
    }
    if (content == _lastContent) return;
    if (!_reloadFromDisk()) return;
    notifyListeners();
    // Gọi từ Timer (không ai await) -> lỗi của hook (đăng ký phím tắt Windows…)
    // phải bắt tại đây, không thì thành lỗi async không ai xử lý.
    try {
      if (onChanged != null) await onChanged!(_value);
    } catch (e) {
      debugPrint('[Settings] Áp cấu hình mới lỗi: $e');
    }
  }

  /// Gộp bản bộ nhớ vào bản trên đĩa: bắt đầu từ ĐĨA (giữ cả khoá UI không biết),
  /// chỉ đè khoá mà UI đã đổi so với [_base] hoặc khoá đĩa chưa có.
  @visibleForTesting
  static Map<String, dynamic> merge({
    required Map<String, dynamic> disk,
    required Map<String, dynamic> mem,
    required Map<String, dynamic> base,
  }) {
    final out = Map<String, dynamic>.of(disk);
    mem.forEach((k, v) {
      // Bộ gõ chỉ gieo cặp tự-sửa MẶC ĐỊNH khi khoá vắng mặt — ghi [] lúc đĩa chưa
      // có khoá (app Cài đặt chạy trước bộ gõ) là người dùng mất luôn bộ mặc định.
      if (k == 'autoCorrectPairs' && !disk.containsKey(k) && v is List && v.isEmpty) {
        return;
      }
      final uiChanged = !_jsonEq(v, base[k]);
      if (uiChanged || !disk.containsKey(k)) out[k] = v;
    });
    return out;
  }

  Future<void> _write() async {
    final f = _file;
    if (f == null) return;

    final mem = _value.toJson();
    Map<String, dynamic> out;
    if (f.existsSync()) {
      try {
        final disk = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        out = merge(disk: disk, mem: mem, base: _base);
      } catch (_) {
        out = mem; // File hỏng -> ghi bản trong bộ nhớ (đã gồm thay đổi UI).
      }
    } else {
      out = mem;
      // Lần đầu: KHÔNG ghi danh sách tự-sửa rỗng — bộ gõ chỉ gieo bộ mặc định khi
      // khoá vắng mặt, ghi [] là người dùng mất luôn bộ mặc định.
      if (_value.autoCorrectPairs.isEmpty) out.remove('autoCorrectPairs');
    }

    const encoder = JsonEncoder.withIndent('  ');
    final content = encoder.convert(out);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(content, flush: true);
    // Windows: DLL bộ gõ mở file không kèm FILE_SHARE_DELETE -> rename trúng lúc nó
    // đang đọc sẽ lỗi sharing violation. Thử lại vài lần trước khi bỏ cuộc.
    for (var attempt = 1;; attempt++) {
      try {
        await tmp.rename(f.path);
        break;
      } on FileSystemException {
        if (attempt >= 5) {
          if (tmp.existsSync()) tmp.deleteSync();
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    _lastContent = content;

    // Bản vừa ghi có thể đã gộp thay đổi của bộ gõ -> UI phản ánh đúng đĩa. Nếu
    // người dùng vừa sửa thêm trong lúc đang ghi, giữ các sửa đó (so với `mem`).
    _base = BowSettings.fromJson(out).toJson();
    final latest = _value.toJson();
    final rebased = BowSettings.fromJson(merge(disk: out, mem: latest, base: mem));
    if (!_jsonEq(rebased.toJson(), latest)) {
      _value = rebased;
      notifyListeners();
    }
  }

  /// So sánh hai giá trị JSON qua chuỗi hoá — model không có operator == nên so
  /// bằng JSON là cách chắc chắn và đủ nhanh cho danh sách nhỏ.
  static bool _jsonEq(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);
}
