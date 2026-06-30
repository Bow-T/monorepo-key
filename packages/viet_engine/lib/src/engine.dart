// engine.dart
// ------------
// Bộ não của bộ gõ. Nhận từng phím người dùng nhấn và quyết định:
//   - giữ nguyên ký tự đó, HAY
//   - biến đổi "từ đang gõ" thành dạng có dấu tiếng Việt.
//
// MÔ HÌNH XỬ LÝ (đơn giản hoá để học):
//   Engine giữ một "buffer" = từ đang gõ dở (vd: đã gõ "tieeng").
//   Mỗi phím mới tới, engine thử xem nó có phải phím-dấu của Telex không:
//     - 's' -> sắc, 'f' -> huyền, 'r' -> hỏi, 'x' -> ngã, 'j' -> nặng, 'z' -> xoá dấu
//     - 'aa'->â, 'ee'->ê, 'oo'->ô, 'aw'->ă, 'ow'->ơ, 'uw'->ư, 'dd'->đ, 'w'->ơ/ư
//   Nếu là phím-dấu áp được -> sửa buffer. Nếu không -> nối ký tự vào buffer.
//
//   Khi gặp khoảng trắng / dấu câu / phím không phải chữ -> "chốt từ", reset buffer.
//
// LƯU Ý: đây là bản TỐI GIẢN để bạn học cơ chế. Bộ gõ thật còn xử lý
// đặt dấu thanh đúng vị trí theo quy tắc chính tả, gõ lại để bỏ dấu, undo, v.v.
//
// Đây là bản port sang Dart của engine Swift (apps/macos_ime/Sources/VietEngine).
// Hai bản phải cho ra KẾT QUẢ GIỐNG HỆT trên cùng bộ ca test.

import 'viet_model.dart';
import 'viet_table.dart';

/// Một chữ cái trong âm tiết: chữ gốc + dấu biến âm riêng.
class _Letter {
  String base;
  Mark mark;
  _Letter(this.base, {this.mark = Mark.none});
}

/// Một âm tiết đang được gõ, mô tả theo (các ký tự) + (tone).
class _Syllable {
  final List<_Letter> letters = [];
  Tone tone = Tone.none;

  bool get isEmpty => letters.isEmpty;

  void reset() {
    letters.clear();
    tone = Tone.none;
  }
}

/// Kết quả khi thử coi một ký tự là phím-dấu.
enum _DiacriticResult {
  applied, // đã áp dấu/biến âm vào âm tiết
  cancelled, // gõ lại trùng dấu -> đã GỠ dấu; trả ký tự thô cho caller
  notDiacritic, // không phải phím-dấu -> nối như chữ thường
}

class VietEngine {
  final _Syllable _syllable = _Syllable();
  final InputMethod method;
  final ToneStyle toneStyle;

  /// Đúng dãy phím người dùng đã gõ cho âm tiết hiện tại (vd "tieengs").
  /// Giữ buffer này để có thể DỰNG LẠI (replay) âm tiết — cần cho backspace, ESC.
  final List<String> _rawKeys = [];

  VietEngine({this.method = InputMethod.telex, this.toneStyle = ToneStyle.modern});

  /// Nhận một ký tự người dùng gõ, trả về chuỗi văn bản hiện tại của âm tiết
  /// (cái mà ô nhập liệu nên hiển thị cho âm tiết đang gõ).
  ///
  /// Trả về `null` nghĩa là: ký tự này KHÔNG thuộc âm tiết (vd khoảng trắng) —
  /// caller nên xuất ký tự đó nguyên bản và bắt đầu âm tiết mới.
  String? process(String ch) {
    // Ghi lại phím thô TRƯỚC khi xử lý (nếu nó thuộc về âm tiết).
    // Ký tự ngắt từ sẽ tự reset bên dưới nên không cần ghi.
    final willBeWordBreak = () {
      if (_isLetter(ch)) return false;
      final isVNIToneKey =
          method == InputMethod.vni && _isDigit(ch) && !_syllable.isEmpty;
      return !isVNIToneKey;
    }();
    if (!willBeWordBreak) {
      _rawKeys.add(ch);
    }
    return _step(ch);
  }

