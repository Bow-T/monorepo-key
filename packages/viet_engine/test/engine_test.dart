// engine_test.dart
// ----------------
// Test engine bằng cách "gõ" một chuỗi phím rồi xem kết quả âm tiết cuối cùng.
// Chạy: dart test  (hoặc: fvm dart test)
//
// ĐÂY LÀ BỘ CA CHUẨN (golden cases). Engine Dart và các bộ gõ native phải cho
// ra KẾT QUẢ GIỐNG HỆT trên cùng bộ ca này. Port 1:1 từ bản Swift
// (apps/macos_ime/Tests/VietEngineTests).

import 'package:test/test.dart';
import 'package:viet_engine/viet_engine.dart';

/// Gõ lần lượt từng ký tự của [keys] qua engine, trả về chuỗi hiển thị
/// của âm tiết cuối cùng.
String type(
  String keys, {
  InputMethod method = InputMethod.telex,
  ToneStyle toneStyle = ToneStyle.modern,
}) {
  final engine = VietEngine(method: method, toneStyle: toneStyle);
  var current = '';
  for (final ch in keys.split('')) {
    final rendered = engine.process(ch);
    current = rendered ?? ''; // gặp ký tự ngắt từ -> bắt đầu âm tiết mới
  }
  return current;
}

/// Gõ [keys], rồi nhấn backspace [n] lần, trả về chuỗi âm tiết cuối.
String typeThenBackspace(String keys, int n,
    {InputMethod method = InputMethod.telex}) {
  final engine = VietEngine(method: method);
  var current = '';
  for (final ch in keys.split('')) {
    current = engine.process(ch) ?? '';
  }
  for (var i = 0; i < n; i++) {
    current = engine.backspace() ?? '';
  }
  return current;
}

