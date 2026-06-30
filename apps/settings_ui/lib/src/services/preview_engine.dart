// preview_engine.dart
// -------------------
// Bộ gõ XEM TRƯỚC, NHẸ, chỉ phục vụ ô "gõ thử" ngay trong UI cài đặt. Nó KHÔNG
// phải engine thật (engine thật là Swift/Dart trong packages/viet_engine) — đây
// chỉ là bản rút gọn đủ để người dùng thấy Telex/VNI hoạt động khi đổi cài đặt.
//
// Cách dùng: gọi [transform] với chuỗi thô người dùng đã gõ; trả về chuỗi tiếng
// Việt tương ứng. Xử lý lại toàn chuỗi mỗi lần (đơn giản, không tối ưu) — ổn cho
// một ô preview ngắn.

import '../models/settings.dart';

class PreviewEngine {
  PreviewEngine({required this.method, required this.toneStyle});

  final InputMethod method;
  final ToneStyle toneStyle;

  /// Bảng tổ hợp nguyên âm + dấu thanh -> ký tự Unicode.
  /// Khoá: nguyên âm gốc (đã gắn mũ/móc/trăng). Thứ tự dấu: none,acute,grave,hook,tilde,dot
  static const Map<String, List<String>> _toneTable = {
    'a': ['a', 'á', 'à', 'ả', 'ã', 'ạ'],
    'ă': ['ă', 'ắ', 'ằ', 'ẳ', 'ẵ', 'ặ'],
    'â': ['â', 'ấ', 'ầ', 'ẩ', 'ẫ', 'ậ'],
    'e': ['e', 'é', 'è', 'ẻ', 'ẽ', 'ẹ'],
    'ê': ['ê', 'ế', 'ề', 'ể', 'ễ', 'ệ'],
    'i': ['i', 'í', 'ì', 'ỉ', 'ĩ', 'ị'],
    'o': ['o', 'ó', 'ò', 'ỏ', 'õ', 'ọ'],
    'ô': ['ô', 'ố', 'ồ', 'ổ', 'ỗ', 'ộ'],
    'ơ': ['ơ', 'ớ', 'ờ', 'ở', 'ỡ', 'ợ'],
    'u': ['u', 'ú', 'ù', 'ủ', 'ũ', 'ụ'],
    'ư': ['ư', 'ứ', 'ừ', 'ử', 'ữ', 'ự'],
    'y': ['y', 'ý', 'ỳ', 'ỷ', 'ỹ', 'ỵ'],
  };

  // Telex: phím -> dấu thanh.
  static const Map<String, int> _telexTone = {
    's': 1, 'f': 2, 'r': 3, 'x': 4, 'j': 5,
  };
  // VNI: phím số -> dấu thanh.
  static const Map<String, int> _vniTone = {
    '1': 1, '2': 2, '3': 3, '4': 4, '5': 5,
  };

  /// Biến đổi cả chuỗi thô thành chuỗi tiếng Việt.
  String transform(String raw) {
    final words = raw.split(RegExp(r'(\s+)'));
    return words.map(_word).join();
  }

  String _word(String w) {
    if (w.trim().isEmpty) return w; // khoảng trắng giữ nguyên
    var chars = w.split('');
    var tone = 0;

    final out = <String>[];
    for (final ch in chars) {
      final lower = ch.toLowerCase();

      // 1) Dấu thanh?
      final toneMap = method == InputMethod.telex ? _telexTone : _vniTone;
      if (toneMap.containsKey(lower) && out.isNotEmpty) {
        tone = toneMap[lower]!;
        continue;
      }

      // 2) Dấu biến âm (mũ/móc/trăng/đ)?
      final mod = _applyModifier(lower, out);
      if (mod) continue;

      out.add(ch);
    }

    var result = out.join();
    if (tone != 0) result = _applyTone(result, tone);
    return result;
  }

  /// Áp dấu biến âm vào ký tự cuối phù hợp trong [out]. Trả true nếu phím này là
  /// phím biến âm (đã tiêu thụ).
  bool _applyModifier(String key, List<String> out) {
    if (method == InputMethod.telex) {
      switch (key) {
        case 'a':
        case 'e':
        case 'o':
          return _doubleVowel(key, out); // aa->â, ee->ê, oo->ô
        case 'w':
          return _telexW(out); // a->ă, o->ơ, u->ư  (hoặc w đứng -> ư)
        case 'd':
          return _telexD(out); // dd -> đ
      }
    } else {
      // VNI: 6 mũ, 7 móc(o/u->ơ/ư), 8 trăng(a->ă), 9 đ
      switch (key) {
        case '6':
          return _vniCircumflex(out);
        case '7':
          return _vniHorn(out);
        case '8':
          return _vniBreve(out);
        case '9':
          return _vniD(out);
      }
    }
    return false;
  }