  /// Một bước xử lý thuần (không đụng rawKeys) — để replay dùng lại được.
  String? _step(String ch) {
    // 1) Ký tự ngắt từ (space, dấu câu...) -> chốt âm tiết.
    //    Ngoại lệ: với VNI, các CHỮ SỐ là phím-dấu, không phải ngắt từ.
    if (!_isLetter(ch)) {
      final isVNIToneKey =
          method == InputMethod.vni && _isDigit(ch) && !_syllable.isEmpty;
      if (!isVNIToneKey) {
        _syllable.reset();
        _rawKeys.clear(); // chốt âm tiết -> buffer thô bắt đầu lại
        return null;
      }
    }

    // 2) Thử coi ch là phím-dấu của phương thức gõ.
    switch (_applyAsDiacritic(ch)) {
      case _DiacriticResult.applied:
        return _render();
      case _DiacriticResult.cancelled:
        // GÕ LẠI ĐỂ BỎ DẤU: vd "hoaf" rồi gõ "f" nữa.
        // Dấu đã bị gỡ. Ký tự phím-dấu lúc này hiện ra như chữ thường ->
        // "hoa" + "f" = "hoaf". Nối ký tự thô rồi render.
        _syllable.letters.add(_Letter(ch));
        return _render();
      case _DiacriticResult.notDiacritic:
        break; // rơi xuống bước 3
    }

    // 3) Không phải phím-dấu -> nối như một chữ cái thường.
    _syllable.letters.add(_Letter(ch));
    _propagateUoHorn();
    return _render();
  }

  /// Lan móc trên cụm "uo" -> "ươ" khi gặp âm đóng đứng ngay sau.
  ///
  /// Tiếng Việt không có âm tiết chứa "ưo"/"uơ" trần — luôn là "ươ". Khi người
  /// dùng gõ tắt (vd "tw"->tư, rồi "o","n"), ta có "tưon"; lúc này cần đồng bộ
  /// móc cho cả u và o thành "tươn". Chỉ kích hoạt khi âm đóng kế tiếp thuộc
  /// {n, c, i, m, p, t} (âm đóng hợp lệ của cụm "ươ") và ĐÚNG MỘT trong u/o đang
  /// có móc — để không đụng vào "huow"->hươ đang gõ dở (chưa có âm đóng).
  void _propagateUoHorn() {
    final letters = _syllable.letters;
    final n = letters.length;
    if (n < 3) return;
    const closers = {'n', 'c', 'i', 'm', 'p', 't'};
    if (!closers.contains(letters[n - 1].base.toLowerCase())) return;
    final u = letters[n - 3];
    final o = letters[n - 2];
    if (u.base.toLowerCase() != 'u' || o.base.toLowerCase() != 'o') return;
    final uHorn = u.mark == Mark.horn;
    final oHorn = o.mark == Mark.horn;
    if (uHorn != oHorn) {
      // đúng một cái có móc -> móc cả hai thành "ươ".
      u.mark = Mark.horn;
      o.mark = Mark.horn;
    }
  }

  /// Reset thủ công (gọi khi con trỏ nhảy chỗ khác, click chuột, v.v.)
  void clear() {
    _syllable.reset();
    _rawKeys.clear();
  }

  /// Xử lý phím Backspace: xoá 1 phím thô cuối rồi DỰNG LẠI âm tiết từ đầu.
  ///
  /// Vì sao dựng lại thay vì "tháo dấu"? Vì một ký tự hiển thị có thể do nhiều phím
  /// tạo nên (vd "ế" = e+e+s). Xoá 1 phím thô rồi replay luôn cho kết quả ĐÚNG mà
  /// không cần logic đảo ngược phức tạp.
  ///
  /// Trả về chuỗi hiển thị mới của âm tiết (rỗng nếu đã hết), hoặc `null` nếu không
  /// còn gì trong buffer (caller cứ để Backspace đi qua như bình thường).
  String? backspace() {
    if (_rawKeys.isEmpty) return null;
    _rawKeys.removeLast();
    // Dựng lại từ đầu.
    _syllable.reset();
    final keys = List<String>.from(_rawKeys);
    _rawKeys.clear(); // _step() không tự ghi rawKeys; ta ghi lại bên dưới
    var current = '';
    for (final key in keys) {
      _rawKeys.add(key);
      current = _step(key) ?? '';
    }
    return current;
  }

  // MARK: - Áp dụng phím-dấu

  _DiacriticResult _applyAsDiacritic(String ch) {
    switch (method) {
      case InputMethod.telex:
        return _applyTelex(ch);
      case InputMethod.vni:
        return _applyVNI(ch);
    }
  }

