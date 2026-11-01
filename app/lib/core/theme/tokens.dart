import 'package:flutter/painting.dart';

/// Phone color tokens (CLAUDE.md §9.1).
abstract final class Q {
  static const bg = Color(0xFF111218);
  static const surface = Color(0xFF1B1D27);
  static const surface2 = Color(0xFF252836);
  static const border = Color(0xFF2F3242);
  static const inputBorder = Color(0xFF3A3D50);
  static const nav = Color(0xFF16171F);
  static const text = Color(0xFFF4F2EC);
  static const textMuted = Color(0xFFA0A4B5);
  static const primary = Color(0xFFBAD69B);
  static const onPrimary = Color(0xFF15200C);
  static const primaryLight = Color(0xFFD9EBC6);
  static const dontKnow = Color(0xFFFF8A8A);
  static const points = Color(0xFFFFCB52);
  static const multiplier = Color(0xFFC4BAFF);
  static const info = Color(0xFF8FC7F0);
  static const cardFace = Color(0xFFF4F2EC);
  static const cardText = Color(0xFF111218);
  static const cardMuted = Color(0xFF5E6170);
  static const stack1 = Color(0xFF2A2D3B);
  static const stack2 = Color(0xFF1F2130);
  static const legendNew = Color(0xFF4A4E63);
  static const heart = Color(0xFF6B6F82);

  /// Heatmap levels 0–4 (§9.1).
  static const heat = [Color(0xFF252836), Color(0xFF33402A), Color(0xFF4F6A3A), Color(0xFF7FA05E), Color(0xFFBAD69B)];

  /// A token at 16 % opacity, for chip and icon backgrounds.
  static Color tint(Color color) => color.withValues(alpha: 0.16);

  static const headingFont = 'Bricolage Grotesque';
  static const bodyFont = 'Manrope';
}
