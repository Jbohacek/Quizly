import 'package:flutter/material.dart';

import '../strings.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';

/// The main CTA: primary background, heading font, 58–60 px tall.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, this.onPressed, this.icon, this.height = 58, this.busy = false});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: FilledButton(
        onPressed: enabled ? onPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor: Q.primary,
          foregroundColor: Q.onPrimary,
          disabledBackgroundColor: Q.surface2,
          disabledForegroundColor: Q.textMuted,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: QText.heading(19, color: Q.onPrimary),
        ),
        child: busy
            ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 3, color: Q.onPrimary))
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[Icon(icon, size: 22), const SizedBox(width: 10)],
                  Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
                ],
              ),
      ),
    );
  }
}

/// A secondary button on surface2.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({super.key, required this.label, this.onPressed, this.color = Q.text, this.outlined = false});

  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: outlined ? Colors.transparent : Q.surface2,
          foregroundColor: color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: outlined ? const BorderSide(color: Q.inputBorder, width: 1.5) : BorderSide.none,
          ),
          textStyle: QText.body(16, weight: FontWeight.w800),
        ),
        child: Text(label),
      ),
    );
  }
}

/// A rounded panel on the surface color with a 1 px border.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.radius = 24, this.color});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Q.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Q.border),
      ),
      child: child,
    );
  }
}

/// A small rounded label.
class Tag extends StatelessWidget {
  const Tag({super.key, required this.label, required this.color, this.background});

  final String label;
  final Color color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: background ?? Q.tint(color), borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: QText.body(13, color: color, weight: FontWeight.w800)),
    );
  }
}

/// Error with a retry button, for a screen that failed to load.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 48, color: Q.textMuted),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center, style: QText.body(16, color: Q.textMuted, height: 1.45)),
            const SizedBox(height: 24),
            SizedBox(width: 220, child: PrimaryButton(label: S.retry, onPressed: onRetry, height: 52)),
          ],
        ),
      ),
    );
  }
}

/// "Jsi offline" banner (api.md §11.7).
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, this.detail = S.offlineHint});

  final String detail;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Q.tint(Q.dontKnow),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Q.dontKnow.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            const Icon(Icons.wifi_off_rounded, color: Q.dontKnow),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(S.offline, style: QText.body(15, color: Q.dontKnow, weight: FontWeight.w800)),
                  Text(detail, style: QText.body(13, color: Q.textMuted, weight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Parses `#RRGGBB`; falls back to the primary color.
Color parseHex(String hex) {
  final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
  return value == null || hex.length != 7 ? Q.primary : Color(0xFF000000 | value);
}