  _DiacriticResult _applyTelex(String ch) {
    final lower = ch.toLowerCase();
    switch (lower) {
      // Dấu thanh
      case 's':
        return _setTone(Tone.acute);
      case 'f':
        return _setTone(Tone.grave);
      case 'r':
        return _setTone(Tone.hook);
      case 'x':
        return _setTone(Tone.tilde);
      case 'j':
        return _setTone(Tone.dot);
      case 'z':
        return _setTone(Tone.none); // xoá dấu thanh

      // Dấu biến âm bằng cách lặp chữ / KÉO DÀI nguyên âm: aa, ee, oo
      case 'a':
      case 'e':
      case 'o':
        return _applyCircumflexRepeat(lower);

      // w: ă/ơ/ư tuỳ chữ cái cuối; dd -> đ
      case 'w':
        // Xử lý ww -> w: nếu phím trước là w và không có nguyên âm trước w đó
        final rawLen = _rawKeys.length;
        final isConsecutiveW = rawLen >= 2 && _rawKeys[rawLen - 2].toLowerCase() == 'w';
        if (isConsecutiveW) {
          final hasVowelBeforePrevW = rawLen >= 3 && 'uoa'.contains(_rawKeys[rawLen - 3].toLowerCase());
          if (!hasVowelBeforePrevW) {
            if (_syllable.letters.isNotEmpty) {
              final last = _syllable.letters.last;
              if (last.mark == Mark.horn && (last.base == 'u' || last.base == 'U')) {
                last.base = ch;
                last.mark = Mark.none;
                return _DiacriticResult.applied;
              }
            }
          } else {
            return _DiacriticResult.notDiacritic;
          }
        }
        return _applyHornOrBreve();
      case 'd':
        final last = _syllable.letters.isNotEmpty ? _syllable.letters.last : null;
        if (last != null && last.base.toLowerCase() == 'd') {
          if (last.mark == Mark.dyet) {
            return _removeMarkOnLast(); // đ rồi gõ 'd' nữa -> bỏ gạch (ddd -> dd)
          }
          if (last.mark == Mark.none) {
            return _setMarkOnLast(Mark.dyet); // dd -> đ
          }
        }
        return _DiacriticResult.notDiacritic;

      default:
        return _DiacriticResult.notDiacritic;
    }
  }

  /// Lặp nguyên âm a/e/o trong Telex: tạo mũ (aa->â) hoặc KÉO DÀI nguyên âm.
  ///
  /// CHU KỲ MŨ tính theo SỐ LẦN gõ nguyên âm đó trong "run" cuối (đếm cả khi có
  /// phím-thanh xen giữa — vd "casa" == "caas" == cấ). Dấu thanh "ăn theo", không
  /// phá chu kỳ; vị trí dấu do [_toneTargetIndex] quyết định:
  ///   lần 2 gõ -> tạo mũ (aa->â, asa->ấ, these->thế)
  ///   lần 3 gõ -> gỡ mũ  (aaa->aa, asaa->áaa, nhesee->nhéee)
  ///   lần >=4  -> kéo dài thô, KHÔNG tạo lại mũ (aaaa->aaa, ojooo->ọoo)
  _DiacriticResult _applyCircumflexRepeat(String lower) {
    final last = _syllable.letters.isNotEmpty ? _syllable.letters.last : null;
    if (last == null || last.base.toLowerCase() != lower) {
      return _DiacriticResult.notDiacritic; // 'a/e/o' đơn -> nối như chữ thường
    }

    final pressCount = _trailingVowelPressCount(lower);

    if (last.mark == Mark.circumflex) {
      return _removeMarkOnLast(); // â/ê/ô + gõ thêm -> gỡ mũ (chu kỳ lần 3)
    }
    if (last.mark == Mark.none) {
      if (pressCount == 2 && composeViet(last.base, Mark.circumflex, Tone.none) != null) {
        return _setMarkOnLast(Mark.circumflex); // aa -> â
      }
      return _DiacriticResult.notDiacritic; // kéo dài thô (aaaa->aaa, áaa...)
    }
    return _DiacriticResult.notDiacritic;
  }

