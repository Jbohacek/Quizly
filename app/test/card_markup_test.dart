import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizly/core/card_markup.dart';
import 'package:quizly/core/widgets/card_text.dart';

void main() {
  group('card formatting (docs/yaml-format.md)', () {
    test('plain text stays one plain run', () {
      expect(parseInline('struct je hodnotový typ'), [const Run('struct je hodnotový typ')]);
    });

    test('bold, italic and small text, also nested', () {
      expect(parseInline('**struct** je *hodnotový* typ <small>(C#)</small>'), [
        const Run('struct', bold: true),
        const Run(' je '),
        const Run('hodnotový', italic: true),
        const Run(' typ '),
        const Run('(C#)', small: true),
      ]);
      expect(parseInline('**tučně a *kurzíva***'), [
        const Run('tučně a ', bold: true),
        const Run('kurzíva', bold: true, italic: true),
      ]);
    });

    test('stars that aren\'t markup stay as typed', () {
      expect(parseInline('2 * 3 * 4'), [const Run('2 * 3 * 4')]);
      expect(parseInline('a ** b'), [const Run('a ** b')]);
      expect(parseInline('*nedokončené'), [const Run('*nedokončené')]);
    });

    test('bullets, numbered items and paragraphs', () {
      final blocks = parseCard('Typy:\n- **struct**\n- class\n\n1. první\n2) druhý');
      expect([for (final b in blocks) b.kind], [
        BlockKind.paragraph,
        BlockKind.bullet,
        BlockKind.bullet,
        BlockKind.paragraph,
        BlockKind.numbered,
        BlockKind.numbered,
      ]);
      expect(blocks[1].runs, [const Run('struct', bold: true)]);
      expect([blocks[4].marker, blocks[5].marker], ['1.', '2.']);
      expect(blocks[3].plain, '');
    });

    test('plain text for screen readers and search', () {
      expect(plainCardText('**a** b\n- c\n<small>d</small>'), 'a b\n• c\nd');
      expect(foldForSearch('Hodnotová ROVNOST, řeč'), 'hodnotova rovnost, rec');
    });
  });

  testWidgets('CardText draws the formatting and a list marker', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: CardText('**Typy**\n- struct\n- class', style: TextStyle(fontSize: 16))),
    ));
    expect(find.text('Typy', findRichText: true), findsOneWidget);
    expect(find.text('•'), findsNWidgets(2));
    final root = tester.widget<RichText>(find.text('Typy', findRichText: true)).text;
    TextStyle? style;
    root.visitChildren((span) {
      if (span is TextSpan && span.text == 'Typy') style = span.style;
      return style == null;
    });
    expect(style?.fontWeight, FontWeight.w800);
  });
}
