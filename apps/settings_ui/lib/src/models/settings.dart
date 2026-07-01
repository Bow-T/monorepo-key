// settings.dart
// -------------
// Mô hình cấu hình bộ gõ — đây là "hợp đồng" (contract) giữa app UI (Flutter)
// và bộ gõ thật (Swift, macOS). Flutter GHI file JSON này; app Swift ĐỌC nó.
//
// Vì cùng một file JSON được hai ngôn ngữ đọc/ghi, các KHOÁ và GIÁ TRỊ chuỗi ở
// đây phải KHỚP TUYỆT ĐỐI với phía Swift (xem SettingsStore.swift). Đừng đổi tên
// khoá một bên mà quên bên kia.

import 'hotkey.dart';

export 'hotkey.dart';

/// Kiểu gõ: Telex hay VNI. Khớp `InputMethod` của engine Swift/Dart.
enum InputMethod {
  telex,
  vni;

  String get json => name; // "telex" / "vni"

  static InputMethod fromJson(String? v) =>
      InputMethod.values.firstWhere((e) => e.name == v, orElse: () => telex);

  String get label => this == telex ? 'TELEX' : 'VNI';
}

/// Kiểu đặt dấu thanh. Khớp `ToneStyle` của engine.
///   - modern: hoà, quý  (đặt dấu theo quy tắc hiện đại)
///   - old:    hòa, qúy  (kiểu cũ)
enum ToneStyle {
  modern,
  old;

  String get json => name; // "modern" / "old"

  static ToneStyle fromJson(String? v) =>
      ToneStyle.values.firstWhere((e) => e.name == v, orElse: () => modern);

  String get label => this == modern ? 'HIỆN ĐẠI' : 'KIỂU CŨ';
  String get example => this == modern ? 'hoà · quý' : 'hòa · qúy';
}

/// Một định nghĩa gõ tắt (macro): từ khoá thô -> nội dung. Khớp `MacroDefinition`
/// của engine Swift (xem Macro.swift) và khoá JSON "macros".
class MacroEntry {
  const MacroEntry({required this.keyword, required this.content, this.type = 'staticText'});

  final String keyword; // phím thô ASCII, vd "vn"
  final String content; // nội dung thay thế / format
  final String type;    // staticText | date | time | dateTime | random | counter

  MacroEntry copyWith({String? keyword, String? content, String? type}) => MacroEntry(
        keyword: keyword ?? this.keyword,
        content: content ?? this.content,
        type: type ?? this.type,
      );

  Map<String, dynamic> toJson() => {'keyword': keyword, 'content': content, 'type': type};

  factory MacroEntry.fromJson(Map<String, dynamic> j) => MacroEntry(
        keyword: (j['keyword'] as String?) ?? '',
        content: (j['content'] as String?) ?? '',
        type: (j['type'] as String?) ?? 'staticText',
      );
}

/// Một cặp tự-sửa-lỗi: gõ ra `wrong` -> tự thay bằng `right`. Khớp `AutoCorrectPair`
/// phía Swift và khoá JSON "autoCorrectPairs".
class AutoCorrectPair {
  const AutoCorrectPair({required this.wrong, required this.right});

  final String wrong; // từ gõ sai, vd "giừo"
  final String right; // từ đúng, vd "giờ"

  AutoCorrectPair copyWith({String? wrong, String? right}) =>
      AutoCorrectPair(wrong: wrong ?? this.wrong, right: right ?? this.right);

  Map<String, dynamic> toJson() => {'wrong': wrong, 'right': right};

  factory AutoCorrectPair.fromJson(Map<String, dynamic> j) => AutoCorrectPair(
        wrong: (j['wrong'] as String?) ?? '',
        right: (j['right'] as String?) ?? '',
      );
}

/// Toàn bộ cấu hình bộ gõ, gói trong một object để serialize 1 lần.
class BowSettings {
  const BowSettings({
    this.enabled = true,
    this.method = InputMethod.telex,
    this.toneStyle = ToneStyle.modern,
    this.hotkey = Hotkey.defaultToggle,
    this.smartSwitch = false,
    this.perApp = const {},
    this.autoRestoreEnglish = false,
    this.autoCorrect = false,
    this.autoCorrectPairs = const [],
    this.macroEnabled = true,
    this.macros = const [],
    this.clipboardHistoryEnabled = true,
    this.clipboardHistoryLimit = 40,
    this.clipboardHistoryHotkey = Hotkey.defaultClipboard,
  });

  /// Bộ gõ có đang bật không (toggle toàn cục).
  final bool enabled;

  /// Telex / VNI.
  final InputMethod method;

  /// Modern / Old.
  final ToneStyle toneStyle;

  /// Phím tắt bật/tắt nhanh (tuỳ biến, máy đọc được).
  final Hotkey hotkey;

  /// Smart Switch: tự nhớ bật/tắt theo từng app.
  final bool smartSwitch;

  /// Bảng nhớ per-app (bundleId -> enabled) do bộ gõ Swift quản lý. UI KHÔNG sửa
  /// trực tiếp nhưng PHẢI giữ nguyên khi ghi lại file, nếu không sẽ xoá mất bộ nhớ.
  final Map<String, bool> perApp;

