import 'package:flutter_test/flutter_test.dart';
import 'package:quizly/core/api/models.dart';
import 'package:quizly/core/format.dart';
import 'package:quizly/core/strings.dart';
import 'package:quizly/features/home/week.dart';
import 'package:quizly/features/shop/wishlist.dart';
import 'package:quizly/features/stats/stats_logic.dart';

const nbsp = ' ';

/// 17 weeks from Monday 2026-07-13; the last one is the current week.
Heatmap heatmap(List<int?> lastWeek, {String today = '2026-11-04'}) => Heatmap.fromJson({
      'from': '2026-07-13',
      'to': '2026-11-08',
      'today': today,
      'weeks': [
        for (var w = 0; w < 16; w++) [0, 1, 2, 3, 4, 0, 2],
        lastWeek,
      ],
    });

ShopItem item(int id, {int price = 100, int missing = 0, bool wishlisted = true, bool soldOut = false}) => ShopItem(
      id: id,
      name: 'Odměna $id',
      description: '',
      price: price,
      stock: soldOut ? 0 : 1,
      soldOut: soldOut,
      wishlisted: wishlisted,
      missing: missing,
    );

void main() {
  group('week strip', () {
    test('met days are ticked, today is open until met, later days are empty', () {
      // Wednesday: Monday met (level 3), Tuesday below goal (1), today not met yet (0).
      expect(weekMarks(heatmap([3, 1, 0, null, null, null, null])), [
        DayMark.done,
        DayMark.missed,
        DayMark.today,
        DayMark.future,
        DayMark.future,
        DayMark.future,
        DayMark.future,
      ]);
    });

    test('today counts as done once the goal is met', () {
      expect(weekMarks(heatmap([2, 4, 2, null, null, null, null])).take(3), everyElement(DayMark.done));
    });

    test('Sunday is the last day of the week', () {
      final marks = weekMarks(heatmap([2, 2, 2, 2, 2, 0, 1], today: '2026-11-08'));
      expect(marks.sublist(5), [DayMark.missed, DayMark.today]);
    });
  });

  group('wishlist target', () {
    test('the nearest item still missing points wins', () {
      final target = wishlistTarget([
        item(1, price: 5000, missing: 3543),
        item(2, price: 1500, missing: 43),
        item(3, price: 80, missing: 0, wishlisted: false),
      ]);
      expect(target?.item.id, 2);
      expect(target?.reached, isFalse);
    });

    test('when every hearted item is affordable, the cheapest one is shown as reached', () {
      final target = wishlistTarget([item(1, price: 900), item(2, price: 300)]);
      expect(target?.item.id, 2);
      expect(target?.reached, isTrue);
    });

    test('sold-out and un-hearted items are left out', () {
      expect(wishlistTarget([item(1, missing: 10, soldOut: true), item(2, missing: 5, wishlisted: false)]), isNull);
      expect(wishlistTarget(const []), isNull);
    });

    test('Vím answers needed for the missing points round up', () {
      expect(knowAnswersFor(43, 11), 4);
      expect(knowAnswersFor(44, 11), 4);
      expect(knowAnswersFor(45, 11), 5);
      expect(knowAnswersFor(0, 11), 0);
      expect(knowAnswersFor(15, 0), 2);
    });
  });

  group('stats', () {
    test('month labels go on the weeks that hold the 1st of a month', () {
      final labels = monthLabels(heatmap([0, 0, 0, null, null, null, null]));
      // From 13 July: Aug 1 is in week 2 (27 Jul–2 Aug), Sep 1 week 7, Oct 1 week 11, Nov 1 week 15.
      expect(labels.map((l) => (l.column, l.month)), [(0, 7), (2, 8), (7, 9), (11, 10), (15, 11)]);
    });

    test('a month starting too close to the first column gets no extra label', () {
      final h = Heatmap.fromJson({
        'from': '2026-07-27',
        'today': '2026-11-18',
        'weeks': [for (var w = 0; w < 17; w++) List.filled(7, 0)],
      });
      expect(monthLabels(h).first, (column: 0, month: 8));
    });

    test('met days count level 2 and up', () {
      // 16 weeks × 4 met days + Monday of this week.
      expect(metDays(heatmap([3, 1, 0, null, null, null, null])), 16 * 4 + 1);
    });

    test('best weekday: highest rate, then more answers; days without enough answers are skipped', () {
      WeekdayStat w(int day, int? rate, int graded) => WeekdayStat(weekday: day, successRate: rate, graded: graded);
      expect(bestWeekday([w(1, 78, 40), w(4, 88, 20), w(5, 88, 30), w(6, null, 3)])?.weekday, 5);
      expect(bestWeekday([w(1, null, 2)]), isNull);
      expect(hourOf('18:00'), 18);
    });
  });

  group('Czech texts', () {
    test('purchase dates: time today, short date otherwise', () {
      final now = DateTime(2026, 11, 2, 21);
      expect(formatWhen(DateTime(2026, 11, 2, 19, 40), now), 'dnes 19:40');
      expect(formatWhen(DateTime(2026, 11, 2, 8, 5), now), 'dnes 8:05');
      expect(formatWhen(DateTime(2026, 10, 24, 12), now), '24.${nbsp}10.');
    });

    test('refunded points agree with the number', () {
      expect(S.claimRefunded(1), '1${nbsp}bod vrácen');
      expect(S.claimRefunded(3), '3${nbsp}body vráceny');
      expect(S.claimRefunded(800), '800${nbsp}bodů vráceno');
    });

    test('milestone, streak and wishlist lines', () {
      expect(S.milestoneTitle(7), '7${nbsp}dní v řadě!');
      expect(S.milestoneText(50), 'Bonus +50${nbsp}bodů je tvůj. Tohle je paráda! 🎉');
      expect(S.streakGrows(13), 'Série roste na 13${nbsp}dní.');
      expect(S.multiplierTomorrow(1.2), 'Zítra se ti násobič zvedne na 1,2×.');
      expect(S.wishlistLeft(43, 4), 'Chybí už jen 43${nbsp}bodů, to je zhruba 4 × Vím.');
      expect(S.stockLeft(2), 'Zbývá 2 ks');
      expect(S.bestDay(4), 'Nejlíp ti to jde ve čtvrtek.');
      expect(S.reviewedTotal(1284), 'karet celkem');
      expect(S.earnedTotal(2), 'body celkem');
    });
  });
}
