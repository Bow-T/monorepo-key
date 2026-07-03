// Test parse TypingStats từ stats.json (contract với Swift) + tính vietRatio.

import 'package:flutter_test/flutter_test.dart';
import 'package:bow_settings/src/services/stats_service.dart';

void main() {
  group('TypingStats (UI) parse', () {
    test('fromJson đọc đủ trường', () {
      final s = TypingStats.fromJson({
        'keystrokes': 1200,
        'vietWords': 340,
        'charsSaved': 56,
        'vietKeystrokes': 900,
        'engKeystrokes': 300,
        'streak': 5,
        'lastActiveDay': '2026-07-03',
        'wordsToday': 42,
      });
      expect(s.keystrokes, 1200);
      expect(s.vietWords, 340);
      expect(s.charsSaved, 56);
      expect(s.streak, 5);
      expect(s.lastActiveDay, '2026-07-03');
      expect(s.wordsToday, 42);
      expect(s.known, isTrue);
    });

    test('vietRatio = vietKeystrokes / tổng', () {
      final s = TypingStats.fromJson({
        'vietKeystrokes': 900,
        'engKeystrokes': 100,
      });
      expect(s.vietRatio, closeTo(0.9, 1e-9));
    });

    test('vietRatio = 0 khi chưa có phím', () {
      expect(const TypingStats().vietRatio, 0);
    });

    test('khoá thiếu -> mặc định 0/rỗng, không lỗi', () {
      final s = TypingStats.fromJson({});
      expect(s.keystrokes, 0);
      expect(s.lastActiveDay, '');
      expect(s.streak, 0);
    });

    test('unknown khác với bản đã đọc (known=false)', () {
      expect(const TypingStats.unknown().known, isFalse);
      expect(const TypingStats().known, isTrue);
    });
  });
}