  /// Đếm số lần phím nguyên âm [lower] được gõ trong "run" nguyên âm cuối của
  /// [_rawKeys] — bỏ qua phím-thanh (s f r x j z) xen giữa, dừng khi gặp nguyên
  /// âm KHÁC hoặc phụ âm. Vd "casa" -> 2; "asaa" -> 3.
  int _trailingVowelPressCount(String lower) {
    const toneKeys = {'s', 'f', 'r', 'x', 'j', 'z'};
    var n = 0;
    for (var i = _rawKeys.length - 1; i >= 0; i--) {
      final k = _rawKeys[i].toLowerCase();
      if (k == lower) {
        n++;
        continue;
      }
      if (toneKeys.contains(k)) continue; // phím-thanh không phá run
      break; // nguyên âm khác / phụ âm -> dừng
    }
    return n;
  }

  _DiacriticResult _applyVNI(String ch) {
    switch (ch) {
      case '1':
        return _setTone(Tone.acute);
      case '2':
        return _setTone(Tone.grave);
      case '3':
        return _setTone(Tone.hook);
      case '4':
        return _setTone(Tone.tilde);
      case '5':
        return _setTone(Tone.dot);
      case '0':
        return _setTone(Tone.none);
      case '6':
        return _setMarkOrToggle(Mark.circumflex); // â/ê/ô
      case '7':
        return _applyHornVNI(); // VNI horn: ơ/ư/ươ/ưa
      case '8':
        return _setMarkOrToggle(Mark.breve); // ă
      case '9':
        return _setMarkOrToggle(Mark.dyet); // đ
      default:
        return _DiacriticResult.notDiacritic;
    }
  }

  /// w trong Telex: a->ă, o->ơ, u->ư.
  /// Trường hợp đặc biệt: cụm "uo" -> "ươ" — móc CẢ HAI nguyên âm,
  /// vì "ươ" là một nguyên âm đôi (nướng, được, thương).
  _DiacriticResult _applyHornOrBreve() {
    final n = _syllable.letters.length;

    // "uo" + w -> "ươ": áp móc cho cả u và o.
    if (n >= 2 &&
        _syllable.letters[n - 2].base.toLowerCase() == 'u' &&
        _syllable.letters[n - 1].base.toLowerCase() == 'o') {
      final isPartOfQu = n >= 3 && _syllable.letters[n - 3].base.toLowerCase() == 'q';
      if (!isPartOfQu) {
        final isThuo = n >= 4 &&
            _syllable.letters[n - 4].base.toLowerCase() == 't' &&
            _syllable.letters[n - 3].base.toLowerCase() == 'h';
        if (isThuo) {
          if (_syllable.letters[n - 1].mark == Mark.horn) {
            _syllable.letters[n - 1].mark = Mark.none;
            return _DiacriticResult.cancelled;
          }
          _syllable.letters[n - 1].mark = Mark.horn;
          return _DiacriticResult.applied;
        }

        // Gõ lại w khi đã là "ươ" -> bỏ móc cả hai.
        if (_syllable.letters[n - 1].mark == Mark.horn &&
            _syllable.letters[n - 2].mark == Mark.horn) {
          _syllable.letters[n - 2].mark = Mark.none;
          _syllable.letters[n - 1].mark = Mark.none;
          return _DiacriticResult.cancelled;
        }
        _syllable.letters[n - 2].mark = Mark.horn;
        _syllable.letters[n - 1].mark = Mark.horn;
        return _DiacriticResult.applied;
      }
    }

    // "ua" + w -> "ưa": áp móc cho u.
    if (n >= 2 &&
        _syllable.letters[n - 2].base.toLowerCase() == 'u' &&
        _syllable.letters[n - 1].base.toLowerCase() == 'a') {
      final isPartOfQu = n >= 3 && _syllable.letters[n - 3].base.toLowerCase() == 'q';
      if (!isPartOfQu) {
        // Gõ lại w khi đã là "ưa" -> bỏ móc u.
        if (_syllable.letters[n - 2].mark == Mark.horn) {
          _syllable.letters[n - 2].mark = Mark.none;
          return _DiacriticResult.cancelled;
        }
        _syllable.letters[n - 2].mark = Mark.horn;
        return _DiacriticResult.applied;
      }
    }

    if (!_syllable.isEmpty) {
      final last = _syllable.letters.last;
      switch (last.base.toLowerCase()) {
        case 'a':
          return last.mark == Mark.breve
              ? _removeMarkOnLast()
              : _setMarkOnLast(Mark.breve);
        case 'o':
        case 'u':
          return last.mark == Mark.horn
              ? _removeMarkOnLast()
              : _setMarkOnLast(Mark.horn);
      }
    }

    // GÕ TẮT 'w' -> 'ư': khi 'w' không áp được móc/trăng cho chữ cuối (chữ cuối
    // không phải a/o/u, hoặc âm tiết chưa có nguyên âm), 'w' tự tạo nguyên âm 'ư'.
    // Ví dụ: "tw"->tư, "mwf"->mừ, "w"->ư. Đây là cách gõ tắt Telex phổ biến.
    // Ngoại lệ: nếu chữ NGAY TRƯỚC thuộc nhóm không-ghép-được thì 'w' giữ thô.
    // (Nhóm chữ không ghép 'w': w e y f j k z.)
    if (!_syllable.isEmpty) {
      final prev = _syllable.letters.last.base.toLowerCase();
      const standaloneWBad = {'w', 'e', 'y', 'f', 'j', 'k', 'z'};
      if (standaloneWBad.contains(prev)) {
        return _DiacriticResult.notDiacritic;
      }
    }
    // Chèn 'u' mang móc -> hiển thị 'ư'.
    _syllable.letters.add(_Letter('u', mark: Mark.horn));
    return _DiacriticResult.applied;
  }

