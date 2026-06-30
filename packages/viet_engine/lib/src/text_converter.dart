// text_converter.dart
// -------------------
// CÔNG CỤ CHUYỂN MÃ / BIẾN ĐỔI VĂN BẢN tiếng Việt (port từ TextConverter.swift).
// Thuần xử lý chuỗi -> dùng được trong app Flutter (UI công cụ chuyển mã).
//
// Hỗ trợ:
//   • Bỏ dấu:      "Tiếng Việt" -> "Tieng Viet"
//   • Hoa/thường:  ALL CAPS / all lower / Hoa Đầu Câu / Hoa Mỗi Từ
//   • NFC <-> NFD: Unicode dựng sẵn <-> tổ hợp
//   • TCVN3 / VNI-Windows (bảng mã cũ) <-> Unicode

/// Bảng mã đích/nguồn.
enum CodeTable { unicode, tcvn3, vniWindows }

/// Kiểu đổi hoa/thường.
enum LetterCase { allUpper, allLower, capitalizeFirst, capitalizeWords }

class TextConverter {
  TextConverter._();

  /// Unicode -> unicodeToTcvn: 134 ký tự (chuẩn bảng mã TCVN3).
  static const Map<String, String> unicodeToTcvn = {
    '\u{C0}': '\u{B5}',
    '\u{C1}': '\u{B8}',
    '\u{C2}': '\u{A2}',
    '\u{C3}': '\u{B7}',
    '\u{C8}': '\u{CC}',
    '\u{C9}': '\u{D0}',
    '\u{CA}': '\u{A3}',
    '\u{CC}': '\u{D7}',
    '\u{CD}': '\u{DD}',
    '\u{D2}': '\u{DF}',
    '\u{D3}': '\u{E3}',
    '\u{D4}': '\u{A4}',
    '\u{D5}': '\u{E2}',
    '\u{D9}': '\u{EF}',
    '\u{DA}': '\u{F3}',
    '\u{DD}': '\u{FD}',
    '\u{E0}': '\u{B5}',
    '\u{E1}': '\u{B8}',
    '\u{E2}': '\u{A9}',
    '\u{E3}': '\u{B7}',
    '\u{E8}': '\u{CC}',
    '\u{E9}': '\u{D0}',
    '\u{EA}': '\u{AA}',
    '\u{EC}': '\u{D7}',
    '\u{ED}': '\u{DD}',
    '\u{F2}': '\u{DF}',
    '\u{F3}': '\u{E3}',
    '\u{F4}': '\u{AB}',
    '\u{F5}': '\u{E2}',
    '\u{F9}': '\u{EF}',
    '\u{FA}': '\u{F3}',
    '\u{FD}': '\u{FD}',
    '\u{102}': '\u{A1}',
    '\u{103}': '\u{A8}',
    '\u{110}': '\u{A7}',
    '\u{111}': '\u{AE}',
    '\u{128}': '\u{DC}',
    '\u{129}': '\u{DC}',
    '\u{168}': '\u{F2}',
    '\u{169}': '\u{F2}',
    '\u{1A0}': '\u{A5}',
    '\u{1A1}': '\u{AC}',
    '\u{1AF}': '\u{A6}',
    '\u{1B0}': '\u{AD}',
    '\u{1EA0}': '\u{B9}',
    '\u{1EA1}': '\u{B9}',
    '\u{1EA2}': '\u{B6}',
    '\u{1EA3}': '\u{B6}',
    '\u{1EA4}': '\u{CA}',
    '\u{1EA5}': '\u{CA}',
    '\u{1EA6}': '\u{C7}',
    '\u{1EA7}': '\u{C7}',
    '\u{1EA8}': '\u{C8}',
    '\u{1EA9}': '\u{C8}',
    '\u{1EAA}': '\u{C9}',
    '\u{1EAB}': '\u{C9}',
    '\u{1EAC}': '\u{CB}',
    '\u{1EAD}': '\u{CB}',
    '\u{1EAE}': '\u{BE}',
    '\u{1EAF}': '\u{BE}',
    '\u{1EB0}': '\u{BB}',
    '\u{1EB1}': '\u{BB}',
    '\u{1EB2}': '\u{BC}',
    '\u{1EB3}': '\u{BC}',
    '\u{1EB4}': '\u{BD}',
    '\u{1EB5}': '\u{BD}',
    '\u{1EB6}': '\u{C6}',
    '\u{1EB7}': '\u{C6}',
    '\u{1EB8}': '\u{D1}',
    '\u{1EB9}': '\u{D1}',
    '\u{1EBA}': '\u{CE}',
    '\u{1EBB}': '\u{CE}',
    '\u{1EBC}': '\u{CF}',
    '\u{1EBD}': '\u{CF}',
    '\u{1EBE}': '\u{D5}',
    '\u{1EBF}': '\u{D5}',
    '\u{1EC0}': '\u{D2}',
    '\u{1EC1}': '\u{D2}',
    '\u{1EC2}': '\u{D3}',
    '\u{1EC3}': '\u{D3}',
    '\u{1EC4}': '\u{D4}',
    '\u{1EC5}': '\u{D4}',
    '\u{1EC6}': '\u{D6}',
    '\u{1EC7}': '\u{D6}',
    '\u{1EC8}': '\u{D8}',
    '\u{1EC9}': '\u{D8}',
    '\u{1ECA}': '\u{DE}',
    '\u{1ECB}': '\u{DE}',
    '\u{1ECC}': '\u{E4}',
    '\u{1ECD}': '\u{E4}',
    '\u{1ECE}': '\u{E1}',
    '\u{1ECF}': '\u{E1}',
    '\u{1ED0}': '\u{E8}',
    '\u{1ED1}': '\u{E8}',
    '\u{1ED2}': '\u{E5}',
    '\u{1ED3}': '\u{E5}',
    '\u{1ED4}': '\u{E6}',
    '\u{1ED5}': '\u{E6}',
    '\u{1ED6}': '\u{E7}',
    '\u{1ED7}': '\u{E7}',
    '\u{1ED8}': '\u{E9}',
    '\u{1ED9}': '\u{E9}',
    '\u{1EDA}': '\u{ED}',
    '\u{1EDB}': '\u{ED}',
    '\u{1EDC}': '\u{EA}',
    '\u{1EDD}': '\u{EA}',
    '\u{1EDE}': '\u{EB}',
    '\u{1EDF}': '\u{EB}',
    '\u{1EE0}': '\u{EC}',
    '\u{1EE1}': '\u{EC}',
    '\u{1EE2}': '\u{EE}',
    '\u{1EE3}': '\u{EE}',
    '\u{1EE4}': '\u{F4}',
    '\u{1EE5}': '\u{F4}',
    '\u{1EE6}': '\u{F1}',
    '\u{1EE7}': '\u{F1}',
    '\u{1EE8}': '\u{F8}',
    '\u{1EE9}': '\u{F8}',
    '\u{1EEA}': '\u{F5}',
    '\u{1EEB}': '\u{F5}',
    '\u{1EEC}': '\u{F6}',
    '\u{1EED}': '\u{F6}',
    '\u{1EEE}': '\u{F7}',
    '\u{1EEF}': '\u{F7}',
    '\u{1EF0}': '\u{F9}',
    '\u{1EF1}': '\u{F9}',
    '\u{1EF2}': '\u{FA}',
    '\u{1EF3}': '\u{FA}',
    '\u{1EF4}': '\u{FE}',
    '\u{1EF5}': '\u{FE}',
    '\u{1EF6}': '\u{FB}',
    '\u{1EF7}': '\u{FB}',
    '\u{1EF8}': '\u{FC}',
    '\u{1EF9}': '\u{FC}',
  };

