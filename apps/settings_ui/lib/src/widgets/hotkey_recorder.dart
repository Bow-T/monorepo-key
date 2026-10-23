// hotkey_recorder.dart
// --------------------
// Ô "thu" phím tắt kiểu pixel: bấm vào để vào chế độ thu, rồi giữ tổ hợp phím
// (vd ⌃⌥ Space) — widget bắt đúng tổ hợp đó và trả về [Hotkey]. Giống cách đặt
// phím tắt trong System Settings.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/hotkey.dart';
import '../services/hotkey_recording_lock.dart';
import '../theme/app_theme.dart';
import 'pixel.dart';

class HotkeyRecorder extends StatefulWidget {
  const HotkeyRecorder({
    super.key,
    required this.hotkey,
    required this.onChanged,
    this.allowModifierOnly = false,
  });

  final Hotkey hotkey;
  final ValueChanged<Hotkey> onChanged;

  /// Cho phép tổ hợp CHỈ-modifier (vd ⌃⇧). Bộ gõ chỉ hiểu kiểu này ở phím tắt
  /// bật/tắt; các phím tắt tính năng khác bỏ qua keyCode 0 nên sẽ "chết" im lặng.
  final bool allowModifierOnly;

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

  /// Tập modifier ĐÃ TỪNG được giữ trong lần thu này (tích luỹ). Cần vì khi nhả
  /// phím modifier CUỐI, `logicalKeysPressed` đã loại nó ra -> đọc lúc đó sẽ
  /// thiếu phím vừa nhả. Ta ghi nhớ "đỉnh" số modifier để dựng tổ hợp đúng.
  final Set<HotkeyModifier> _peakModifiers = {};

  /// Tự huỷ thu sau 60s: bộ gõ coi cờ quá 120s là hết hạn và lại nuốt phím tắt,
  /// ô thu để mở lâu hơn sẽ âm thầm không bắt được tổ hợp đã gán.
  Timer? _timeout;

  @override
  void dispose() {
    _timeout?.cancel();
    // Thoát khi đang thu -> vẫn phải nhả cờ, kẻo bộ gõ tưởng còn đang thu.
    if (_recording) HotkeyRecordingLock.release();
    _focusNode.dispose();
    super.dispose();
  }

  void _startRecording() {
    _sawMainKey = false;
    _peakModifiers.clear();
    // Báo bộ gõ NGỪNG nuốt phím tắt trong lúc thu — nếu không, những tổ hợp đã gán
    // (⌃⇧ bật/tắt, ⌃⇧K bảng ký hiệu…) bị tap của bộ gõ ăn trước và ô này không bao
    // giờ thấy chúng, nên chỉ đặt được tổ hợp còn trống (vd ⌥⇧).
    HotkeyRecordingLock.acquire();
    _timeout = Timer(const Duration(seconds: 60), _stopRecording);
    setState(() => _recording = true);
    _focusNode.requestFocus();
  }

  void _stopRecording() {
    if (!_recording) return;
    _timeout?.cancel();
    HotkeyRecordingLock.release();
    setState(() => _recording = false);
    _focusNode.unfocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_recording) return KeyEventResult.ignored;

    // NHẢ phím: nếu đang nhả một MODIFIER mà chưa nhấn phím chính nào -> đây là
    // phím tắt CHỈ-MODIFIER. Dùng `_peakModifiers` (đỉnh modifier đã giữ) chứ
    // KHÔNG đọc `logicalKeysPressed` lúc này — vì phím vừa nhả đã bị loại khỏi tập.
    if (event is KeyUpEvent) {
      if (!_sawMainKey && Hotkey.isModifierKey(event.logicalKey)) {
        final hk = Hotkey(keyCode: 0, modifiers: Set.of(_peakModifiers));
        if (widget.allowModifierOnly && hk.isValid) {
          widget.onChanged(hk);
          _sawMainKey = false;
          _peakModifiers.clear();
          _stopRecording();
          return KeyEventResult.handled;
        }
      }
      // Đã nhả HẾT modifier mà chưa thành tổ hợp -> quên tập đỉnh, kẻo lần chạm ⌘
      // lỡ tay trước đó bị dính vào tổ hợp kế tiếp (⌃K thành ⌃⌘K).
      if (Hotkey.isModifierKey(event.logicalKey) && _currentModifierSet().isEmpty) {
        _peakModifiers.clear();
        setState(() {});
      }
      return KeyEventResult.handled;
    }

    // Esc -> huỷ thu.
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _sawMainKey = false;
      _peakModifiers.clear();
      _stopRecording();
      return KeyEventResult.handled;
    }

    // Mới chỉ nhấn modifier — ghi vào tập đỉnh, chờ phím chính HOẶC chờ nhả.
    if (Hotkey.isModifierKey(event.logicalKey)) {
      // Modifier ĐẦU TIÊN của một lượt bấm mới -> phím chính lỡ bấm trước đó (A, F5…)
      // không còn liên quan; không xoá thì ⌃⇧ chỉ-modifier không bao giờ thu được.
      if (_peakModifiers.isEmpty) _sawMainKey = false;
      final m = _modifierOf(event.logicalKey);
      if (m != null) _peakModifiers.add(m);
      setState(() {}); // vẽ lại để hiện modifier đang giữ
      return KeyEventResult.handled;
    }

    // Đã có phím chính -> không còn là phím tắt chỉ-modifier.
    _sawMainKey = true;
    final code = Hotkey.macKeyCode(event.logicalKey);
    // keyCode 0 của phím A trùng mã "chỉ-modifier" trong settings.json -> bộ gõ
    // hiểu sai, nên không cho gán phím A.
    if (code == null || code == 0) {
      // Phím chính chưa hỗ trợ ánh xạ -> bỏ qua, giữ chế độ thu.
      return KeyEventResult.handled;
    }
    // Modifier lấy từ tập đỉnh đã giữ (đáng tin hơn logicalKeysPressed).
    final mods = Set.of(_peakModifiers);
    if (mods.isEmpty) {
      // Yêu cầu ít nhất 1 modifier để tránh nuốt nhầm phím thường.
      return KeyEventResult.handled;
    }

    widget.onChanged(Hotkey(keyCode: code, modifiers: mods));
    _sawMainKey = false;
    _peakModifiers.clear();
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

  /// Ánh xạ TRỰC TIẾP phím vật lý vừa nhấn -> modifier. Đọc thẳng từ logicalKey
  /// của sự kiện (đáng tin), tránh suy ra từ `logicalKeysPressed` vốn có thể lẫn.
  HotkeyModifier? _modifierOf(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight) {
      return HotkeyModifier.control;
    }
    if (key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight) {
      return HotkeyModifier.option;
    }
    if (key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight) {
      return HotkeyModifier.shift;
    }
    if (key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight) {
      return HotkeyModifier.command;
    }
    return null;
  }

  /// Tập modifier đang thực sự giữ (sau sự kiện hiện tại).
  Set<HotkeyModifier> _currentModifierSet() => HardwareKeyboard
      .instance.logicalKeysPressed
      .map(_modifierOf)
      .whereType<HotkeyModifier>()
      .toSet();

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
