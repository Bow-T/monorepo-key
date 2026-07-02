// permission_status_service.dart
// ------------------------------
// Trạng thái quyền TCC (Accessibility / Input Monitoring) để UI hiển thị quyền
// nào đã/chưa cấp. Có HAI nguồn, theo thứ tự ưu tiên:
//
//   1. NGUỒN CHÍNH — kênh native `bowgo/permissions` (macOS). UI tự gọi thẳng
//      AXIsProcessTrusted / CGPreflightListenEventAccess trong tiến trình của
//      chính nó. Realtime, luôn đúng, không trễ.
//
//   2. DỰ PHÒNG — file do bộ gõ Swift ghi ngầm:
//        ~/Library/Application Support/BowGo/status.json
//        { "accessibility": Bool, "inputMonitoring": Bool, "ready": Bool }
//      Dùng khi native trả về lỗi/null. Trên Windows (không có kênh native lẫn
//      file) trạng thái là [PermissionStatus.unknown] và UI bỏ qua onboarding.
//
// Vì sao cần nguồn (1): status.json chỉ được ghi lại mỗi ~5s và có thể "đóng
// băng" ở trạng thái cũ đúng lúc bộ gõ relaunch để áp quyền mới, hoặc bị nhiều
// instance ghi đè nhau -> UI báo "chưa cấp" dù người dùng đã cấp xong.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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

  /// Kênh native để tự kiểm tra quyền TCC trong tiến trình app UI (macOS).
  /// Xem Runner/PermissionChannel.swift.
  static const _channel = MethodChannel('bowgo/permissions');

  PermissionStatus _value = const PermissionStatus.unknown();
  PermissionStatus get value => _value;

  File? _file;
  Timer? _timer;

  /// Bắt đầu đọc + poll. Gọi một lần khi mở app.
  ///
  /// Nguồn chính là kênh native (macOS); status.json chỉ là dự phòng. Trên
  /// Windows, TSF không cần cấp quyền kiểu TCC nên cả hai nguồn đều không có;
  /// khi đó trạng thái là [PermissionStatus.unknown] (known=false) và UI bỏ
  /// qua bước onboarding quyền.
  Future<void> start() async {
    // Dùng chung thư mục "BowGo" như settings.json (xem [BowPaths]).
    _file = await BowPaths.sharedFile('status.json');
    await _read();
    // Poll mỗi 1s — kiểm tra native rất rẻ (chỉ đọc TCC), phản ánh gần như tức
    // thì khi người dùng vừa bật quyền trong System Settings.
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => _read());
  }

  /// Đọc lại ngay (gọi khi người dùng quay lại app / bấm nút làm mới).
  Future<void> refresh() => _read();

  Future<void> _read() async {
    // 1) Nguồn chính: hỏi thẳng native. Luôn đúng & realtime.
    final native = await _readNative();
    if (native != null) {
      _apply(native);
      return;
    }
    // 2) Dự phòng: đọc status.json do bộ gõ Swift ghi.
    await _readStatusFile();
  }

  /// Hỏi kênh native. Trả null nếu không có kênh (Windows) hoặc gặp lỗi.
  Future<PermissionStatus?> _readNative() async {
    if (!Platform.isMacOS) return null;
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('check');
      if (raw == null) return null;
      return PermissionStatus(
        accessibility: raw['accessibility'] == true,
        inputMonitoring: raw['inputMonitoring'] == true,
        screenRecording: raw['screenRecording'] == true,
      );
    } catch (_) {
      // Kênh chưa đăng ký / bản build cũ -> để dự phòng status.json xử lý.
      return null;
    }
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
