// viet_table.dart
// ---------------
// Bảng tra: (chữ cái gốc, dấu biến âm, dấu thanh) -> ký tự Unicode tiếng Việt.
//
// Vì sao cần bảng này? Vì tiếng Việt có sẵn các ký tự dựng sẵn (precomposed) trong
// Unicode như "ế", "ữ", "ặ". Engine suy nghĩ theo (gốc + mark + tone) rồi tra ra
// ký tự cuối cùng để "gõ ra màn hình".
//
// Cách đọc bảng: với mỗi nguyên âm có dấu, ta liệt kê 6 biến thể theo 6 thanh,
// theo đúng thứ tự enum Tone: [none, acute, grave, hook, tilde, dot].

import 'viet_model.dart';

/// Mảng 6 biến thể theo thanh [ngang, sắc, huyền, hỏi, ngã, nặng]
/// cho chữ cái gốc (đã lowercase) với dấu biến âm `mark`.
/// Trả null nếu tổ hợp không hợp lệ trong tiếng Việt.
List<String>? _toneVariants(String lower, Mark mark) {
  final entry = _variants['$lower|${mark.name}'];
  return entry;
}

List<String> _chars(String s) => s.split(' ');

final Map<String, List<String>> _variants = {
  // --- a ---
  'a|none': _chars('a á à ả ã ạ'),
  'a|circumflex': _chars('â ấ ầ ẩ ẫ ậ'),
  'a|breve': _chars('ă ắ ằ ẳ ẵ ặ'),
  // --- e ---
  'e|none': _chars('e é è ẻ ẽ ẹ'),
  'e|circumflex': _chars('ê ế ề ể ễ ệ'),
  // --- i ---
  'i|none': _chars('i í ì ỉ ĩ ị'),
  // --- o ---
  'o|none': _chars('o ó ò ỏ õ ọ'),
  'o|circumflex': _chars('ô ố ồ ổ ỗ ộ'),
  'o|horn': _chars('ơ ớ ờ ở ỡ ợ'),
  // --- u ---
  'u|none': _chars('u ú ù ủ ũ ụ'),
  'u|horn': _chars('ư ứ ừ ử ữ ự'),
  // --- y ---
  'y|none': _chars('y ý ỳ ỷ ỹ ỵ'),
  // --- đ (phụ âm, không mang dấu thanh; lặp 6 lần cho khớp định dạng) ---
  'd|dyet': _chars('đ đ đ đ đ đ'),
};

/// Trả về ký tự tiếng Việt dựng sẵn cho tổ hợp (base + mark + tone).
/// Nếu không phải nguyên âm hợp lệ -> trả về null (engine sẽ giữ nguyên ký tự gốc).
String? composeViet(String base, Mark mark, Tone tone) {
  final isUpper = base.toUpperCase() == base && base.toLowerCase() != base;
  final lower = base.toLowerCase();

  final variants = _toneVariants(lower, mark);
  if (variants == null) return null;
  final result = variants[tone.index];
  return isUpper ? result.toUpperCase() : result;
}