void main() {
  group('Telex cơ bản', () {
    test('Dấu thanh đơn giản', () {
      expect(type('as'), 'á');
      expect(type('af'), 'à');
      expect(type('ar'), 'ả');
      expect(type('ax'), 'ã');
      expect(type('aj'), 'ạ');
    });

    test('Dấu mũ bằng cách lặp chữ', () {
      expect(type('aa'), 'â');
      expect(type('ee'), 'ê');
      expect(type('oo'), 'ô');
    });

    test('Dấu trăng / móc bằng w', () {
      expect(type('aw'), 'ă');
      expect(type('ow'), 'ơ');
      expect(type('uw'), 'ư');
    });

    test('dd -> đ', () {
      expect(type('dd'), 'đ');
    });

    test('Kết hợp mũ + thanh: ê + sắc -> ế', () {
      expect(type('ees'), 'ế');
      expect(type('oof'), 'ồ');
      expect(type('uwx'), 'ữ');
    });

    test('Từ hoàn chỉnh', () {
      expect(type('tieengs'), 'tiếng'); // mục tiêu kinh điển
      expect(type('ddaays'), 'đấy');
      expect(type('Vieetj'), 'Việt');
    });

    test('Xoá dấu bằng z', () {
      expect(type('asz'), 'a');
    });
  });

  group('Quy tắc đặt dấu chính tả (modern)', () {
    test('Cụm hở 2 nguyên âm: dấu lên nguyên âm đầu', () {
      expect(type('muaf'), 'mùa'); // mùa: lên u
      expect(type('biaf'), 'bìa'); // bìa: lên i
    });

    test('Đuôi mở oa/oe/uy: dấu lên nguyên âm sau (modern)', () {
      expect(type('hoaf'), 'hoà'); // hoà (không phải hòa)
      expect(type('khoer'), 'khoẻ'); // khoẻ
      expect(type('quys'), 'quý'); // quý
    });

    test('Có phụ âm cuối: dấu lên nguyên âm cuối của cụm', () {
      expect(type('toans'), 'toán'); // toán: lên a
      expect(type('hoangf'), 'hoàng'); // hoàng: lên a
    });

    test('Nguyên âm có dấu biến âm luôn được ưu tiên', () {
      expect(type('tieengs'), 'tiếng'); // lên ê
      expect(type('nuowngs'), 'nướng'); // lên ơ
      expect(type('dduwowcj'), 'được'); // được
    });

    test('Ba nguyên âm: dấu lên nguyên âm giữa', () {
      expect(type('ngoaif'), 'ngoài'); // ngoài: lên a (giữa, có i cuối)
    });
  });

  group('Chế độ đặt dấu cũ (old orthography)', () {
    test('Đuôi mở oa/oe/uy: dấu lên nguyên âm đầu', () {
      expect(type('hoaf', toneStyle: ToneStyle.old), 'hòa'); // hòa
      expect(type('quys', toneStyle: ToneStyle.old), 'qúy'); // qúy
      expect(type('khoer', toneStyle: ToneStyle.old), 'khỏe'); // khỏe
    });

    test('Trường hợp có phụ âm cuối / biến âm: giống modern', () {
      expect(type('toans', toneStyle: ToneStyle.old), 'toán');
      expect(type('tieengs', toneStyle: ToneStyle.old), 'tiếng');
    });
  });

  group('Gõ lại để bỏ/đổi dấu', () {
    test('Gõ lại trùng dấu thanh -> bỏ dấu, trả ký tự thô', () {
      expect(type('hoaf'), 'hoà');
      expect(type('hoaff'), 'hoaf'); // f lần 2: bỏ huyền, f hiện ra
      expect(type('ass'), 'as'); // sắc bị huỷ, s hiện ra
    });

    test('Gõ dấu khác -> đổi dấu', () {
      expect(type('hoafs'), 'hoá'); // huyền -> sắc
      expect(type('asx'), 'ã'); // sắc -> ngã
    });

    test('Gõ lại trùng biến âm -> bỏ biến âm', () {
      expect(type('aaa'), 'aa'); // mũ bị huỷ, a hiện ra
      expect(type('oww'), 'ow'); // móc bị huỷ, w hiện ra
    });

    test('z là phím xoá dấu thuần (không tự hiện chữ z)', () {
      expect(type('asz'), 'a'); // z xoá sắc
      expect(type('azz'), 'a'); // z gõ mấy lần cũng chỉ giữ 'không dấu'
    });
  });

  group('Backspace (dựng lại từ buffer phím thô)', () {
    test('Backspace xoá 1 phím thô rồi dựng lại đúng', () {
      // "tieengs" = tiếng. Xoá 's' -> mất dấu sắc -> "tieng" = "tiêng".
      expect(typeThenBackspace('tieengs', 1), 'tiêng');
      // Xoá thêm 'g' -> "tieen" = "tiên".
      expect(typeThenBackspace('tieengs', 2), 'tiên');
    });

    test('Backspace qua phím tạo biến âm', () {
      // "aas" = ấ. Xoá 's' -> "aa" = "â".
      expect(typeThenBackspace('aas', 1), 'â');
      // Xoá thêm 'a' -> "a".
      expect(typeThenBackspace('aas', 2), 'a');
    });

    test('Backspace tới rỗng', () {
      expect(typeThenBackspace('as', 2), '');
    });

    test('Backspace khi buffer rỗng -> null (caller để phím đi qua)', () {
      final engine = VietEngine();
      expect(engine.backspace(), isNull);
    });
  });

  group('VNI cơ bản', () {
    test('Thanh bằng số', () {
      expect(type('a1', method: InputMethod.vni), 'á');
      expect(type('a2', method: InputMethod.vni), 'à');
    });

    test('Biến âm bằng số', () {
      expect(type('a6', method: InputMethod.vni), 'â');
      expect(type('o7', method: InputMethod.vni), 'ơ');
      expect(type('a8', method: InputMethod.vni), 'ă');
      expect(type('d9', method: InputMethod.vni), 'đ');
    });

    test('Từ hoàn chỉnh VNI: tie61ng -> tiếng', () {
      expect(type('tie61ng', method: InputMethod.vni), 'tiếng');
    });
  });
}
