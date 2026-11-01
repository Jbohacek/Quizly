import 'package:flutter/material.dart';

import 'tokens.dart';

/// Text styles used across screens.
abstract final class QText {
  static TextStyle heading(double size, {Color color = Q.text, FontWeight weight = FontWeight.w800}) => TextStyle(
        fontFamily: Q.headingFont,
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: 1.15,
        letterSpacing: -0.02 * size,
      );

  static TextStyle body(double size, {Color color = Q.text, FontWeight weight = FontWeight.w600, double? height}) =>
      TextStyle(fontFamily: Q.bodyFont, fontSize: size, fontWeight: weight, color: color, height: height);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Q.primary,
    brightness: Brightness.dark,
  ).copyWith(
    primary: Q.primary,
    onPrimary: Q.onPrimary,
    surface: Q.bg,
    onSurface: Q.text,
    error: Q.dontKnow,
    outline: Q.border,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Q.bg,
    fontFamily: Q.bodyFont,
    textTheme: ThemeData.dark().textTheme.apply(fontFamily: Q.bodyFont, bodyColor: Q.text, displayColor: Q.text),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Q.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      hintStyle: QText.body(16, color: Q.textMuted, weight: FontWeight.w400),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Q.inputBorder, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Q.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Q.dontKnow, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Q.dontKnow, width: 1.5),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Q.surface2,
      contentTextStyle: QText.body(14),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Q.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: QText.heading(22),
      contentTextStyle: QText.body(15, color: Q.textMuted, weight: FontWeight.w400, height: 1.45),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Q.primary),
  );
}
