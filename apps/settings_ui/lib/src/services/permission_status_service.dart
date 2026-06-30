// permission_status_service.dart
// ------------------------------
// Đọc trạng thái quyền mà bộ gõ Swift ghi ra để UI hiển thị quyền nào đã/chưa cấp:
//
//     ~/Library/Application Support/BowGo/status.json
//     { "accessibility": Bool, "inputMonitoring": Bool, "ready": Bool }
//
// Bộ gõ Swift ghi file này lúc khởi động và trong health-check mỗi 5 giây
// (Permissions.writeStatus). UI poll định kỳ để phản ánh khi người dùng vừa bật
// quyền trong System Settings.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Ảnh chụp trạng thái quyền đọc từ status.json.
@immutable
class PermissionStatus {
  const PermissionStatus({
    required this.accessibility,
    required this.inputMonitoring,
    this.known = true,
  });

  /// Chưa đọc được file (bộ gõ chưa chạy lần nào) — trạng thái không xác định.
  const PermissionStatus.unknown()
      : accessibility = false,
        inputMonitoring = false,
        known = false;

  final bool accessibility;
  final bool inputMonitoring;

  /// false nếu chưa đọc được file status (bộ gõ chưa từng chạy).
  final bool known;

  bool get ready => accessibility && inputMonitoring;

  @override
  bool operator ==(Object other) =>
      other is PermissionStatus &&
      other.accessibility == accessibility &&
      other.inputMonitoring == inputMonitoring &&
      other.known == known;

  @override
  int get hashCode => Object.hash(accessibility, inputMonitoring, known);
}

class PermissionStatusService extends ChangeNotifier {
  PermissionStatusService._();
  static final PermissionStatusService instance = PermissionStatusService._();

  PermissionStatus _value = const PermissionStatus.unknown();
  PermissionStatus get value => _value;

  File? _file;
  Timer? _timer;

  /// Bắt đầu đọc + poll. Gọi một lần khi mở app.
  Future<void> start() async {
    final dir = await getApplicationSupportDirectory();
    // getApplicationSupportDirectory() trả .../Application Support/<bundleId>;
    // dùng chung thư mục "BowGo" như settings.json.
    _file = File('${dir.parent.path}/BowGo/status.json');
    await _read();
    // Poll mỗi 2s — đủ nhanh để phản ánh khi người dùng vừa bật quyền.
    _timer ??= Timer.periodic(const Duration(seconds: 2), (_) => _read());
  }

  /// Đọc lại ngay (gọi khi người dùng quay lại tab / bấm nút làm mới).
  Future<void> refresh() => _read();

  Future<void> _read() async {
    final f = _file;
    if (f == null || !f.existsSync()) return; // giữ "unknown" nếu chưa có file
    try {
      final raw = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final next = PermissionStatus(
        accessibility: raw['accessibility'] == true,
        inputMonitoring: raw['inputMonitoring'] == true,
      );
      if (next != _value) {
        _value = next;
        notifyListeners();
      }
    } catch (_) {
      // File đang ghi dở / hỏng -> bỏ qua, lần poll sau đọc lại.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
