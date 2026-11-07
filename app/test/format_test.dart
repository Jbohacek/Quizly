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

  group('review intervals (#31)', () {
    const min = 60, hour = 3600, day = 86400;

    test('minutes, hours, days, months and years', () {
      expect(formatInterval(0), '1${nbsp}min');
      expect(formatInterval(20), '1${nbsp}min');
      expect(formatInterval(330), '6${nbsp}min');
      expect(formatInterval(10 * min), '10${nbsp}min');
      expect(formatInterval(5 * hour), '5${nbsp}h');
      expect(formatInterval(8 * day), '8${nbsp}d');
      expect(formatInterval(45 * day), '1,5${nbsp}měs.');
      expect(formatInterval(60 * day), '2${nbsp}měs.');
      expect(formatInterval(730 * day), '2${nbsp}r.');
      expect(formatInterval(36500 * day), '100${nbsp}r.');
    });

    test('the unit is picked after rounding', () {
      expect(formatInterval(59 * min + 40), '1${nbsp}h');
      expect(formatInterval(23 * hour + 40 * min), '1${nbsp}d');
      expect(formatInterval(29 * day + 14 * hour), '1${nbsp}měs.');
      expect(formatInterval(364 * day), '1${nbsp}r.');
      expect(formatInterval(330 * day), '11${nbsp}měs.');
    });

    test('in words for screen readers', () {
      expect(formatIntervalSpoken(min), '1${nbsp}minuta');
      expect(formatIntervalSpoken(3 * min), '3${nbsp}minuty');
      expect(formatIntervalSpoken(10 * min), '10${nbsp}minut');
      expect(formatIntervalSpoken(1 * hour), '1${nbsp}hodina');
      expect(formatIntervalSpoken(8 * day), '8${nbsp}dní');
      expect(formatIntervalSpoken(2 * day), '2${nbsp}dny');
      expect(formatIntervalSpoken(45 * day), '1,5${nbsp}měsíce');
      expect(formatIntervalSpoken(365 * day), '1${nbsp}rok');
      expect(formatIntervalSpoken(912 * day), '2,5${nbsp}roku');
      expect(formatIntervalSpoken(1825 * day), '5${nbsp}let');
    });
  });
}
