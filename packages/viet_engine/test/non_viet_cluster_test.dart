// non_viet_cluster_test.dart
// Regression: âm tiết mở đầu bằng tổ hợp phụ âm phi-Việt (cl/str/pr...) -> engine
// KHÔNG áp dấu, giữ nguyên phím thô. Tránh phá lệnh terminal & từ tiếng Anh.
// Port 1:1 từ apps/macos_ime/Tests/VietEngineTests/NonVietClusterTests.swift.

import 'package:test/test.dart';
import 'package:viet_engine/viet_engine.dart';

String render(String keys, [InputMethod method = InputMethod.telex]) {
  final e = VietEngine(method: method);
  var out = '';
  for (final ch in keys.split('')) {
    out = e.process(ch) ?? out;
  }
  return out;
}

void main() {
  group('Tổ hợp phụ âm đầu phi-Việt (terminal/English)', () {
    test('lệnh terminal & từ Anh có cụm phụ âm phi-Việt giữ nguyên (Telex)', () {
      for (final w in ['clear', 'printf', 'strings', 'brew', 'drop', 'flag', 'scp',
          'blur', 'split', 'class', 'free', 'frooch']) {
        expect(render(w), w);
      }
    });

    test('áp cả cho VNI (số không thành dấu sau cụm phi-Việt)', () {
      expect(render('st1', InputMethod.vni), 'st1');
    });

    test("KHÔNG chặn gõ tắt 'w' (sw->sư, tw->tư) dù chứa w", () {
      expect(render('tw'), 'tư');
      expect(render('sw'), 'sư');
    });

    test('KHÔNG đụng từ tiếng Việt hợp lệ', () {
      expect(render('tieengs'), 'tiếng');
      expect(render('ddaays'), 'đấy');
      expect(render('nuowngs'), 'nướng');
      expect(render('cuar'), 'của');
      expect(render('tooi'), 'tôi');
      // 'tr' là phụ âm đầu Việt hợp lệ -> 'trees' vẫn được áp dấu.
      expect(render('trees'), isNot('trees'));
    });

    test('dd -> đ KHÔNG bị chặn (không phải cụm phi-Việt)', () {
      expect(render('dd'), 'đ');
      expect(render('ddi'), 'đi');
    });
  });
}
