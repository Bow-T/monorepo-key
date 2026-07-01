// auto_correct.dart
// -----------------
// TỰ SỬA LỖI GÕ NHANH — sửa từ vừa gõ xong (khi chốt từ bằng space/dấu câu).
//
// Ví dụ người gõ nhanh hay sai:
//   "giừo"  -> "giờ"    (dấu huyền rơi nhầm vào 'ư' thay vì 'ơ' + sai chữ)
//   "nhièu" -> "nhiều"  (dấu huyền rơi vào 'e' thay vì 'ê')
//   "hoÀ"   -> "hoà"    (dấu đặt sai vị trí trong cụm nguyên âm)
//
// CHIẾN LƯỢC 2 LỚP (chạy theo thứ tự, dừng ở lớp đầu tiên sửa được):
//
//   Lớp 1 — SỬA VỊ TRÍ DẤU THANH (không cần từ điển).
//     Phân rã từ về (các chữ cái + dấu biến âm) + (1 dấu thanh) rồi ĐẶT LẠI dấu
//     thanh đúng vị trí theo quy tắc chính tả. Nếu từ gốc hợp lệ nhưng đặt dấu sai
//     chỗ, lớp này sửa ngay mà không cần biết "từ đúng" là gì.
//
//   Lớp 2 — TỪ ĐIỂN TĨNH (lỗi phổ biến -> từ đúng).
//     Bảng ánh xạ các lỗi gõ nhanh hay gặp (thiếu/thừa/sai ký tự) sang từ đúng.
//     Bảng này TỰ SINH: cho một danh sách từ tiếng Việt phổ biến ("trend"), ta sinh
//     các biến thể-lỗi thường gặp (đảo dấu-nguyên-âm, thiếu dấu mũ...) rồi map ngược
//     về từ đúng. Muốn thêm từ mới -> chỉ cần thêm vào `AutoCorrectDictionary.words`.
//
// NGUYÊN TẮC AN TOÀN (để không phá văn bản người dùng):
//   • Chỉ sửa TỪ ĐÃ MANG DẤU TIẾNG VIỆT (có mũ/móc/trăng/thanh). Từ thuần ASCII
//     ("hello", "the", tên riêng) -> KHÔNG đụng.
//   • Chỉ sửa khi từ gốc SAI (không hợp lệ hoặc dấu đặt sai) và bản sửa HỢP LỆ.
//   • Giữ nguyên chữ HOA/thường của ký tự đầu (Giừo -> Giờ, giừo -> giờ).
//
// LƯU Ý VỀ CHUẨN HOÁ UNICODE:
//   Bản Swift dùng `precomposedStringWithCanonicalMapping` để đưa chuỗi về NFC.
//   Dart không có sẵn API này và package không phụ thuộc `unorm_dart`, nên ở đây
//   ta BỎ QUA bước chuẩn hoá NFC: chuỗi tiếng Việt do engine gõ ra vốn đã là dạng
//   dựng sẵn (NFC precomposed) khớp với bảng `composeViet`.

import 'viet_model.dart';
import 'viet_table.dart';
import 'viet_syllable.dart';

/// Lý do sửa — hữu ích cho log/test.
enum AutoCorrectReason {
  toneReposition, // lớp 1: dời dấu thanh về đúng vị trí
  dictionary, // lớp 2: khớp từ điển lỗi phổ biến
}

/// Kết quả tự sửa một từ.
class AutoCorrectResult {
  /// Từ sau khi sửa (đã đảm bảo khác từ gốc).
  final String corrected;

  /// Vì sao sửa.
  final AutoCorrectReason reason;

  const AutoCorrectResult(this.corrected, this.reason);

  @override
  bool operator ==(Object other) =>
      other is AutoCorrectResult &&
      other.corrected == corrected &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(corrected, reason);
}

/// Bộ tự-sửa-lỗi gõ nhanh (thuần, không trạng thái).
class AutoCorrect {
  AutoCorrect._();

