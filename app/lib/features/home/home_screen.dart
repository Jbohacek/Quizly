import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';

/// Domů (design screen 2): greeting, points, streak, daily goal, CTA and decks.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(homeProvider);
    return SafeArea(
      bottom: false,
      child: switch (home) {
        AsyncValue(:final value?) => RefreshIndicator(
            color: Q.primary,
            backgroundColor: Q.surface,
            onRefresh: () => ref.refresh(homeProvider.future),
            child: _HomeBody(data: value),
          ),
        AsyncValue(:final error?) => ErrorView(
            message: error is ApiException ? error.message : S.loadFailed,
            onRetry: () => ref.invalidate(homeProvider),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _HomeBody extends StatelessWidget {
  const _HomeBody({required this.data});

  final HomeData data;

  @override
  Widget build(BuildContext context) {
    final me = data.me;
    final decks = data.decks.items;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      children: [
        _Header(name: me.user.displayName, balance: me.summary.balance),
        const SizedBox(height: 16),
        _StreakCard(summary: me.summary),
        const SizedBox(height: 16),
        _GoalCard(today: me.summary.today, due: data.dueReviews, fresh: data.newToday),
        const SizedBox(height: 16),
        PrimaryButton(
          label: me.dueNow > 0 ? S.studyAll(me.dueNow) : S.nothingDue,
          icon: me.dueNow > 0 ? Icons.play_arrow_rounded : Icons.check_rounded,
          height: 60,
          onPressed: me.dueNow > 0 ? () => context.push('/session') : null,
        ),
        const SizedBox(height: 22),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: Text(S.decks, style: QText.heading(19))),
            Text(S.deckCount(decks.length), style: QText.body(13, color: Q.textMuted)),
          ],
        ),
        const SizedBox(height: 10),
        if (decks.isEmpty)
          Panel(
            radius: 18,
            child: Text(S.noDecks, style: QText.body(14, color: Q.textMuted, weight: FontWeight.w400, height: 1.5)),
          ),
        for (final deck in decks) ...[
          _DeckTile(deck: deck),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.name, required this.balance});

  final String name;
  final int balance;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(formatLongDate(now), style: QText.body(13, color: Q.textMuted)),
              const SizedBox(height: 2),
              Text(S.greeting(name), style: QText.heading(26), maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Semantics(
          button: true,
          label: S.pointsPill(balance),
          excludeSemantics: true,
          child: Material(
            color: Q.surface2,
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => context.go('/shop'),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star_rounded, color: Q.points, size: 20),
                      const SizedBox(width: 6),
                      Text(formatInt(balance), style: QText.body(16, color: Q.points, weight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.summary});

  final Summary summary;

  @override
  Widget build(BuildContext context) {
    final next = summary.nextMultiplier;
    final hint = summary.streak == 0 && !summary.today.goalMet
        ? S.startStreak
        : next == null
            ? S.maxMultiplier
            : S.nextMultiplier(next.inDays, next.value);
    return Panel(
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: Q.tint(Q.primary), borderRadius: BorderRadius.circular(18)),
            child: const Icon(Icons.local_fire_department_rounded, color: Q.primary, size: 32),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(formatInt(summary.streak), style: QText.heading(40, color: Q.primary).copyWith(height: 1)),
                    const SizedBox(width: 8),
                    Flexible(child: Text(S.streakLabel(summary.streak), style: QText.body(17, weight: FontWeight.w800))),
                  ],
                ),
                const SizedBox(height: 4),
                Text(hint, style: QText.body(13, color: Q.textMuted)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: Q.tint(Q.multiplier), borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                Text(formatMultiplier(summary.multiplier), style: QText.heading(18, color: Q.multiplier)),
                Text(S.multiplier, style: QText.body(11, color: Q.multiplier, weight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.today, required this.due, required this.fresh});

  final Today today;
  final int due;
  final int fresh;

  @override
  Widget build(BuildContext context) {
    final progress = today.goal == 0 ? 1.0 : math.min(1.0, today.graded / today.goal);
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 76,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.square(
                  dimension: 70,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: progress),
                    duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) => CircularProgressIndicator(
                      value: value,
                      strokeWidth: 8,
                      strokeCap: StrokeCap.round,
                      backgroundColor: Q.border,
                      color: Q.primary,
                    ),
                  ),
                ),
                Text('${today.graded}/${today.goal}', style: QText.heading(18)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(S.dailyGoal, style: QText.body(13, color: Q.primary, weight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  today.goalMet ? S.goalMet : S.goalLeft(today.left),
                  style: QText.body(17, weight: FontWeight.w800, height: 1.25),
                ),
                const SizedBox(height: 4),
                Text(S.dueAndNew(due, fresh), style: QText.body(13, color: Q.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeckTile extends StatelessWidget {
  const _DeckTile({required this.deck});

  final Deck deck;

  @override
  Widget build(BuildContext context) {
    final color = parseHex(deck.color);
    final status = deck.dueNow > 0
        ? S.deckDue(deck.dueNow)
        : deck.newAvailable > 0
            ? S.deckNew(deck.newAvailable)
            : S.deckDone;
    final canStudy = deck.dueNow + deck.newAvailable > 0;
    return Material(
      color: Q.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Q.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/home/deck/${deck.id}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Q.tint(color), borderRadius: BorderRadius.circular(12)),
                child: Text(_initials(deck.name), style: QText.heading(15, color: color).copyWith(letterSpacing: 0)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            deck.name,
                            style: QText.body(15, weight: FontWeight.w800),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(status, style: QText.body(12, color: canStudy ? color : Q.textMuted, weight: FontWeight.w800)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: deck.masteredPercent / 100,
                        minHeight: 6,
                        backgroundColor: Q.border,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(S.deckMeta(deck.totalCards, deck.masteredPercent), style: QText.body(12, color: Q.textMuted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _initials(String name) {
    final letters = name.replaceAll(RegExp(r'\s+'), '');
    if (letters.isEmpty) return '?';
    return letters.characters.take(2).toString().toUpperCase();
  }
}
