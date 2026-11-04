/// Card tags (#29), as the server keeps them (docs/spec.md §2.5.1).
library;

/// Splits typed text into tag names, e.g. "AI_gen ; prednaska_01" → [ai_gen, prednaska_01].
/// Like the server: split at `;`, `,` and whitespace, lowercased, duplicates dropped, sorted
/// (ordinal, the server's order). The server checks the characters and the limits.
List<String> splitTags(String text) {
  final names = {
    for (final part in text.split(RegExp(r'[;,\s]+')))
      if (part.trim().isNotEmpty) part.trim().toLowerCase(),
  }.toList()
    ..sort();
  return names;
}

/// How an editor shows tags as one text: `ai_gen ; prednaska_01`.
String tagsAsText(List<String> tags) => tags.join(' ; ');

/// How a card shows its tags: `ai_gen · prednaska_01`.
String tagsLine(List<String> tags) => tags.join(' · ');

/// Whether two tag lists hold the same names.
bool sameTags(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  final sortedB = [...b]..sort();
  final sortedA = [...a]..sort();
  for (var i = 0; i < sortedA.length; i++) {
    if (sortedA[i] != sortedB[i]) return false;
  }
  return true;
}
