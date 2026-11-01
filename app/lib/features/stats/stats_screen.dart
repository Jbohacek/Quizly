import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';
import 'stats_logic.dart';

/// Statistiky (design screen 6, CLAUDE.md §5.9): all decks or one deck.
class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  int? _deckId;

  Future<void> _pickDeck() async {
    final decks = ref.read(homeProvider).value?.decks.items ?? const <Deck>[];
    final picked = await showModalBottomSheet<({int? id})>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Q.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(S.chooseDeck, style: QText.heading(20)),
            ),
            _DeckOption(label: S.allDecksFilter, selected: _deckId == null, onTap: () => Navigator.pop(context, (id: null))),
            for (final d in decks)
              _DeckOption(
                label: d.name,
                color: parseHex(d.color),
                selected: _deckId == d.id,
                onTap: () => Navigator.pop(context, (id: d.id)),
              ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _deckId = picked.id);
  }

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(statsProvider(_deckId));
    final decks = ref.watch(homeProvider).value?.decks.items ?? const <Deck>[];
    final deckName = decks.where((d) => d.id == _deckId).firstOrNull?.name;
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: Q.primary,
        backgroundColor: Q.surface,
        onRefresh: () => ref.refresh(statsProvider(_deckId).future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          children: [
            ScreenHeader(
              title: S.navStats,
              trailing: _FilterButton(label: _deckId == null ? S.allDecksFilter : deckName ?? S.allDecksFilter, onTap: _pickDeck),
            ),
            const SizedBox(height: 14),
            ...switch (stats) {
              AsyncValue(:final value?) => _sections(value),
              AsyncValue(:final error?) => [
                  SizedBox(
                    height: 420,
                    child: ErrorView(
                      message: error is ApiException ? error.message : S.loadFailed,
                      onRetry: () => ref.invalidate(statsProvider(_deckId)),
                    ),
                  ),
                ],
              _ => const [SizedBox(height: 320, child: Center(child: CircularProgressIndicator()))],
            },
          ],
        ),
      ),
    );
  }

  List<Widget> _sections(Stats s) => [
        _Tiles(tiles: s.tiles),
        const SizedBox(height: 14),
        _HeatmapPanel(heatmap: s.heatmap),
        const SizedBox(height: 14),
        _DailyPanel(days: s.daily, goal: s.goal),
        const SizedBox(height: 14),
        _BestPanel(weekdays: s.weekdays, bestTime: s.bestTime),
        const SizedBox(height: 14),
        _ProgressPanel(decks: s.deckProgress),
      ];
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 190),
      child: Material(
        color: Q.surface,
        shape: const StadiumBorder(side: BorderSide(color: Q.inputBorder)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: SizedBox(
              height: 44,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(label, overflow: TextOverflow.ellipsis, style: QText.body(14, weight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.expand_more_rounded, size: 20, color: Q.textMuted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DeckOption extends StatelessWidget {
  const _DeckOption({required this.label, required this.selected, required this.onTap, this.color});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      selected: selected,
      minTileHeight: 52,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      leading: color == null
          ? const Icon(Icons.layers_rounded, color: Q.textMuted)
          : Container(width: 14, height: 14, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      title: Text(label, style: QText.body(16, weight: FontWeight.w700)),
      trailing: selected ? const Icon(Icons.check_rounded, color: Q.primary) : null,
    );
  }
}

class _Tiles extends StatelessWidget {
  const _Tiles({required this.tiles});

  final StatsTiles tiles;

  @override
  Widget build(BuildContext context) {
    final rate = tiles.successRate30d;
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Tile(label: S.tileStreak, value: days(tiles.streak), sub: Text(S.record(tiles.bestStreak), style: _subStyle)),
              const SizedBox(width: 10),
              _Tile(
                label: S.tileSuccess,
                value: rate == null ? S.noValue : formatPercent(rate),
                sub: _Sparkline(values: tiles.sparkline),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Tile(
                label: S.tileReviewed,
                value: formatInt(tiles.totalReviews),
                valueColor: Q.text,
                sub: Text(S.reviewedTotal(tiles.totalReviews), style: _subStyle),
              ),
              const SizedBox(width: 10),
              _Tile(
                label: S.tileEarned,
                value: formatInt(tiles.totalPointsEarned),
                valueColor: Q.points,
                sub: Text(S.earnedTotal(tiles.totalPointsEarned), style: _subStyle),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static final _subStyle = QText.body(12, color: Q.textMuted);
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, required this.sub, this.valueColor = Q.primary});

  final String label;
  final String value;
  final Widget sub;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Panel(
        radius: 20,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: QText.body(12, color: Q.textMuted, weight: FontWeight.w700)),
            const SizedBox(height: 4),
            FittedBox(child: Text(value, style: QText.heading(28, color: valueColor).copyWith(height: 1.1))),
            const SizedBox(height: 4),
            sub,
          ],
        ),
      ),
    );
  }
}

