import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizly/core/api/models.dart';
import 'package:quizly/features/home/deck_screen.dart';

void main() {
  group('DeckCard.isProblematic', () {
    test('defaults lapses to 0 and parses from json', () {
      final cardDefault = DeckCard.fromJson(const {
        'id': 1,
        'question': 'Q1',
        'answer': 'A1',
        'status': 'new',
      });
      expect(cardDefault.lapses, 0);
      expect(cardDefault.isProblematic, isFalse);

      final cardWithLapses = DeckCard.fromJson(const {
        'id': 2,
        'question': 'Q2',
        'answer': 'A2',
        'status': 'learning',
        'lapses': 2,
      });
      expect(cardWithLapses.lapses, 2);
      expect(cardWithLapses.isProblematic, isTrue);
    });

    test('identified as problematic when lapses >= 2', () {
      const card = DeckCard(
        id: 1,
        question: 'Q',
        answer: 'A',
        status: CardStatus.learning,
        lapses: 2,
        dontKnowCount: 0,
        knowCount: 5,
        masteryPercent: 70,
      );
      expect(card.isProblematic, isTrue);
    });

    test('identified as problematic when dontKnowCount >= 3 and dontKnowCount >= knowCount', () {
      const card = DeckCard(
        id: 2,
        question: 'Q',
        answer: 'A',
        status: CardStatus.learning,
        lapses: 0,
        dontKnowCount: 3,
        knowCount: 3,
        masteryPercent: 50,
      );
      expect(card.isProblematic, isTrue);
    });

    test('identified as problematic when dontKnowCount >= 3 and masteryPercent < 50', () {
      const card = DeckCard(
        id: 3,
        question: 'Q',
        answer: 'A',
        status: CardStatus.learning,
        lapses: 1,
        dontKnowCount: 3,
        knowCount: 5,
        masteryPercent: 40,
      );
      expect(card.isProblematic, isTrue);
    });

    test('not problematic when below thresholds', () {
      const card1 = DeckCard(
        id: 4,
        question: 'Q',
        answer: 'A',
        status: CardStatus.learning,
        lapses: 1,
        dontKnowCount: 2,
        knowCount: 1,
        masteryPercent: 30,
      );
      expect(card1.isProblematic, isFalse);

      const card2 = DeckCard(
        id: 5,
        question: 'Q',
        answer: 'A',
        status: CardStatus.mastered,
        lapses: 1,
        dontKnowCount: 3,
        knowCount: 10,
        masteryPercent: 80,
      );
      expect(card2.isProblematic, isFalse);
    });
  });

  group('DeckScreen problematic card filter and badges', () {
    const deck = Deck(
      id: 1,
      name: 'Přírodopis',
      description: 'Základní rostliny a zvířata',
      color: '#BAD69B',
      totalCards: 3,
      dueNow: 1,
      newAvailable: 1,
      masteredPercent: 33,
      learningPercent: 33,
      unseenCards: 1,
    );

    const normalCard1 = DeckCard(
      id: 101,
      question: 'Co je dub?',
      answer: 'Strom',
      status: CardStatus.mastered,
      masteryPercent: 100,
      knowCount: 5,
      dontKnowCount: 0,
      lapses: 0,
    );

    const problematicCard = DeckCard(
      id: 102,
      question: 'Co je fotosyntéza?',
      answer: 'Proces přeměny světla na energii',
      status: CardStatus.learning,
      masteryPercent: 35,
      knowCount: 2,
      dontKnowCount: 4,
      lapses: 2,
      nextReview: null,
    );

    const normalCard2 = DeckCard(
      id: 103,
      question: 'Co je chlorofyl?',
      answer: 'Zelené barvivo',
      status: CardStatus.newCard,
      masteryPercent: 0,
      knowCount: 0,
      dontKnowCount: 0,
      lapses: 0,
    );

    testWidgets('shows problematic chip, warning tag, filters on tap, and shows lapse info on expand',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            deckCardsProvider(1).overrideWith(
              (ref) => Future.value(
                const DeckCards(deck: deck, cards: [normalCard1, problematicCard, normalCard2]),
              ),
            ),
          ],
          child: const MaterialApp(
            home: DeckScreen(deckId: 1),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Problémové filter chip is present with count 1
      expect(find.text('Problémové · 1'), findsOneWidget);

      // Warning tag 'Problémová' is shown on the card tile
      expect(find.text('Problémová'), findsOneWidget);

      // All 3 cards are initially shown
      expect(find.text('Co je dub?'), findsOneWidget);
      expect(find.text('Co je fotosyntéza?'), findsOneWidget);
      expect(find.text('Co je chlorofyl?'), findsOneWidget);

      // Tap the Problémové filter chip
      await tester.tap(find.text('Problémové · 1'));
      await tester.pumpAndSettle();

      // Only the problematic card should be shown
      expect(find.text('Co je dub?'), findsNothing);
      expect(find.text('Co je fotosyntéza?'), findsOneWidget);
      expect(find.text('Co je chlorofyl?'), findsNothing);

      // Tap the problematic card to expand it
      await tester.tap(find.text('Co je fotosyntéza?'));
      await tester.pumpAndSettle();

      // Expanded answer and lapse info should be visible
      expect(find.text('Proces přeměny světla na energii'), findsOneWidget);
      expect(find.text('Výpadky z paměti: 2'), findsOneWidget);

      // Tap Problémové filter chip again to toggle it off
      await tester.tap(find.text('Problémové · 1'));
      await tester.pumpAndSettle();

      // All 3 cards should be visible again
      expect(find.text('Co je dub?'), findsOneWidget);
      expect(find.text('Co je fotosyntéza?'), findsOneWidget);
      expect(find.text('Co je chlorofyl?'), findsOneWidget);
    });
  });
}