  /// Unicode -> unicodeToVni: 134 ký tự (chuẩn bảng mã VNI-Windows).
  static const Map<String, String> unicodeToVni = {
    '\u{C0}': '\u{41}\u{D8}',
    '\u{C1}': '\u{41}\u{D9}',
    '\u{C2}': '\u{41}\u{C2}',
    '\u{C3}': '\u{41}\u{D5}',
    '\u{C8}': '\u{45}\u{D8}',
    '\u{C9}': '\u{45}\u{D9}',
    '\u{CA}': '\u{45}\u{C2}',
    '\u{CC}': '\u{CC}',
    '\u{CD}': '\u{CD}',
    '\u{D2}': '\u{4F}\u{D8}',
    '\u{D3}': '\u{4F}\u{D9}',
    '\u{D4}': '\u{4F}\u{C2}',
    '\u{D5}': '\u{4F}\u{D5}',
    '\u{D9}': '\u{55}\u{D8}',
    '\u{DA}': '\u{55}\u{D9}',
    '\u{DD}': '\u{59}\u{D9}',
    '\u{E0}': '\u{61}\u{F8}',
    '\u{E1}': '\u{61}\u{F9}',
    '\u{E2}': '\u{61}\u{E2}',
    '\u{E3}': '\u{61}\u{F5}',
    '\u{E8}': '\u{65}\u{F8}',
    '\u{E9}': '\u{65}\u{F9}',
    '\u{EA}': '\u{65}\u{E2}',
    '\u{EC}': '\u{EC}',
    '\u{ED}': '\u{ED}',
    '\u{F2}': '\u{6F}\u{F8}',
    '\u{F3}': '\u{6F}\u{F9}',
    '\u{F4}': '\u{6F}\u{E2}',
    '\u{F5}': '\u{6F}\u{F5}',
    '\u{F9}': '\u{75}\u{F8}',
    '\u{FA}': '\u{75}\u{F9}',
    '\u{FD}': '\u{79}\u{F9}',
    '\u{102}': '\u{41}\u{CA}',
    '\u{103}': '\u{61}\u{EA}',
    '\u{110}': '\u{D1}',
    '\u{111}': '\u{F1}',
    '\u{128}': '\u{D3}',
    '\u{129}': '\u{F3}',
    '\u{168}': '\u{55}\u{D5}',
    '\u{169}': '\u{75}\u{F5}',
    '\u{1A0}': '\u{D4}',
    '\u{1A1}': '\u{F4}',
    '\u{1AF}': '\u{D6}',
    '\u{1B0}': '\u{F6}',
    '\u{1EA0}': '\u{41}\u{CF}',
    '\u{1EA1}': '\u{61}\u{EF}',
    '\u{1EA2}': '\u{41}\u{DB}',
    '\u{1EA3}': '\u{61}\u{FB}',
    '\u{1EA4}': '\u{41}\u{C1}',
    '\u{1EA5}': '\u{61}\u{E1}',
    '\u{1EA6}': '\u{41}\u{C0}',
    '\u{1EA7}': '\u{61}\u{E0}',
    '\u{1EA8}': '\u{41}\u{C5}',
    '\u{1EA9}': '\u{61}\u{E5}',
    '\u{1EAA}': '\u{41}\u{C3}',
    '\u{1EAB}': '\u{61}\u{E3}',
    '\u{1EAC}': '\u{41}\u{C4}',
    '\u{1EAD}': '\u{61}\u{E4}',
    '\u{1EAE}': '\u{41}\u{C9}',
    '\u{1EAF}': '\u{61}\u{E9}',
    '\u{1EB0}': '\u{41}\u{C8}',
    '\u{1EB1}': '\u{61}\u{E8}',
    '\u{1EB2}': '\u{41}\u{DA}',
    '\u{1EB3}': '\u{61}\u{FA}',
    '\u{1EB4}': '\u{41}\u{DC}',
    '\u{1EB5}': '\u{61}\u{FC}',
    '\u{1EB6}': '\u{41}\u{CB}',
    '\u{1EB7}': '\u{61}\u{EB}',
    '\u{1EB8}': '\u{45}\u{CF}',
    '\u{1EB9}': '\u{65}\u{EF}',
    '\u{1EBA}': '\u{45}\u{DB}',
    '\u{1EBB}': '\u{65}\u{FB}',
    '\u{1EBC}': '\u{45}\u{D5}',
    '\u{1EBD}': '\u{65}\u{F5}',
    '\u{1EBE}': '\u{45}\u{C1}',
    '\u{1EBF}': '\u{65}\u{E1}',
    '\u{1EC0}': '\u{45}\u{C0}',
    '\u{1EC1}': '\u{65}\u{E0}',
    '\u{1EC2}': '\u{45}\u{C5}',
    '\u{1EC3}': '\u{65}\u{E5}',
    '\u{1EC4}': '\u{45}\u{C3}',
    '\u{1EC5}': '\u{65}\u{E3}',
    '\u{1EC6}': '\u{45}\u{C4}',
    '\u{1EC7}': '\u{65}\u{E4}',
    '\u{1EC8}': '\u{C6}',
    '\u{1EC9}': '\u{E6}',
    '\u{1ECA}': '\u{D2}',
    '\u{1ECB}': '\u{F2}',
    '\u{1ECC}': '\u{4F}\u{CF}',
    '\u{1ECD}': '\u{6F}\u{EF}',
    '\u{1ECE}': '\u{4F}\u{DB}',
    '\u{1ECF}': '\u{6F}\u{FB}',
    '\u{1ED0}': '\u{4F}\u{C1}',
    '\u{1ED1}': '\u{6F}\u{E1}',
    '\u{1ED2}': '\u{4F}\u{C0}',
    '\u{1ED3}': '\u{6F}\u{E0}',
    '\u{1ED4}': '\u{4F}\u{C5}',
    '\u{1ED5}': '\u{6F}\u{E5}',
    '\u{1ED6}': '\u{4F}\u{C3}',
    '\u{1ED7}': '\u{6F}\u{E3}',
    '\u{1ED8}': '\u{4F}\u{C4}',
    '\u{1ED9}': '\u{6F}\u{E4}',
    '\u{1EDA}': '\u{D4}\u{D9}',
    '\u{1EDB}': '\u{F4}\u{F9}',
    '\u{1EDC}': '\u{D4}\u{D8}',
    '\u{1EDD}': '\u{F4}\u{F8}',
    '\u{1EDE}': '\u{D4}\u{DB}',
    '\u{1EDF}': '\u{F4}\u{FB}',
    '\u{1EE0}': '\u{D4}\u{D5}',
    '\u{1EE1}': '\u{F4}\u{F5}',
    '\u{1EE2}': '\u{D4}\u{CF}',
    '\u{1EE3}': '\u{F4}\u{EF}',
    '\u{1EE4}': '\u{55}\u{CF}',
    '\u{1EE5}': '\u{75}\u{EF}',
    '\u{1EE6}': '\u{55}\u{DB}',
    '\u{1EE7}': '\u{75}\u{FB}',
    '\u{1EE8}': '\u{D6}\u{D9}',
    '\u{1EE9}': '\u{F6}\u{F9}',
    '\u{1EEA}': '\u{D6}\u{D8}',
    '\u{1EEB}': '\u{F6}\u{F8}',
    '\u{1EEC}': '\u{D6}\u{DB}',
    '\u{1EED}': '\u{F6}\u{FB}',
    '\u{1EEE}': '\u{D6}\u{D5}',
    '\u{1EEF}': '\u{F6}\u{F5}',
    '\u{1EF0}': '\u{D6}\u{CF}',
    '\u{1EF1}': '\u{F6}\u{EF}',
    '\u{1EF2}': '\u{59}\u{D8}',
    '\u{1EF3}': '\u{79}\u{F8}',
    '\u{1EF4}': '\u{CE}',
    '\u{1EF5}': '\u{EE}',
    '\u{1EF6}': '\u{59}\u{DB}',
    '\u{1EF7}': '\u{79}\u{FB}',
    '\u{1EF8}': '\u{59}\u{D5}',
    '\u{1EF9}': '\u{79}\u{F5}',
  };

