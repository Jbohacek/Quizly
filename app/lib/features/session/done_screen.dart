import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/strings.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import 'session_controller.dart';

/// Hotovo (design screen 5, basic version): results, points breakdown, new balance.
/// Confetti and wishlist progress come in Etapa 6.
class DoneScreen extends StatelessWidget {
  const DoneScreen({super.key, required this.result});

  final SessionResult result;

  @override
  Widget build(BuildContext context) {
    final tally = result.tally;
    final summary = result.summary;
    final today = summary.today;
    final goalMet = tally.goalMetInSession;
    final subtitle = goalMet || today.goalMet ? S.streakNow(summary.streak) : S.doneGoalLeft(today.left);
    return Scaffold(
      body: SafeArea(
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
                    Text(formatInt(summary.streak), style: QText.heading(44, color: Q.primary).copyWith(height: 1)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(goalMet ? S.goalMetTitle : S.doneTitle, textAlign: TextAlign.center, style: QText.heading(34)),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center, style: QText.body(16, color: Q.textMuted, weight: FontWeight.w400, height: 1.45)),
            const SizedBox(height: 20),
            Row(
              children: [
                _Tile(value: formatInt(tally.graded), label: S.tileCards),
                const SizedBox(width: 8),
                _Tile(
                  value: formatPercent(percentOf(tally.knowCount, tally.graded)),
                  label: S.tileCorrect,
                  color: Q.primary,
                ),
                const SizedBox(width: 8),
                _Tile(value: formatSigned(tally.points), label: S.tilePoints, color: Q.points),
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
                  for (final m in tally.milestones) _Row(S.milestoneRow(m.days ?? 0), formatSigned(m.bonus ?? 0), color: Q.points),
                  _Row(S.multiplierRow, S.multiplierCounted(tally.lastMultiplier ?? summary.multiplier), color: Q.multiplier),
                  const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Divider(height: 1, color: Q.border)),
                  _Row(S.newBalance, points(summary.balance), color: Q.points, strong: true),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    label: S.studyMore,
                    onPressed: () => context.pushReplacement(
                      result.deckId == null ? '/session' : '/session?deck=${result.deckId}',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: PrimaryButton(label: S.done, height: 56, onPressed: () => context.pop())),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.value, required this.label, this.color = Q.text});

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Panel(
        radius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
        child: Column(
          children: [
            FittedBox(child: Text(value, style: QText.heading(26, color: color))),
            const SizedBox(height: 2),
            Text(label, style: QText.body(12, color: Q.textMuted, weight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.color = Q.text, this.strong = false});

  final String label;
  final String value;
  final Color color;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: strong ? QText.body(15, weight: FontWeight.w800) : QText.body(14, color: Q.textMuted, weight: FontWeight.w600),
            ),
          ),
          Text(value, style: QText.body(strong ? 15 : 14, color: color, weight: FontWeight.w800)),
        ],
      ),
    );
  }
}
