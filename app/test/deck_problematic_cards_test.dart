import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizly/core/api/models.dart';
import 'package:quizly/core/theme/theme.dart';
import 'package:quizly/features/home/deck_screen.dart';

// #27: "Problémové" cards in the deck detail. The server decides which cards are problematic (spec §3.6);
// the app filters, sorts the worst first and marks them.
void main() {
  group('DeckCard', () {
    test('reads the recent answers and the problematic flag', () {
      final card = DeckCard.fromJson(const {
        'id': 2,
        'question': 'Q',
        'answer': 'A',
        'status': 'learning',
        'recentDontKnow': 3,
        'recentAnswers': 5,
        'problematic': true,
      });
      expect((card.recentDontKnow, card.recentAnswers, card.problematic), (3, 5, true));
    });

    test('defaults to not problematic when the server sends nothing', () {
      final card = DeckCard.fromJson(const {'id': 1, 'question': 'Q', 'answer': 'A', 'status': 'new'});
      expect((card.recentDontKnow, card.recentAnswers, card.problematic), (0, 0, false));
    });
  });

  group('DeckScreen Problémové', () {
    const deck = Deck(
      id: 1,
      name: 'Přírodopis',
      description: 'Základní rostliny a zvířata',
      color: '#BAD69B',
      totalCards: 5,
      dueNow: 1,
      newAvailable: 1,
      masteredPercent: 20,
      learningPercent: 60,
      unseenCards: 1,
    );

    // Deck order: dub, fotosyntéza (2 of 3), chlorofyl, dýchání (4 of 6), průduch (2 of 5).
    // The worst first: dýchání (4 Nevím), fotosyntéza (2 of 3), průduch (2 of 5).
    const cards = [
      DeckCard(id: 101, question: 'Co je dub?', answer: 'Strom', status: CardStatus.mastered, masteryPercent: 100,
          knowCount: 5, recentAnswers: 5),
      DeckCard(id: 102, question: 'Co je fotosyntéza?', answer: 'Proces přeměny světla na energii',
          status: CardStatus.learning, masteryPercent: 35, knowCount: 1, dontKnowCount: 2,
          recentDontKnow: 2, recentAnswers: 3, problematic: true),
      DeckCard(id: 103, question: 'Co je chlorofyl?', answer: 'Zelené barvivo', status: CardStatus.newCard),
      DeckCard(id: 104, question: 'Jaký je rozdíl mezi fotosyntézou a dýcháním rostlin?', answer: 'Opačný směr',
          status: CardStatus.learning, masteryPercent: 4, knowCount: 2, dontKnowCount: 4,
          recentDontKnow: 4, recentAnswers: 6, problematic: true, tags: ['prednaska_01', 'ai_gen']),
      DeckCard(id: 105, question: 'Co je průduch?', answer: 'Otvor v listu', status: CardStatus.learning,
          masteryPercent: 20, knowCount: 3, dontKnowCount: 2, recentDontKnow: 2, recentAnswers: 5, problematic: true),
    ];

    Future<void> pump(WidgetTester tester, {double textScale = 1}) async {
      // A common phone width; tall, so every card is built.
      tester.view.physicalSize = const Size(360, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            deckCardsProvider(1).overrideWith((ref) => Future.value(const DeckCards(deck: deck, cards: cards))),
          ],
          child: MaterialApp(
            theme: buildTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: const DeckScreen(deckId: 1),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    List<String> visibleQuestions(WidgetTester tester) {
      final questions = [for (final c in cards) c.question].where((q) => find.text(q).evaluate().isNotEmpty).toList();
      questions.sort((a, b) => tester.getTopLeft(find.text(a)).dy.compareTo(tester.getTopLeft(find.text(b)).dy));
      return questions;
    }

    testWidgets('filters the problematic cards, worst first, and back to deck order', (tester) async {
      await pump(tester);

      expect(find.text('Problémové · 3'), findsOneWidget);
      expect(find.text('Problémová'), findsNWidgets(3));
      expect(visibleQuestions(tester), [for (final c in cards) c.question]);

      await tester.tap(find.text('Problémové · 3'));
      await tester.pumpAndSettle();
      expect(visibleQuestions(tester), [
        'Jaký je rozdíl mezi fotosyntézou a dýcháním rostlin?',
        'Co je fotosyntéza?',
        'Co je průduch?',
      ]);

      // The opened card says why.
      await tester.tap(find.text('Co je fotosyntéza?'));
      await tester.pumpAndSettle();
      expect(find.text('Proces přeměny světla na energii'), findsOneWidget);
      expect(find.text('Z posledních 3 odpovědí: Nevím 2×'), findsOneWidget);

      // A status chip leaves the problematic filter; tapping Problémové again goes back to Vše.
      await tester.tap(find.text('Učím se · 3'));
      await tester.pumpAndSettle();
      expect(visibleQuestions(tester), ['Co je fotosyntéza?', 'Jaký je rozdíl mezi fotosyntézou a dýcháním rostlin?',
          'Co je průduch?']);
      await tester.tap(find.text('Problémové · 3'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Problémové · 3'));
      await tester.pumpAndSettle();
      expect(visibleQuestions(tester), [for (final c in cards) c.question]);
    });

    for (final scale in [1.0, 1.3]) {
      testWidgets('fits a 360 dp phone at text scale $scale', (tester) async {
        await pump(tester, textScale: scale);
        // A RenderFlex overflow fails the test by itself; the question also keeps a usable width.
        expect(tester.getSize(find.text('Jaký je rozdíl mezi fotosyntézou a dýcháním rostlin?')).width,
            greaterThan(100));
        await tester.tap(find.text('Problémové · 3'));
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      });
    }
  });
}
