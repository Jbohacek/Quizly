import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/widgets.dart';

final deckCardsProvider = FutureProvider.autoDispose.family<DeckCards, int>(
  (ref, deckId) => ref.watch(apiClientProvider).deckCards(deckId),
);

/// A deck: counts, "Učit se" and every card with my status. Tapping a card shows its answer.
class DeckScreen extends ConsumerWidget {
  const DeckScreen({super.key, required this.deckId});

  final int deckId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(deckCardsProvider(deckId));
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: switch (data) {
          AsyncValue(:final value?) => RefreshIndicator(
              color: Q.primary,
              backgroundColor: Q.surface,
              onRefresh: () => ref.refresh(deckCardsProvider(deckId).future),
              child: _DeckBody(data: value),
            ),
          AsyncValue(:final error?) => Column(
              children: [
                const Padding(padding: EdgeInsets.fromLTRB(20, 16, 20, 0), child: _BackRow(title: '')),
                Expanded(
                  child: ErrorView(
                    message: error is ApiException ? error.message : S.loadFailed,
                    onRetry: () => ref.invalidate(deckCardsProvider(deckId)),
                  ),
                ),
              ],
            ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class _DeckBody extends StatelessWidget {
  const _DeckBody({required this.data});

  final DeckCards data;

  @override
  Widget build(BuildContext context) {
    final deck = data.deck;
    final color = parseHex(deck.color);
    final toStudy = deck.dueNow + deck.newAvailable;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        _BackRow(title: deck.name, color: color),
        if (deck.description.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(deck.description, style: QText.body(15, color: Q.textMuted, weight: FontWeight.w400, height: 1.45)),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            _Tile(value: formatInt(deck.totalCards), label: S.tileTotal),
            const SizedBox(width: 8),
            _Tile(value: formatInt(deck.dueNow), label: S.tileDue, color: color),
            const SizedBox(width: 8),
            _Tile(value: formatInt(deck.newAvailable), label: S.tileNew, color: Q.info),
            const SizedBox(width: 8),
            _Tile(value: formatPercent(deck.masteredPercent), label: S.tileMastered, color: Q.primary),
          ],
        ),
        const SizedBox(height: 16),
        PrimaryButton(
          label: toStudy > 0 ? S.studyDeck(toStudy) : S.nothingDue,
          icon: toStudy > 0 ? Icons.play_arrow_rounded : Icons.check_rounded,
          height: 60,
          onPressed: toStudy > 0 ? () => context.push('/session?deck=${deck.id}') : null,
        ),
        const SizedBox(height: 22),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: Text(S.cardsInDeck, style: QText.heading(19))),
            Text(cards(data.cards.length), style: QText.body(13, color: Q.textMuted)),
          ],
        ),
        const SizedBox(height: 10),
        if (data.cards.isEmpty)
          Panel(
            radius: 18,
            child: Text(S.emptyDeck, style: QText.body(14, color: Q.textMuted, weight: FontWeight.w400, height: 1.5)),
          ),
        for (final card in data.cards) ...[
          _CardTile(card: card),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _BackRow extends StatelessWidget {
  const _BackRow({required this.title, this.color = Q.text});

  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox.square(
          dimension: 44,
          child: IconButton(
            tooltip: S.back,
            onPressed: () => context.pop(),
            style: IconButton.styleFrom(
              backgroundColor: Q.surface,
              foregroundColor: Q.textMuted,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(child: Text(title, style: QText.heading(26), maxLines: 2, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.value, required this.label, this.color = Q.text});

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Panel(
        radius: 16,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Column(
          children: [
            FittedBox(child: Text(value, style: QText.heading(22, color: color))),
            const SizedBox(height: 2),
            FittedBox(child: Text(label, style: QText.body(11, color: Q.textMuted, weight: FontWeight.w700))),
          ],
        ),
      ),
    );
  }
}

class _CardTile extends StatefulWidget {
  const _CardTile({required this.card});

  final DeckCard card;

  @override
  State<_CardTile> createState() => _CardTileState();
}

class _CardTileState extends State<_CardTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final (label, color) = switch (card.status) {
      CardStatus.newCard => (S.statusNew, Q.info),
      CardStatus.learning => (S.statusLearning, Q.multiplier),
      CardStatus.mastered => (S.statusMastered, Q.primary),
    };
    return Material(
      color: Q.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Q.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _open = !_open),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          child: AnimatedSize(
            duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(card.question, style: QText.body(15, weight: FontWeight.w800, height: 1.35)),
                    ),
                    const SizedBox(width: 10),
                    Tag(label: label, color: color),
                  ],
                ),
                const SizedBox(height: 8),
                if (_open)
                  Text(card.answer, style: QText.body(15, color: Q.text, weight: FontWeight.w400, height: 1.45))
                else
                  Text(S.showAnswer, style: QText.body(13, color: Q.textMuted, weight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