  // ── Bảng đảo (sinh từ map thuận) ──────────────────────────────────────────

  /// TCVN3 -> Unicode. TCVN3 chung 1 byte cho HOA/thường nguyên âm có dấu nên
  /// đảo bị mất hoa (ưu tiên trả thường) — tính chất bảng mã, không phải lỗi.
  static final Map<String, String> _tcvnToUnicode = () {
    final m = <String, String>{};
    unicodeToTcvn.forEach((uni, legacy) {
      if (legacy.length != 1) return;
      final existing = m[legacy];
      if (existing == null) {
        m[legacy] = uni;
      } else if (_isUpper(existing) && _isLower(uni)) {
        m[legacy] = uni; // giữ bản thường
      }
    });
    return m;
  }();

  /// VNI-Windows -> Unicode (token 1-2 ký tự, đảo trực tiếp).
  static final Map<String, String> _vniToUnicode = () {
    final m = <String, String>{};
    unicodeToVni.forEach((uni, legacy) => m[legacy] = uni);
    return m;
  }();

  // ── Bỏ dấu ────────────────────────────────────────────────────────────────

  /// Bản đồ nguyên âm tiếng Việt (dựng sẵn) -> chữ Latin cơ bản.
  static const Map<String, String> _stripMap = {
    'à': 'a', 'á': 'a', 'ả': 'a', 'ã': 'a', 'ạ': 'a',
    'ă': 'a', 'ằ': 'a', 'ắ': 'a', 'ẳ': 'a', 'ẵ': 'a', 'ặ': 'a',
    'â': 'a', 'ầ': 'a', 'ấ': 'a', 'ẩ': 'a', 'ẫ': 'a', 'ậ': 'a',
    'è': 'e', 'é': 'e', 'ẻ': 'e', 'ẽ': 'e', 'ẹ': 'e',
    'ê': 'e', 'ề': 'e', 'ế': 'e', 'ể': 'e', 'ễ': 'e', 'ệ': 'e',
    'ì': 'i', 'í': 'i', 'ỉ': 'i', 'ĩ': 'i', 'ị': 'i',
    'ò': 'o', 'ó': 'o', 'ỏ': 'o', 'õ': 'o', 'ọ': 'o',
    'ô': 'o', 'ồ': 'o', 'ố': 'o', 'ổ': 'o', 'ỗ': 'o', 'ộ': 'o',
    'ơ': 'o', 'ờ': 'o', 'ớ': 'o', 'ở': 'o', 'ỡ': 'o', 'ợ': 'o',
    'ù': 'u', 'ú': 'u', 'ủ': 'u', 'ũ': 'u', 'ụ': 'u',
    'ư': 'u', 'ừ': 'u', 'ứ': 'u', 'ử': 'u', 'ữ': 'u', 'ự': 'u',
    'ỳ': 'y', 'ý': 'y', 'ỷ': 'y', 'ỹ': 'y', 'ỵ': 'y',
    'đ': 'd',
    'À': 'A', 'Á': 'A', 'Ả': 'A', 'Ã': 'A', 'Ạ': 'A',
    'Ă': 'A', 'Ằ': 'A', 'Ắ': 'A', 'Ẳ': 'A', 'Ẵ': 'A', 'Ặ': 'A',
    'Â': 'A', 'Ầ': 'A', 'Ấ': 'A', 'Ẩ': 'A', 'Ẫ': 'A', 'Ậ': 'A',
    'È': 'E', 'É': 'E', 'Ẻ': 'E', 'Ẽ': 'E', 'Ẹ': 'E',
    'Ê': 'E', 'Ề': 'E', 'Ế': 'E', 'Ể': 'E', 'Ễ': 'E', 'Ệ': 'E',
    'Ì': 'I', 'Í': 'I', 'Ỉ': 'I', 'Ĩ': 'I', 'Ị': 'I',
    'Ò': 'O', 'Ó': 'O', 'Ỏ': 'O', 'Õ': 'O', 'Ọ': 'O',
    'Ô': 'O', 'Ồ': 'O', 'Ố': 'O', 'Ổ': 'O', 'Ỗ': 'O', 'Ộ': 'O',
    'Ơ': 'O', 'Ờ': 'O', 'Ớ': 'O', 'Ở': 'O', 'Ỡ': 'O', 'Ợ': 'O',
    'Ù': 'U', 'Ú': 'U', 'Ủ': 'U', 'Ũ': 'U', 'Ụ': 'U',
    'Ư': 'U', 'Ừ': 'U', 'Ứ': 'U', 'Ử': 'U', 'Ữ': 'U', 'Ự': 'U',
    'Ỳ': 'Y', 'Ý': 'Y', 'Ỷ': 'Y', 'Ỹ': 'Y', 'Ỵ': 'Y',
    'Đ': 'D',
  };

