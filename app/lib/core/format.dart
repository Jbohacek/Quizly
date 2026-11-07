/// Czech number, date and plural formatting (CLAUDE.md §2.12).
///
/// Thousands use a non-breaking space (`1 457`), decimals a comma (`1,1×`),
/// percent a non-breaking space before `%` (`83 %`).
library;

import 'dart:math' as math;

const _nbsp = ' ';

/// `1457` → `1 457`, `-1200` → `−1 200`.
String formatInt(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(_nbsp);
    buffer.write(digits[i]);
  }
  return value < 0 ? '−$buffer' : buffer.toString();
}

/// `11` → `+11`, `0` → `0`.
String formatSigned(int value) => value > 0 ? '+${formatInt(value)}' : formatInt(value);

/// `1.1` → `1,1×`, `2` → `2,0×`.
String formatMultiplier(num value) => '${value.toStringAsFixed(1).replaceAll('.', ',')}×';

/// `83` → `83 %`.
String formatPercent(int value) => '$value$_nbsp%';

/// An APK size: `12,3 MB` (decimal comma, CLAUDE.md §2.12).
String formatMegabytes(int bytes) => '${(bytes / 1000000).toStringAsFixed(1).replaceAll('.', ',')}${_nbsp}MB';

/// Whole percent of [part] in [total], rounded half up; 0 when [total] is 0.
int percentOf(int part, int total) => total == 0 ? 0 : ((part * 100) / total).round();

/// Picks the Czech plural form: 1 [one], 2–4 [few], 0 and 5+ [many].
String plural(int count, String one, String few, String many) {
  final n = count.abs();
  if (n == 1) return one;
  if (n >= 2 && n <= 4) return few;
  return many;
}

/// `5` → `5 karet` with the number formatted.
String countOf(int count, String one, String few, String many) =>
    '${formatInt(count)}$_nbsp${plural(count, one, few, many)}';

/// Cards in the nominative: 1 karta · 2 karty · 5 karet.
String cards(int count) => countOf(count, 'karta', 'karty', 'karet');

/// Cards in the accusative: 1 kartu · 2 karty · 5 karet.
String cardsAccusative(int count) => countOf(count, 'kartu', 'karty', 'karet');

/// Days: 1 den · 2 dny · 5 dní.
String days(int count) => countOf(count, 'den', 'dny', 'dní');

/// Points: 1 bod · 2 body · 5 bodů.
String points(int count) => countOf(count, 'bod', 'body', 'bodů');

enum _IntervalUnit { minute, hour, day, month, year }

/// Rounds [seconds] to the unit people would say. The unit is picked after rounding, so 59,6 min is `1 h`,
/// not `60 min`, and 364 days is `1 r.`, not `12,1 měs.` (a month is 30 days, a year 365).
({num amount, _IntervalUnit unit}) _interval(int seconds) {
  final minutes = math.max(1, (seconds / 60).round());
  if (minutes < 60) return (amount: minutes, unit: _IntervalUnit.minute);
  final hours = (seconds / 3600).round();
  if (hours < 24) return (amount: hours, unit: _IntervalUnit.hour);
  final days = (seconds / 86400).round();
  if (days < 30) return (amount: days, unit: _IntervalUnit.day);
  final months = _oneDecimal(days / 30);
  if (months < 12) return (amount: months, unit: _IntervalUnit.month);
  return (amount: _oneDecimal(days / 365), unit: _IntervalUnit.year);
}

/// `1.5` stays, `2.0` becomes `2`.
num _oneDecimal(double value) {
  final rounded = (value * 10).round() / 10;
  return rounded == rounded.roundToDouble() ? rounded.round() : rounded;
}

String _decimal(num value) => value.toString().replaceAll('.', ',');

/// The time to a card's next review under an answer button (#31): `1 min`, `5 h`, `8 d`, `1,5 měs.`, `2 r.`.
/// Abbreviations, so the number never needs a plural.
String formatInterval(int seconds) {
  final i = _interval(seconds);
  final unit = switch (i.unit) {
    _IntervalUnit.minute => 'min',
    _IntervalUnit.hour => 'h',
    _IntervalUnit.day => 'd',
    _IntervalUnit.month => 'měs.',
    _IntervalUnit.year => 'r.',
  };
  return '${_decimal(i.amount)}$_nbsp$unit';
}

/// [formatInterval] in words for screen readers: `1 minuta`, `5 hodin`, `8 dní`, `1,5 měsíce`, `2 roky`.
/// A decimal number takes the genitive singular (`1,5 měsíce`, `2,5 roku`).
String formatIntervalSpoken(int seconds) {
  final i = _interval(seconds);
  final amount = i.amount;
  final forms = switch (i.unit) {
    _IntervalUnit.minute => ('minuta', 'minuty', 'minut', 'minuty'),
    _IntervalUnit.hour => ('hodina', 'hodiny', 'hodin', 'hodiny'),
    _IntervalUnit.day => ('den', 'dny', 'dní', 'dne'),
    _IntervalUnit.month => ('měsíc', 'měsíce', 'měsíců', 'měsíce'),
    _IntervalUnit.year => ('rok', 'roky', 'let', 'roku'),
  };
  final word = amount is int ? plural(amount, forms.$1, forms.$2, forms.$3) : forms.$4;
  return '${_decimal(amount)}$_nbsp$word';
}

const _weekdays = ['Pondělí', 'Úterý', 'Středa', 'Čtvrtek', 'Pátek', 'Sobota', 'Neděle'];
const _monthsGenitive = [
  'ledna', 'února', 'března', 'dubna', 'května', 'června',
  'července', 'srpna', 'září', 'října', 'listopadu', 'prosince',
];

/// `Sobota 31. října`.
String formatLongDate(DateTime date) =>
    '${_weekdays[date.weekday - 1]} ${date.day}. ${_monthsGenitive[date.month - 1]}';

/// `31. 10.`
String formatShortDate(DateTime date) => '${date.day}.$_nbsp${date.month}.';

/// `dnes 19:40` for a time today, else `24. 10.` (both in local time).
String formatWhen(DateTime time, DateTime now) {
  final t = time.toLocal();
  final n = now.toLocal();
  if (t.year == n.year && t.month == n.month && t.day == n.day) {
    return 'dnes ${t.hour}:${t.minute.toString().padLeft(2, '0')}';
  }
  return formatShortDate(t);
}