  /// Thử tự sửa MỘT từ (chuỗi hiển thị, không chứa khoảng trắng).
  /// Trả `null` nếu không cần/không nên sửa (giữ nguyên từ gốc).
  ///
  /// Đây là hàm THUẦN (không trạng thái) — engine gọi khi chốt từ, caller so sánh
  /// độ dài để biết cần xoá/gõ lại bao nhiêu ký tự.
  static AutoCorrectResult? correctWord(String word) {
    if (word.isEmpty) return null;
    // An toàn: chỉ xét từ có dấu tiếng Việt. Bỏ qua ASCII thuần (Anh/tên riêng).
    if (!containsVietnameseDiacritic(word)) return null;

    // Lớp 1: dời dấu thanh về đúng vị trí.
    final repositioned = repositionTone(word);
    if (repositioned != null && repositioned != word) {
      return AutoCorrectResult(repositioned, AutoCorrectReason.toneReposition);
    }

    // Lớp 2: tra từ điển lỗi phổ biến (khớp không phân biệt hoa/thường).
    final fixed = AutoCorrectDictionary.shared.lookup(word);
    if (fixed != null && fixed != word) {
      return AutoCorrectResult(fixed, AutoCorrectReason.dictionary);
    }

    return null;
  }

  // ── Lớp 1: dời dấu thanh về đúng vị trí ────────────────────────────────────

  /// Phân rã từ thành (chữ cái + mark) + (một dấu thanh), rồi dựng lại với dấu thanh
  /// đặt đúng vị trí theo quy tắc chính tả. Trả null nếu không áp dụng được (không có
  /// dấu thanh, hoặc cấu trúc không phải âm tiết tiếng Việt hợp lệ).
  static String? repositionTone(String word) {
    // Chỉ xử lý một ÂM TIẾT (từ đơn). Từ ghép nhiều âm tiết hiếm khi gõ liền.
    final decomposed = Decomposed.tryParse(word);
    if (decomposed == null) return null;
    // Không có dấu thanh -> không có gì để dời.
    if (decomposed.tone == Tone.none) return null;
    // Cấu trúc phải là âm tiết tiếng Việt hợp lệ (đã bỏ thanh) — nếu không, dời
    // dấu cũng vô nghĩa, để lớp từ điển lo.
    if (!VietSyllable.isValidToneless(decomposed.toneless)) return null;

    // Vị trí đúng theo luật chính tả.
    final target = ToneRules.targetIndex(decomposed.letters);
    if (target < 0) return null;

    // Dựng lại: dấu thanh CHỈ đặt lên `target`.
    return decomposed.render(target);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Chuỗi có chứa ký tự MANG DẤU tiếng Việt (dấu thanh HOẶC mũ/móc/trăng/đ) không?
  /// LƯU Ý: chữ thường a/e/o/u/i/y KHÔNG tính là "có dấu" — nếu tính, mọi từ ASCII
  /// (kể cả "hello", "bay") sẽ lọt qua guard an toàn và bị auto-correct đụng nhầm.
  static bool containsVietnameseDiacritic(String word) {
    for (final ch in word.split('')) {
      final parts = CharDecompose.map[ch];
      if (parts != null && (parts.tone != Tone.none || parts.mark != Mark.none)) {
        return true;
      }
    }
    return false;
  }
}

// ── Phân rã ký tự tiếng Việt về (base, mark, tone) ────────────────────────────

/// Bảng ngược của bảng gõ: ký tự dựng sẵn -> (chữ gốc, dấu biến âm, dấu thanh).
/// Vd 'ế' -> ('e', circumflex, acute); 'ự' -> ('u', horn, dot); 'đ' -> ('d', dyet, none).
class CharDecompose {
  CharDecompose._();

  /// Xây dựng bảng ngược từ chính `composeViet` để LUÔN đồng bộ với bảng gõ.
  static final Map<String, CharParts> map = _build();

