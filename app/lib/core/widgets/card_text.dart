import 'package:flutter/material.dart';

import '../card_markup.dart';

/// A card's question or answer with its formatting (bold, italic, small text, lists).
class CardText extends StatelessWidget {
  const CardText(this.text, {super.key, required this.style, this.smallColor});

  final String text;
  final TextStyle style;

  /// Color of `<small>` text; the base color when null.
  final Color? smallColor;

  TextSpan _span(List<Run> runs) => TextSpan(
        children: [
          for (final r in runs)
            TextSpan(
              text: r.text,
              style: TextStyle(
                fontWeight: r.bold ? FontWeight.w800 : null,
                fontStyle: r.italic ? FontStyle.italic : null,
                fontSize: r.small ? (style.fontSize ?? 14) * 0.72 : null,
                color: r.small ? smallColor : null,
              ),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final blocks = parseCard(text);
    if (blocks.length == 1 && blocks.single.kind == BlockKind.paragraph) {
      return Text.rich(_span(blocks.single.runs), style: style);
    }
    final gap = (style.fontSize ?? 14) * 0.25;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final b in blocks)
          if (b.kind == BlockKind.paragraph)
            Text.rich(_span(b.runs), style: style)
          else
            Padding(
              padding: EdgeInsets.only(top: gap),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: (style.fontSize ?? 14) * (b.kind == BlockKind.numbered ? 1.6 : 1.1),
                    child: Text(b.marker, style: style),
                  ),
                  Expanded(child: Text.rich(_span(b.runs), style: style)),
                ],
              ),
            ),
      ],
    );
  }
}
