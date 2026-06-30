// hotkey_recorder.dart
// --------------------
// Ô "thu" phím tắt kiểu pixel: bấm vào để vào chế độ thu, rồi giữ tổ hợp phím
// (vd ⌃⌥ Space) — widget bắt đúng tổ hợp đó và trả về [Hotkey]. Giống cách đặt
// phím tắt trong System Settings.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/hotkey.dart';
import '../theme/app_theme.dart';
import 'pixel.dart';

class HotkeyRecorder extends StatefulWidget {
  const HotkeyRecorder({
    super.key,
    required this.hotkey,
    required this.onChanged,
  });

  final Hotkey hotkey;
  final ValueChanged<Hotkey> onChanged;

  @override
  State<HotkeyRecorder> createState() => _HotkeyRecorderState();
}

class _HotkeyRecorderState extends State<HotkeyRecorder> {
  final _focusNode = FocusNode();
  bool _recording = false;

  /// Có phím CHÍNH (không phải modifier) nào được nhấn trong lần thu này chưa?
  /// Nếu chưa và người dùng nhả modifier khi đang giữ ≥2 modifier -> thu phím tắt
  /// chỉ-modifier (vd ⌃⇧).
  bool _sawMainKey = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _startRecording() {
    _sawMainKey = false;
    setState(() => _recording = true);
    _focusNode.requestFocus();
  }

  void _stopRecording() {
    setState(() => _recording = false);
    _focusNode.unfocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_recording) return KeyEventResult.ignored;

    // NHẢ phím: nếu đang nhả một MODIFIER mà chưa nhấn phím chính nào và (sau khi
    // nhả) vẫn còn ≥1 modifier khác đang giữ -> đây là phím tắt CHỈ-MODIFIER.
    // Thu tổ hợp modifier đang giữ NGAY TRƯỚC khi nhả (gồm cả phím vừa nhả).
    if (event is KeyUpEvent) {
      if (!_sawMainKey && Hotkey.isModifierKey(event.logicalKey)) {
        final hk = Hotkey.fromKeyEvent(event); // keyCode 0 + modifiers đang giữ
        if (hk != null && hk.isValid) {
          widget.onChanged(hk);
          _sawMainKey = false;
          _stopRecording();
        }
      }
      return KeyEventResult.handled;
    }

    // Esc -> huỷ thu.
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _sawMainKey = false;
      _stopRecording();
      return KeyEventResult.handled;
    }

    // Mới chỉ nhấn modifier — chờ phím chính HOẶC chờ nhả (modifier-only).
    if (Hotkey.isModifierKey(event.logicalKey)) {
      setState(() {}); // vẽ lại để hiện modifier đang giữ
      return KeyEventResult.handled;
    }

    // Đã có phím chính -> không còn là phím tắt chỉ-modifier.
    _sawMainKey = true;
    final hk = Hotkey.fromKeyEvent(event);
    if (hk == null) {
      // Phím chính chưa hỗ trợ ánh xạ -> bỏ qua, giữ chế độ thu.
      return KeyEventResult.handled;
    }
    if (hk.modifiers.isEmpty) {
      // Yêu cầu ít nhất 1 modifier để tránh nuốt nhầm phím thường.
      return KeyEventResult.handled;
    }

    widget.onChanged(hk);
    _sawMainKey = false;
    _stopRecording();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // Khi đang thu: hiện modifier đang giữ (gợi ý trực quan).
    final liveMods = _recording ? _currentModifiers() : '';

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKey,
      onFocusChange: (has) {
        if (!has && _recording) _stopRecording();
      },
      child: GestureDetector(
        onTap: _recording ? _stopRecording : _startRecording,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: PixelPanel(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            borderWidth: AppBorders.thin,
            shadowOffset: AppBorders.shadowSm,
            borderColor: _recording ? AppColors.yellow : t.outline,
            fill: _recording ? AppColors.yellow.withValues(alpha: 0.15) : t.inset,
            child: Text(
              _recording
                  ? (liveMods.isEmpty ? 'GIỮ PHÍM…' : '$liveMods …')
                  : widget.hotkey.display,
              style: TextStyle(
                fontFamily: AppFonts.head,
                fontSize: 9,
                color: _recording ? AppColors.blueDark : t.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Ký hiệu modifier đang giữ — chỉ để hiển thị khi đang thu.
  String _currentModifiers() {
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final out = StringBuffer();
    if (pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight)) {
      out.write('⌃');
    }
    if (pressed.contains(LogicalKeyboardKey.altLeft) ||
        pressed.contains(LogicalKeyboardKey.altRight)) {
      out.write('⌥');
    }
    if (pressed.contains(LogicalKeyboardKey.shiftLeft) ||
        pressed.contains(LogicalKeyboardKey.shiftRight)) {
      out.write('⇧');
    }
    if (pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight)) {
      out.write('⌘');
    }
    return out.toString();
  }
}
