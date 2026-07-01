// auto_correct_test.dart
// Kiểm tra tự-sửa-lỗi gõ nhanh: lớp dời-dấu-thanh, lớp từ điển, an toàn,
// và tích hợp với engine khi chốt từ (port từ Swift AutoCorrectTests).

import 'package:test/test.dart';
import 'package:viet_engine/viet_engine.dart';

/// Gõ `keys` qua engine, khi gặp ký tự ngắt từ thì thử tự-sửa âm tiết vừa gõ.
/// Trả về văn bản cuối cùng caller thấy (mô phỏng caller: hiển thị âm tiết đang
/// gõ, hoặc khi chốt từ thì xoá âm tiết và chèn từ đã sửa + ký tự ngắt).
String _typeAC(String keys, {InputMethod method = InputMethod.telex}) {
  final engine = VietEngine(method: method, autoCorrect: true);
  var visible = '';
  var currentSyllable = '';
  for (final ch in keys.split('')) {
    final result = engine.process(ch);
    if (result != null) {
      // Âm tiết đang gõ: thay phần hiển thị của âm tiết bằng chuỗi mới.
      visible = visible.substring(0, visible.length - currentSyllable.length);
      visible += result;
      currentSyllable = result;
    } else {
      // Ngắt từ: chốt âm tiết. Thử tự-sửa từ vừa gõ xong.
      final correction = AutoCorrect.correctWord(currentSyllable);
      if (correction != null) {
        visible = visible.substring(0, visible.length - currentSyllable.length);
        visible += correction.corrected;
      }
      visible += ch;
      currentSyllable = '';
    }
  }
  return visible;
}

void main() {
  group('Auto-correct: dời dấu thanh (lớp 1)', () {
    test('Dấu đặt sai vị trí trong cụm nguyên âm -> dời đúng', () {
      // "hòa" (dấu ở 'o') là chính tả CŨ. Ở chế độ modern, dấu đúng lên 'a' -> "hoà".
      expect(AutoCorrect.repositionTone('hòa'), 'hoà');
      // "qúy" -> "quý" (dấu lên 'y')
      expect(AutoCorrect.repositionTone('qúy'), 'quý');
      // "khỏe" -> "khoẻ"
      expect(AutoCorrect.repositionTone('khỏe'), 'khoẻ');
    });

    test('Từ đã đúng vị trí -> không đổi', () {
      expect(AutoCorrect.repositionTone('tiếng'), 'tiếng'); // dấu đã ở 'ê'
      expect(AutoCorrect.repositionTone('giờ'), 'giờ'); // dấu đã ở 'ơ'
      expect(AutoCorrect.repositionTone('hoà'), 'hoà');
    });

    test('Không có dấu thanh -> null', () {
      expect(AutoCorrect.repositionTone('hoa'), isNull);
      expect(AutoCorrect.repositionTone('tieng'), isNull);
    });
  });

  group('Auto-correct: từ điển (lớp 2)', () {
    final dict = AutoCorrectDictionary.shared;

    test('Các lỗi override kinh điển', () {
      expect(dict.lookup('giừo'), 'giờ');
      expect(dict.lookup('nhièu'), 'nhiều');
      expect(dict.lookup('ngừoi'), 'người');
      expect(dict.lookup('đựoc'), 'được');
    });

    test('Biến thể-lỗi tự sinh: dấu rơi nhầm nguyên âm', () {
      // "nhiều" đúng ở 'ê'. Biến thể dấu ở 'e' cuối "nhiêù" -> phải map về "nhiều".
      expect(dict.lookup('nhiêù'), 'nhiều');
    });

    test('Từ đúng KHÔNG bị "sửa" (an toàn)', () {
      expect(dict.lookup('giờ'), isNull);
      expect(dict.lookup('nhiều'), isNull);
      expect(dict.lookup('người'), isNull);
      expect(dict.lookup('được'), isNull);
    });

    test('Giữ kiểu hoa của chữ đầu', () {
      expect(dict.lookup('Giừo'), 'Giờ');
      expect(dict.lookup('Nhièu'), 'Nhiều');
    });
  });

  group('Auto-correct: an toàn', () {
    test('Từ thuần ASCII / tiếng Anh -> KHÔNG đụng', () {
      expect(AutoCorrect.correctWord('hello'), isNull);
      expect(AutoCorrect.correctWord('the'), isNull);
      expect(AutoCorrect.correctWord('Github'), isNull);
    });

    test('Từ ASCII chứa nguyên âm thường (a/e/o/u/i/y) -> KHÔNG đụng', () {
      // Nguyên âm thường có trong bảng ngược nhưng KHÔNG mang dấu -> không tính
      // là "có dấu tiếng Việt", nên guard an toàn phải bỏ qua.
      expect(AutoCorrect.correctWord('bay'), isNull);
      expect(AutoCorrect.correctWord('cay'), isNull);
      expect(AutoCorrect.correctWord('hello'), isNull);
    });

    test('Từ tiếng Việt đúng -> KHÔNG đụng', () {
      expect(AutoCorrect.correctWord('tiếng'), isNull);
      expect(AutoCorrect.correctWord('giờ'), isNull);
      expect(AutoCorrect.correctWord('người'), isNull);
    });

    test('Sửa được -> trả kết quả có lý do', () {
      final r1 = AutoCorrect.correctWord('hòa');
      expect(r1?.corrected, 'hoà');
      expect(r1?.reason, AutoCorrectReason.toneReposition);

      final r2 = AutoCorrect.correctWord('giừo');
      expect(r2?.corrected, 'giờ');
      expect(r2?.reason, AutoCorrectReason.dictionary);
    });
  });

  group('Auto-correct: tích hợp engine (chốt từ)', () {
    test('Sửa khi gõ space — gõ nhanh sai vị trí dấu', () {
      // Gõ nhanh "giuwof": engine dựng ra "giừo" (móc rơi nhầm vào 'u', dấu vào 'o').
      // Chốt bằng space -> auto-correct sửa thành "giờ ".
      expect(_typeAC('giuwof '), 'giờ ');
      // Gõ nhanh "nhieuf": engine dựng ra "nhièu" (quên mũ ê). Space -> "nhiều ".
      expect(_typeAC('nhieuf '), 'nhiều ');
      // Chốt bằng dấu câu cũng sửa.
      expect(_typeAC('nhiefu.'), 'nhiều.');
    });

    test('Từ đúng gõ bình thường -> KHÔNG bị đụng', () {
      expect(_typeAC('tieengs '), 'tiếng '); // gõ đúng -> giữ nguyên
      expect(_typeAC('nguowif '), 'người '); // gõ đúng -> giữ nguyên
      expect(_typeAC('dduwocj '), 'được '); // gõ đúng -> giữ nguyên
    });

    test('Tắt autoCorrect (mặc định) -> engine ra chữ hợp lệ, không crash', () {
      final engine = VietEngine(method: InputMethod.telex); // autoCorrect: false
      var visible = '';
      var cur = '';
      for (final ch in 'hoaf '.split('')) {
        final r = engine.process(ch);
        if (r != null) {
          visible = visible.substring(0, visible.length - cur.length);
          visible += r;
          cur = r;
        } else {
          visible += ch;
          cur = '';
        }
      }
      // "hoaf" telex -> "hoà" (đã đúng modern). Không có gì để test tắt ở đây,
      // chỉ đảm bảo không crash và ra chữ hợp lệ.
      expect(visible, 'hoà ');
    });
  });
}
