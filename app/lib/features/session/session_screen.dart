import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/models.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../home/deck_screen.dart';
import 'session_controller.dart';
import 'swipe_card.dart';

/// Učení (design screens 3–4): one deck or all decks ([deckId] null).
class SessionScreen extends ConsumerStatefulWidget {
  const SessionScreen({super.key, this.deckId, this.extraNew = 0});

  final int? deckId;

  /// New cards over today's allowance ("Ještě 5 nových karet").
  final int extraNew;

  @override
  ConsumerState<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends ConsumerState<SessionScreen> {
  late final SessionController _controller;
  // A new key (and card state) per answer or skip, so a returning card starts unflipped.
  GlobalKey<SwipeCardState> _cardKey = GlobalKey();
  int _keyTurn = 0;
  late final Map<int, Deck> _decks;

  // Floating "+N" labels, one per answer, removed when their animation ends.
  final _floaters = <({int id, int points, Rating rating})>[];
  int _floatTurn = 0;

  /// The current card has been turned over: Vím / Nevím are offered (and the card is bigger).
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    _controller = SessionController(
      client: ref.read(apiClientProvider),
      sync: ref.read(reviewSyncProvider)!,
      deckId: widget.deckId,
      extraNew: widget.extraNew,
    )..addListener(_onChange);
    _decks = {for (final d in ref.read(homeProvider).value?.decks.items ?? const <Deck>[]) d.id: d};
    _controller.load();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onChange)
      ..dispose();
    super.dispose();
  }

  void _onChange() {
    final result = _controller.result;
    if (_controller.phase == SessionPhase.finished && result != null) {
      invalidateProgress(ref);
      ref.invalidate(deckCardsProvider);
      context.pushReplacement('/done', extra: result);
    } else {
      final answer = _controller.lastAnswer;
      if (_controller.turn != _floatTurn) {
        _floatTurn = _controller.turn;
        if (answer != null && !MediaQuery.disableAnimationsOf(context)) {
          _floaters.add((id: _floatTurn, points: answer.points, rating: answer.rating));
        }
      }
      setState(() {});
    }
  }

  Future<void> _close() async {
    final answered = _controller.tally.graded > 0 && _controller.phase == SessionPhase.studying;
    if (answered) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text(S.leaveTitle),
          content: const Text(S.leaveText),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text(S.stay)),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text(S.leave)),
          ],
        ),
      );
      if (leave != true || !mounted) return;
    }
    invalidateProgress(ref);
    ref.invalidate(deckCardsProvider);
    if (mounted) context.pop();
  }

  /// Cards never answered in this session's deck (or all decks), as Domů last saw them.
  int get _unseen => [
        for (final d in ref.read(homeProvider).value?.decks.items ?? const <Deck>[])
          if (widget.deckId == null || d.id == widget.deckId) d.unseenCards,
      ].fold(0, (a, b) => a + b);

  /// Otočit kartu: the same as tapping the card.
  void _reveal() => _cardKey.currentState?.flip();

  void _answer(Rating rating) {
    final card = _cardKey.currentState;
    if (card != null) {
      card.fly(rating);
    } else {
      _controller.answer(rating);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        body: SafeArea(
          child: switch (c.phase) {
            SessionPhase.loading => const Center(child: CircularProgressIndicator()),
            SessionPhase.error => ErrorView(message: c.error ?? S.loadFailed, onRetry: c.recover),
            SessionPhase.empty => _Empty(
                onClose: _close,
                unseen: _unseen,
                onMore: () => context.pushReplacement(
                  sessionPath(deckId: widget.deckId, extraNew: math.min(extraNewStep, _unseen)),
                ),
              ),
            SessionPhase.saving => _Saving(offline: c.offline, onClose: _close),
            SessionPhase.studying || SessionPhase.finished => _buildStudy(c),
          },
        ),
      ),
    );
  }

  Widget _buildStudy(SessionController c) {
    final card = c.queue.current;
    if (card == null) return const SizedBox.shrink();
    if (c.turn != _keyTurn) {
      _keyTurn = c.turn;
      _cardKey = GlobalKey();
      _revealed = false;
    }
    final grow = MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 280);
    final deck = _decks[card.deckId];
    final deckColor = deck == null ? Q.primary : parseHex(deck.color);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        children: [
          _Header(
            position: c.queue.position,
            total: c.queue.total,
            points: c.tally.points,
            onClose: _close,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              // The deck name gets all the room the other chips leave.
              Expanded(
                child: Row(
                  children: [
                    Flexible(child: Tag(label: deck?.name ?? S.allDecks, color: deckColor)),
                    const SizedBox(width: 8),
                    Tag(label: _kind(card.kind), color: Q.textMuted, background: Q.surface),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Pulse(trigger: c.multiplier, child: Tag(label: S.multiplierChip(c.multiplier), color: Q.multiplier)),
            ],
          ),
          const SizedBox(height: 14),
          if (c.offline) ...[
            const OfflineBanner(),
            const SizedBox(height: 10),
          ],
          Expanded(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (c.queue.remaining > 2) const _StackLayer(inset: 24, top: 22, bottom: -4, color: Q.stack2),
                if (c.queue.remaining > 1) const _StackLayer(inset: 12, top: 12, bottom: 4, color: Q.stack1),
                Positioned.fill(
                  bottom: 14,
                  // The card grows once it's turned over: the answer gets more room.
                  child: AnimatedPadding(
                    duration: grow,
                    curve: Curves.easeOutCubic,
                    padding: _revealed ? EdgeInsets.zero : const EdgeInsets.fromLTRB(14, 12, 14, 0),
                    child: SwipeCard(
                      key: _cardKey,
                      card: card,
                      enabled: c.canAnswer,
                      onAnswer: c.answer,
                      onRevealed: () => setState(() => _revealed = true),
                    ),
                  ),
                ),
                for (final f in _floaters)
                  Positioned(
                    key: ValueKey(f.id),
                    top: 28,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: _FloatingPoints(
                        points: f.points,
                        rating: f.rating,
                        onDone: () => setState(() => _floaters.removeWhere((x) => x.id == f.id)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(S.hintDontKnow(c.points.dontKnow), style: QText.body(13, color: Q.dontKnow, weight: FontWeight.w800)),
              Expanded(child: Text(S.hintDrag, textAlign: TextAlign.center, style: QText.body(13, color: Q.textMuted))),
              Text(S.hintKnow(c.points.know), style: QText.body(13, color: Q.primary, weight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            // Vím / Nevím with their labels; the reveal row is centered in the same height.
            height: 96,
            child: AnimatedSwitcher(
              duration: grow,
              child: _revealed ? _answerRow(c) : _revealRow(c),
            ),
          ),
        ],
      ),
    );
  }

  /// Before the card is turned: turn it over, or skip it. Swiping works anyway.
  Widget _revealRow(SessionController c) => Row(
        key: const ValueKey('reveal'),
        children: [
          _RoundButton(
            label: S.skip,
            icon: Icons.redo_rounded,
            color: Q.textMuted,
            size: 52,
            filled: true,
            onPressed: c.canAnswer && c.queue.remaining > 1 ? c.skip : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: PrimaryButton(
              label: S.flipCard,
              icon: Icons.flip_rounded,
              height: 60,
              onPressed: c.canAnswer ? _reveal : null,
            ),
          ),
        ],
      );

  /// After the card is turned: Nevím / Přeskočit / Vím.
  Widget _answerRow(SessionController c) => Padding(
        key: const ValueKey('answer'),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _RoundButton(
                  label: S.dontKnow,
                  icon: Icons.close_rounded,
                  color: Q.dontKnow,
                  size: 68,
                  onPressed: c.canAnswer ? () => _answer(Rating.dontKnow) : null,
                ),
                _RoundButton(
                  label: S.skip,
                  icon: Icons.redo_rounded,
                  color: Q.textMuted,
                  size: 52,
                  filled: true,
                  onPressed: c.canAnswer && c.queue.remaining > 1 ? c.skip : null,
                ),
                _RoundButton(
                  label: S.know,
                  icon: Icons.check_rounded,
                  color: Q.primary,
                  size: 68,
                  onPressed: c.canAnswer ? () => _answer(Rating.know) : null,
                ),
              ],
            ),
      );

  static String _kind(CardKind kind) => switch (kind) {
        CardKind.newCard => S.kindNew,
        CardKind.learning => S.kindLearning,
        CardKind.review => S.kindReview,
        CardKind.relearning => S.kindRelearning,
      };
}

class _Header extends StatelessWidget {
  const _Header({required this.position, required this.total, required this.points, required this.onClose});

  final int position;
  final int total;
  final int points;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : (position - 1) / total;
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          SizedBox.square(
            dimension: 44,
            child: IconButton(
              tooltip: S.closeSession,
              onPressed: onClose,
              style: IconButton.styleFrom(
                backgroundColor: Q.surface,
                foregroundColor: Q.textMuted,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.close_rounded),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Semantics(
              label: S.progressLabel,
              value: S.cardOf(position, total),
              excludeSemantics: true,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: progress),
                      duration: const Duration(milliseconds: 300),
                      builder: (context, value, _) => LinearProgressIndicator(
                        value: value,
                        minHeight: 10,
                        backgroundColor: Q.surface2,
                        color: Q.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(S.cardOf(position, total), style: QText.body(12, color: Q.textMuted, weight: FontWeight.w700)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: Q.surface2, borderRadius: BorderRadius.circular(999)),
            child: Row(
              children: [
                const Icon(Icons.star_rounded, color: Q.points, size: 18),
                const SizedBox(width: 5),
                RollingNumber(
                  value: points,
                  format: formatSigned,
                  style: QText.body(15, color: Q.points, weight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "+11" rising from the card after an answer (design screen 4).
class _FloatingPoints extends StatelessWidget {
  const _FloatingPoints({required this.points, required this.rating, required this.onDone});

  final int points;
  final Rating rating;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final color = rating == Rating.know ? Q.primary : Q.dontKnow;
    return ExcludeSemantics(
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Q.bg.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.6)),
          ),
          child: Text(formatSigned(points), style: QText.heading(30, color: color)),
        )
            .animate(onComplete: (_) => onDone())
            .scaleXY(begin: 0.6, end: 1, duration: 220.ms, curve: Curves.easeOutBack)
            .moveY(begin: 20, end: -70, duration: 950.ms, curve: Curves.easeOutCubic)
            .fadeOut(delay: 550.ms, duration: 400.ms),
      ),
    );
  }
}

class _StackLayer extends StatelessWidget {
  const _StackLayer({required this.inset, required this.top, required this.bottom, required this.color});

  final double inset;
  final double top;
  final double bottom;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: inset,
      right: inset,
      top: top,
      bottom: bottom,
      child: DecoratedBox(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(28))),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.size,
    required this.onPressed,
    this.filled = false,
  });

  final String label;
  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final c = enabled ? color : Q.border;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          enabled: enabled,
          label: label,
          excludeSemantics: true,
          child: SizedBox.square(
            dimension: size,
            child: IconButton(
              onPressed: onPressed,
              style: IconButton.styleFrom(
                backgroundColor: filled ? Q.surface2 : c.withValues(alpha: 0.12),
                foregroundColor: c,
                disabledForegroundColor: c,
                disabledBackgroundColor: filled ? Q.surface2 : c.withValues(alpha: 0.08),
                shape: CircleBorder(side: filled ? BorderSide.none : BorderSide(color: c, width: 2)),
              ),
              icon: Icon(icon, size: size * 0.45),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: QText.body(13, color: c, weight: FontWeight.w800)),
      ],
    );
  }
}

