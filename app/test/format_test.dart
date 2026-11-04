import 'package:flutter_test/flutter_test.dart';
import 'package:quizly/core/format.dart';

const nbsp = ' ';

void main() {
  test('thousands use a non-breaking space', () {
    expect(formatInt(0), '0');
    expect(formatInt(999), '999');
    expect(formatInt(1457), '1${nbsp}457');
    expect(formatInt(1000000), '1${nbsp}000${nbsp}000');
    expect(formatInt(-1200), '−1${nbsp}200');
    expect(formatSigned(11), '+11');
    expect(formatSigned(0), '0');
  });

  test('multiplier and percent', () {
    expect(formatMultiplier(1.1), '1,1×');
    expect(formatMultiplier(2), '2,0×');
    expect(formatPercent(83), '83$nbsp%');
    expect(percentOf(19, 23), 83);
    expect(percentOf(1, 2), 50);
    expect(percentOf(0, 0), 0);
  });

  test('APK size in megabytes', () {
    expect(formatMegabytes(23456789), '23,5${nbsp}MB');
    expect(formatMegabytes(1234), '0,0${nbsp}MB');
  });

  test('Czech plurals', () {
    expect(cards(1), '1${nbsp}karta');
    expect(cards(3), '3${nbsp}karty');
    expect(cards(5), '5${nbsp}karet');
    expect(cards(0), '0${nbsp}karet');
    expect(cardsAccusative(1), '1${nbsp}kartu');
    expect(days(1), '1${nbsp}den');
    expect(days(4), '4${nbsp}dny');
    expect(days(12), '12${nbsp}dní');
    expect(points(1), '1${nbsp}bod');
    expect(points(2), '2${nbsp}body');
    expect(points(1457), '1${nbsp}457${nbsp}bodů');
  });

  test('dates', () {
    expect(formatLongDate(DateTime(2026, 10, 31)), 'Sobota 31. října');
    expect(formatLongDate(DateTime(2026, 11, 2)), 'Pondělí 2. listopadu');
    expect(formatShortDate(DateTime(2026, 10, 31)), '31.${nbsp}10.');
  });
}
