import '../../core/api/models.dart';

/// Columns of the heatmap that get a month label: each week that holds the 1st of a
/// month. The first column also gets one when the first new month is 2+ columns away.
List<({int column, int month})> monthLabels(Heatmap heatmap) {
  final labels = <({int column, int month})>[];
  for (var c = 0; c < heatmap.weeks.length; c++) {
    final monday = heatmap.dayAt(c, 0);
    final sunday = heatmap.dayAt(c, 6);
    if (monday.day == 1 || sunday.month != monday.month) {
      labels.add((column: c, month: sunday.month));
    }
  }
  if (heatmap.weeks.isNotEmpty && (labels.isEmpty || labels.first.column >= 2)) {
    labels.insert(0, (column: 0, month: heatmap.from.month));
  }
  return labels;
}

/// Days with the goal met in the heatmap (level 2+).
int metDays(Heatmap heatmap) => heatmap.weeks.expand((w) => w).where((l) => l != null && l >= 2).length;

/// The weekday with the highest success rate; a tie goes to the one with more answers.
WeekdayStat? bestWeekday(Iterable<WeekdayStat> weekdays) {
  WeekdayStat? best;
  for (final w in weekdays) {
    final rate = w.successRate;
    if (rate == null) continue;
    final b = best;
    if (b == null || rate > b.successRate! || (rate == b.successRate && w.graded > b.graded)) best = w;
  }
  return best;
}

/// Whole hour of an `HH:mm` time.
int hourOf(String time) => int.parse(time.split(':').first);