  static Map<String, CharParts> _build() {
    final m = <String, CharParts>{};
    final bases = <MapEntry<String, List<Mark>>>[
      const MapEntry('a', [Mark.none, Mark.circumflex, Mark.breve]),
      const MapEntry('e', [Mark.none, Mark.circumflex]),
      const MapEntry('i', [Mark.none]),
      const MapEntry('o', [Mark.none, Mark.circumflex, Mark.horn]),
      const MapEntry('u', [Mark.none, Mark.horn]),
      const MapEntry('y', [Mark.none]),
    ];
    const tones = <Tone>[
      Tone.none,
      Tone.acute,
      Tone.grave,
      Tone.hook,
      Tone.tilde,
      Tone.dot,
    ];
    for (final entry in bases) {
      final base = entry.key;
      for (final mark in entry.value) {
        for (final tone in tones) {
          final ch = composeViet(base, mark, tone);
          if (ch != null) {
            // Chỉ ghi nếu chưa có (none-mark ưu tiên cho ký tự gốc a/e/...).
            m.putIfAbsent(ch, () => CharParts(base, mark, tone));
            final up = ch.toUpperCase();
            if (up != ch) {
              m.putIfAbsent(up, () => CharParts(base.toUpperCase(), mark, tone));
            }
          }
        }
      }
    }
    // đ (không mang dấu thanh).
    final d = composeViet('d', Mark.dyet, Tone.none);
    if (d != null) {
      m[d] = CharParts('d', Mark.dyet, Tone.none);
      m[d.toUpperCase()] = CharParts('D', Mark.dyet, Tone.none);
    }
    return m;
  }
}

/// Một ký tự đã phân rã thành (chữ gốc, dấu biến âm, dấu thanh).
class CharParts {
  final String base;
  final Mark mark;
  final Tone tone;
  const CharParts(this.base, this.mark, this.tone);
}

/// Một chữ cái trong âm tiết: chữ gốc + dấu biến âm riêng.
class DecomposedLetter {
  String base;
  Mark mark;
  DecomposedLetter(this.base, this.mark);

  DecomposedLetter copy() => DecomposedLetter(base, mark);
}

/// Một từ đã phân rã thành các chữ cái (base + mark) và MỘT dấu thanh chung.
/// (Âm tiết tiếng Việt chỉ mang tối đa một dấu thanh, ta gom nó ra.)
class Decomposed {
  final List<DecomposedLetter> letters;
  final Tone tone;

  Decomposed._(this.letters, this.tone);

  /// Phân rã một chuỗi hiển thị. Trả null nếu có ký tự lạ (không phải chữ tiếng Việt).
  /// Nếu từ mang >1 dấu thanh (bất thường) -> lấy dấu thanh cuối cùng gặp được.
  static Decomposed? tryParse(String word) {
    final letters = <DecomposedLetter>[];
    var tone = Tone.none;
    for (final ch in word.split('')) {
      final parts = CharDecompose.map[ch];
      if (parts != null) {
        letters.add(DecomposedLetter(parts.base, parts.mark));
        if (parts.tone != Tone.none) tone = parts.tone;
      } else if (_isAsciiLetter(ch)) {
        letters.add(DecomposedLetter(ch, Mark.none));
      } else {
        return null; // ký tự lạ -> không phân rã được
      }
    }
    if (letters.isEmpty) return null;
    return Decomposed._(letters, tone);
  }

  /// Bản sao (deep copy) — để sinh biến thể mà không phá bản gốc.
  Decomposed copy() =>
      Decomposed._(letters.map((l) => l.copy()).toList(), tone);

  /// Chuỗi toneless (giữ mũ/móc/trăng, bỏ thanh) — để kiểm tra hợp lệ.
  String get toneless {
    final buf = StringBuffer();
    for (final l in letters) {
      buf.write(composeViet(l.base, l.mark, Tone.none) ?? l.base);
    }
    return buf.toString();
  }

  /// Dựng lại chuỗi, đặt dấu thanh CHỈ lên chữ cái ở `toneAt`.
  String render(int toneAt) {
    final buf = StringBuffer();
    for (var i = 0; i < letters.length; i++) {
      final l = letters[i];
      final t = (i == toneAt) ? tone : Tone.none;
      buf.write(composeViet(l.base, l.mark, t) ?? l.base);
    }
    return buf.toString();
  }

