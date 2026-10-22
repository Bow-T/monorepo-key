// Test đồng bộ settings.json giữa app Cài đặt và bộ gõ (cùng ghi một file):
// UI không được bật ngược / xoá mất những gì bộ gõ vừa ghi, và phải nạp lại khi
// bộ gõ đổi file.

import 'dart:convert';
import 'dart:io';

import 'package:bow_settings/src/models/settings.dart';
import 'package:bow_settings/src/pages/settings_page.dart';
import 'package:bow_settings/src/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('bowgo_settings_test');
    file = File('${dir.path}/settings.json');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Map<String, dynamic> readDisk() =>
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

  /// Giả lập bộ gõ Swift ghi file (đọc-sửa-ghi, giữ khoá khác).
  void imeWrites(Map<String, dynamic> changes) {
    final obj = readDisk()..addAll(changes);
    file.writeAsStringSync(jsonEncode(obj));
  }

  group('merge', () {
    test('khoá UI không đổi -> giữ bản đĩa; khoá UI đổi -> đè; khoá lạ giữ nguyên', () {
      final out = SettingsService.merge(
        disk: {'enabled': false, 'method': 'telex', 'fixBrowserDoubleType': false},
        mem: {'enabled': true, 'method': 'vni'},
        base: {'enabled': true, 'method': 'telex'},
      );
      expect(out, {'enabled': false, 'method': 'vni', 'fixBrowserDoubleType': false});
    });

    test('khoá đĩa chưa có -> lấy bản bộ nhớ', () {
      final out = SettingsService.merge(disk: {}, mem: {'enabled': true}, base: {'enabled': true});
      expect(out, {'enabled': true});
    });
  });

  group('SettingsService với file thật', () {
    test('bộ gõ tắt (⌃⇧) rồi UI lưu cài khác: KHÔNG bật ngược, giữ khoá UI không biết', () async {
      file.writeAsStringSync(jsonEncode({
        ...const BowSettings().toJson(),
        'fixBrowserDoubleType': false,
      }));
      final svc = SettingsService.forTest();
      await svc.loadFrom(file);
      expect(svc.value.enabled, isTrue);

      imeWrites({'enabled': false});
      await svc.update(svc.value.copyWith(method: InputMethod.vni));

      final disk = readDisk();
      expect(disk['enabled'], isFalse);
      expect(disk['method'], 'vni');
      expect(disk['fixBrowserDoubleType'], isFalse);
      expect(svc.value.enabled, isFalse, reason: 'UI phải phản ánh bản trên đĩa');
    });

    test('cặp tự-sửa bộ gõ ghi (thứ tự khoá khác Dart) không bị đè khi UI lưu', () async {
      file.writeAsStringSync(jsonEncode(const BowSettings().toJson()..remove('autoCorrectPairs')));
      final svc = SettingsService.forTest();
      await svc.loadFrom(file);

      // Swift gieo cặp mặc định với khoá sắp xếp (right trước wrong).
      imeWrites({
        'autoCorrectPairs': [
          {'right': 'giờ', 'wrong': 'giừo'},
        ],
      });
      await svc.update(svc.value.copyWith(autoCorrect: false));

      expect(readDisk()['autoCorrectPairs'], [
        {'right': 'giờ', 'wrong': 'giừo'},
      ]);
    });

    test('lần chạy đầu: không ghi autoCorrectPairs rỗng (để bộ gõ gieo mặc định)', () async {
      final svc = SettingsService.forTest();
      await svc.loadFrom(file);
      expect(file.existsSync(), isTrue);
      expect(readDisk().containsKey('autoCorrectPairs'), isFalse);
    });

    test('bộ gõ đổi file -> reloadIfChanged nạp lại và báo listener', () async {
      file.writeAsStringSync(jsonEncode(const BowSettings().toJson()));
      final svc = SettingsService.forTest();
      await svc.loadFrom(file);
      var notified = 0;
      svc.addListener(() => notified++);

      await svc.reloadIfChanged();
      expect(notified, 0, reason: 'file không đổi thì không làm gì');

      imeWrites({'macroEnabled': false});
      await svc.reloadIfChanged();
      expect(svc.value.macroEnabled, isFalse);
      expect(notified, 1);
    });

    test('hai lần lưu liên tiếp không await: cả hai thay đổi đều vào file, JSON hợp lệ', () async {
      final svc = SettingsService.forTest();
      await svc.loadFrom(file);
      final a = svc.update(svc.value.copyWith(method: InputMethod.vni));
      final b = svc.update(svc.value.copyWith(smartSwitch: true));
      await Future.wait([a, b]);
      final disk = readDisk();
      expect(disk['method'], 'vni');
      expect(disk['smartSwitch'], isTrue);
      expect(File('${file.path}.tmp').existsSync(), isFalse);
    });
  });

  group('upsertByKey (sửa macro / cặp tự-sửa)', () {
    String key(String s) => s;

    test('đổi tên mục giữa thành tên mục đầu: bỏ mục trùng, KHÔNG đè mục cuối', () {
      expect(upsertByKey(['a', 'b', 'c'], 'b', 'a', key), ['c', 'a']);
    });

    test('sửa mục cuối thành tên trùng mục đầu: không RangeError', () {
      expect(upsertByKey(['a', 'b', 'c'], 'c', 'a', key), ['b', 'a']);
    });

    test('sửa giữ tên: thay đúng chỗ', () {
      expect(upsertByKey(['a', 'b', 'c'], 'b', 'b', key), ['a', 'b', 'c']);
    });

    test('thêm mới trùng mục cũ: thay mục cũ, đưa xuống cuối', () {
      expect(upsertByKey(['a', 'b'], null, 'a', key), ['b', 'a']);
    });

    test('mục đang sửa đã biến mất khỏi danh sách (nạp lại giữa chừng): thêm vào cuối', () {
      expect(upsertByKey(['a'], 'x', 'y', key), ['a', 'y']);
    });
  });
}