  /// 7 trong VNI: o->ơ, u->ư.
  /// Trường hợp đặc biệt: cụm "uo" -> "ươ" — móc CẢ HAI nguyên âm,
  /// và cụm "ua" -> "ưa" — móc u.
  _DiacriticResult _applyHornVNI() {
    final n = _syllable.letters.length;

    // "uo" + 7 -> "ươ": áp móc cho cả u và o.
    if (n >= 2 &&
        _syllable.letters[n - 2].base.toLowerCase() == 'u' &&
        _syllable.letters[n - 1].base.toLowerCase() == 'o') {
      final isPartOfQu = n >= 3 && _syllable.letters[n - 3].base.toLowerCase() == 'q';
      if (!isPartOfQu) {
        final isThuo = n >= 4 &&
            _syllable.letters[n - 4].base.toLowerCase() == 't' &&
            _syllable.letters[n - 3].base.toLowerCase() == 'h';
        if (isThuo) {
          if (_syllable.letters[n - 1].mark == Mark.horn) {
            _syllable.letters[n - 1].mark = Mark.none;
            return _DiacriticResult.cancelled;
          }
          _syllable.letters[n - 1].mark = Mark.horn;
          return _DiacriticResult.applied;
        }

        if (_syllable.letters[n - 1].mark == Mark.horn &&
            _syllable.letters[n - 2].mark == Mark.horn) {
          _syllable.letters[n - 2].mark = Mark.none;
          _syllable.letters[n - 1].mark = Mark.none;
          return _DiacriticResult.cancelled;
        }
        _syllable.letters[n - 2].mark = Mark.horn;
        _syllable.letters[n - 1].mark = Mark.horn;
        return _DiacriticResult.applied;
      }
    }

    // "ua" + 7 -> "ưa": áp móc cho u.
    if (n >= 2 &&
        _syllable.letters[n - 2].base.toLowerCase() == 'u' &&
        _syllable.letters[n - 1].base.toLowerCase() == 'a') {
      final isPartOfQu = n >= 3 && _syllable.letters[n - 3].base.toLowerCase() == 'q';
      if (!isPartOfQu) {
        if (_syllable.letters[n - 2].mark == Mark.horn) {
          _syllable.letters[n - 2].mark = Mark.none;
          return _DiacriticResult.cancelled;
        }
        _syllable.letters[n - 2].mark = Mark.horn;
        return _DiacriticResult.applied;
      }
    }

    if (!_syllable.isEmpty) {
      final last = _syllable.letters.last;
      switch (last.base.toLowerCase()) {
        case 'o':
        case 'u':
          return last.mark == Mark.horn
              ? _removeMarkOnLast()
              : _setMarkOnLast(Mark.horn);
      }
    }

    return _DiacriticResult.notDiacritic;
  }

  // MARK: - Thao tác trên âm tiết

  /// Âm tiết hiện tại đã chứa ít nhất một nguyên âm chưa?
  bool _hasVowel() => _syllable.letters.any((l) => _isVietVowel(l.base));

