// viet_syllable_test.dart
// Kiểm tra luật âm tiết + khôi phục tiếng Anh + chính tả (port từ Swift).

import 'package:test/test.dart';
import 'package:viet_engine/viet_engine.dart';

String _render(String keys) {
  final e = VietEngine(method: InputMethod.telex);
  var out = '';
  for (final ch in keys.split('')) {
    out = e.process(ch) ?? '';
  }
  return out;
}

void main() {
  group('Âm tiết tiếng Việt hợp lệ', () {
    test('Từ thật -> hợp lệ', () {
      for (final s in [
        'tiêng', 'viêt', 'nha', 'ban', 'đương', 'phô', 'nghiêng',
        'trương', 'quyên', 'không', 'ngươi', 'cha', 'me', 'khoe', 'hoa',
        'quy', 'giưa', 'nguyên', 'buôc', 'nươc', 'thương', 'đep', 'xinh',
        'yêu', 'uông',
      ]) {
        expect(VietSyllable.isValidToneless(s), isTrue, reason: 'hợp lệ: $s');
      }
    });

    test('Từ Anh không cấu trúc VN -> không hợp lệ', () {
      for (final s in [
        'terminal', 'google', 'test', 'user', 'file', 'data', 'code',
        'english', 'world', 'blfoo', 'xyz', 'strong', 'fast', 'click', 'and',
      ]) {
        expect(VietSyllable.isValidToneless(s), isFalse, reason: 'không hợp lệ: $s');
      }
    });

    test('Từ Anh trùng cấu trúc VN -> hợp lệ (ưu tiên tiếng Việt)', () {
      expect(VietSyllable.isValidToneless('the'), isTrue);
      expect(VietSyllable.isValidToneless('can'), isTrue);
      expect(VietSyllable.isValidToneless('ban'), isTrue);
    });

    test('Dạng hiển thị có dấu', () {
      expect(VietSyllable.isValidDisplay('tiếng'), isTrue);
      expect(VietSyllable.isValidDisplay('được'), isTrue);
      expect(VietSyllable.isValidDisplay('terminäl'), isFalse);
    });

    test('stripTone giữ mũ/móc/trăng', () {
      expect(VietSyllable.stripTone('tiếng'), 'tiêng');
      expect(VietSyllable.stripTone('được'), 'đươc');
      expect(VietSyllable.stripTone('nước'), 'nươc');
    });

    test('Chỉ phụ âm -> không hợp lệ', () {
      expect(VietSyllable.isValidToneless('ng'), isFalse);
      expect(VietSyllable.isValidToneless('tr'), isFalse);
    });
  });

  group('Tự khôi phục tiếng Anh', () {
    String? restore(String keys) =>
        VietEngine.englishRestoreKeys(rawKeys: keys, display: _render(keys));

    test('Từ Anh biến dạng -> khôi phục', () {
      expect(restore('waht'), 'waht');
    });

    test('Từ VN thật -> giữ (null)', () {
      expect(restore('tieengs'), isNull); // tiếng
      expect(restore('nuowngs'), isNull); // nướng
      expect(restore('hoaf'), isNull); // hoà
    });

    test('ASCII không biến dạng -> giữ', () {
      expect(restore('test'), isNull);
      expect(restore('code'), isNull);
    });

    test('aas -> ấ (biến dạng nhưng hợp lệ VN) -> giữ', () {
      expect(restore('aas'), isNull);
    });
  });

  group('Kiểm tra chính tả', () {
    test('Từ đúng -> không sai', () {
      for (final w in ['tiếng', 'Việt', 'được', 'nướng', 'phở']) {
        expect(VietSyllable.isMisspelled(w), isFalse, reason: w);
      }
    });

    test('Từ ASCII -> không đánh dấu sai', () {
      for (final w in ['terminal', 'google', 'the', 'abc']) {
        expect(VietSyllable.isMisspelled(w), isFalse, reason: w);
      }
    });

    test('Tìm từ sai trong câu', () {
      final bad = VietSyllable.misspelledWords('Tôi viết tểrn rồi');
      expect(bad.length, 1);
      expect(bad.first.word, 'tểrn');
    });

    test('Câu sạch -> không có từ sai', () {
      expect(VietSyllable.misspelledWords('Tôi yêu tiếng Việt'), isEmpty);
    });
  });
}
