import 'package:flutter/material.dart';

import '../format.dart';
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

/// [duration], or zero when the system asks for less motion (CLAUDE.md §9.3).
Duration motion(BuildContext context, Duration duration) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;

/// A number that rolls to its new value. The first build shows [from] rolling to
/// [value] when [from] is given, else [value] at once.
class RollingNumber extends StatelessWidget {
  const RollingNumber({super.key, required this.value, required this.style, this.from, this.format = formatInt});

  final int value;
  final int? from;
  final TextStyle style;
  final String Function(int) format;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: (from ?? value).toDouble(), end: value.toDouble()),
      duration: motion(context, const Duration(milliseconds: 900)),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(format(v.round()), style: style),
    );
  }
}

/// Bumps its child once each time [trigger] changes (not on the first build).
class Pulse extends StatefulWidget {
  const Pulse({super.key, required this.trigger, required this.child, this.scale = 1.3});

  final Object? trigger;
  final Widget child;
  final double scale;

  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));

  @override
  void didUpdateWidget(Pulse old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger && !MediaQuery.disableAnimationsOf(context)) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeOut.transform(_controller.value);
        final bump = _controller.isAnimating ? (t < 0.35 ? t / 0.35 : 1 - (t - 0.35) / 0.65) : 0.0;
        return Transform.scale(scale: 1 + (widget.scale - 1) * bump, child: child);
      },
      child: widget.child,
    );
  }
}

/// The balance with a star, rolling when it changes; tappable when [onTap] is set.
class PointsPill extends StatelessWidget {
  const PointsPill({super.key, required this.balance, this.onTap, this.semanticsLabel});

  final int balance;
  final VoidCallback? onTap;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: semanticsLabel ?? points(balance),
      excludeSemantics: true,
      child: Material(
        color: Q.surface2,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star_rounded, color: Q.points, size: 20),
                  const SizedBox(width: 6),
                  RollingNumber(value: balance, style: QText.body(16, color: Q.points, weight: FontWeight.w800)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A screen title row (Obchod, Statistiky) with an optional widget on the right.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Expanded(child: Semantics(header: true, child: Text(title, style: QText.heading(28)))),
          ?trailing,
        ],
      ),
    );
  }
}

/// A bar split into Zvládnuto / Učím se / Nové.
class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.mastered, required this.learning, required this.fresh});

  final int mastered;
  final int learning;
  final int fresh;

  @override
  Widget build(BuildContext context) {
    final parts = [(mastered, Q.primary), (learning, Q.multiplier), (fresh, Q.legendNew)].where((p) => p.$1 > 0).toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: SizedBox(
        height: 10,
        child: parts.isEmpty
            ? const ColoredBox(color: Q.surface2)
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < parts.length; i++) ...[
                    if (i > 0) const SizedBox(width: 2),
                    Expanded(flex: parts[i].$1, child: ColoredBox(color: parts[i].$2)),
                  ],
                ],
              ),
      ),
    );
  }
}

/// A number setting with a hint and − / + buttons (Nastavení, onboarding).
class ValueStepper extends StatelessWidget {
  const ValueStepper({
    super.key,
    required this.title,
    required this.hint,
    required this.value,
    required this.min,
    required this.max,
    required this.decreaseLabel,
    required this.increaseLabel,
    required this.onChanged,
  });

  final String title;
  final String hint;
  final int value;
  final int min;
  final int max;
  final String decreaseLabel;
  final String increaseLabel;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: QText.body(15, weight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(hint, style: QText.body(12, color: Q.textMuted, weight: FontWeight.w400, height: 1.35)),
              ],
            ),
          ),
          _StepperButton(label: decreaseLabel, text: '−', onPressed: value > min ? () => onChanged(value - 1) : null),
          Semantics(
            label: title,
            value: '$value',
            child: SizedBox(
              width: 44,
              child: Text('$value', textAlign: TextAlign.center, style: QText.heading(20).copyWith(letterSpacing: 0)),
            ),
          ),
          _StepperButton(label: increaseLabel, text: '+', onPressed: value < max ? () => onChanged(value + 1) : null),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.label, required this.text, required this.onPressed});

  final String label;
  final String text;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: 44,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            backgroundColor: Q.surface2,
            foregroundColor: Q.text,
            disabledForegroundColor: Q.border,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: QText.body(22, weight: FontWeight.w700),
          ),
          child: Text(text),
        ),
      ),
    );
  }
}
