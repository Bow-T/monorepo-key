// clipboard_history_overlay.dart
// ------------------------------
// Cửa sổ overlay lịch sử clipboard (phong cách pixel) — bản Flutter của
// ClipboardHistoryWindow.swift (macOS), dùng cho tính năng đồng hành Windows.
//
// Hiện danh sách mục đã copy (text + ảnh). Bấm một mục -> đưa lại lên clipboard
// và đóng overlay (người dùng tự Ctrl+V). Có nút xoá từng mục + xoá hết.
//
// Overlay này được [WindowsRuntime] hiện khi bấm phím tắt clipboard; đa nền về
// mặt widget nhưng chỉ dùng trên Windows.

import 'dart:io';

import 'package:flutter/material.dart';

import '../services/clipboard_history_service.dart';
import '../theme/app_theme.dart';
import '../widgets/pixel.dart';

class ClipboardHistoryOverlay extends StatefulWidget {
  const ClipboardHistoryOverlay({super.key, this.onClose});

  /// Gọi khi người dùng đóng overlay (Esc / bấm nút đóng / đã chọn một mục).
  final VoidCallback? onClose;

  @override
  State<ClipboardHistoryOverlay> createState() => _ClipboardHistoryOverlayState();
}

class _ClipboardHistoryOverlayState extends State<ClipboardHistoryOverlay> {
  final _service = ClipboardHistoryService.instance;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onChange);
  }

  @override
  void dispose() {
    _service.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _pick(ClipboardEntry e) async {
    await _service.copyToClipboard(e);
    widget.onClose?.call();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final entries = _service.entries;
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        // Esc -> đóng.
        if (event.logicalKey.keyLabel == 'Escape') {
          widget.onClose?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        color: t.background,
        child: Column(
          children: [
            _header(context, entries.length),
            Expanded(
              child: entries.isEmpty
                  ? _empty(context)
                  : ListView.separated(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      itemCount: entries.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.xs),
                      itemBuilder: (_, i) => _row(context, entries[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, int count) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
      child: Row(
        children: [
          PixelWindowDots(onClose: widget.onClose),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'LỊCH SỬ CLIPBOARD',
              style: TextStyle(
                fontFamily: AppFonts.head,
                fontSize: 12,
                color: t.textPrimary,
              ),
            ),
          ),
          if (count > 0)
            PixelButton(
              label: 'XOÁ HẾT',
              small: true,
              onPressed: () => _service.clear(),
            ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final t = context.tokens;
    return Center(
      child: Text(
        'Chưa có gì trong lịch sử.',
        style: TextStyle(fontFamily: AppFonts.body, fontSize: 18, color: t.textMuted),
      ),
    );
  }

  Widget _row(BuildContext context, ClipboardEntry e) {
    final t = context.tokens;
    return PixelHover(
      builder: (hovering) => PixelPanel(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          children: [
            PixelBadge(
              label: e.isImage ? 'ẢNH' : 'TEXT',
              color: e.isImage ? t.textSecondary : AppColors.blue,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: e.isImage
                  ? _imagePreview(e)
                  : Text(
                      e.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppFonts.body,
                        fontSize: 18,
                        color: t.textPrimary,
                      ),
                    ),
            ),
            const SizedBox(width: AppSpacing.xs),
            PixelIconButton(
              icon: Icons.content_paste,
              onPressed: () => _pick(e),
            ),
            const SizedBox(width: 4),
            PixelIconButton(
              icon: Icons.close,
              onPressed: () => _service.removeEntry(e.id),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imagePreview(ClipboardEntry e) {
    final f = File(e.imagePath);
    if (!f.existsSync()) {
      return const Text('[Ảnh đã mất]');
    }
    return Row(
      children: [
        Image.file(f, height: 40, fit: BoxFit.contain),
      ],
    );
  }
}
