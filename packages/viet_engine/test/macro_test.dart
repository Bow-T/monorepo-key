// macro_test.dart
// Gõ tắt / macro (port từ MacroTests.swift).

import 'package:test/test.dart';
import 'package:viet_engine/viet_engine.dart';

void main() {
  group('Macro tĩnh', () {
    test('Tra từ khoá -> nội dung', () {
      final store = MacroStore([
        const MacroDefinition(keyword: 'vn', content: 'Việt Nam'),
        const MacroDefinition(keyword: 'kb', content: 'không biết'),
      ]);
      expect(store.expand('vn'), 'Việt Nam');
      expect(store.expand('kb'), 'không biết');
      expect(store.expand('xx'), isNull);
    });

    test('clear + isEmpty', () {
      final store = MacroStore([const MacroDefinition(keyword: 'a', content: 'b')]);
      expect(store.isEmpty, isFalse);
      store.clear();
      expect(store.isEmpty, isTrue);
      expect(store.expand('a'), isNull);
    });
  });

  group('Macro động', () {
    DateTime fixed() => DateTime(2026, 6, 30, 9, 5, 7);

    test('Ngày / giờ theo format', () {
      final store = MacroStore([
        const MacroDefinition(keyword: 'td', content: 'dd/MM/yyyy', type: MacroSnippetType.date),
        const MacroDefinition(keyword: 'tg', content: 'HH:mm:ss', type: MacroSnippetType.time),
      ], MacroEnvironment(now: fixed));
      expect(store.expand('td'), '30/06/2026');
      expect(store.expand('tg'), '09:05:07');
    });

    test('Counter tăng dần', () {
      final store = MacroStore(
          [const MacroDefinition(keyword: 'no', content: '#', type: MacroSnippetType.counter)]);
      expect(store.expand('no'), '#1');
      expect(store.expand('no'), '#2');
      expect(store.expand('no'), '#3');
    });

    test('Random theo index tiêm vào', () {
      final store = MacroStore([
        const MacroDefinition(keyword: 'rr', content: 'a, b, c', type: MacroSnippetType.random),
      ], const MacroEnvironment(randomIndex: _alwaysOne));
      expect(store.expand('rr'), 'b');
    });
  });
}

int _alwaysOne(int count) => 1;
