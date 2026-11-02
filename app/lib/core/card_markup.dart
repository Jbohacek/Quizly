/// Light formatting on cards (docs/yaml-format.md "Formatting"): `**tučně**`, `*kurzíva*`,
/// `<small>malé</small>`, lines starting with `- ` (bullets) or `1. ` (numbered).
///
/// Pure Dart. Anything that isn't valid markup (a lone `*`, `2 * 3`) stays as typed.
library;

/// A run of text with one style.
class Run {
  const Run(this.text, {this.bold = false, this.italic = false, this.small = false});

  final String text;
  final bool bold;
  final bool italic;
  final bool small;

  @override
  bool operator ==(Object other) =>
      other is Run && other.text == text && other.bold == bold && other.italic == italic && other.small == small;

  @override
  int get hashCode => Object.hash(text, bold, italic, small);

  @override
  String toString() => '${bold ? 'B' : ''}${italic ? 'I' : ''}${small ? 'S' : ''}"$text"';
}

enum BlockKind { paragraph, bullet, numbered }

/// One line: a paragraph or a list item ([marker] is `•` or `3.`).
class Block {
  const Block(this.kind, this.runs, {this.marker = ''});

  final BlockKind kind;
  final List<Run> runs;
  final String marker;

  String get plain => runs.map((r) => r.text).join();
}

final _bullet = RegExp(r'^\s*[-•]\s+(.*)$');
final _numbered = RegExp(r'^\s*(\d{1,3})[.)]\s+(.*)$');

// Bold before italic; italic needs no space just inside the stars, so "2 * 3 * 4" stays math.
final _inline = RegExp(r'\*\*(?=\S)(.+?)(?<=\S)\*\*(?!\*)|<small>(.+?)</small>|\*(?=[^\s*])(.+?)(?<=[^\s*])\*');

/// Lines of the card text; an empty line is an empty paragraph (a gap).
List<Block> parseCard(String text) => [
      for (final line in text.replaceAll('\r\n', '\n').split('\n'))
        if (_bullet.firstMatch(line) case final m?)
          Block(BlockKind.bullet, parseInline(m.group(1)!), marker: '•')
        else if (_numbered.firstMatch(line) case final m?)
          Block(BlockKind.numbered, parseInline(m.group(2)!), marker: '${m.group(1)}.')
        else
          Block(BlockKind.paragraph, parseInline(line)),
    ];

/// Inline styles of one line; nested markup combines (`**tučně a *kurzíva***`).
List<Run> parseInline(String text, {bool bold = false, bool italic = false, bool small = false}) {
  final runs = <Run>[];
  var at = 0;
  for (final m in _inline.allMatches(text)) {
    if (m.start > at) runs.add(Run(text.substring(at, m.start), bold: bold, italic: italic, small: small));
    if (m.group(1) case final inner?) {
      runs.addAll(parseInline(inner, bold: true, italic: italic, small: small));
    } else if (m.group(2) case final inner?) {
      runs.addAll(parseInline(inner, bold: bold, italic: italic, small: true));
    } else {
      runs.addAll(parseInline(m.group(3)!, bold: bold, italic: true, small: small));
    }
    at = m.end;
  }
  if (at < text.length) runs.add(Run(text.substring(at), bold: bold, italic: italic, small: small));
  return runs;
}

/// The text without markup, for screen readers, search and sizing.
String plainCardText(String text) => parseCard(text)
    .map((b) => b.kind == BlockKind.paragraph ? b.plain : '${b.marker} ${b.plain}')
    .join('\n');

const _plainLetters = {
  'á': 'a', 'č': 'c', 'ď': 'd', 'é': 'e', 'ě': 'e', 'í': 'i', 'ň': 'n', 'ó': 'o',
  'ř': 'r', 'š': 's', 'ť': 't', 'ú': 'u', 'ů': 'u', 'ý': 'y', 'ž': 'z',
};

/// Lower case without Czech diacritics, so "zaklady" finds "Základy".
String foldForSearch(String text) => text.toLowerCase().split('').map((c) => _plainLetters[c] ?? c).join();
