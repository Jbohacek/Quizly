import '../../core/api/models.dart';

/// One day of the Mon–Sun strip on Domů.
enum DayMark { done, today, missed, future }

/// The current week from the stats heatmap (its last column, Monday first).
///
/// Level 2 and above means the goal was met: the level is graded ÷ that day's goal,
/// and a met day keeps the goal it was met with (spec §5.3, §10).
List<DayMark> weekMarks(Heatmap heatmap) {
  if (heatmap.weeks.isEmpty) return const [];
  final week = heatmap.weeks.last;
  final todayIndex = heatmap.today.weekday - 1;
  return [
    for (var i = 0; i < week.length; i++)
      switch (week[i]) {
        final level? when level >= 2 => DayMark.done,
        _ when i == todayIndex => DayMark.today,
        null => DayMark.future,
        _ => DayMark.missed,
      },
  ];
}
