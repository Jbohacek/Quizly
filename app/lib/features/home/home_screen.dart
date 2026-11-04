import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
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
import '../notifications/ask_card.dart';
import '../session/session_controller.dart';
import '../updates/app_update.dart';
import '../updates/update_card.dart';
import 'deck_screen.dart';
import 'week.dart';

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
            onRefresh: () {
              ref.invalidate(availableUpdateProvider);
              return ref.refresh(homeProvider.future);
            },
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
    final unseen = decks.fold(0, (sum, d) => sum + d.unseenCards);
    final extra = math.min(extraNewStep, unseen);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      children: [
        _Header(name: me.user.displayName, balance: me.summary.balance),
        const SizedBox(height: 16),
        const UpdateCard(),
        const NotificationAskCard(),
        _StreakCard(summary: me.summary, week: data.week),
        const SizedBox(height: 16),
        _GoalCard(today: me.summary.today, due: data.dueReviews, fresh: data.newToday),
        const SizedBox(height: 16),
        if (me.dueNow > 0)
          PrimaryButton(
            label: S.studyAll(me.dueNow),
            icon: Icons.play_arrow_rounded,
            height: 60,
            onPressed: () => context.push(sessionPath()),
          )
        else if (extra > 0)
          // Today's new cards are done; more only when asked for (#9).
          PrimaryButton(
            label: S.moreNewCards(extra),
            icon: Icons.add_rounded,
            height: 60,
            onPressed: () => context.push(sessionPath(extraNew: extra)),
          )
        else
          const PrimaryButton(label: S.nothingDue, icon: Icons.check_rounded, height: 60),
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

class _Header extends ConsumerWidget {
  const _Header({required this.name, required this.balance});

  final String name;
  final int balance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        // Without the shop the pill only shows the balance.
        if (ref.watch(shopEnabledProvider))
          PointsPill(balance: balance, semanticsLabel: S.pointsPill(balance), onTap: () => context.go('/shop'))
        else
          PointsPill(balance: balance, semanticsLabel: S.pointsBalance(balance)),
      ],
    );
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.summary, required this.week});

  final Summary summary;

  /// Null when the stats couldn't be loaded; the strip is left out then.
  final List<DayMark>? week;

  @override
  Widget build(BuildContext context) {
    final next = summary.nextMultiplier;
    final hint = summary.streak == 0 && !summary.today.goalMet
        ? S.startStreak
        : next == null
            ? S.maxMultiplier
            : S.nextMultiplier(next.inDays, next.value);
    final week = this.week;
    return Panel(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: Q.tint(Q.primary), borderRadius: BorderRadius.circular(18)),
                child: _Flame(lit: summary.streak > 0),
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
          if (week != null && week.length == 7) ...[
            const SizedBox(height: 16),
            _WeekStrip(marks: week),
          ],
        ],
      ),
    );
  }
}

/// The streak flame; it breathes gently while a streak is going (off with reduce motion).
class _Flame extends StatelessWidget {
  const _Flame({required this.lit});

  final bool lit;

  @override
  Widget build(BuildContext context) {
    const icon = Icon(Icons.local_fire_department_rounded, color: Q.primary, size: 32);
    if (!lit || MediaQuery.disableAnimationsOf(context)) return icon;
    return icon
        .animate(onPlay: (controller) => controller.repeat(reverse: true))
        .scaleXY(begin: 1, end: 1.12, duration: 900.ms, curve: Curves.easeInOut);
  }
}

/// Mon–Sun of this week: met days ticked, today dashed (design screen 2).
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.marks});

  final List<DayMark> marks;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: S.thisWeek,
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Semantics(
                container: true,
                label: '${S.weekdaysLong[i]}: ${_meaning(marks[i])}',
                excludeSemantics: true,
                child: Column(
                  children: [
                    Text(
                      S.weekdaysShort[i],
                      style: QText.body(12, color: marks[i] == DayMark.today ? Q.primary : Q.textMuted, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    _Dot(mark: marks[i]),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _meaning(DayMark mark) => switch (mark) {
        DayMark.done => S.dayDone,
        DayMark.today => S.dayToday,
        DayMark.missed => S.dayMissed,
        DayMark.future => S.dayFuture,
      };
}

class _Dot extends StatelessWidget {
  const _Dot({required this.mark});

  final DayMark mark;

  @override
  Widget build(BuildContext context) {
    return switch (mark) {
      DayMark.done => Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(color: Q.primary, shape: BoxShape.circle),
          child: const Icon(Icons.check_rounded, color: Q.onPrimary, size: 20),
        ),
      DayMark.today => CustomPaint(size: const Size.square(32), painter: _DashedCircle()),
      DayMark.missed => Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Q.inputBorder, width: 1.5)),
        ),
      DayMark.future => Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(color: Q.surface2, shape: BoxShape.circle),
        ),
    };
  }
}

/// Today in the week strip: a dashed primary ring.
class _DashedCircle extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Q.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    const dashes = 12;
    const sweep = 2 * math.pi / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc((Offset.zero & size).deflate(1), i * sweep, sweep * 0.55, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedCircle oldDelegate) => false;
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
                    const SizedBox(height: 8),
                    DeckProgressBar(deck: deck),
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
