import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/api/models.dart';
import '../../core/strings.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';

/// The flashcard: tap flips it (3D), a drag tilts it and shows the VÍM / NEVÍM stamp,
/// a long enough drag (or [SwipeCardState.fly]) throws it off screen and calls [onAnswer].
class SwipeCard extends StatefulWidget {
  const SwipeCard({super.key, required this.card, required this.enabled, required this.onAnswer});

  final SessionCard card;
  final bool enabled;
  final ValueChanged<Rating> onAnswer;

  @override
  State<SwipeCard> createState() => SwipeCardState();
}

class SwipeCardState extends State<SwipeCard> with TickerProviderStateMixin {
  late final AnimationController _flip = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
  late final AnimationController _move = AnimationController(vsync: this);
  Offset _drag = Offset.zero;
  Animation<Offset>? _moveAnimation;
  bool _flying = false;

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  @override
  void initState() {
    super.initState();
    _move.addListener(() => setState(() => _drag = _moveAnimation!.value));
  }

  @override
  void dispose() {
    _flip.dispose();
    _move.dispose();
    super.dispose();
  }

  void _toggleFlip() {
    if (_flying) return;
    if (_reduceMotion) {
      _flip.value = _flip.value < 0.5 ? 1 : 0;
    } else if (_flip.value < 0.5 || _flip.status == AnimationStatus.forward) {
      _flip.animateTo(1, curve: Curves.easeInOutCubic);
    } else {
      _flip.animateTo(0, curve: Curves.easeInOutCubic);
    }
  }

  /// Throws the card to the right (Vím) or left (Nevím), then reports the answer.
  Future<void> fly(Rating rating) async {
    if (_flying || !widget.enabled) return;
    _flying = true;
    final width = MediaQuery.sizeOf(context).width;
    final target = Offset((rating == Rating.know ? 1 : -1) * width * 1.4, _drag.dy + 40);
    if (!_reduceMotion) {
      await _animateTo(target, const Duration(milliseconds: 260), Curves.easeIn);
    }
    if (mounted) widget.onAnswer(rating);
  }

  Future<void> _animateTo(Offset target, Duration duration, Curve curve) {
    _moveAnimation = Tween(begin: _drag, end: target).animate(CurvedAnimation(parent: _move, curve: curve));
    _move.duration = duration;
    return _move.forward(from: 0);
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_flying || !widget.enabled) return;
    _move.stop();
    setState(() => _drag += d.delta);
  }

  void _onPanEnd(DragEndDetails d, double width) {
    if (_flying || !widget.enabled) return;
    final threshold = width * 0.28;
    final vx = d.velocity.pixelsPerSecond.dx;
    if (_drag.dx > threshold || vx > 900) {
      fly(Rating.know);
    } else if (_drag.dx < -threshold || vx < -900) {
      fly(Rating.dontKnow);
    } else {
      _animateTo(Offset.zero, const Duration(milliseconds: 300), Curves.easeOutBack);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final progress = (_drag.dx / (width * 0.28)).clamp(-1.0, 1.0);
      final angle = _drag.dx / width * 0.35;
      final borderColor = progress > 0.15
          ? Q.primary.withValues(alpha: progress)
          : progress < -0.15
              ? Q.dontKnow.withValues(alpha: -progress)
              : Colors.transparent;
      return GestureDetector(
        onTap: _toggleFlip,
        onPanUpdate: _onPanUpdate,
        onPanEnd: (d) => _onPanEnd(d, width),
        child: Transform.translate(
          offset: _drag,
          child: Transform.rotate(
            angle: angle,
            alignment: Alignment.bottomCenter,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _flip,
                    builder: (context, _) {
                      final t = _flip.value;
                      final showBack = t >= 0.5;
                      return Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.0012)
                          ..rotateY(math.pi * t + (showBack ? math.pi : 0)),
                        child: _Face(card: widget.card, back: showBack, borderColor: borderColor),
                      );
                    },
                  ),
                ),
                if (progress > 0.15)
                  Positioned(left: 28, top: 36, child: _Stamp(S.stampKnow, Q.primary, -0.2, progress)),
                if (progress < -0.15)
                  Positioned(right: 28, top: 36, child: _Stamp(S.stampDontKnow, Q.dontKnow, 0.2, -progress)),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _Face extends StatelessWidget {
  const _Face({required this.card, required this.back, required this.borderColor});

  final SessionCard card;
  final bool back;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final main = back ? card.answer : card.question;
    return Semantics(
      label: '${back ? S.answer : S.question}: $main',
      hint: back ? S.tapToFlipBack : S.tapToFlip,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        decoration: BoxDecoration(
          color: Q.cardFace,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: borderColor, width: 3),
          boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 24, offset: Offset(0, 10))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: Q.cardText, borderRadius: BorderRadius.circular(8)),
                child: Text(
                  back ? S.answer : S.question,
                  style: QText.body(11, color: Q.cardFace, weight: FontWeight.w800).copyWith(letterSpacing: 0.9),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: box.maxHeight),
                    child: Column(
                      mainAxisAlignment: back ? MainAxisAlignment.start : MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (back) ...[
                          Text(card.question, style: QText.body(15, color: Q.cardMuted, weight: FontWeight.w700, height: 1.4)),
                          const SizedBox(height: 18),
                        ],
                        Text(
                          main,
                          style: QText.heading(_size(main, back), color: Q.cardText, weight: FontWeight.w700)
                              .copyWith(height: 1.25, letterSpacing: -0.1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.flip_rounded, size: 18, color: Q.cardMuted),
                const SizedBox(width: 8),
                Text(back ? S.tapToFlipBack : S.tapToFlip, style: QText.body(14, color: Q.cardMuted, weight: FontWeight.w700)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Long texts get a smaller font so they fit without scrolling where possible.
  static double _size(String text, bool back) {
    final n = text.length;
    if (back) return n <= 80 ? 24 : n <= 200 ? 20 : n <= 500 ? 17 : 15;
    return n <= 60 ? 30 : n <= 140 ? 25 : n <= 300 ? 21 : 18;
  }
}

class _Stamp extends StatelessWidget {
  const _Stamp(this.text, this.color, this.angle, this.opacity);

  final String text;
  final Color color;
  final double angle;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: opacity.clamp(0, 1),
        child: Transform.rotate(
          angle: angle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
            child: Text(text, style: QText.heading(30, color: Q.cardText).copyWith(letterSpacing: 1.2)),
          ),
        ),
      ),
    );
  }
}
