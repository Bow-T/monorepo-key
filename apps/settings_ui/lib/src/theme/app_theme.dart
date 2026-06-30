import 'package:flutter/material.dart';

/// Bow Remote — Pixel / Retro 8-bit Design System
///
/// A deliberately un-glossy visual language: flat color blocks, hard 2–3px
/// black borders, NO rounded corners, NO gradients/blur, and chunky offset
/// "hard shadows" (a solid color rectangle behind each surface). Typography is
/// pixel — Press Start 2P for headings, VT323 for body/UI text.
class AppColors {
  AppColors._();

  // ── Farm / JRPG pixel-art palette (sampled from the reference art) ──────
  // Warm earthy tones: meadow greens, oak wood, terracotta roof, slate stone.

  static const Color ink = Color(0xFF2A1E16); // warm near-black outline/shadow
  static const Color paper = Color(0xFFEAD9B0); // parchment / UI panel cream
  static const Color paperAlt = Color(0xFFDCC79A); // panel inset (darker cream)

  // Primary = meadow green (the dominant grass color in the art).
  static const Color blue = Color(0xFF5DA130); // "primary" (kept name) → grass green
  static const Color blueDark = Color(0xFF3E7D2C); // deep grass
  static const Color cyan = Color(0xFF4FA89B); // teal pond / water accent
  static const Color green = Color(0xFF6FB83C); // bright leaf → success
  static const Color yellow = Color(0xFFE8B844); // flower / coin gold → warning
  static const Color red = Color(0xFFC0432F); // mushroom / roof red → danger
  static const Color magenta = Color(0xFFB23A34); // terracotta roof → controller accent
  static const Color purple = Color(0xFF8C5A8C); // dusk flower accent

  // Earthy support tones used for surfaces & details.
  static const Color wood = Color(0xFF9B6B3F); // fence / wood
  static const Color woodDark = Color(0xFF6E4828); // dark wood
  static const Color stone = Color(0xFF5C6B7A); // slate wall
  static const Color stoneDark = Color(0xFF3F4A57); // dark slate

  // Dark "dusk / night in the forest" mode.
  static const Color crt = Color(0xFF1A2418); // deep forest night background
  static const Color crtPanel = Color(0xFF243524); // mossy panel
  static const Color crtInset = Color(0xFF152014); // recessed mossy inset
  static const Color crtBorder = Color(0xFF3C5234); // mossy border
}

/// Tokens that read from the active [Brightness].
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.brightness,
    required this.background,
    required this.panel,
    required this.inset,
    required this.outline,
    required this.shadow,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.scanline,
  });

  final Brightness brightness;

  final Color background; // screen background
  final Color panel; // raised surface fill
  final Color inset; // recessed field fill
  final Color outline; // hard border color
  final Color shadow; // hard offset shadow color
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color scanline; // CRT scanline overlay color

  bool get isDark => brightness == Brightness.dark;

  // "Daytime meadow" — warm parchment panels, oak-brown outlines on a soft
  // grassy-cream backdrop.
  static const AppTokens light = AppTokens(
    brightness: Brightness.light,
    background: Color(0xFFCFE0A8), // pale meadow grass tint
    panel: AppColors.paper, // parchment cream
    inset: AppColors.paperAlt, // darker cream inset
    outline: AppColors.ink, // warm dark-brown border
    shadow: AppColors.ink,
    textPrimary: AppColors.ink,
    textSecondary: Color(0xFF5A4030),
    textMuted: Color(0xFF917A5E),
    scanline: Color(0x0A2A1E16),
  );

  // "Forest night" — mossy panels, deep-green backdrop.
  static const AppTokens dark = AppTokens(
    brightness: Brightness.dark,
    background: AppColors.crt,
    panel: AppColors.crtPanel,
    inset: AppColors.crtInset,
    outline: Color(0xFF0E1A0C),
    shadow: Color(0xFF0A140A),
    textPrimary: Color(0xFFF0E8CE),
    textSecondary: Color(0xFFC4D2A8),
    textMuted: Color(0xFF7E9070),
    scanline: Color(0x18000000),
  );

  @override
  AppTokens copyWith({
    Brightness? brightness,
    Color? background,
    Color? panel,
    Color? inset,
    Color? outline,
    Color? shadow,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? scanline,
  }) {
    return AppTokens(
      brightness: brightness ?? this.brightness,
      background: background ?? this.background,
      panel: panel ?? this.panel,
      inset: inset ?? this.inset,
      outline: outline ?? this.outline,
      shadow: shadow ?? this.shadow,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      scanline: scanline ?? this.scanline,
    );
  }

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    // Snap at the midpoint — no smooth tween (pixel themes don't fade).
    return t < 0.5 ? this : other;
  }
}

