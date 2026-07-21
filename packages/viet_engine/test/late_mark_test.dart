// late_mark_test.dart
// -------------------
// Regression: móc/trăng (Telex 'w' / VNI '7') và mũ/trăng (VNI '6'/'8') gõ SAU phụ
// âm cuối hoặc sau bán nguyên âm 'i' phải đặt đúng CỤM NGUYÊN ÂM.
//
// BUG (đã sửa, port từ bản Swift): engine Dart cũ chỉ nhìn 1-2 chữ CUỐI khi áp biến
// âm. Khi chữ cuối là phụ âm ("đuoc"+w) hoặc bán nguyên âm ("muoi"+6), biến âm không
// đặt được -> "đuocự" / "muoi6" thay vì "được" / "muôi".
//
// SỬA: _vowelNucleusRange + _applyHornToNucleus + _setMarkOnNucleus (khớp Swift).

import 'package:test/test.dart';
import 'package:viet_engine/viet_engine.dart';

String _type(String keys, {InputMethod method = InputMethod.telex}) {
  final e = VietEngine(method: method);
  var out = '';
  for (final ch in keys.split('')) {
    final r = e.process(ch);
    if (r == null) {
      out += ch;
      e.clear();
    } else {
      out = r;
    }
  }
  return out;
}

void main() {
  group('Telex: móc/trăng gõ SAU phụ âm cuối', () {
    final cases = {
      'dduocwj': 'được',
      'nuocws': 'nước',
      'huongwf': 'hường',
      'nguoiwf': 'người',
      'muonws': 'mướn',
      'comw': 'cơm',
      'manw': 'măn',
      'nangw': 'năng',
    };
    cases.forEach((k, v) {
      test('"$k" -> "$v"', () => expect(_type(k), v));
    });
  });

  group('Telex: regression — móc gõ TRƯỚC phụ âm vẫn đúng', () {
    final cases = {
      'dduowcj': 'được',
      'nuowsc': 'nước',
      'thuowng': 'thương',
      'thuowr': 'thuở',
      'muws': 'mứ',
      'tw': 'tư',
    };
    cases.forEach((k, v) {
      test('"$k" -> "$v"', () => expect(_type(k), v));
    });
  });

  group('VNI: mũ/trăng (6/8) gõ muộn', () {
    final cases = {
      'muoi64': 'muỗi',
      'tuoi63': 'tuổi',
      'buoi63': 'buổi',
      'chuoi61': 'chuối',
      'xuoi61': 'xuối',
      'muon61': 'muốn',
      'con6': 'côn',
      'tang8': 'tăng',
      'man8': 'măn',
    };
    cases.forEach((k, v) {
      test('"$k" -> "$v"', () => expect(_type(k, method: InputMethod.vni), v));
    });
  });

  group('VNI: móc (7) + toggle + regression', () {
    final cases = {
      'nuoc71': 'nước',
      'con7': 'cơn',
      'thuong72': 'thường',
      'tie61ng': 'tiếng',
      'vie65t': 'việt',
      'a6': 'â',
      'a66': 'a6', // gõ 6 lần 2 -> gỡ mũ + '6' thô
      'd9': 'đ',
    };
    cases.forEach((k, v) {
      test('"$k" -> "$v"', () => expect(_type(k, method: InputMethod.vni), v));
    });
  });
}
