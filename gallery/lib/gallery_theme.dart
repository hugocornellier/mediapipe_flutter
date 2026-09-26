import 'package:flutter/material.dart';

/// The gallery's shared palette. Task categories and platforms use the same
/// accent; only the neutral surfaces change with brightness.
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

  static ThemeData data(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final canvas = dark ? _darkCanvas : _lightCanvas;
    final chrome = dark ? _darkChrome : _lightChrome;
    final raised = dark ? _darkRaised : _lightRaised;
    final ink = dark ? white : _lightInk;
    final muted = ink.withValues(alpha: 0.72);
    final outline = dark ? const Color(0xFF4A5A5D) : const Color(0xFF9BAEB0);
    final subtleOutline = dark
        ? const Color(0xFF354246)
        : const Color(0xFFCDD7D8);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: brightness,
        ).copyWith(
          primary: accent,
          onPrimary: white,
          primaryContainer: accent,
          onPrimaryContainer: white,
          primaryFixed: accent,
          primaryFixedDim: accent,
          onPrimaryFixed: white,
          onPrimaryFixedVariant: white,
          secondary: accentLight,
          onSecondary: _lightInk,
          secondaryContainer: accent,
          onSecondaryContainer: white,
          secondaryFixed: accentLight,
          secondaryFixedDim: accentLight,
          onSecondaryFixed: _lightInk,
          onSecondaryFixedVariant: _lightInk,
          tertiary: accentLight,
          onTertiary: _lightInk,
          tertiaryContainer: accent,
          onTertiaryContainer: white,
          tertiaryFixed: accentLight,
          tertiaryFixedDim: accentLight,
          onTertiaryFixed: _lightInk,
          onTertiaryFixedVariant: _lightInk,
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
          inversePrimary: accent,
          surfaceTint: Colors.transparent,
        );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      canvasColor: canvas,
      dividerColor: outline,
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
