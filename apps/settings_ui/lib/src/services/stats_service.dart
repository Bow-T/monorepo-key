// stats_service.dart
// ------------------
// Đọc thống kê gõ do bộ gõ (Swift/C++) ghi ra:
//     ~/Library/Application Support/BowGo/stats.json   (Windows: %APPDATA%\BowGo\)
// UI chỉ ĐỌC (bộ gõ làm chủ việc ghi). Poll định kỳ để cập nhật khi đang mở tab.
//
// stats.json (khớp TypingStats bên Swift):
//   { keystrokes, vietWords, charsSaved, vietKeystrokes, engKeystrokes,
//     streak, lastActiveDay, wordsToday }

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'bow_paths.dart';

/// Ảnh chụp thống kê gõ đọc từ stats.json.
@immutable
class TypingStats {
  const TypingStats({
    this.keystrokes = 0,
    this.vietWords = 0,
    this.charsSaved = 0,
    this.vietKeystrokes = 0,
    this.engKeystrokes = 0,
    this.streak = 0,
    this.lastActiveDay = '',
    this.wordsToday = 0,
    this.known = true,
  });

  /// Chưa đọc được file (bộ gõ chưa chạy lần nào).
  const TypingStats.unknown()
      : keystrokes = 0,
        vietWords = 0,
        charsSaved = 0,
        vietKeystrokes = 0,
        engKeystrokes = 0,
        streak = 0,
        lastActiveDay = '',
        wordsToday = 0,
        known = false;

  final int keystrokes;
  final int vietWords;
  final int charsSaved;
  final int vietKeystrokes;
  final int engKeystrokes;
  final int streak;
  final String lastActiveDay;
  final int wordsToday;
  final bool known;

  /// Tỉ lệ phím gõ tiếng Việt / tổng phím có phân loại (0…1).
  double get vietRatio {
    final total = vietKeystrokes + engKeystrokes;
    return total == 0 ? 0 : vietKeystrokes / total;
  }

  factory TypingStats.fromJson(Map<String, dynamic> j) => TypingStats(
        keystrokes: (j['keystrokes'] as num?)?.toInt() ?? 0,
        vietWords: (j['vietWords'] as num?)?.toInt() ?? 0,
        charsSaved: (j['charsSaved'] as num?)?.toInt() ?? 0,
        vietKeystrokes: (j['vietKeystrokes'] as num?)?.toInt() ?? 0,
        engKeystrokes: (j['engKeystrokes'] as num?)?.toInt() ?? 0,
        streak: (j['streak'] as num?)?.toInt() ?? 0,
        lastActiveDay: (j['lastActiveDay'] as String?) ?? '',
        wordsToday: (j['wordsToday'] as num?)?.toInt() ?? 0,
      );

  @override
  bool operator ==(Object other) =>
      other is TypingStats &&
      other.keystrokes == keystrokes &&
      other.vietWords == vietWords &&
      other.charsSaved == charsSaved &&
      other.vietKeystrokes == vietKeystrokes &&
      other.engKeystrokes == engKeystrokes &&
      other.streak == streak &&
      other.lastActiveDay == lastActiveDay &&
      other.wordsToday == wordsToday &&
      other.known == known;

  @override
  int get hashCode => Object.hash(keystrokes, vietWords, charsSaved,
      vietKeystrokes, engKeystrokes, streak, lastActiveDay, wordsToday, known);
}

class StatsService extends ChangeNotifier {
  StatsService._();
  static final StatsService instance = StatsService._();

  TypingStats _value = const TypingStats.unknown();
  TypingStats get value => _value;

  File? _file;
  Timer? _timer;

  /// Bắt đầu đọc + poll. Gọi một lần khi mở app.
  Future<void> start() async {
    _file = await BowPaths.sharedFile('stats.json');
    await _read();
    // Bộ gõ flush mỗi ~5s; poll 3s là đủ mượt mà không tốn kém.
    _timer ??= Timer.periodic(const Duration(seconds: 3), (_) => _read());
  }

  /// Đọc lại ngay (gọi khi mở tab Thống kê / bấm làm mới).
  Future<void> refresh() => _read();

  Future<void> _read() async {
    final f = _file;
    if (f == null || !f.existsSync()) return; // giữ "unknown" nếu chưa có file
    try {
      final raw = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      _apply(TypingStats.fromJson(raw));
    } catch (_) {
      // File đang ghi dở / hỏng -> bỏ qua, lần poll sau đọc lại.
    }
  }

  void _apply(TypingStats next) {
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
