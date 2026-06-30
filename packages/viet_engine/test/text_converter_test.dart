// text_converter_test.dart
// Test công cụ chuyển mã (port từ TextConverterTests.swift).

import 'package:test/test.dart';
import 'package:viet_engine/viet_engine.dart';

void main() {
  group('Bỏ dấu tiếng Việt', () {
    test('Cơ bản', () {
      expect(TextConverter.removeDiacritics('Tiếng Việt'), 'Tieng Viet');
      expect(TextConverter.removeDiacritics('Phở bò Hà Nội'), 'Pho bo Ha Noi');
      expect(TextConverter.removeDiacritics('đường'), 'duong');
      expect(TextConverter.removeDiacritics('Đặng'), 'Dang');
    });

    test('Đủ nguyên âm', () {
      expect(TextConverter.removeDiacritics('ăâêôơưđ'), 'aaeooud');
      expect(TextConverter.removeDiacritics('ưởng'), 'uong');
      expect(TextConverter.removeDiacritics('nghiêng'), 'nghieng');
    });

    test('Giữ ký tự khác', () {
      expect(TextConverter.removeDiacritics('100% ổn!'), '100% on!');
    });
  });

  group('Hoa / thường', () {
    test('ALL CAPS / lower giữ dấu', () {
      expect(TextConverter.changeCase('Tiếng Việt', LetterCase.allUpper), 'TIẾNG VIỆT');
      expect(TextConverter.changeCase('Tiếng Việt', LetterCase.allLower), 'tiếng việt');
      expect(TextConverter.changeCase('đẹp', LetterCase.allUpper), 'ĐẸP');
    });

    test('Hoa đầu câu', () {
      expect(TextConverter.changeCase('xin chào. tôi tên an', LetterCase.capitalizeFirst),
          'Xin chào. Tôi tên an');
    });

    test('Hoa mỗi từ', () {
      expect(TextConverter.changeCase('nguyễn văn an', LetterCase.capitalizeWords),
          'Nguyễn Văn An');
    });
  });

  group('Bảng mã cũ TCVN3 / VNI-Windows', () {
    test('TCVN3 khứ hồi (lowercase exact)', () {
      for (final s in ['tiếng việt', 'đường phố', 'phở bò', 'nghiêng ngả']) {
        final tcvn = TextConverter.convert(s, from: CodeTable.unicode, to: CodeTable.tcvn3);
        final back = TextConverter.convert(tcvn, from: CodeTable.tcvn3, to: CodeTable.unicode);
        expect(back, s, reason: 'TCVN round-trip: $s');
      }
    });

    test('VNI-Windows khứ hồi', () {
      for (final s in ['Tiếng Việt', 'đường phố', 'Phở bò', 'nghiêng ngả']) {
        final vni = TextConverter.convert(s, from: CodeTable.unicode, to: CodeTable.vniWindows);
        final back = TextConverter.convert(vni, from: CodeTable.vniWindows, to: CodeTable.unicode);
        expect(back, s, reason: 'VNI round-trip: $s');
      }
    });

    test('Giá trị cụ thể', () {
      expect(TextConverter.convert('đ', from: CodeTable.unicode, to: CodeTable.vniWindows), 'ñ');
      expect(TextConverter.convert('á', from: CodeTable.unicode, to: CodeTable.vniWindows), 'aù');
    });

    test('ASCII giữ nguyên', () {
      expect(TextConverter.convert('abc 123 .', from: CodeTable.unicode, to: CodeTable.tcvn3),
          'abc 123 .');
    });
  });
}