  /// Bỏ toàn bộ dấu tiếng Việt. Xử lý cả dạng dựng sẵn (tra _stripMap) lẫn dạng
  /// tổ hợp (xoá các dấu kết hợp U+0300..U+0341 + dấu móc U+031B).
  static String removeDiacritics(String text) {
    final buf = StringBuffer();
    for (final ch in text.split('')) {
      final code = ch.codeUnitAt(0);
      // Bỏ qua dấu kết hợp (combining diacritics) của dạng NFD.
      if ((code >= 0x0300 && code <= 0x036F)) continue;
      buf.write(_stripMap[ch] ?? ch);
    }
    return buf.toString();
  }

  // ── Hoa / thường ──────────────────────────────────────────────────────────

  static String changeCase(String text, LetterCase mode) {
    switch (mode) {
      case LetterCase.allUpper:
        return text.toUpperCase();
      case LetterCase.allLower:
        return text.toLowerCase();
      case LetterCase.capitalizeFirst:
        return _capitalize(text, eachWord: false);
      case LetterCase.capitalizeWords:
        return _capitalize(text, eachWord: true);
    }
  }

  static const Set<String> _sentenceBreaks = {'.', '?', '!'};

  static String _capitalize(String text, {required bool eachWord}) {
    final buf = StringBuffer();
    var shouldUpper = true;
    var pendingBreak = false;
    for (final ch in text.split('')) {
      if (_isLetter(ch)) {
        buf.write(shouldUpper ? ch.toUpperCase() : ch.toLowerCase());
        shouldUpper = false;
        pendingBreak = false;
      } else {
        buf.write(ch);
        if (eachWord) {
          if (_isWhitespace(ch)) shouldUpper = true;
        } else {
          if (ch == '\n') {
            shouldUpper = true;
            pendingBreak = false;
          } else if (_sentenceBreaks.contains(ch)) {
            pendingBreak = true;
          } else if (_isWhitespace(ch)) {
            if (pendingBreak) shouldUpper = true;
            pendingBreak = false;
          } else {
            pendingBreak = false;
          }
        }
      }
    }
    return buf.toString();
  }