  _DiacriticResult _setTone(Tone tone) {
    // Dấu thanh chỉ hợp lệ khi âm tiết ĐÃ CÓ ÍT NHẤT MỘT NGUYÊN ÂM.
    // Nếu không, phím-dấu (s f r x j z) chỉ là phụ âm thường — ví dụ chữ 'r'
    // trong "tre"/"trên", chữ 's' trong "sai", 'x' trong "xin".
    // Không có guard này, gõ "tre" sẽ thành "tẻ" và "trên" thành "tển" vì 'r'
    // bị nuốt làm dấu hỏi dù âm tiết mới chỉ có phụ âm 't'.
    if (!_hasVowel()) return _DiacriticResult.notDiacritic;

    // GÕ LẠI ĐỂ BỎ/ĐỔI DẤU THANH:
    if (_syllable.tone == tone && tone != Tone.none) {
      // Gõ đúng dấu đang có -> GỠ dấu, trả ký tự thô (hoá + s -> hoas).
      _syllable.tone = Tone.none;
      return _DiacriticResult.cancelled;
    }
    // Khác dấu (hoặc 'z' xoá dấu) -> đặt/thay dấu mới.
    _syllable.tone = tone;
    return _DiacriticResult.applied;
  }

  _DiacriticResult _setMarkOnLast(Mark mark) {
    if (_syllable.letters.isEmpty) return _DiacriticResult.notDiacritic;
    final last = _syllable.letters.last;
    // Kiểm tra mark có hợp lệ cho chữ cái này không (tra bảng).
    if (composeViet(last.base, mark, Tone.none) == null) {
      return _DiacriticResult.notDiacritic;
    }
    last.mark = mark;
    return _DiacriticResult.applied;
  }

  /// Như [_setMarkOnLast] nhưng nếu chữ cuối ĐÃ mang đúng biến âm đó thì GỠ ra
  /// và trả ký tự thô — dùng cho VNI khi gõ lại số-biến-âm trùng để hủy.
  /// Ví dụ a6→â, a66→a6 (mũ bị gỡ, số '6' hiện ra); d9→đ, d99→d9.
  /// Cơ chế toggle: gõ lại số-biến-âm trùng thì gỡ dấu rồi chèn phím thô.
  _DiacriticResult _setMarkOrToggle(Mark mark) {
    if (_syllable.letters.isEmpty) return _DiacriticResult.notDiacritic;
    if (_syllable.letters.last.mark == mark) {
      return _removeMarkOnLast(); // gõ lại số-biến-âm trùng -> gỡ + ký tự số thô
    }
    return _setMarkOnLast(mark);
  }

  /// Gỡ dấu biến âm của chữ cái cuối (dùng khi gõ lại trùng biến âm: aa+a, ow+w...).
  _DiacriticResult _removeMarkOnLast() {
    if (_syllable.letters.isEmpty) return _DiacriticResult.notDiacritic;
    _syllable.letters.last.mark = Mark.none;
    return _DiacriticResult.cancelled;
  }

  // MARK: - Render

  /// Dựng chuỗi hiển thị của âm tiết, đặt dấu thanh lên nguyên âm phù hợp.
  String _render() {
    final toneIndex = _toneTargetIndex();
    final out = StringBuffer();
    for (var i = 0; i < _syllable.letters.length; i++) {
      final letter = _syllable.letters[i];
      final tone = (i == toneIndex) ? _syllable.tone : Tone.none;
      final composed = composeViet(letter.base, letter.mark, tone);
      out.write(composed ?? letter.base);
    }
    return out.toString();
  }