class _Sparkline extends StatelessWidget {
  const _Sparkline({required this.values});

  final List<int?> values;

  @override
  Widget build(BuildContext context) {
    final spots = [
      for (var i = 0; i < values.length; i++)
        if (values[i] != null) FlSpot(i.toDouble(), values[i]!.toDouble()),
    ];
    if (spots.length < 2) return Text(spots.isEmpty ? S.noReviewsYet : '', style: QText.body(12, color: Q.textMuted));
    final low = spots.map((s) => s.y).reduce(math.min);
    final high = spots.map((s) => s.y).reduce(math.max);
    return ExcludeSemantics(
      child: SizedBox(
        height: 22,
        child: LineChart(
          duration: motion(context, const Duration(milliseconds: 400)),
          LineChartData(
            minX: 0,
            maxX: (values.length - 1).toDouble(),
            minY: math.max(0, low - 5),
            maxY: math.min(100, high + 5),
            lineTouchData: const LineTouchData(enabled: false),
            titlesData: const FlTitlesData(show: false),
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                preventCurveOverShooting: true,
                color: Q.primary,
                barWidth: 2,
                dotData: const FlDotData(show: false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.note});

  final String title;
  final String? note;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Panel(
      radius: 20,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Semantics(header: true, child: Text(title, style: QText.heading(17)))),
              if (note != null) Text(note!, style: QText.body(12, color: Q.textMuted)),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _HeatmapPanel extends StatelessWidget {
  const _HeatmapPanel({required this.heatmap});

  final Heatmap heatmap;

  static const _labelWidth = 26.0;
  static const _gap = 3.0;

  @override
  Widget build(BuildContext context) {
    final weeks = heatmap.weeks;
    final todayWeek = weeks.length - 1;
    final todayDay = heatmap.today.weekday - 1;
    return _Section(
      title: S.activity,
      note: S.last17Weeks,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final cell = math.min(16.0, (constraints.maxWidth - _labelWidth - _gap * weeks.length) / weeks.length);
              final step = cell + _gap;
              return Semantics(
                container: true,
                label: S.activityLabel(metDays(heatmap)),
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 16,
                      child: Stack(
                        children: [
                          for (final m in monthLabels(heatmap))
                            Positioned(
                              left: _labelWidth + m.column * step,
                              child: Text(S.monthsShort[m.month - 1], style: _labelStyle),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: _labelWidth,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var d = 0; d < 7; d++)
                                SizedBox(
                                  height: step,
                                  child: d.isEven ? Text(S.weekdaysShort[d], style: _labelStyle.copyWith(height: 1.1)) : null,
                                ),
                            ],
                          ),
                        ),
                        for (var w = 0; w < weeks.length; w++)
                          Padding(
                            padding: const EdgeInsets.only(right: _gap),
                            child: Column(
                              children: [
                                for (var d = 0; d < 7; d++)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: _gap),
                                    child: _Cell(
                                      size: cell,
                                      level: d < weeks[w].length ? weeks[w][d] : null,
                                      today: w == todayWeek && d == todayDay,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 6,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(S.less, style: _labelStyle),
                  const SizedBox(width: 6),
                  for (final c in Q.heat) ...[
                    Container(width: 12, height: 12, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
                    const SizedBox(width: 4),
                  ],
                  const SizedBox(width: 2),
                  Text(S.more, style: _labelStyle),
                ],
              ),
              Text(S.darkerBelowGoal, style: _labelStyle),
            ],
          ),
        ],
      ),
    );
  }

  static final _labelStyle = QText.body(11, color: Q.textMuted, weight: FontWeight.w700);
}

class _Cell extends StatelessWidget {
  const _Cell({required this.size, required this.level, required this.today});

  final double size;
  final int? level;
  final bool today;

  @override
  Widget build(BuildContext context) {
    final l = level;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: l == null ? Colors.transparent : Q.heat[l.clamp(0, 4)],
        borderRadius: BorderRadius.circular(3),
        border: today
            ? Border.all(color: Q.text, width: 2)
            : l == null
                ? Border.all(color: Q.inputBorder)
                : null,
      ),
    );
  }
}

class _DailyPanel extends StatelessWidget {
  const _DailyPanel({required this.days, required this.goal});

  final List<DayCount> days;
  final int goal;