  /// Tự khôi phục tiếng Anh (heuristic). Khớp khoá "autoRestoreEnglish".
  final bool autoRestoreEnglish;

  /// Tự sửa lỗi gõ nhanh (dời dấu sai vị trí + từ điển lỗi phổ biến).
  /// Khớp khoá "autoCorrect".
  final bool autoCorrect;

  /// Danh sách cặp (sai -> đúng) người dùng cấu hình. Khớp khoá "autoCorrectPairs".
  final List<AutoCorrectPair> autoCorrectPairs;

  /// Bật/tắt gõ tắt (macro). Khớp khoá "macroEnabled".
  final bool macroEnabled;

  /// Danh sách macro. Khớp khoá "macros".
  final List<MacroEntry> macros;

  /// Bật/tắt lịch sử clipboard.
  final bool clipboardHistoryEnabled;

  /// Số mục tối đa lưu trong lịch sử clipboard.
  final int clipboardHistoryLimit;

  /// Phím tắt mở lịch sử clipboard.
  final Hotkey clipboardHistoryHotkey;

  BowSettings copyWith({
    bool? enabled,
    InputMethod? method,
    ToneStyle? toneStyle,
    Hotkey? hotkey,
    bool? smartSwitch,
    Map<String, bool>? perApp,
    bool? autoRestoreEnglish,
    bool? autoCorrect,
    List<AutoCorrectPair>? autoCorrectPairs,
    bool? macroEnabled,
    List<MacroEntry>? macros,
    bool? clipboardHistoryEnabled,
    int? clipboardHistoryLimit,
    Hotkey? clipboardHistoryHotkey,
  }) {
    return BowSettings(
      enabled: enabled ?? this.enabled,
      method: method ?? this.method,
      toneStyle: toneStyle ?? this.toneStyle,
      hotkey: hotkey ?? this.hotkey,
      smartSwitch: smartSwitch ?? this.smartSwitch,
      perApp: perApp ?? this.perApp,
      autoRestoreEnglish: autoRestoreEnglish ?? this.autoRestoreEnglish,
      autoCorrect: autoCorrect ?? this.autoCorrect,
      autoCorrectPairs: autoCorrectPairs ?? this.autoCorrectPairs,
      macroEnabled: macroEnabled ?? this.macroEnabled,
      macros: macros ?? this.macros,
      clipboardHistoryEnabled: clipboardHistoryEnabled ?? this.clipboardHistoryEnabled,
      clipboardHistoryLimit: clipboardHistoryLimit ?? this.clipboardHistoryLimit,
      clipboardHistoryHotkey: clipboardHistoryHotkey ?? this.clipboardHistoryHotkey,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'method': method.json,
        'toneStyle': toneStyle.json,
        // Hotkey tự ghi 3 khoá: hotkeyKeyCode, hotkeyModifiers, toggleHotkey.
        ...hotkey.toJson(),
        'smartSwitch': smartSwitch,
        'perApp': perApp,
        'autoRestoreEnglish': autoRestoreEnglish,
        'autoCorrect': autoCorrect,
        'autoCorrectPairs': autoCorrectPairs.map((p) => p.toJson()).toList(),
        'macroEnabled': macroEnabled,
        'macros': macros.map((m) => m.toJson()).toList(),
        'clipboardHistoryEnabled': clipboardHistoryEnabled,
        'clipboardHistoryLimit': clipboardHistoryLimit,
        ...clipboardHistoryHotkey.toJsonWithPrefix('clipboardHistoryHotkey'),
      };

  factory BowSettings.fromJson(Map<String, dynamic> j) => BowSettings(
        enabled: j['enabled'] as bool? ?? true,
        method: InputMethod.fromJson(j['method'] as String?),
        toneStyle: ToneStyle.fromJson(j['toneStyle'] as String?),
        hotkey: Hotkey.fromJson(j),
        smartSwitch: j['smartSwitch'] as bool? ?? false,
        perApp: (j['perApp'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), v == true),
            ) ??
            const {},
        autoRestoreEnglish: j['autoRestoreEnglish'] as bool? ?? false,
        autoCorrect: j['autoCorrect'] as bool? ?? false,
        autoCorrectPairs: (j['autoCorrectPairs'] as List?)
                ?.whereType<Map>()
                .map((m) => AutoCorrectPair.fromJson(m.cast<String, dynamic>()))
                .toList() ??
            const [],
        macroEnabled: j['macroEnabled'] as bool? ?? true,
        macros: (j['macros'] as List?)
                ?.whereType<Map>()
                .map((m) => MacroEntry.fromJson(m.cast<String, dynamic>()))
                .toList() ??
            const [],
        clipboardHistoryEnabled: j['clipboardHistoryEnabled'] as bool? ?? true,
        clipboardHistoryLimit: j['clipboardHistoryLimit'] as int? ?? 40,
        clipboardHistoryHotkey: Hotkey.fromJsonWithPrefix(
            j, 'clipboardHistoryHotkey', Hotkey.defaultClipboard),
      );
}
