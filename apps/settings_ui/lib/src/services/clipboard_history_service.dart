// clipboard_history_service.dart
// ------------------------------
// Lịch sử clipboard cho tính năng đồng hành trên Windows — bản Dart của
// ClipboardManager.swift (macOS). Theo dõi clipboard hệ thống bằng poll định
// kỳ, lưu lịch sử (text + ảnh) và bền hoá ra thư mục dùng chung BowGo.
//
// ⚠️ CHỈ chạy trên desktop có super_clipboard hỗ trợ (Windows/macOS/Linux).
// Trên macOS bộ gõ Swift đã lo việc này rồi, nên service này chỉ được KHỞI
// ĐỘNG trên Windows (xem windows_runtime.dart). Model + lưu trữ thì đa nền.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:super_clipboard/super_clipboard.dart';

import 'bow_paths.dart';

/// Một mục trong lịch sử clipboard.
@immutable
class ClipboardEntry {
  const ClipboardEntry({
    required this.id,
    required this.isImage,
    required this.text,
    required this.imagePath,
    required this.createdAtMs,
  });

  final String id;
  final bool isImage;
  final String text; // với ảnh: nhãn hiển thị ("[Ảnh]")
  final String imagePath; // đường dẫn PNG đã lưu (nếu isImage)
  final int createdAtMs;

  Map<String, dynamic> toJson() => {
        'id': id,
        'isImage': isImage,
        'text': text,
        'imagePath': imagePath,
        'createdAtMs': createdAtMs,
      };

  static ClipboardEntry fromJson(Map<String, dynamic> j) => ClipboardEntry(
        id: j['id'] as String? ?? '',
        isImage: j['isImage'] as bool? ?? false,
        text: j['text'] as String? ?? '',
        imagePath: j['imagePath'] as String? ?? '',
        createdAtMs: j['createdAtMs'] as int? ?? 0,
      );
}

class ClipboardHistoryService extends ChangeNotifier {
  ClipboardHistoryService._();
  static final ClipboardHistoryService instance = ClipboardHistoryService._();

  final List<ClipboardEntry> _entries = [];
  List<ClipboardEntry> get entries => List.unmodifiable(_entries);

  int _limit = 40;
  set limit(int v) {
    _limit = v.clamp(1, 500);
    _enforceLimit();
  }

  Timer? _timer;
  File? _historyFile;
  Directory? _imagesDir;
  String? _lastTextSeen; // chống lưu trùng liên tiếp

  bool get _supported {
    // super_clipboard hỗ trợ Windows/macOS/Linux; chỉ dùng cho desktop.
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  /// Bắt đầu theo dõi + nạp lịch sử đã lưu. Gọi một lần khi bật tính năng.
  Future<void> start({int limit = 40}) async {
    _limit = limit.clamp(1, 500);
    if (!_supported) return;
    final dir = await BowPaths.sharedDir();
    _historyFile = File('${dir.path}${Platform.pathSeparator}clipboard_history.json');
    _imagesDir = Directory('${dir.path}${Platform.pathSeparator}clipboard_images');
    if (!_imagesDir!.existsSync()) _imagesDir!.createSync(recursive: true);
    await _load();
    // Poll mỗi 800ms (đủ nhạy, nhẹ) — super_clipboard không có sự kiện đổi.
    _timer ??= Timer.periodic(const Duration(milliseconds: 800), (_) => _poll());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _poll() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return; // nền không hỗ trợ
    try {
      final reader = await clipboard.read();
      // Ưu tiên text; nếu không có text mà có ảnh -> lưu ảnh.
      if (reader.canProvide(Formats.plainText)) {
        final text = await reader.readValue(Formats.plainText);
        if (text != null && text.isNotEmpty && text != _lastTextSeen) {
          _lastTextSeen = text;
          _addText(text);
        }
        return;
      }
      if (reader.canProvide(Formats.png)) {
        reader.getFile(Formats.png, (file) async {
          final bytes = await file.readAll();
          await _addImage(bytes);
        });
      }
    } catch (_) {
      // Đọc clipboard có thể thất bại tạm thời (đang bị app khác giữ) -> bỏ qua.
    }
  }

  void _addText(String text) {
    // Bỏ nếu trùng mục đầu.
    if (_entries.isNotEmpty && !_entries.first.isImage && _entries.first.text == text) {
      return;
    }
    _entries.insert(
      0,
      ClipboardEntry(
        id: _newId(),
        isImage: false,
        text: text,
        imagePath: '',
        createdAtMs: _nowMs(),
      ),
    );
    _enforceLimit();
    _save();
    notifyListeners();
  }

  Future<void> _addImage(List<int> pngBytes) async {
    final dir = _imagesDir;
    if (dir == null) return;
    final id = _newId();
    final path = '${dir.path}${Platform.pathSeparator}$id.png';
    try {
      await File(path).writeAsBytes(pngBytes);
    } catch (_) {
      return;
    }
    _entries.insert(
      0,
      ClipboardEntry(
        id: id,
        isImage: true,
        text: '[Ảnh]',
        imagePath: path,
        createdAtMs: _nowMs(),
      ),
    );
    _enforceLimit();
    _save();
    notifyListeners();
  }

  /// Dán lại một mục (đưa lên clipboard). Caller tự lo gõ Ctrl+V nếu muốn.
  Future<void> copyToClipboard(ClipboardEntry entry) async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return;
    final item = DataWriterItem();
    if (entry.isImage) {
      try {
        final bytes = await File(entry.imagePath).readAsBytes();
        item.add(Formats.png(bytes));
      } catch (_) {
        return;
      }
    } else {
      item.add(Formats.plainText(entry.text));
    }
    _lastTextSeen = entry.isImage ? _lastTextSeen : entry.text; // tránh tự bắt lại
    await clipboard.write([item]);
  }

  void removeEntry(String id) {
    final idx = _entries.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    _deleteImageFile(_entries[idx]);
    _entries.removeAt(idx);
    _save();
    notifyListeners();
  }

  void clear() {
    for (final e in _entries) {
      _deleteImageFile(e);
    }
    _entries.clear();
    _save();
    notifyListeners();
  }

  void _enforceLimit() {
    while (_entries.length > _limit) {
      _deleteImageFile(_entries.last);
      _entries.removeLast();
    }
  }

  void _deleteImageFile(ClipboardEntry e) {
    if (!e.isImage || e.imagePath.isEmpty) return;
    try {
      final f = File(e.imagePath);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {/* bỏ qua */}
  }

  Future<void> _load() async {
    final f = _historyFile;
    if (f == null || !f.existsSync()) return;
    try {
      final list = jsonDecode(f.readAsStringSync()) as List<dynamic>;
      _entries
        ..clear()
        ..addAll(list.map((e) => ClipboardEntry.fromJson(e as Map<String, dynamic>)));
      _enforceLimit();
      notifyListeners();
    } catch (_) {/* file hỏng -> bỏ */}
  }

  Future<void> _save() async {
    final f = _historyFile;
    if (f == null) return;
    try {
      await f.writeAsString(jsonEncode(_entries.map((e) => e.toJson()).toList()));
    } catch (_) {/* bỏ qua */}
  }

  int _idCounter = 0;
  String _newId() => '${_nowMs()}_${_idCounter++}';
  int _nowMs() => DateTime.now().millisecondsSinceEpoch;
}