  static bool _isAsciiLetter(String ch) {
    if (ch.length != 1) return false;
    final code = ch.codeUnitAt(0);
    return (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);
  }
}

// ── Quy tắc đặt dấu thanh (dùng chung, tách để test độc lập) ──────────────────

/// Chọn vị trí đặt dấu thanh cho một dãy chữ cái — theo quy tắc chính tả "modern".
/// Đây là bản rút gọn, ĐỒNG NHẤT với `VietEngine._toneTargetIndex()`:
///   1. Nguyên âm mang dấu biến âm (â ê ô ơ ư ă) -> dấu lên đó.
///   2. Có phụ âm cuối -> nguyên âm cuối của cụm.
///   3. Cụm hở: 2 nguyên âm -> đầu, trừ "oa/oe/uy" -> sau; 3 nguyên âm -> giữa.
///   4. 1 nguyên âm -> chính nó.
class ToneRules {
  ToneRules._();

  static int targetIndex(List<DecomposedLetter> letters) {
    // Luật 1: nguyên âm có dấu biến âm (lấy cái cuối cùng gặp).
    for (var i = letters.length - 1; i >= 0; i--) {
      final m = letters[i].mark;
      if (m == Mark.circumflex || m == Mark.breve || m == Mark.horn) {
        return i;
      }
    }

    var vowelIdx = <int>[];
    for (var i = 0; i < letters.length; i++) {
      if (_isVowel(letters[i].base)) vowelIdx.add(i);
    }

    // Gộp nguyên âm trùng liên tiếp (kéo dài) về một đại diện đầu.
    if (vowelIdx.length >= 2) {
      final collapsed = <int>[];
      for (final idx in vowelIdx) {
        if (collapsed.isNotEmpty &&
            _lower(letters[collapsed.last].base) == _lower(letters[idx].base)) {
          continue;
        }
        collapsed.add(idx);
      }
      vowelIdx = collapsed;
    }

    // "gi"/"qu": 'i'/'u' là bán phụ âm đầu, loại khỏi cụm nếu còn nguyên âm khác.
    if (vowelIdx.length >= 2) {
      final first = vowelIdx.first;
      final firstBase = _lower(letters[first].base);
      final prevBase = first > 0 ? _lower(letters[first - 1].base) : ' ';
      if ((firstBase == 'i' && prevBase == 'g') ||
          (firstBase == 'u' && prevBase == 'q')) {
        vowelIdx.removeAt(0);
      }
    }

    if (vowelIdx.isEmpty) return -1;
    final start = vowelIdx.first;
    final end = vowelIdx.last;
    final count = vowelIdx.length;

    final hasFinalConsonant =
        (end + 1 < letters.length) && !_isVowel(letters[end + 1].base);
    if (hasFinalConsonant) return end;

    switch (count) {
      case 1:
        return start;
      case 2:
        final a = _lower(letters[start].base);
        final b = _lower(letters[end].base);
        final openTail =
            (a == 'o' && (b == 'a' || b == 'e')) || (a == 'u' && b == 'y');
        return openTail ? end : start;
      default:
        return vowelIdx[1];
    }
  }

  static bool _isVowel(String ch) => 'aeiouy'.contains(_lower(ch));
  static String _lower(String ch) => ch.toLowerCase();
}

// ── Từ điển tĩnh: lỗi phổ biến -> từ đúng ─────────────────────────────────────

/// TỪ ĐIỂN TĨNH cho tự-sửa lỗi gõ nhanh — dựng sẵn, chạy offline.
///
/// Cách hoạt động:
///   • `words` = danh sách TỪ ĐÚNG tiếng Việt phổ biến (phần "trend" — muốn thêm từ
///     mới chỉ cần bổ sung vào đây).
///   • Với mỗi từ đúng, ta TỰ SINH các biến thể-lỗi gõ nhanh hay gặp (đảo thứ tự chữ
///     trong cụm nguyên âm, thiếu dấu mũ, thừa/thiếu chữ...) rồi map ngược variant->đúng.
///   • `overrides` = các cặp (lỗi -> đúng) đặc thù không sinh tự động được, ưu tiên cao.
///
/// Vì sao tự sinh thay vì liệt kê tay? Vì cùng một loại lỗi ("dấu rơi nhầm nguyên âm")
/// lặp lại trên hàng nghìn từ. Sinh tự động từ từ-đúng giúp thêm 1 từ là phủ nhiều lỗi.
class AutoCorrectDictionary {
  /// Bản dùng chung (xây một lần, tra nhiều lần).
  static final AutoCorrectDictionary shared = AutoCorrectDictionary();

