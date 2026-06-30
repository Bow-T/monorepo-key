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

    // Regression: 'u' sau 'q' và 'i' sau 'g' là phần của phụ âm đầu, KHÔNG nhận
    // dấu thanh (quy tắc chính tả "gi"/"qu").
    test('qu-: dấu không lên u (quà, quá, quán)', () {
      expect(type('quaf'), 'quà'); // KHÔNG phải "qùa"
      expect(type('quas'), 'quá');
      expect(type('quans'), 'quán');
      expect(type('quys'), 'quý'); // u-y: y là nguyên âm chính -> lên y
    });

    test('gi-: dấu không lên i (già, giá, giò, giúp)', () {
      expect(type('giaf'), 'già'); // KHÔNG phải "gìa"
      expect(type('gias'), 'giá');
      expect(type('giof'), 'giò');
      expect(type('giups'), 'giúp');
      expect(type('giuwxa'), 'giữa');
    });

    test('gi-/qu- khi nguyên âm đó là DUY NHẤT thì vẫn nhận dấu', () {
      expect(type('gif'), 'gì'); // i duy nhất -> dấu lên i
      expect(type('gir'), 'gỉ');
    });
  });

  group('Chế độ đặt dấu cũ (old orthography)', () {
    test('Đuôi mở oa/oe/uy: dấu lên nguyên âm đầu', () {
      expect(type('hoaf', toneStyle: ToneStyle.old), 'hòa'); // hòa
      // Dùng "uy" THẬT (thùy), không phải "quy" — trong "qu" thì 'u' là bán phụ âm
      // nên "quý" luôn đặt dấu trên y ở cả hai chế độ (xem group qu-/gi- ở trên).
      expect(type('thuyf', toneStyle: ToneStyle.old), 'thùy'); // thùy (lên u)
      expect(type('khoer', toneStyle: ToneStyle.old), 'khỏe'); // khỏe
    });

    test('"quy" đặt dấu trên y ở cả modern lẫn old (u là bán phụ âm)', () {
      expect(type('quys'), 'quý');
      expect(type('quys', toneStyle: ToneStyle.old), 'quý');
    });

    test('Trường hợp có phụ âm cuối / biến âm: giống modern', () {
      expect(type('toans', toneStyle: ToneStyle.old), 'toán');
      expect(type('tieengs', toneStyle: ToneStyle.old), 'tiếng');
    });
  });

  // Regression: phím-dấu (s f r x j z) đứng sau phụ âm đầu mà CHƯA có nguyên âm
  // không được nuốt làm dấu thanh (phụ âm đầu không bị hiểu nhầm là phím-dấu).
  group('Phụ âm-dấu sau phụ âm đầu (chưa có nguyên âm)', () {
    test('tr- không bị nuốt thành dấu hỏi', () {
      expect(type('tre'), 'tre'); // cây tre, KHÔNG phải "tẻ"
      expect(type('tres'), 'tré');
      expect(type('treen'), 'trên'); // trên, KHÔNG phải "tển"
      expect(type('trong'), 'trong');
      expect(type('truowcs'), 'trước');
    });

    test('các cụm phụ âm khác (gr/xr/...) giữ nguyên phím-dấu', () {
      expect(type('gra'), 'gra'); // 'r' sau 'g' là chữ thường
      expect(type('xra'), 'xra'); // 'x' đầu + 'r'
      expect(type('strong'), 'strong'); // không có gì bị nuốt
    });

    test('phụ âm-dấu là chữ ĐẦU vẫn giữ nguyên (đã đúng từ trước)', () {
      expect(type('sai'), 'sai');
      expect(type('xin'), 'xin');
      expect(type('rum'), 'rum');
      expect(type('fan'), 'fan');
      expect(type('zap'), 'zap');
    });
  });

  // Gõ tắt 'w': 'w' đơn (không ghép được a/o/u) tạo 'ư'; cụm "ưo" tự thành "ươ"
  // khi có âm đóng {n,c,i,m,p,t} đứng sau (quy tắc chính tả cụm "ươ").
  group("Gõ tắt 'w'", () {
    test("'w' đơn -> ư (sau phụ âm hoặc đầu từ)", () {
      expect(type('w'), 'ư');
      expect(type('tw'), 'tư');
      expect(type('cw'), 'cư');
      expect(type('qw'), 'qư');
      expect(type('mwf'), 'mừ');
      expect(type('dwfng'), 'dừng');
      expect(type('mwfng'), 'mừng');
      expect(type('wf'), 'ừ');
    });

    test('"ưo" -> "ươ" khi có âm đóng kế tiếp', () {
      expect(type('huwong'), 'hương');
      expect(type('huwongs'), 'hướng');
      expect(type('tuwong'), 'tương');
      expect(type('thuwong'), 'thương');
      expect(type('nuwocs'), 'nước');
    });

    test('Không phá cách gõ chuẩn uw / aw / ow / uow', () {
      expect(type('uw'), 'ư');
      expect(type('aw'), 'ă');
      expect(type('ow'), 'ơ');
      expect(type('huowng'), 'hương');
      expect(type('huow'), 'hươ'); // gõ dở, chưa âm đóng -> giữ nguyên
    });

    test('Telex ua + w -> ưa và quaw -> quă', () {
      expect(type('muaw'), 'mưa');
      expect(type('chuaw'), 'chưa');
      expect(type('luawj'), 'lựa');
      expect(type('dduaw'), 'đưa');
      expect(type('quaw'), 'quă'); // không thành qưa
    });

    test('Telex quow -> quơ', () {
      expect(type('quow'), 'quơ'); // không thành quươ
    });

    test('Telex thuo + w -> thuơ và thuowng -> thương', () {
      expect(type('thuow'), 'thuơ');
      expect(type('thuowr'), 'thuở');
      expect(type('thuowng'), 'thương');
    });

    test('Telex consecutive w collapsing', () {
      expect(type('ww'), 'w');
      expect(type('uww'), 'ưw');
      expect(type('tww'), 'tw');
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
      expect(type('oww'), 'ơw'); // oww -> ơw (standard Telex/Unikey)
      expect(type('ddd'), 'dd'); // đ bị huỷ, d hiện ra (đối xứng aaa)
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

    // Regression: gõ lại số-biến-âm trùng -> huỷ biến âm, số hiện ra như ký tự thô
    // (cơ chế toggle: gỡ dấu rồi chèn phím thô).
    test('Gõ lại số-biến-âm trùng -> huỷ biến âm + số thô', () {
      expect(type('a66', method: InputMethod.vni), 'a6'); // huỷ mũ
      expect(type('o77', method: InputMethod.vni), 'o7'); // huỷ móc
      expect(type('a88', method: InputMethod.vni), 'a8'); // huỷ trăng
      expect(type('d99', method: InputMethod.vni), 'd9'); // huỷ đ
    });

    test('Kết hợp số-thanh + số-biến-âm vẫn đúng', () {
      expect(type('a16', method: InputMethod.vni), 'ấ'); // sắc rồi mũ -> ấ
      expect(type('a61', method: InputMethod.vni), 'ấ'); // mũ rồi sắc -> ấ
    });

    test('VNI ua/uo + 7 -> ưa/ươ và qua7/quo7', () {
      expect(type('mua7', method: InputMethod.vni), 'mưa');
      expect(type('muo7n', method: InputMethod.vni), 'mươn');
      expect(type('muo75n', method: InputMethod.vni), 'mượn');
      expect(type('qua7', method: InputMethod.vni), 'qua7'); // không thành qưa
      expect(type('quo7', method: InputMethod.vni), 'quơ');  // không thành quươ
      expect(type('thuo7', method: InputMethod.vni), 'thuơ');
      expect(type('thuo73', method: InputMethod.vni), 'thuở');
      expect(type('thuo7ng', method: InputMethod.vni), 'thương');
    });
  });

  // Kéo dài nguyên âm (vowel stretching) — đối chiếu engine PHTV.
  group('Kéo dài nguyên âm (elongation)', () {
    test('Chu kỳ mũ theo số lần gõ, không tạo lại mũ sau khi gỡ', () {
      expect(type('aa'), 'â');
      expect(type('aaa'), 'aa');
      expect(type('aaaa'), 'aaa'); // regression: không tạo lại mũ
      expect(type('aaaaa'), 'aaaa');
      expect(type('eee'), 'ee');
      expect(type('ooo'), 'oo');
      expect(type('cooo'), 'coo');
      expect(type('theee'), 'thee');
    });

    test('Phím-thanh xen giữa không phá chu kỳ mũ', () {
      expect(type('these'), 'thế');
      expect(type('baasm'), 'bấm');
      expect(type('casa'), type('caas'));
    });

    test('Dấu thanh giữ trên nguyên âm gốc khi nguyên âm bị kéo dài', () {
      expect(type('choifiii'), 'chòiiii');
      expect(type('choiiiif'), 'chòiiii');
      expect(type('ojooo'), 'ọoo');
      expect(type('curaaa'), 'củaa');
    });
  });
}
