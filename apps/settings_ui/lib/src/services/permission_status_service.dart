// permission_status_service.dart
// ------------------------------
// Trạng thái quyền TCC (Accessibility / Input Monitoring) để UI hiển thị quyền
// nào đã/chưa cấp. Nguồn DUY NHẤT là file do bộ gõ Swift ghi:
//
//     ~/Library/Application Support/BowGo/status.json
//     { "accessibility": Bool, "inputMonitoring": Bool, "screenRecording": Bool, "ready": Bool }
//
// Vì sao KHÔNG để app Cài đặt tự kiểm tra quyền qua kênh native? Gọi
// AXIsProcessTrusted / CGPreflight* trong tiến trình app Cài đặt sẽ khiến macOS
// ĐĂNG KÝ app này vào danh sách quyền (Accessibility/Input Monitoring…) như một
// entry "Bow Go" THỪA — dù app Cài đặt không cần các quyền đó (chỉ BỘ GÕ cần).
// Vì vậy ta chỉ ĐỌC status.json. Bộ gõ ghi file này mỗi ~1s (và ngay khi trạng
// thái đổi), nên UI phản ánh gần như tức thì mà không chạm TCC API.
//
// Trên Windows (không có file) trạng thái là [PermissionStatus.unknown]
// (known=false) và UI bỏ qua bước onboarding quyền.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'bow_paths.dart';

/// Ảnh chụp trạng thái quyền đọc từ status.json.
@immutable
class PermissionStatus {
  const PermissionStatus({
    required this.accessibility,
    required this.inputMonitoring,
    this.screenRecording = false,
    this.known = true,
  });

  /// Chưa đọc được file (bộ gõ chưa chạy lần nào) — trạng thái không xác định.
  const PermissionStatus.unknown()
      : accessibility = false,
        inputMonitoring = false,
        screenRecording = false,
        known = false;

  final bool accessibility;
  final bool inputMonitoring;

  /// Ghi màn hình (Screen Recording) — chỉ cần cho tính năng chụp màn hình,
  /// KHÔNG tính vào [ready] của bộ gõ.
  final bool screenRecording;

  /// false nếu chưa đọc được file status (bộ gõ chưa từng chạy).
  final bool known;

  bool get ready => accessibility && inputMonitoring;

  @override
  bool operator ==(Object other) =>
      other is PermissionStatus &&
      other.accessibility == accessibility &&
      other.inputMonitoring == inputMonitoring &&
      other.screenRecording == screenRecording &&
      other.known == known;

  @override
  int get hashCode =>
      Object.hash(accessibility, inputMonitoring, screenRecording, known);
}

class PermissionStatusService extends ChangeNotifier {
  PermissionStatusService._();
  static final PermissionStatusService instance = PermissionStatusService._();

  PermissionStatus _value = const PermissionStatus.unknown();
  PermissionStatus get value => _value;

  File? _file;
  Timer? _timer;

  /// Bắt đầu đọc + poll. Gọi một lần khi mở app.
  ///
  /// Nguồn duy nhất là status.json do bộ gõ ghi (mỗi ~1s). Trên Windows, TSF
  /// không cần cấp quyền kiểu TCC nên không có file; khi đó trạng thái là
  /// [PermissionStatus.unknown] (known=false) và UI bỏ qua bước onboarding quyền.
  Future<void> start() async {
    // Dùng chung thư mục "BowGo" như settings.json (xem [BowPaths]).
    _file = await BowPaths.sharedFile('status.json');
    await _read();
    // Poll file mỗi 1s — bộ gõ cũng ghi mỗi ~1s nên độ trễ tối đa ~2s, đủ realtime
    // cho onboarding mà app Cài đặt KHÔNG phải chạm TCC API (tránh entry quyền thừa).
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => _read());
  }

  /// Đọc lại ngay (gọi khi người dùng quay lại app / bấm nút làm mới).
  Future<void> refresh() => _read();

  Future<void> _read() async {
    await _readStatusFile();
  }

  Future<void> _readStatusFile() async {
    final f = _file;
    if (f == null || !f.existsSync()) return; // giữ "unknown" nếu chưa có file
    try {
      final raw = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      _apply(PermissionStatus(
        accessibility: raw['accessibility'] == true,
        inputMonitoring: raw['inputMonitoring'] == true,
        screenRecording: raw['screenRecording'] == true,
      ));
    } catch (_) {
      // File đang ghi dở / hỏng -> bỏ qua, lần poll sau đọc lại.
    }
  }

  void _apply(PermissionStatus next) {
    if (next != _value) {
      _value = next;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
