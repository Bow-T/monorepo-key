// macro.dart
// ----------
// GÕ TẮT (macro/snippet) — port từ Macro.swift. Gõ từ khoá ASCII (vd "vn") rồi
// nhấn phím ngắt từ -> thay bằng nội dung. Hỗ trợ nội dung tĩnh + động
// (ngày/giờ/đếm/ngẫu nhiên).

/// Loại nội dung macro.
enum MacroSnippetType { staticText, date, time, dateTime, random, counter }

MacroSnippetType macroSnippetTypeFromString(String? s) {
  switch (s) {
    case 'date':
      return MacroSnippetType.date;
    case 'time':
      return MacroSnippetType.time;
    case 'dateTime':
      return MacroSnippetType.dateTime;
    case 'random':
      return MacroSnippetType.random;
    case 'counter':
      return MacroSnippetType.counter;
    default:
      return MacroSnippetType.staticText;
  }
}

/// Một định nghĩa macro: từ khoá -> nội dung.
class MacroDefinition {
  const MacroDefinition({
    required this.keyword,
    required this.content,
    this.type = MacroSnippetType.staticText,
  });

  final String keyword; // phím thô ASCII kích hoạt, vd "vn"
  final String content; // nội dung (tĩnh) hoặc format/tham số (động)
  final MacroSnippetType type;
}

/// Môi trường tiêm (đồng hồ + random) để test xác định.
class MacroEnvironment {
  const MacroEnvironment({this.now, this.randomIndex, this.clipboard});

  final DateTime Function()? now;
  final int Function(int count)? randomIndex;
  final String Function()? clipboard;
}

/// Kho macro + bộ sinh nội dung động.
class MacroStore {
  MacroStore([List<MacroDefinition> definitions = const [], MacroEnvironment? environment])
      : _env = environment ?? const MacroEnvironment() {
    for (final d in definitions) {
      _byKeyword[d.keyword] = d;
    }
  }

  final Map<String, MacroDefinition> _byKeyword = {};
  final Map<String, int> _counters = {};
  final MacroEnvironment _env;

  bool get isEmpty => _byKeyword.isEmpty;

  void set(MacroDefinition definition) => _byKeyword[definition.keyword] = definition;

  void clear() {
    _byKeyword.clear();
    _counters.clear();
  }

  /// Tra macro theo từ khoá thô. Trả nội dung ĐÃ BUNG (giải động), hoặc null.
  String? expand(String keyword) {
    final def = _byKeyword[keyword];
    if (def == null) return null;
    return _render(def);
  }

  String _render(MacroDefinition def) {
    switch (def.type) {
      case MacroSnippetType.staticText:
        return def.content;
      case MacroSnippetType.date:
        return _formatDateTime(def.content.isEmpty ? 'dd/MM/yyyy' : def.content);
      case MacroSnippetType.time:
        return _formatDateTime(def.content.isEmpty ? 'HH:mm:ss' : def.content);
      case MacroSnippetType.dateTime:
        return _formatDateTime(def.content.isEmpty ? 'dd/MM/yyyy HH:mm' : def.content);
      case MacroSnippetType.random:
        return _randomValue(def.content);
      case MacroSnippetType.counter:
        return _counterValue(def.content);
    }
  }

  /// Bung format ngày giờ dd/MM/yyyy HH:mm:ss (port từ PHTV). Token lặp d/M/y/H/m/s;
  /// lặp >=2 -> đệm 0; yyyy -> năm đủ 4 số.
  String _formatDateTime(String format) {
    const tokens = {'d', 'M', 'y', 'H', 'm', 's'};
    final now = _env.now?.call() ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');

    final buf = StringBuffer();
    String? lastChar;
    var repeatCount = 0;
    void flush() {
      if (lastChar == null || repeatCount == 0) return;
      switch (lastChar) {
        case 'd':
          buf.write(repeatCount >= 2 ? two(now.day) : '${now.day}');
        case 'M':
          buf.write(repeatCount >= 2 ? two(now.month) : '${now.month}');
        case 'y':
          buf.write(repeatCount >= 4 ? '${now.year}' : two(now.year % 100));
        case 'H':
          buf.write(repeatCount >= 2 ? two(now.hour) : '${now.hour}');
        case 'm':
          buf.write(repeatCount >= 2 ? two(now.minute) : '${now.minute}');
        case 's':
          buf.write(repeatCount >= 2 ? two(now.second) : '${now.second}');
        default:
          buf.write(lastChar * repeatCount);
      }
      repeatCount = 0;
    }

    for (final ch in format.split('')) {
      if (ch == lastChar && tokens.contains(ch)) {
        repeatCount++;
      } else {
        flush();
        lastChar = ch;
        repeatCount = 1;
      }
    }
    flush();
    return buf.toString();
  }

  String _randomValue(String list) {
    final items = list
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (items.isEmpty) return list;
    final idx = _env.randomIndex?.call(items.length) ?? 0;
    return items[idx % items.length];
  }

  String _counterValue(String prefix) {
    final next = (_counters[prefix] ?? 0) + 1;
    _counters[prefix] = next;
    return '$prefix$next';
  }
}