class _Saving extends StatelessWidget {
  const _Saving({required this.offline, required this.onClose});

  final bool offline;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (offline) ...[const OfflineBanner(), const SizedBox(height: 32)],
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(S.saving, style: QText.body(16, color: Q.textMuted)),
          if (offline) ...[
            const SizedBox(height: 32),
            SecondaryButton(label: S.backHome, onPressed: onClose),
          ],
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onClose, required this.unseen, required this.onMore});

  final VoidCallback onClose;

  /// New cards that could still be learned today on request.
  final int unseen;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(color: Q.tint(Q.primary), shape: BoxShape.circle),
            child: const Icon(Icons.check_rounded, color: Q.primary, size: 52),
          ),
          const SizedBox(height: 24),
          Text(S.emptySessionTitle, style: QText.heading(28), textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Text(
            unseen > 0 ? S.emptySessionMore : S.emptySessionText,
            textAlign: TextAlign.center,
            style: QText.body(16, color: Q.textMuted, weight: FontWeight.w400, height: 1.45),
          ),
          const SizedBox(height: 32),
          if (unseen > 0) ...[
            PrimaryButton(label: S.moreNewCards(math.min(extraNewStep, unseen)), icon: Icons.add_rounded, onPressed: onMore),
            const SizedBox(height: 10),
            SecondaryButton(label: S.backHome, onPressed: onClose),
          ] else
            PrimaryButton(label: S.backHome, onPressed: onClose),
        ],
      ),
    );
  }
}