  /// variant (đã lowercase) -> từ đúng (lowercase).
  final Map<String, String> _table;

  AutoCorrectDictionary({
    List<String>? words,
    Map<String, String>? overrides,
  }) : _table = _buildTable(
          words ?? AutoCorrectDictionary.words,
          overrides ?? AutoCorrectDictionary.overrides,
        );

  static Map<String, String> _buildTable(
      List<String> words, Map<String, String> overrides) {
    final t = <String, String>{};

    // 1) Sinh biến thể-lỗi từ danh sách từ đúng.
    for (final correct in words) {
      final key = correct.toLowerCase();
      for (final variant in _misspellings(key)) {
        // Không ghi đè nếu variant TRÙNG một từ đúng khác (tránh sửa nhầm từ thật).
        if (variant == key) continue;
        t.putIfAbsent(variant, () => key);
      }
    }
    // Xoá các key mà bản thân nó cũng là một từ đúng (an toàn: đừng "sửa" từ đúng).
    final correctSet = words.map((w) => w.toLowerCase()).toSet();
    for (final k in t.keys.toList()) {
      if (correctSet.contains(k)) t.remove(k);
    }

    // 2) Overrides thủ công (ưu tiên cao nhất, ghi đè bản sinh tự động).
    for (final entry in overrides.entries) {
      t[entry.key.toLowerCase()] = entry.value.toLowerCase();
    }

    return t;
  }

  /// Tra từ đúng cho một từ (không phân biệt hoa/thường), giữ lại kiểu hoa của bản gốc.
  /// Trả null nếu không có trong từ điển.
  String? lookup(String word) {
    final key = word.toLowerCase();
    final fixed = _table[key];
    if (fixed == null) return null;
    return _applyCasing(word, fixed);
  }

  /// Số cặp lỗi->đúng đã dựng (để test/thống kê).
  int get count => _table.length;

  // ── Bộ sinh biến thể-lỗi gõ nhanh ──────────────────────────────────────────

  /// Sinh các biến thể-lỗi thường gặp của MỘT từ đúng (đã lowercase).
  /// Các lỗi mô phỏng: gõ nhanh làm dấu thanh rơi nhầm nguyên âm, thiếu dấu mũ/móc.
  static Set<String> _misspellings(String correct) {
    final out = <String>{};
    final dec = Decomposed.tryParse(correct);
    if (dec == null) return out;

    if (dec.tone == Tone.none) {
      // Không có dấu thanh: chỉ sinh lỗi thiếu-dấu-mũ (nếu có mũ/móc/trăng).
      out.addAll(_missingMarkVariants(dec));
      return out;
    }

    // (a) DẤU THANH RƠI NHẦM NGUYÊN ÂM: đặt dấu thanh lên MỖI nguyên âm khác vị trí
    //     đúng. Đây là lỗi gõ nhanh phổ biến nhất ("nhièu", "giừo"...).
    final correctTarget = ToneRules.targetIndex(dec.letters);
    for (var i = 0; i < dec.letters.length; i++) {
      if (!_isVowelLetter(dec.letters[i].base)) continue;
      if (i == correctTarget) continue;
      final variant = dec.render(i);
      out.add(variant.toLowerCase());
    }

    // (b) THIẾU DẤU MŨ/MÓC/TRĂNG trên nguyên âm mang dấu thanh (giừo: dấu ở 'ư'
    //     nhưng chữ đúng là 'ơ'). Kết hợp: bỏ mark của nguyên âm mang dấu thanh
    //     rồi vẫn giữ dấu thanh ở đó.
    out.addAll(_missingMarkVariants(dec));

    return out;
  }

