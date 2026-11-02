import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/card_text.dart';

/// "Jak Quizly dávkuje karty": FSRS in plain words (from Nastavení and a deck's detail).
Future<void> showHowItWorks(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Q.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            children: [
              Text(S.howItWorks, style: QText.heading(24)),
              for (final paragraph in S.howItWorksText) ...[
                const SizedBox(height: 14),
                CardText(paragraph, style: QText.body(15, color: Q.text, weight: FontWeight.w400, height: 1.5)),
              ],
            ],
          ),
        ),
      ),
    );