  /// Chọn nguyên âm để đặt dấu thanh — theo QUY TẮC CHÍNH TẢ tiếng Việt.
  ///
  /// Vị trí dấu thanh KHÔNG cố định mà phụ thuộc vào "cụm nguyên âm" và việc
  /// có phụ âm cuối hay không. Ta rút gọn thành các luật ưu tiên:
  ///
  ///   1. Nguyên âm nào MANG DẤU biến âm (â ê ô ơ ư ă) thì dấu thanh đặt lên đó.
  ///   2. Nếu cụm có phụ âm cuối -> dấu đặt lên nguyên âm CUỐI của cụm.
  ///   3. Cụm nguyên âm hở (không phụ âm cuối):
  ///        - 2 nguyên âm: đặt lên nguyên âm ĐẦU, TRỪ các đuôi mở
  ///          "oa/oe/uy" thì đặt lên nguyên âm SAU (hoà, quý, khoẻ).
  ///        - 3 nguyên âm (oai, uây, uyê...): đặt lên nguyên âm GIỮA.
  ///   4. 1 nguyên âm: đặt lên chính nó.
  int _toneTargetIndex() {
    // Luật 1: ưu tiên nguyên âm có dấu biến âm.
    for (var i = _syllable.letters.length - 1; i >= 0; i--) {
      final m = _syllable.letters[i].mark;
      if (m == Mark.circumflex || m == Mark.breve || m == Mark.horn) {
        return i;
      }
    }

    // Tìm cụm nguyên âm liên tiếp [start...end].
    var vowelIdx = <int>[];
    for (var i = 0; i < _syllable.letters.length; i++) {
      if (_isVietVowel(_syllable.letters[i].base)) vowelIdx.add(i);
    }
    if (vowelIdx.isEmpty) return -1;

    // KÉO DÀI NGUYÊN ÂM: gộp các nguyên âm TRÙNG nhau liên tiếp về một đại diện
    // (giữ ký tự ĐẦU — dấu thuộc về nguyên âm gốc). Nhờ vậy "oiii" tính như "oi"
    // khi đặt dấu (chòiiii, không phải choìiii); diphthong thật (oa, uy, ươ) không
    // bị ảnh hưởng vì các chữ khác nhau.
    if (vowelIdx.length >= 2) {
      final collapsed = <int>[];
      for (final idx in vowelIdx) {
        if (collapsed.isNotEmpty &&
            _syllable.letters[collapsed.last].base.toLowerCase() ==
                _syllable.letters[idx].base.toLowerCase()) {
          continue; // cùng nguyên âm với cái trước -> bỏ (kéo dài)
        }
        collapsed.add(idx);
      }
      vowelIdx = collapsed;
    }

    // "qu" và "gi": chữ 'u' sau 'q' và chữ 'i' sau 'g' KHÔNG phải nguyên âm chính
    // mà là một phần của phụ âm đầu. Loại nó khỏi cụm tính dấu — NHƯNG chỉ khi
    // cụm còn nguyên âm khác phía sau (vd "quà"->dấu lên a, "già"->lên a). Nếu nó
    // là nguyên âm DUY NHẤT thì giữ lại để nhận dấu ("gì", "qù").
    // Quy tắc chính tả: "gi"/"qu" — 'i'/'u' là bán phụ âm của phụ âm đầu.
    if (vowelIdx.length >= 2) {
      final first = vowelIdx.first;
      final firstBase = _syllable.letters[first].base.toLowerCase();
      final prevBase = first > 0
          ? _syllable.letters[first - 1].base.toLowerCase()
          : '';
      if ((firstBase == 'i' && prevBase == 'g') ||
          (firstBase == 'u' && prevBase == 'q')) {
        vowelIdx.removeAt(0);
      }
    }

    final start = vowelIdx.first;
    final end = vowelIdx.last;
    final count = vowelIdx.length;

    // Có phụ âm sau cụm nguyên âm không?
    final hasFinalConsonant = (end + 1 < _syllable.letters.length) &&
        !_isVietVowel(_syllable.letters[end + 1].base);

    // Luật 2: có phụ âm cuối -> dấu lên nguyên âm cuối của cụm.
    if (hasFinalConsonant) return end;

    // Cụm nguyên âm hở:
    switch (count) {
      case 1:
        return start; // luật 4
      case 2:
        // luật 3: mặc định lên nguyên âm đầu, trừ "oa/oe/uy" -> lên sau.
        // Ở chế độ "old", các đuôi mở này vẫn đặt dấu lên nguyên âm đầu.
        if (toneStyle == ToneStyle.old) return start;
        final a = _syllable.letters[start].base.toLowerCase();
        final b = _syllable.letters[end].base.toLowerCase();
        final openTail =
            (a == 'o' && (b == 'a' || b == 'e')) || (a == 'u' && b == 'y');
        return openTail ? end : start;
      default:
        // luật 3: 3 nguyên âm -> nguyên âm giữa.
        return vowelIdx[1];
    }
  }
}

// MARK: - Helpers ký tự

bool _isLetter(String ch) => RegExp(r'^[a-zA-Z]$').hasMatch(ch);
bool _isDigit(String ch) => RegExp(r'^[0-9]$').hasMatch(ch);
bool _isVietVowel(String ch) => 'aeiouy'.contains(ch.toLowerCase());
