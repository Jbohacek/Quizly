import 'package:flutter_test/flutter_test.dart';
import 'package:quizly/core/api/models.dart';
import 'package:quizly/core/tags.dart';

/// Card tags (#29).
void main() {
  group('splitTags', () {
    test('splits at ; , and spaces, lowercases, drops duplicates, sorts like the server', () {
      expect(splitTags('AI_gen ; prednaska_01'), ['ai_gen', 'prednaska_01']);
      expect(splitTags('prednaska_01,ai_gen  ai_gen;;\tČeština'), ['ai_gen', 'prednaska_01', 'čeština']);
      expect(splitTags(''), isEmpty);
      expect(splitTags(' ; , '), isEmpty);
    });

    test('a list round-trips through the editor text', () {
      const tags = ['ai_gen', 'prednaska_01'];
      expect(tagsAsText(tags), 'ai_gen ; prednaska_01');
      expect(splitTags(tagsAsText(tags)), tags);
      expect(tagsLine(tags), 'ai_gen · prednaska_01');
    });

    test('sameTags ignores the order', () {
      expect(sameTags(['b', 'a'], ['a', 'b']), isTrue);
      expect(sameTags(['a'], ['a', 'b']), isFalse);
      expect(sameTags(const [], const []), isTrue);
    });
  });

  group('models', () {
    const session = {'cardId': 1, 'deckId': 2, 'question': 'Q', 'answer': 'A', 'kind': 'new'};
    const deckCard = {'id': 1, 'question': 'Q', 'answer': 'A', 'status': 'new'};

    test('cards read their tags', () {
      expect(SessionCard.fromJson({...session, 'tags': ['ai_gen', 'prednaska_01']}).tags, ['ai_gen', 'prednaska_01']);
      expect(DeckCard.fromJson({...deckCard, 'tags': ['ai_gen']}).tags, ['ai_gen']);
    });

    test('an older server without tags still works', () {
      expect(SessionCard.fromJson(session).tags, isEmpty);
      expect(DeckCard.fromJson(deckCard).tags, isEmpty);
      expect(SessionCard.fromJson({...session, 'tags': null}).tags, isEmpty);
    });

    test('an edited session card keeps its id, deck and kind', () {
      final card = SessionCard.fromJson(session).edited(question: 'Q2', answer: 'A2', tags: ['x']);
      expect((card.cardId, card.deckId, card.kind, card.question, card.answer), (1, 2, CardKind.newCard, 'Q2', 'A2'));
      expect(card.tags, ['x']);
    });
  });
}
