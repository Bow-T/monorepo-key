// pixel_controls.dart
// -------------------
// Các control pixel riêng cho màn hình cài đặt: công tắc bật/tắt, nút chọn nhiều
// lựa chọn (segmented), hàng cài đặt có nhãn + mô tả. Bám đúng design system
// (viền vuông cứng, hard shadow, font Press Start 2P / VT323) trong app_theme.dart.

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'pixel.dart';

/// Công tắc ON/OFF kiểu pixel: khối vuông, viền cứng, trượt cứng (không mượt).
class PixelSwitch extends StatelessWidget {
  const PixelSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 76,
          height: 34,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: value ? AppColors.green : t.inset,
            border: Border.all(color: t.outline, width: AppBorders.thick),
          ),
          child: Row(
            mainAxisAlignment:
                value ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              // Nhãn ON/OFF ở khoảng trống còn lại.
              if (value)
                Expanded(
                  child: Center(
                    child: Text('ON',
                        style: _capStyle(Colors.white)),
                  ),
                ),
              // "Núm" trượt — khối vuông đặc.
              Container(
                width: 24,
                height: double.infinity,
                decoration: BoxDecoration(
                  color: value ? AppColors.paper : t.textMuted,
                  border: Border.all(color: t.outline, width: AppBorders.thin),
                ),
              ),
              if (!value)
                Expanded(
                  child: Center(
                    child: Text('OFF', style: _capStyle(t.textMuted)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  TextStyle _capStyle(Color c) => TextStyle(
        fontFamily: AppFonts.head,
        fontSize: 7,
        color: c,
        letterSpacing: 0.5,
      );
}

/// Nút chọn segmented (vd Telex | VNI): các ô liền nhau, ô đang chọn tô màu.
class PixelSegmented<T> extends StatelessWidget {
  const PixelSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.color = AppColors.blue,
  });

  /// Danh sách (giá trị, nhãn) theo thứ tự hiển thị.
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return PixelPanel(
      padding: EdgeInsets.zero,
      borderWidth: AppBorders.thick,
      shadowOffset: AppBorders.shadowSm,
      fill: t.inset,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0)
              Container(width: AppBorders.thin, height: 40, color: t.outline),
            _seg(context, options[i].$1, options[i].$2),
          ],
        ],
      ),
    );
  }

  Widget _seg(BuildContext context, T v, String label) {
    final t = context.tokens;
    final selected = v == value;
    return GestureDetector(
      onTap: () => onChanged(v),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          alignment: Alignment.center,
          color: selected ? color : Colors.transparent,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: AppFonts.head,
              fontSize: 9,
              color: selected ? Colors.white : t.textMuted,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

/// Một hàng cài đặt: tiêu đề + mô tả phụ bên trái, control bên phải.
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.control,
  });

  final String title;
  final String? subtitle;
  final Widget control;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: Theme.of(context).textTheme.titleMedium),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(subtitle!,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: t.textMuted)),
              ],
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        control,
      ],
    );
  }
}