  /// Biến thể "thiếu dấu biến âm": với mỗi nguyên âm mang mũ/móc/trăng, tạo bản bỏ
  /// mark đó (giữ nguyên dấu thanh) — mô phỏng gõ nhanh quên dấu mũ.
  static Set<String> _missingMarkVariants(Decomposed dec) {
    final out = <String>{};
    for (var i = 0; i < dec.letters.length; i++) {
      if (dec.letters[i].mark == Mark.none || dec.letters[i].mark == Mark.dyet) {
        continue;
      }
      final copy = dec.copy();
      copy.letters[i].mark = Mark.none;
      final target = ToneRules.targetIndex(copy.letters);
      if (target < 0) continue;
      final variant = copy.render(target);
      out.add(variant.toLowerCase());
    }
    return out;
  }

  static bool _isVowelLetter(String ch) => 'aeiouy'.contains(ch.toLowerCase());

  /// Áp kiểu hoa/thường của `source` lên `target` (theo từng ký tự, phần dư giữ thường).
  static String _applyCasing(String source, String target) {
    final src = source.split('');
    final tgt = target.split('');
    final buf = StringBuffer();
    for (var i = 0; i < tgt.length; i++) {
      final ch = tgt[i];
      if (i < src.length && _isUpper(src[i])) {
        buf.write(ch.toUpperCase());
      } else {
        buf.write(ch);
      }
    }
    return buf.toString();
  }

  static bool _isUpper(String ch) =>
      ch.toUpperCase() == ch && ch.toLowerCase() != ch;

  // ── Dữ liệu: danh sách từ đúng ("trend") + override thủ công ────────────────

  /// DANH SÁCH TỪ ĐÚNG phổ biến. Thêm từ mới vào đây để mở rộng ("tự thêm để trend").
  /// Mỗi từ đúng tự sinh ra các biến thể-lỗi gõ nhanh (xem `_misspellings`).
  /// Ưu tiên các âm tiết đơn hay bị gõ sai vị trí dấu / thiếu dấu mũ.
  static const List<String> words = [
    // đại từ / hư từ hay gặp
    'giờ', 'giờ', 'giữa', 'giường', 'người', 'được', 'nhiều', 'chiều', 'yêu',
    'tiền', 'biết', 'việc', 'hiểu', 'chuyện', 'muốn', 'buồn', 'luôn', 'cuộc',
    // động từ / tính từ thường dùng
    'trường', 'thương', 'hường', 'phường', 'vườn', 'mượn', 'lười', 'cười',
    'rượu', 'hươu', 'bưởi', 'tưởng', 'thưởng', 'nướng', 'xưởng',
    'tuổi', 'cuối', 'suối', 'chuối', 'đuối', 'nuôi', 'muối',
    'khỏe', 'khoẻ', 'hoà', 'hoạ', 'loạ', 'toà', 'xoà', 'goá',
    'quý', 'quà', 'quả', 'quẻ', 'quỳ', 'thuý', 'tuý',
    // âm tiết mang mũ hay bị quên
    'mấy', 'thấy', 'đấy', 'cây', 'mây', 'bây', 'gây',
    'tôi', 'rồi', 'mới', 'với', 'vội', 'đội', 'hỏi', 'gọi', 'nói',
    'về', 'lễ', 'kể', 'thế', 'để', 'nếu', 'đều', 'kêu', 'nhiêu',
    'cũng', 'những', 'từng', 'cùng', 'vẫn', 'lần', 'phần', 'gần',
  ];

  /// OVERRIDES thủ công — cặp (lỗi -> đúng) đặc thù, ưu tiên cao hơn bản sinh tự động.
  /// Dùng cho lỗi không suy ra được từ từ-đúng (đảo phụ âm, viết tắt phổ biến...).
  static const Map<String, String> overrides = {
    'giừo': 'giờ', // 'ư' + dời chữ -> 'ờ'
    'nhièu': 'nhiều', // dấu ở 'e' -> ở 'ê'
    'ngừoi': 'người',
    'đựoc': 'được',
    'cuộcj': 'cuộc',
  };
}
