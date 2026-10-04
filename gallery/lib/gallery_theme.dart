import 'package:flutter/material.dart';

/// The gallery's shared palette. Controls and navigation are neutral; the
/// accent is kept for what tasks draw (overlays, progress, scores) and GPU.
abstract final class GalleryTheme {
  static const accent = Color(0xFF007F8B);
  static const accentLight = Color(0xFF8CD0D6);
  static const white = Colors.white;
  static const preview = Colors.black;

  static const _darkCanvas = Color(0xFF101718);
  static const _darkChrome = Color(0xFF192123);
  static const _darkRaised = Color(0xFF232D2F);
  static const _lightCanvas = Colors.white;
  static const _lightChrome = Color(0xFFF2F6F6);
  static const _lightRaised = Color(0xFFE7EEEE);
  static const _lightInk = Color(0xFF192B2E);
  static const _lightNeutral = Color(0xFF3C4446);
  static const _darkNeutral = Color(0xFFD6DCDD);

  /// Section and field labels ("VISION", "MODE"): small grey caps, so they
  /// read as labels rather than controls.
  static TextStyle? label(ThemeData theme) =>
      theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      );

  static ThemeData data(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final canvas = dark ? _darkCanvas : _lightCanvas;
    final chrome = dark ? _darkChrome : _lightChrome;
    final raised = dark ? _darkRaised : _lightRaised;
    final ink = dark ? white : _lightInk;
    final muted = ink.withValues(alpha: 0.72);
    final outline = dark ? const Color(0xFF4A5A5D) : const Color(0xFF9BAEB0);
    // Selected controls: dark grey on light surfaces, light grey on dark.
    final neutral = dark ? _darkNeutral : _lightNeutral;
    final onNeutral = dark ? _lightInk : white;
    final subtleOutline = dark
        ? const Color(0xFF354246)
        : const Color(0xFFCDD7D8);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: brightness,
        ).copyWith(
          primary: neutral,
          onPrimary: onNeutral,
          primaryContainer: neutral,
          onPrimaryContainer: onNeutral,
          primaryFixed: neutral,
          primaryFixedDim: neutral,
          onPrimaryFixed: onNeutral,
          onPrimaryFixedVariant: onNeutral,
          secondary: neutral,
          onSecondary: onNeutral,
          secondaryContainer: neutral,
          onSecondaryContainer: onNeutral,
          secondaryFixed: neutral,
          secondaryFixedDim: neutral,
          onSecondaryFixed: onNeutral,
          onSecondaryFixedVariant: onNeutral,
          tertiary: neutral,
          onTertiary: onNeutral,
          tertiaryContainer: neutral,
          onTertiaryContainer: onNeutral,
          tertiaryFixed: neutral,
          tertiaryFixedDim: neutral,
          onTertiaryFixed: onNeutral,
          onTertiaryFixedVariant: onNeutral,
          error: dark ? accentLight : accent,
          onError: dark ? _lightInk : white,
          errorContainer: raised,
          onErrorContainer: ink,
          surface: canvas,
          onSurface: ink,
          surfaceDim: canvas,
          surfaceBright: raised,
          surfaceContainerLowest: canvas,
          surfaceContainerLow: chrome,
          surfaceContainer: chrome,
          surfaceContainerHigh: raised,
          surfaceContainerHighest: raised,
          onSurfaceVariant: muted,
          outline: outline,
          outlineVariant: subtleOutline,
          shadow: preview,
          scrim: preview,
          inverseSurface: dark ? white : _darkCanvas,
          onInverseSurface: dark ? _darkCanvas : white,
          inversePrimary: neutral,
          surfaceTint: Colors.transparent,
        );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      canvasColor: canvas,
      dividerColor: outline,
      // Spinners over the camera and result score bars keep the accent.
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: dark ? accentLight : accent,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: chrome,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      useMaterial3: true,
    );
  }
}