/// Geometry & motion constants. Note: radii are intentionally all zero — pixel
/// surfaces have hard square corners. We keep the class for a single source of
/// truth on border / shadow thickness.
class AppRadii {
  AppRadii._();
  static const double none = 0;
}

class AppBorders {
  AppBorders._();
  static const double thin = 2;
  static const double thick = 3;
  static const double shadow = 5; // hard shadow offset
  static const double shadowSm = 3;
}

class AppSpacing {
  AppSpacing._();
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 20;
  static const double lg = 28;
  static const double xl = 44;
}

class AppMotion {
  AppMotion._();
  // Snappy, stepped feel.
  static const Duration fast = Duration(milliseconds: 90);
  static const Duration medium = Duration(milliseconds: 160);
  static const Duration slow = Duration(milliseconds: 280);
  // Linear / stepped — no eased "material" curves for the retro feel.
  static const Curve stepped = Curves.easeOutQuad;
}

class AppFonts {
  AppFonts._();
  static const String head = 'PixelHead'; // Press Start 2P
  static const String body = 'PixelBody'; // VT323
}

class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(Brightness.light, AppTokens.light);
  static ThemeData dark() => _build(Brightness.dark, AppTokens.dark);

  static ThemeData _build(Brightness brightness, AppTokens tokens) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.blue,
      brightness: brightness,
    ).copyWith(primary: AppColors.blue, surface: tokens.panel);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: tokens.background,
      fontFamily: AppFonts.body,
      // No ink ripple — pixel buttons don't ripple.
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      extensions: <ThemeExtension<dynamic>>[tokens],
      textTheme: _textTheme(tokens),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: tokens.isDark ? AppColors.crtPanel : AppColors.ink,
        contentTextStyle: TextStyle(
          fontFamily: AppFonts.body,
          color: tokens.isDark ? AppColors.paper : AppColors.paper,
          fontSize: 18,
          letterSpacing: 0.5,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(
              color: tokens.isDark ? AppColors.crtBorder : AppColors.ink,
              width: AppBorders.thin),
        ),
        insetPadding: const EdgeInsets.all(AppSpacing.md),
      ),
    );
  }

  static TextTheme _textTheme(AppTokens t) {
    return TextTheme(
      // Press Start 2P is tiny per em — keep heading sizes modest.
      displaySmall: TextStyle(
        fontFamily: AppFonts.head,
        color: t.textPrimary,
        fontSize: 20,
        height: 1.4,
      ),
      headlineSmall: TextStyle(
        fontFamily: AppFonts.head,
        color: t.textPrimary,
        fontSize: 13,
        height: 1.4,
      ),
      titleMedium: TextStyle(
        fontFamily: AppFonts.head,
        color: t.textPrimary,
        fontSize: 10,
        height: 1.5,
      ),
      // VT323 reads big — bump body sizes up.
      bodyMedium: TextStyle(
        fontFamily: AppFonts.body,
        color: t.textSecondary,
        fontSize: 18,
        height: 1.15,
        letterSpacing: 0.3,
      ),
      labelSmall: TextStyle(
        fontFamily: AppFonts.head,
        color: t.textMuted,
        fontSize: 7,
        height: 1.4,
        letterSpacing: 0.5,
      ),
    );
  }
}

extension AppTokensX on BuildContext {
  AppTokens get tokens =>
      Theme.of(this).extension<AppTokens>() ?? AppTokens.light;
}