  bool _doubleVowel(String key, List<String> out) {
    if (out.isNotEmpty && out.last.toLowerCase() == key) {
      const map = {'a': 'â', 'e': 'ê', 'o': 'ô'};
      out[out.length - 1] = _matchCase(out.last, map[key]!);
      return true;
    }
    return false;
  }

  bool _telexW(List<String> out) {
    if (out.isEmpty) {
      out.add('ư');
      return true;
    }
    const map = {'a': 'ă', 'o': 'ơ', 'u': 'ư', 'A': 'Ă', 'O': 'Ơ', 'U': 'Ư'};
    final last = out.last;
    if (map.containsKey(last)) {
      out[out.length - 1] = map[last]!;
      return true;
    }
    out.add('ư');
    return true;
  }

  bool _telexD(List<String> out) {
    if (out.isNotEmpty && out.last.toLowerCase() == 'd') {
      out[out.length - 1] = _matchCase(out.last, 'đ');
      return true;
    }
    return false;
  }

  bool _vniCircumflex(List<String> out) =>
      _vniMap(out, {'a': 'â', 'e': 'ê', 'o': 'ô'});
  bool _vniHorn(List<String> out) => _vniMap(out, {'o': 'ơ', 'u': 'ư'});
  bool _vniBreve(List<String> out) => _vniMap(out, {'a': 'ă'});

  bool _vniMap(List<String> out, Map<String, String> map) {
    if (out.isEmpty) return false;
    final lower = out.last.toLowerCase();
    if (map.containsKey(lower)) {
      out[out.length - 1] = _matchCase(out.last, map[lower]!);
      return true;
    }
    return false;
  }

  bool _vniD(List<String> out) {
    if (out.isNotEmpty && out.last.toLowerCase() == 'd') {
      out[out.length - 1] = _matchCase(out.last, 'đ');
      return true;
    }
    return false;
  }

  /// Đặt dấu thanh vào nguyên âm phù hợp trong [word].
  String _applyTone(String word, int tone) {
    final chars = word.split('');
    final vowelIdx = _toneTargetIndex(chars);
    if (vowelIdx < 0) return word;

    final base = chars[vowelIdx].toLowerCase();
    final row = _toneTable[base];
    if (row == null) return word;
    chars[vowelIdx] = _matchCase(chars[vowelIdx], row[tone]);
    return chars.join();
  }

  /// Chọn nguyên âm để đặt dấu — quy tắc gần đúng:
  ///   - Nếu có nguyên âm đã mang dấu biến âm (â/ê/ô/ơ/ư/ă) -> đặt vào đó.
  ///   - Cụm "ươ"/"oa"/"oe"/"uy": modern đặt vào nguyên âm thứ 2, old vào thứ 1.
  ///   - Còn lại: nguyên âm cuối cùng.
  int _toneTargetIndex(List<String> chars) {
    final vowels = <int>[];
    for (var i = 0; i < chars.length; i++) {
      if (_toneTable.containsKey(chars[i].toLowerCase())) vowels.add(i);
    }
    if (vowels.isEmpty) return -1;
    if (vowels.length == 1) return vowels.first;

    // Ưu tiên nguyên âm có dấu biến âm.
    for (final i in vowels) {
      if ('ăâêôơư'.contains(chars[i].toLowerCase())) return i;
    }

    // Cụm 2 nguyên âm: modern -> thứ 2, old -> thứ 1.
    final twoLetters =
        '${chars[vowels[0]]}${chars[vowels[1]]}'.toLowerCase();
    const clusters = {'oa', 'oe', 'uy', 'uo', 'ươ'};
    if (clusters.contains(twoLetters)) {
      return toneStyle == ToneStyle.modern ? vowels[1] : vowels[0];
    }

    // Mặc định: nguyên âm áp chót nếu kết thúc bằng nguyên âm, nếu không thì cuối.
    return vowels.last;
  }

  static String _matchCase(String original, String replacement) {
    if (original == original.toUpperCase() &&
        original != original.toLowerCase()) {
      return replacement.toUpperCase();
    }
    return replacement;
  }
}
