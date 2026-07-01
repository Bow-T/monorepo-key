import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../theme/app_theme.dart';

/// Reusable retro / pixel-art building blocks.
///
/// The visual signature: a flat color fill, a hard square black border, and a
/// solid offset "hard shadow" (no blur) sitting behind the surface. Nothing
/// here uses gradients, blur or rounded corners.

/// A pixel panel — flat fill + hard border + offset hard shadow.
class PixelPanel extends StatelessWidget {
  const PixelPanel({
    super.key,
    required this.child,
    this.padding,
    this.fill,
    this.borderColor,
    this.borderWidth = AppBorders.thick,
    this.shadowOffset = AppBorders.shadow,
    this.shadowColor,
    this.width,
    this.height,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? fill;
  final Color? borderColor;
  final double borderWidth;
  final double shadowOffset;
  final Color? shadowColor;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final border = borderColor ?? t.outline;
    // The hard shadow is painted as a solid rectangle offset down-right behind
    // the surface. We reserve that offset with padding so the panel's total
    // size accounts for the shadow — this keeps layout valid under Spacer /
    // IntrinsicHeight / stretch (no Transform that escapes its bounds).
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _HardShadowPainter(
          color: shadowColor ?? t.shadow,
          offset: shadowOffset,
        ),
        child: Padding(
          padding: EdgeInsets.only(right: shadowOffset, bottom: shadowOffset),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: fill ?? t.panel,
              border: Border.all(color: border, width: borderWidth),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Paints a flat (un-blurred) rectangle offset behind the surface to act as a
/// crisp pixel "drop shadow".
class _HardShadowPainter extends CustomPainter {
  _HardShadowPainter({required this.color, required this.offset});
  final Color color;
  final double offset;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    // The surface occupies (0,0)..(w-offset, h-offset); the shadow fills the
    // same rect shifted by `offset` toward the bottom-right.
    canvas.drawRect(
      Rect.fromLTWH(offset, offset, size.width - offset, size.height - offset),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _HardShadowPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.offset != offset;
}

/// CRT scanline overlay — faint horizontal lines drawn over the whole screen
/// to sell the "old monitor" vibe. Cheap: a repeating 1px-on / 1px-off pattern.
class ScanlineOverlay extends StatelessWidget {
  const ScanlineOverlay({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _ScanlinePainter(t.scanline)),
          ),
        ),
      ],
    );
  }
}

class _ScanlinePainter extends CustomPainter {
  _ScanlinePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (double y = 0; y < size.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ScanlinePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// A chunky pixel button. On press it physically "sinks" into its shadow
/// (offset reduces to 0) for a tactile, steppy feel.
class PixelButton extends StatefulWidget {
  const PixelButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = AppColors.blue,
    this.textColor = Colors.white,
    this.expand = true,
    this.height = 48,
    this.small = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color color;
  final Color textColor;
  final bool expand;
  final double height;
  final bool small;

  @override
  State<PixelButton> createState() => _PixelButtonState();
}

class _PixelButtonState extends State<PixelButton> {
  bool _pressed = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final enabled = widget.onPressed != null;
    final depth = widget.small ? AppBorders.shadowSm : AppBorders.shadow;
    final fill = enabled ? widget.color : t.textMuted;
    // Brighten slightly on hover.
    final shownFill =
        _hover && enabled ? Color.alphaBlend(Colors.white24, fill) : fill;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.onPressed,
        // Reserve `depth` on the bottom-right via padding; on press we move
        // the padding to the top-left so the face "sinks" into the shadow.
        // Total size stays constant → layout-safe under any parent.
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: Curves.easeOut,
          width: widget.expand ? double.infinity : null,
          color: t.shadow, // the hard shadow shows through the padding gap
          padding: _pressed
              ? EdgeInsets.only(left: depth, top: depth)
              : EdgeInsets.only(right: depth, bottom: depth),
          child: Container(
            height: widget.height,
            padding: widget.expand
                ? null
                : const EdgeInsets.symmetric(horizontal: 18),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: shownFill,
              border: Border.all(color: t.outline, width: AppBorders.thick),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: 16, color: widget.textColor),
                  const SizedBox(width: 8),
                ],
                Text(
                  widget.label.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppFonts.head,
                    color: widget.textColor,
                    fontSize: widget.small ? 7 : 9,
                    height: 1.4,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small square icon button with hard border; lights up on hover.
class PixelIconButton extends StatefulWidget {
  const PixelIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 38,
    this.iconSize = 18,
    this.tooltip,
    this.color,
    this.fill,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final double size;
  final double iconSize;
  final String? tooltip;
  final Color? color;
  final Color? fill;

  @override
  State<PixelIconButton> createState() => _PixelIconButtonState();
}

class _PixelIconButtonState extends State<PixelIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final btn = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: _hover
                ? (widget.color ?? AppColors.blue)
                : (widget.fill ?? t.inset),
            border: Border.all(color: t.outline, width: AppBorders.thin),
          ),
          child: Icon(
            widget.icon,
            size: widget.iconSize,
            color: _hover ? Colors.white : (widget.color ?? t.textSecondary),
          ),
        ),
      ),
    );
    if (widget.tooltip != null) {
      return Tooltip(message: widget.tooltip!, child: btn);
    }
    return btn;
  }
}

/// macOS-style window control dots, pixel edition: hard square color blocks
/// with a black border (not round). Red wires [onClose].
class PixelWindowDots extends StatelessWidget {
  const PixelWindowDots({super.key, this.onClose, this.onMinimize});
  final VoidCallback? onClose;
  final VoidCallback? onMinimize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _dot(context, AppColors.red, onClose),
        const SizedBox(width: 7),
        _dot(context, AppColors.yellow, onMinimize),
        const SizedBox(width: 7),
        _dot(context, AppColors.green, null),
      ],
    );
  }

  Widget _dot(BuildContext context, Color color, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor:
            onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: Container(
          width: 13,
          height: 13,
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: context.tokens.outline, width: 2),
          ),
        ),
      ),
    );
  }
}

