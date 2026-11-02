import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../core/card_markup.dart';
import '../../core/format.dart';
import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/card_text.dart';
import '../../core/widgets/widgets.dart';
import '../cards/card_editor.dart';
import '../session/session_controller.dart';
import '../settings/how_it_works.dart';

final deckCardsProvider = FutureProvider.autoDispose.family<DeckCards, int>(
  (ref, deckId) => ref.watch(apiClientProvider).deckCards(deckId),
);

/// A deck: counts, "Učit se" and every card with my status. Tapping a card shows its answer.
class DeckScreen extends ConsumerWidget {
  const DeckScreen({super.key, required this.deckId});

  final int deckId;

  /// Adds a card ([card] null) or edits one, then reloads the deck and the counts on Domů.
  Future<void> _edit(BuildContext context, WidgetRef ref, [DeckCard? card]) async {
    final result = await editCard(
      context,
      deckId: deckId,
      cardId: card?.id,
      question: card?.question ?? '',
      answer: card?.answer ?? '',
    );
    if (result == null) return;
    ref.invalidate(deckCardsProvider(deckId));
    invalidateProgress(ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(deckCardsProvider(deckId));
    // The deck as Domů knows it: enough to show the counts and "Učit se" if the card list fails.
    final known = ref.watch(homeProvider).value?.decks.items.where((d) => d.id == deckId).firstOrNull;
    return Scaffold(
      floatingActionButton: data.hasValue
          ? FloatingActionButton(
              tooltip: S.addCard,
              backgroundColor: Q.primary,
              foregroundColor: Q.onPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              onPressed: () => _edit(context, ref),
              child: const Icon(Icons.add_rounded, size: 30),
            )
          : null,
      body: SafeArea(
        bottom: false,
        child: switch (data) {
          AsyncValue(:final value?) => RefreshIndicator(
              color: Q.primary,
              backgroundColor: Q.surface,
              onRefresh: () => ref.refresh(deckCardsProvider(deckId).future),
              child: _DeckBody(data: value, onEdit: (card) => _edit(context, ref, card)),
            ),
          AsyncValue(:final error?) when known != null => RefreshIndicator(
              color: Q.primary,
              backgroundColor: Q.surface,
              onRefresh: () => ref.refresh(deckCardsProvider(deckId).future),
              child: _DeckBody(
                data: DeckCards(deck: known, cards: const []),
                cardsError: error is ApiException ? error.message : S.loadFailed,
                onRetry: () => ref.invalidate(deckCardsProvider(deckId)),
              ),
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

class _DeckBody extends StatefulWidget {
  const _DeckBody({required this.data, this.cardsError, this.onRetry, this.onEdit});

  final DeckCards data;

  /// "Upravit" on an opened card.
  final ValueChanged<DeckCard>? onEdit;

  /// The card list failed to load; the rest comes from Domů and studying still works.
  final String? cardsError;
  final VoidCallback? onRetry;

  @override
  State<_DeckBody> createState() => _DeckBodyState();
}

class _DeckBodyState extends State<_DeckBody> {
  final _search = TextEditingController();
  CardStatus? _status;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<DeckCard> get _shown {
    final query = foldForSearch(_search.text.trim());
    return [
      for (final card in widget.data.cards)
        if ((_status == null || card.status == _status) &&
            (query.isEmpty || foldForSearch(plainCardText('${card.question}\n${card.answer}')).contains(query)))
          card,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final deck = data.deck;
    final color = parseHex(deck.color);
    final toStudy = deck.dueNow + deck.newAvailable;
    final shown = _shown;
    final filtered = _status != null || _search.text.trim().isNotEmpty;
    return ListView(
      // Room at the end for the "+" button.
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
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
        const SizedBox(height: 14),
        DeckProgressBar(deck: deck),
        const SizedBox(height: 16),
        if (toStudy > 0)
          PrimaryButton(
            label: S.studyDeck(toStudy),
            icon: Icons.play_arrow_rounded,
            height: 60,
            onPressed: () => context.push(sessionPath(deckId: deck.id)),
          )
        else if (deck.unseenCards > 0)
          PrimaryButton(
            label: S.moreNewCards(math.min(extraNewStep, deck.unseenCards)),
            icon: Icons.add_rounded,
            height: 60,
            onPressed: () => context.push(
              sessionPath(deckId: deck.id, extraNew: math.min(extraNewStep, deck.unseenCards)),
            ),
          )
        else
          const PrimaryButton(label: S.nothingDue, icon: Icons.check_rounded, height: 60),
        const SizedBox(height: 22),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(child: Text(S.cardsInDeck, style: QText.heading(19))),
            if (widget.cardsError == null)
              Text(
                filtered ? S.cardsShown(shown.length, data.cards.length) : cards(data.cards.length),
                style: QText.body(13, color: Q.textMuted),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (widget.cardsError != null)
          Panel(
            radius: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.cardsError!, style: QText.body(14, color: Q.textMuted, weight: FontWeight.w400, height: 1.5)),
                const SizedBox(height: 12),
                SecondaryButton(label: S.retry, onPressed: widget.onRetry),
              ],
            ),
          )
        else if (data.cards.isEmpty)
          Panel(
            radius: 18,
            child: Text(S.emptyDeck, style: QText.body(14, color: Q.textMuted, weight: FontWeight.w400, height: 1.5)),
          )
        else ...[
          TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: S.searchCards,
              prefixIcon: const Icon(Icons.search_rounded, color: Q.textMuted),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: S.clearSearch,
                      onPressed: _search.clear,
                      icon: const Icon(Icons.close_rounded, color: Q.textMuted),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final status in [null, ...CardStatus.values])
                _FilterChip(
                  label: switch (status) {
                    null => S.filterAll,
                    CardStatus.newCard => S.legendNew,
                    CardStatus.learning => S.statusLearning,
                    CardStatus.mastered => S.statusMastered,
                  },
                  count: status == null ? data.cards.length : data.cards.where((c) => c.status == status).length,
                  selected: _status == status,
                  onTap: () => setState(() => _status = status),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (shown.isEmpty)
            Panel(
              radius: 18,
              child: Text(S.noMatch, style: QText.body(14, color: Q.textMuted, weight: FontWeight.w400, height: 1.5)),
            ),
          for (final card in shown) ...[
            _CardTile(
              key: ValueKey(card.id),
              card: card,
              onEdit: widget.onEdit == null ? null : () => widget.onEdit!(card),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

/// Zvládnuto / Učím se / Nové in one bar, like Statistiky (green, lavender, grey).
class DeckProgressBar extends StatelessWidget {
  const DeckProgressBar({super.key, required this.deck});

  final Deck deck;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: S.deckProgressLabel(deck.masteredPercent, deck.learningPercent),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProgressBar(mastered: deck.masteredPercent, learning: deck.learningPercent, fresh: deck.freshPercent),
          const SizedBox(height: 6),
          Text(
            S.deckMetaLearning(deck.totalCards, deck.masteredPercent, deck.learningPercent),
            style: QText.body(12, color: Q.textMuted),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.count, required this.selected, required this.onTap});

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? Q.primary : Q.surface2,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            // widthFactor 1: as wide as the text, not the whole row.
            child: Align(
              widthFactor: 1,
              child: Text(
              '$label · ${formatInt(count)}',
                style: QText.body(13, color: selected ? Q.onPrimary : Q.text, weight: FontWeight.w800),
              ),
            ),
          ),
        ),
      ),
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
        const SizedBox(width: 8),
        SizedBox.square(
          dimension: 44,
          child: IconButton(
            tooltip: S.howItWorks,
            onPressed: () => showHowItWorks(context),
            style: IconButton.styleFrom(
              backgroundColor: Q.surface,
              foregroundColor: Q.textMuted,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.help_outline_rounded),
          ),
        ),
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
  const _CardTile({super.key, required this.card, this.onEdit});

  final DeckCard card;
  final VoidCallback? onEdit;

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
    final motion = MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 200);
    return Material(
      color: Q.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Q.border)),
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        hint: _open ? S.hideCard : S.showCard,
        child: InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
            child: AnimatedSize(
              duration: motion,
              alignment: Alignment.topCenter,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: CardText(
                          card.question,
                          style: QText.body(15, weight: FontWeight.w800, height: 1.35),
                          smallColor: Q.textMuted,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Tag(label: label, color: color),
                      AnimatedRotation(
                        turns: _open ? 0.5 : 0,
                        duration: motion,
                        child: const Icon(Icons.expand_more_rounded, color: Q.textMuted),
                      ),
                    ],
                  ),
                  if (_open) ...[
                    const SizedBox(height: 10),
                    CardText(
                      card.answer,
                      style: QText.body(15, color: Q.text, weight: FontWeight.w400, height: 1.45),
                      smallColor: Q.textMuted,
                    ),
                    const SizedBox(height: 14),
                    const Divider(height: 1, color: Q.border),
                    const SizedBox(height: 12),
                    _CardProgress(card: card, color: color),
                    if (widget.onEdit != null) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: widget.onEdit,
                          style: TextButton.styleFrom(
                            foregroundColor: Q.primary,
                            minimumSize: const Size(44, 44),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          icon: const Icon(Icons.edit_rounded, size: 18),
                          label: Text(S.editCard, style: QText.body(14, color: Q.primary, weight: FontWeight.w800)),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// How well I know the card: the way to Zvládnuto, my answers, the next review.
class _CardProgress extends StatelessWidget {
  const _CardProgress({required this.card, required this.color});

  final DeckCard card;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final muted = QText.body(12, color: Q.textMuted, weight: FontWeight.w600);
    if (card.status == CardStatus.newCard) return Text(S.notStudiedYet, style: muted);
    final next = card.nextReview;
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(S.cardProgress, style: QText.body(12, color: Q.textMuted, weight: FontWeight.w800))),
            Text(formatPercent(card.masteryPercent), style: QText.body(12, color: color, weight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: card.masteryPercent / 100,
            minHeight: 6,
            backgroundColor: Q.surface2,
            color: color,
          ),
        ),
        const SizedBox(height: 8),
        Text(S.cardAnswers(card.knowCount, card.dontKnowCount), style: muted),
        if (next != null) ...[
          const SizedBox(height: 2),
          Text(next.isAfter(now) ? S.nextReview(formatWhen(next, now)) : S.nextReviewNow, style: muted),
        ],
      ],
    );
  }
}