  // ── Bảng mã cũ: TCVN3 / VNI-Windows ───────────────────────────────────────

  /// Chuyển văn bản giữa hai bảng mã (đi qua trung gian Unicode dựng sẵn).
  static String convert(String text, {required CodeTable from, required CodeTable to}) {
    if (from == to) return text;
    final unicode = _toUnicode(text, from);
    return _fromUnicode(unicode, to);
  }

  static String _toUnicode(String text, CodeTable from) {
    switch (from) {
      case CodeTable.unicode:
        return text;
      case CodeTable.tcvn3:
        final buf = StringBuffer();
        for (final ch in text.split('')) {
          buf.write(_tcvnToUnicode[ch] ?? ch);
        }
        return buf.toString();
      case CodeTable.vniWindows:
        return _decodeVni(text);
    }
  }

  static String _fromUnicode(String text, CodeTable to) {
    switch (to) {
      case CodeTable.unicode:
        return text;
      case CodeTable.tcvn3:
        final buf = StringBuffer();
        for (final ch in text.split('')) {
          buf.write(unicodeToTcvn[ch] ?? ch);
        }
        return buf.toString();
      case CodeTable.vniWindows:
        final buf = StringBuffer();
        for (final ch in text.split('')) {
          buf.write(unicodeToVni[ch] ?? ch);
        }
        return buf.toString();
    }
  }

  /// Giải mã VNI-Windows -> Unicode. Token 1-2 ký tự; quét GREEDY (thử 2 trước).
  static String _decodeVni(String text) {
    final chars = text.split('');
    final buf = StringBuffer();
    var i = 0;
    while (i < chars.length) {
      var matched = false;
      if (i + 1 < chars.length) {
        final two = chars[i] + chars[i + 1];
        final uni = _vniToUnicode[two];
        if (uni != null) {
          buf.write(uni);
          i += 2;
          matched = true;
        }
      }
      if (!matched) {
        buf.write(_vniToUnicode[chars[i]] ?? chars[i]);
        i += 1;
      }
    }
    return buf.toString();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static bool _isLetter(String ch) => ch.toUpperCase() != ch.toLowerCase();
  static bool _isUpper(String ch) => ch == ch.toUpperCase() && ch != ch.toLowerCase();
  static bool _isLower(String ch) => ch == ch.toLowerCase() && ch != ch.toUpperCase();
  static bool _isWhitespace(String ch) => ch.trim().isEmpty && ch.isNotEmpty;
}
