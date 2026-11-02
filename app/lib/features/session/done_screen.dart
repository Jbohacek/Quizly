import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import '../shop/shop_screen.dart';
import '../shop/wishlist.dart';
import 'session_controller.dart';

/// Hotovo (design screen 5): results, points breakdown, new balance, wishlist progress.
/// Confetti when the daily goal or a streak milestone was reached in this session.
class DoneScreen extends StatefulWidget {
  const DoneScreen({super.key, required this.result});

  final SessionResult result;

  @override
  State<DoneScreen> createState() => _DoneScreenState();
}

class _DoneScreenState extends State<DoneScreen> {
  final _confetti = ConfettiController(duration: const Duration(milliseconds: 1200));

  bool get _celebrate => widget.result.tally.goalMetInSession || widget.result.tally.milestones.isNotEmpty;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_celebrate && !MediaQuery.disableAnimationsOf(context) && _confetti.state == ConfettiControllerState.stopped) {
      _confetti.play();
    }
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final tally = result.tally;
    final summary = result.summary;
    final today = summary.today;
    final goalMet = tally.goalMetInSession;
    final milestone = tally.milestones.lastOrNull;
    final next = summary.nextMultiplier;
    final title = milestone != null
        ? S.milestoneTitle(milestone.days ?? summary.streak)
        : goalMet
            ? S.goalMetTitle
            : S.doneTitle;
    final subtitle = milestone != null
        ? S.milestoneText(milestone.bonus ?? 0)
        : goalMet
            ? [
                S.streakGrows(summary.streak),
                if (next != null)
                  next.inDays == 1 ? S.multiplierTomorrow(next.value) : S.multiplierIn(next.inDays, next.value),
              ].join(' ')
            : today.goalMet
                ? S.streakNow(summary.streak)
                : S.doneGoalLeft(today.left);
    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 40, 20, 24),
              children: [
                Center(
                  child: Container(
                    width: 132,
                    height: 132,
                    decoration: BoxDecoration(
                      color: Q.primary.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                      border: Border.all(color: Q.primary, width: 3),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.local_fire_department_rounded, color: Q.primary, size: 34),
                        RollingNumber(
                          value: summary.streak,
                          from: goalMet ? summary.streak - 1 : null,
                          style: QText.heading(44, color: Q.primary).copyWith(height: 1),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Semantics(
                  header: true,
                  liveRegion: true,
                  child: Text(title, textAlign: TextAlign.center, style: QText.heading(34)),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: QText.body(16, color: Q.textMuted, weight: FontWeight.w400, height: 1.45),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    _Tile(label: S.tileCards, child: Text(formatInt(tally.graded), style: QText.heading(26))),
                    const SizedBox(width: 8),
                    _Tile(
                      label: S.tileCorrect,
                      child: Text(
                        formatPercent(percentOf(tally.knowCount, tally.graded)),
                        style: QText.heading(26, color: Q.primary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _Tile(
                      label: S.tilePoints,
                      child: RollingNumber(
                        value: tally.points,
                        from: 0,
                        format: formatSigned,
                        style: QText.heading(26, color: Q.points),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Panel(
                  radius: 20,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  child: Column(
                    children: [
                      _Row(S.knowRow(tally.knowCount), formatSigned(tally.knowPoints)),
                      _Row(S.dontKnowRow(tally.dontKnowCount), formatSigned(tally.dontKnowPoints)),
                      for (final m in tally.milestones)
                        _Row(S.milestoneRow(m.days ?? 0), formatSigned(m.bonus ?? 0), color: Q.points),
                      _Row(
                        S.multiplierRow,
                        S.multiplierCounted(tally.lastMultiplier ?? summary.multiplier),
                        color: Q.multiplier,
                      ),
                      const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Divider(height: 1, color: Q.border)),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            Expanded(child: Text(S.newBalance, style: QText.body(15, weight: FontWeight.w800))),
                            RollingNumber(
                              value: summary.balance,
                              from: summary.balance - tally.points,
                              format: points,
                              style: QText.body(15, color: Q.points, weight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                _WishlistProgress(result: result),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: SecondaryButton(
                        label: S.studyMore,
                        onPressed: () => context.pushReplacement(sessionPath(deckId: result.deckId)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: PrimaryButton(label: S.done, height: 56, onPressed: () => context.pop())),
                  ],
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confetti,
              blastDirectionality: BlastDirectionality.explosive,
              numberOfParticles: 26,
              emissionFrequency: 0.04,
              maxBlastForce: 28,
              minBlastForce: 10,
              gravity: 0.25,
              colors: const [Q.primary, Q.points, Q.multiplier, Q.dontKnow, Q.info],
            ),
          ),
        ],
      ),
    );
  }
}

/// The nearest wishlist item, or the one this session made affordable.
class _WishlistProgress extends ConsumerWidget {
  const _WishlistProgress({required this.result});

  final SessionResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reached = result.tally.wishlistReached.lastOrNull;
    final balance = result.summary.balance;
    final WishlistCard card;
    if (reached != null) {
      card = WishlistCard(
        label: S.wishlistReady,
        name: reached.name ?? '',
        balance: balance,
        price: reached.price ?? balance,
        text: S.wishlistReadyText(reached.name ?? ''),
        onTap: () => context.go('/shop'),
      );
    } else {
      final target = wishlistTarget(ref.watch(shopProvider).value?.items ?? const []);
      if (target == null) return const SizedBox.shrink();
      final item = target.item;
      card = WishlistCard(
        label: S.fromWishlist,
        name: item.name,
        balance: balance,
        price: item.price,
        text: target.reached ? S.savingReady : S.wishlistLeft(item.missing, knowAnswersFor(item.missing, result.knowPoints)),
        onTap: () => context.go('/shop'),
      );
    }
    return Padding(padding: const EdgeInsets.only(top: 16), child: card);
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.child, required this.label});

  final Widget child;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Panel(
        radius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
        child: Column(
          children: [
            FittedBox(child: child),
            const SizedBox(height: 2),
            Text(label, style: QText.body(12, color: Q.textMuted, weight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.color = Q.text});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label, style: QText.body(14, color: Q.textMuted, weight: FontWeight.w600))),
          Text(value, style: QText.body(14, color: color, weight: FontWeight.w800)),
        ],
      ),
    );
  }
}
