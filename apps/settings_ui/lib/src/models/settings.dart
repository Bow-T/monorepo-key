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

/// Toàn bộ cấu hình bộ gõ, gói trong một object để serialize 1 lần.
class BowSettings {
  const BowSettings({
    this.enabled = true,
    this.method = InputMethod.telex,
    this.toneStyle = ToneStyle.modern,
    this.hotkey = Hotkey.defaultToggle,
  });

  /// Bộ gõ có đang bật không (toggle toàn cục).
  final bool enabled;

  /// Telex / VNI.
  final InputMethod method;

  /// Modern / Old.
  final ToneStyle toneStyle;

  /// Phím tắt bật/tắt nhanh (tuỳ biến, máy đọc được).
  final Hotkey hotkey;

  BowSettings copyWith({
    bool? enabled,
    InputMethod? method,
    ToneStyle? toneStyle,
    Hotkey? hotkey,
  }) {
    return BowSettings(
      enabled: enabled ?? this.enabled,
      method: method ?? this.method,
      toneStyle: toneStyle ?? this.toneStyle,
      hotkey: hotkey ?? this.hotkey,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'method': method.json,
        'toneStyle': toneStyle.json,
        // Hotkey tự ghi 3 khoá: hotkeyKeyCode, hotkeyModifiers, toggleHotkey.
        ...hotkey.toJson(),
      };

  factory BowSettings.fromJson(Map<String, dynamic> j) => BowSettings(
        enabled: j['enabled'] as bool? ?? true,
        method: InputMethod.fromJson(j['method'] as String?),
        toneStyle: ToneStyle.fromJson(j['toneStyle'] as String?),
        hotkey: Hotkey.fromJson(j),
      );
}