  @override
  Widget build(BuildContext context) {
    final maxY = math.max(goal * 1.5, days.fold<int>(0, (m, d) => math.max(m, d.graded)) * 1.1).toDouble();
    final last = days.length - 1;
    return _Section(
      title: S.perDay,
      note: S.last14Days,
      child: Semantics(
        container: true,
        label: S.perDayLabel(days.isEmpty ? 0 : days.last.graded, goal),
        excludeSemantics: true,
        child: SizedBox(
          height: 124,
          child: BarChart(
            duration: motion(context, const Duration(milliseconds: 500)),
            BarChartData(
              maxY: maxY <= 0 ? 1 : maxY,
              minY: 0,
              alignment: BarChartAlignment.spaceBetween,
              barTouchData: BarTouchData(enabled: false),
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                topTitles: const AxisTitles(),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 20,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i > last) return const SizedBox.shrink();
                      return SideTitleWidget(
                        meta: meta,
                        space: 6,
                        child: Text(
                          '${days[i].date.day}',
                          style: QText.body(11, color: i == last ? Q.text : Q.textMuted, weight: FontWeight.w700),
                        ),
                      );
                    },
                  ),
                ),
              ),
              extraLinesData: ExtraLinesData(
                horizontalLines: [
                  HorizontalLine(
                    y: goal.toDouble(),
                    color: Q.text,
                    strokeWidth: 1.5,
                    dashArray: const [5, 4],
                    label: HorizontalLineLabel(
                      show: true,
                      alignment: Alignment.topLeft,
                      padding: const EdgeInsets.only(bottom: 2),
                      style: QText.body(11, weight: FontWeight.w800),
                      labelResolver: (_) => S.goalLine(goal),
                    ),
                  ),
                ],
              ),
              barGroups: [
                for (var i = 0; i < days.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: days[i].graded.toDouble(),
                        width: 14,
                        color: i == last
                            ? Q.primary.withValues(alpha: days[i].graded >= goal ? 1 : 0.45)
                            : days[i].graded >= goal
                                ? Q.primary
                                : Q.legendNew,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4), bottom: Radius.circular(2)),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BestPanel extends StatelessWidget {
  const _BestPanel({required this.weekdays, required this.bestTime});

  final List<WeekdayStat> weekdays;
  final BestTime? bestTime;

  @override
  Widget build(BuildContext context) {
    final best = bestWeekday(weekdays);
    final rates = weekdays.map((w) => w.successRate).whereType<int>();
    final low = rates.isEmpty ? 0 : math.max(0, rates.reduce(math.min) - 10);
    final time = bestTime;
    final lines = [
      if (best != null) S.bestDay(best.weekday),
      if (time != null) S.bestTime(hourOf(time.from), hourOf(time.to), time.successRate),
    ];
    return _Section(
      title: S.bestTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 104,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final w in weekdays) ...[
                  if (w != weekdays.first) const SizedBox(width: 6),
                  Expanded(child: _WeekdayBar(stat: w, low: low, best: w == best)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: Q.surface2, borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                const Icon(Icons.schedule_rounded, color: Q.primary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    lines.isEmpty ? S.bestNone : lines.join(' '),
                    style: QText.body(13, weight: FontWeight.w600, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekdayBar extends StatelessWidget {
  const _WeekdayBar({required this.stat, required this.low, required this.best});

  final WeekdayStat stat;
  final int low;
  final bool best;

  @override
  Widget build(BuildContext context) {
    final rate = stat.successRate;
    final color = best ? Q.primary : Q.textMuted;
    final height = rate == null ? 6.0 : 10 + 54 * (rate - low) / math.max(1, 100 - low);
    final name = S.weekdaysShort[stat.weekday - 1];
    return Semantics(
      container: true,
      label: '${S.weekdaysLong[stat.weekday - 1]}: ${rate == null ? S.noValue : formatPercent(rate)}',
      excludeSemantics: true,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FittedBox(
            child: Text(rate == null ? S.noValue : formatPercent(rate), style: QText.body(11, color: color, weight: FontWeight.w800)),
          ),
          const SizedBox(height: 4),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 6, end: height),
            duration: motion(context, const Duration(milliseconds: 500)),
            curve: Curves.easeOutCubic,
            builder: (context, h, _) => Container(
              height: h,
              decoration: BoxDecoration(
                color: best ? Q.primary : rate == null ? Q.surface2 : Q.inputBorder,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(name, style: QText.body(11, color: color, weight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _ProgressPanel extends StatelessWidget {
  const _ProgressPanel({required this.decks});

  final List<DeckProgress> decks;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: S.progressTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (decks.isEmpty)
            Text(S.noProgress, style: QText.body(14, color: Q.textMuted, weight: FontWeight.w400))
          else
            for (final d in decks) ...[
              Row(
                children: [
                  Expanded(child: Text(d.name, style: QText.body(13, weight: FontWeight.w800), overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      S.deckMeta(d.progress.total, percentOf(d.progress.mastered, d.progress.total)),
                      style: QText.body(13, color: Q.textMuted),
                      textAlign: TextAlign.end,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ProgressBar(mastered: d.progress.mastered, learning: d.progress.learning, fresh: d.progress.fresh),
              const SizedBox(height: 14),
            ],
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              _Legend(color: Q.primary, label: S.statusMastered),
              _Legend(color: Q.multiplier, label: S.statusLearning),
              _Legend(color: Q.legendNew, label: S.legendNew),
            ],
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 5),
        Text(label, style: QText.body(11, color: Q.textMuted, weight: FontWeight.w700)),
      ],
    );
  }
}
