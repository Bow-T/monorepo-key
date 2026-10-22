// hotkey_recording_lock.dart
// --------------------------
// Cờ "đang thu phím tắt" chia sẻ với bộ gõ (tiến trình khác).
//
// Bộ gõ macOS cài một CGEvent tap toàn cục và NUỐT mọi tổ hợp đã gán (⌃⇧ bật/tắt
// bộ gõ, ⌃⇧K bảng ký hiệu, ⌃⇧S chụp màn hình…). Vì app Cài đặt là tiến trình
// RIÊNG, khi người dùng thu phím tắt thì tap ăn tổ hợp trước, ô thu không bao giờ
// nhận được -> chỉ đặt được những tổ hợp còn TRỐNG (vd ⌥⇧).
//
// Cách gỡ: trong lúc ô thu mở, tạo file cờ ở thư mục dùng chung; bộ gõ thấy cờ
// (và cửa sổ Cài đặt đang focus) thì nhả tay, cho mọi phím đi qua. Thu xong xoá.
// Bộ gõ cũng bỏ qua cờ quá cũ (>2 phút) phòng khi app Cài đặt tắt đột ngột.

import 'bow_paths.dart';

class HotkeyRecordingLock {
  const HotkeyRecordingLock._();

  static const String _fileName = 'hotkey_recording.lock';

  /// Hàng đợi tuần tự: bấm thu rồi huỷ thật nhanh thì `release` phải chạy SAU
  /// `acquire` — nếu không, xoá chạy trước khi file kịp tạo và cờ bị bỏ lại,
  /// bộ gõ nhả mọi phím trong cửa sổ Cài đặt suốt 2 phút.
  static Future<void> _queue = Future.value();

  /// Số ô thu đang mở. Bấm sang ô B khi ô A đang thu thì B acquire có thể tới
  /// TRƯỚC A release — đếm để chỉ xoá file khi không còn ô nào thu.
  static int _holders = 0;

  /// Bật cờ (ghi lại mốc thời gian — bộ gõ đọc mtime của file).
  static Future<void> acquire() {
    _holders++;
    return _queue = _queue.then((_) => _acquire());
  }

  /// Tắt cờ (khi ô thu cuối cùng đóng).
  static Future<void> release() {
    if (_holders > 0) _holders--;
    if (_holders > 0) return _queue;
    return _queue = _queue.then((_) => _release());
  }

  static Future<void> _acquire() async {
    try {
      final f = await BowPaths.sharedFile(_fileName);
      await f.writeAsString(DateTime.now().toIso8601String(), flush: true);
    } catch (_) {
      // Không ghi được cờ -> chỉ mất tiện ích thu tổ hợp đã gán, không hỏng gì.
    }
  }

  static Future<void> _release() async {
    try {
      final f = await BowPaths.sharedFile(_fileName);
      if (f.existsSync()) await f.delete();
    } catch (_) {
      // Bộ gõ tự bỏ qua cờ quá hạn nên xoá hụt cũng không kẹt phím tắt.
    }
  }
}
