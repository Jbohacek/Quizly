/// Czech number, date and plural formatting (CLAUDE.md §2.12).
///
/// Thousands use a non-breaking space (`1 457`), decimals a comma (`1,1×`),
/// percent a non-breaking space before `%` (`83 %`).
library;

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
