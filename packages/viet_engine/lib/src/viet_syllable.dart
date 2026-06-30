// viet_syllable.dart
// ------------------
// KIỂM TRA ÂM TIẾT TIẾNG VIỆT HỢP LỆ — luật chính tả, KHÔNG cần từ điển.
// Port 1:1 từ VietSyllable.swift (macOS). Dùng cho:
//   • Tự khôi phục tiếng Anh: chuỗi biến dạng & không hợp lệ VN -> trả phím thô.
//   • Kiểm tra chính tả: cảnh báo tổ hợp sai.
//
// Cấu trúc âm tiết: [phụ âm đầu]? + [vần] + [phụ âm cuối]?.

class VietSyllable {
  VietSyllable._();

  /// Phụ âm đầu hợp lệ (sắp dài trước ngắn để khớp tham lam).
  static const List<String> _initials = [
    'ngh', 'ng', 'nh', 'ch', 'gh', 'gi', 'kh', 'ph', 'th', 'tr', 'qu',
    'b', 'c', 'd', 'đ', 'g', 'h', 'k', 'l', 'm', 'n', 'p', 'q', 'r',
    's', 't', 'v', 'x',
  ];

  /// Phụ âm cuối hợp lệ.
  static const List<String> _finals = ['ch', 'nh', 'ng', 'c', 'm', 'n', 'p', 't'];

  /// Vần (nguyên âm + bán nguyên âm) hợp lệ, đã bỏ dấu thanh (giữ mũ/móc/trăng).
  static const Set<String> _nuclei = {
    'a', 'ă', 'â', 'e', 'ê', 'i', 'o', 'ô', 'ơ', 'u', 'ư', 'y',
    'ai', 'ao', 'au', 'ay', 'âu', 'ây',
    'eo', 'êu',
    'ia', 'iê', 'iu', 'yê', 'yêu', 'iêu',
    'oa', 'oă', 'oe', 'oo', 'oi', 'ôi', 'ơi',
    'ua', 'uâ', 'uê', 'uô', 'uơ', 'ui', 'ưi', 'uy', 'ưa', 'ươ', 'ưu', 'ôô',
    'oai', 'oay', 'oao', 'uây', 'uôi', 'ươi',
    'uya', 'uyê', 'uyu',
  };

  /// Một âm tiết (đã bỏ dấu thanh, giữ mũ/móc/trăng) có HỢP LỆ về cấu trúc không?
  static bool isValidToneless(String rawSyllable) {
    final s = rawSyllable.toLowerCase();
    if (s.isEmpty) return false;
    if (!s.split('').every(_isVietLetter)) return false;

    var rest = s;
    final initial = _matchPrefix(rest, _initials);
    if (initial != null) rest = rest.substring(initial.length);
    if (rest.isEmpty) return false; // chỉ có phụ âm

    var nucleus = rest;
    final fin = _matchSuffix(rest, _finals);
    if (fin != null) nucleus = rest.substring(0, rest.length - fin.length);
    if (nucleus.isEmpty) return false;

    return _nuclei.contains(nucleus);
  }

  /// Bỏ DẤU THANH nhưng giữ mũ/móc/trăng: "tiếng" -> "tiêng".
  static String stripTone(String display) {
    final buf = StringBuffer();
    for (final ch in display.split('')) {
      buf.write(_toneStripMap[ch] ?? ch);
    }
    return buf.toString();
  }

  /// Chuỗi hiển thị (có dấu) có phải âm tiết tiếng Việt hợp lệ không?
  static bool isValidDisplay(String display) => isValidToneless(stripTone(display));

  // ── Kiểm tra chính tả ─────────────────────────────────────────────────────

  /// Một TỪ có sai chính tả tiếng Việt không? "Sai" = có dấu tiếng Việt nhưng
  /// cấu trúc âm tiết không hợp lệ. Từ thuần ASCII -> coi là KHÔNG sai.
  static bool isMisspelled(String word) {
    if (!_hasVietnameseDiacritic(word)) return false;
    return !isValidDisplay(word);
  }

  /// Trả danh sách (từ, vị trí start, vị trí end) các từ sai trong chuỗi nhiều từ.
  static List<({String word, int start, int end})> misspelledWords(String text) {
    final result = <({String word, int start, int end})>[];
    final chars = text.split('');
    var i = 0;
    while (i < chars.length) {
      if (!_isLetter(chars[i])) {
        i++;
        continue;
      }
      var j = i;
      while (j < chars.length && _isLetter(chars[j])) {
        j++;
      }
      final word = chars.sublist(i, j).join();
      if (isMisspelled(word)) result.add((word: word, start: i, end: j));
      i = j;
    }
    return result;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String? _matchPrefix(String s, List<String> list) {
    for (final c in list) {
      if (s.startsWith(c)) return c;
    }
    return null;
  }

  static String? _matchSuffix(String s, List<String> list) {
    for (final c in list) {
      if (s.endsWith(c)) return c;
    }
    return null;
  }

  static bool _isLetter(String ch) => ch.toUpperCase() != ch.toLowerCase();

  static bool _isVietLetter(String ch) {
    if (ch.length != 1) return false;
    final code = ch.codeUnitAt(0);
    if (code >= 0x61 && code <= 0x7A) return true; // a-z
    return 'ăâđêôơư'.contains(ch);
  }

  static bool _hasVietnameseDiacritic(String word) {
    for (final ch in word.split('')) {
      if (_toneStripMap.containsKey(ch)) return true;
      if ('ăâđêôơưĂÂĐÊÔƠƯ'.contains(ch)) return true;
      if ('ÁÀẢÃẠẮẰẲẴẶẤẦẨẪẬÉÈẺẼẸẾỀỂỄỆÍÌỈĨỊÓÒỎÕỌỐỒỔỖỘỚỜỞỠỢÚÙỦŨỤỨỪỬỮỰÝỲỶỸỴ'
          .contains(ch)) {
        return true;
      }
    }
    return false;
  }

  /// Bỏ dấu thanh, giữ mũ/móc/trăng.
  static const Map<String, String> _toneStripMap = {
    'á': 'a', 'à': 'a', 'ả': 'a', 'ã': 'a', 'ạ': 'a',
    'ắ': 'ă', 'ằ': 'ă', 'ẳ': 'ă', 'ẵ': 'ă', 'ặ': 'ă',
    'ấ': 'â', 'ầ': 'â', 'ẩ': 'â', 'ẫ': 'â', 'ậ': 'â',
    'é': 'e', 'è': 'e', 'ẻ': 'e', 'ẽ': 'e', 'ẹ': 'e',
    'ế': 'ê', 'ề': 'ê', 'ể': 'ê', 'ễ': 'ê', 'ệ': 'ê',
    'í': 'i', 'ì': 'i', 'ỉ': 'i', 'ĩ': 'i', 'ị': 'i',
    'ó': 'o', 'ò': 'o', 'ỏ': 'o', 'õ': 'o', 'ọ': 'o',
    'ố': 'ô', 'ồ': 'ô', 'ổ': 'ô', 'ỗ': 'ô', 'ộ': 'ô',
    'ớ': 'ơ', 'ờ': 'ơ', 'ở': 'ơ', 'ỡ': 'ơ', 'ợ': 'ơ',
    'ú': 'u', 'ù': 'u', 'ủ': 'u', 'ũ': 'u', 'ụ': 'u',
    'ứ': 'ư', 'ừ': 'ư', 'ử': 'ư', 'ữ': 'ư', 'ự': 'ư',
    'ý': 'y', 'ỳ': 'y', 'ỷ': 'y', 'ỹ': 'y', 'ỵ': 'y',
  };
}
