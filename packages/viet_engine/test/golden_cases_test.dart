// golden_cases_test.dart
// ----------------------
// Chạy BỘ CA GÕ CHUẨN DÙNG CHUNG (spec/typing_cases.tsv) qua engine Dart. Engine
// Swift và C++ nạp đúng file này trong bộ test của chúng — bản nào lệch là đỏ.

import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:viet_engine/viet_engine.dart';

const _methods = {'telex': InputMethod.telex, 'vni': InputMethod.vni};
const _styles = {'modern': ToneStyle.modern, 'old': ToneStyle.old};

/// Gõ [keys] vào một engine mới ('<' = Backspace), trả chuỗi âm tiết sau phím cuối.
String _type(String keys, InputMethod method, ToneStyle style) {
  final engine = VietEngine(method: method, toneStyle: style);
  var current = '';
  for (final ch in keys.split('')) {
    current = (ch == '<' ? engine.backspace() : engine.process(ch)) ?? '';
  }
  return current;
}

void main() {
  // Lần từ package URI để chạy được cả từ gốc repo lẫn từ packages/viet_engine.
  final lib = Isolate.resolvePackageUriSync(Uri.parse('package:viet_engine/'))!;
  final lines =
      File.fromUri(lib.resolve('../spec/typing_cases.tsv')).readAsLinesSync();

  var count = 0;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.isEmpty || line.startsWith('#')) continue;
    final cols = line.split('\t');
    final valid = cols.length == 4 && !cols.contains('');
    final method = valid ? _methods[cols[0]] : null;
    final style = valid ? _styles[cols[1]] : null;
    if (method == null || style == null) {
      throw FormatException('typing_cases.tsv dòng ${i + 1}: sai định dạng', line);
    }
    final keys = cols[2];
    final expected = cols[3] == '∅' ? '' : cols[3];
    count++;
    test('${cols[0]}/${cols[1]} $keys -> $expected',
        () => expect(_type(keys, method, style), expected));
  }

  test('nạp được bộ ca chuẩn', () => expect(count, greaterThan(0)));
}