/// A status badge — flat color block, hard border, pixel label, optional
/// blinking square "LED".
class PixelBadge extends StatelessWidget {
  const PixelBadge({
    super.key,
    required this.label,
    required this.color,
    this.blink = false,
    this.icon,
  });

  final String label;
  final Color color;
  final bool blink;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: t.isDark ? 0.20 : 0.22),
        border: Border.all(color: color, width: AppBorders.thin),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, size: 11, color: color)
          else if (blink)
            BlinkingSquare(color: color)
          else
            Container(width: 8, height: 8, color: color),
          const SizedBox(width: 7),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontFamily: AppFonts.head,
              color: color,
              fontSize: 7,
              height: 1.4,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Header status + theme toggle, fused into ONE pixel panel.
///
/// Left cell: the VN/EN engine status (color block + blinking LED + label).
/// Right cell: a sun/moon button that flips light↔dark. A hard vertical divider
/// splits the two so they read as a single control strip instead of two loose
/// pieces. Shares the panel's border + hard shadow → one cohesive block.
class PixelStatusToggle extends StatelessWidget {
  const PixelStatusToggle({
    super.key,
    required this.ready,
    required this.onToggleTheme,
  });

  /// Engine is in Vietnamese-typing mode (VN) vs. passthrough (EN).
  final bool ready;
  final VoidCallback onToggleTheme;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final statusColor = ready ? AppColors.green : AppColors.stone;

    return PixelPanel(
      padding: EdgeInsets.zero,
      shadowOffset: AppBorders.shadowSm,
      borderWidth: AppBorders.thin,
      fill: t.inset,
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Left cell: engine status ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (ready)
                    BlinkingSquare(color: statusColor)
                  else
                    Container(width: 8, height: 8, color: statusColor),
                  const SizedBox(width: 8),
                  Text(
                    ready ? 'VN' : 'EN',
                    style: TextStyle(
                      fontFamily: AppFonts.head,
                      color: statusColor,
                      fontSize: 8,
                      height: 1.4,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            // ── Hard divider ──────────────────────────────────────────────
            Container(width: AppBorders.thin, color: t.outline),
            // ── Right cell: sun / moon theme toggle ───────────────────────
            _ThemeCell(onTap: onToggleTheme),
          ],
        ),
      ),
    );
  }
}

/// The right-hand cell of [PixelStatusToggle] — a sun/moon button that fills
/// with the accent color on hover (matching [PixelIconButton]'s feel).
class _ThemeCell extends StatefulWidget {
  const _ThemeCell({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_ThemeCell> createState() => _ThemeCellState();
}

class _ThemeCellState extends State<_ThemeCell> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Tooltip(
      message: 'Đổi sáng/tối',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 34,
            color: _hover ? AppColors.blue : Colors.transparent,
            alignment: Alignment.center,
            child: Icon(
              t.isDark ? Iconsax.sun_1 : Iconsax.moon,
              size: 16,
              color: _hover ? Colors.white : t.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// A square LED that blinks on/off in discrete steps (no fade).
class BlinkingSquare extends StatefulWidget {
  const BlinkingSquare({super.key, required this.color, this.size = 8});
  final Color color;
  final double size;

  @override
  State<BlinkingSquare> createState() => _BlinkingSquareState();
}

class _BlinkingSquareState extends State<BlinkingSquare>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        // Stepped: fully on for half the cycle, dim for the other half.
        final on = _c.value > 0.5;
        return Container(
          width: widget.size,
          height: widget.size,
          color: on ? widget.color : widget.color.withValues(alpha: 0.25),
        );
      },
    );
  }
}

/// A blocky loading bar that fills in discrete pixel "ticks" and loops.
class PixelLoadingBar extends StatefulWidget {
  const PixelLoadingBar({
    super.key,
    this.color = AppColors.green,
    this.segments = 12,
    this.width = 200,
  });

  final Color color;
  final int segments;
  final double width;

  @override
  State<PixelLoadingBar> createState() => _PixelLoadingBarState();
}

class _PixelLoadingBarState extends State<PixelLoadingBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return PixelPanel(
      padding: const EdgeInsets.all(5),
      shadowOffset: AppBorders.shadowSm,
      borderWidth: AppBorders.thin,
      fill: t.inset,
      child: SizedBox(
        width: widget.width,
        height: 16,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final lit = (_c.value * widget.segments).floor() + 1;
            return Row(
              children: [
                for (var i = 0; i < widget.segments; i++)
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      color: i < lit
                          ? widget.color
                          : widget.color.withValues(alpha: 0.18),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Entrance: a quick stepped fade-in (no slide easing — keeps it snappy).
class PixelFadeIn extends StatefulWidget {
  const PixelFadeIn({super.key, required this.child, this.delay = Duration.zero});
  final Widget child;
  final Duration delay;

  @override
  State<PixelFadeIn> createState() => _PixelFadeInState();
}

class _PixelFadeInState extends State<PixelFadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: AppMotion.medium);

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _c, child: widget.child);
  }
}

/// A hover wrapper that rebuilds its [builder] when hover changes (used to make
/// panels "lift" by translating up-left on hover).
class PixelHover extends StatefulWidget {
  const PixelHover({super.key, required this.builder, this.onTap});
  final VoidCallback? onTap;
  final Widget Function(bool hovering) builder;

  @override
  State<PixelHover> createState() => _PixelHoverState();
}

class _PixelHoverState extends State<PixelHover> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: widget.builder(_hover),
      ),
    );
  }
}
