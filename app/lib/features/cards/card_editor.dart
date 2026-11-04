import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/providers.dart';
import '../../core/strings.dart';
import '../../core/tags.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/card_text.dart';
import '../../core/widgets/widgets.dart';

/// What the editor did: the card as saved, or [deleted].
class CardEdit {
  const CardEdit.saved({required this.cardId, required this.question, required this.answer, this.tags = const []})
      : deleted = false;

  const CardEdit.deleted(this.cardId)
      : question = '',
        answer = '',
        tags = const [],
        deleted = true;

  final int cardId;
  final String question;
  final String answer;

  /// The tags as the server keeps them: lowercased and sorted (#29).
  final List<String> tags;
  final bool deleted;
}

/// Opens the editor for a card of [deckId] ([cardId] null adds a new card). Null when nothing changed.
Future<CardEdit?> editCard(
  BuildContext context, {
  required int deckId,
  int? cardId,
  String question = '',
  String answer = '',
  List<String> tags = const [],
}) =>
    Navigator.of(context, rootNavigator: true).push<CardEdit>(
      MaterialPageRoute(
        builder: (_) => CardEditorScreen(deckId: deckId, cardId: cardId, question: question, answer: answer, tags: tags),
      ),
    );

/// Add, edit or delete a card from the phone (#23). Anyone may; the change is shared with everyone.
/// No snackbar afterwards: the changed list or card shows it.
class CardEditorScreen extends ConsumerStatefulWidget {
  const CardEditorScreen({
    super.key,
    required this.deckId,
    this.cardId,
    this.question = '',
    this.answer = '',
    this.tags = const [],
  });

  /// Same limits as the server (CLAUDE.md §5.1).
  static const questionMax = 500;
  static const answerMax = 2000;

  final int deckId;
  final int? cardId;
  final String question;
  final String answer;
  final List<String> tags;

  @override
  ConsumerState<CardEditorScreen> createState() => _CardEditorScreenState();
}

class _CardEditorScreenState extends ConsumerState<CardEditorScreen> {
  late final _question = TextEditingController(text: widget.question);
  late final _answer = TextEditingController(text: widget.answer);
  late final _tags = TextEditingController(text: tagsAsText(widget.tags));
  bool _busy = false;
  String? _questionError;
  String? _answerError;
  String? _tagsError;
  String? _error;

  bool get _isNew => widget.cardId == null;
  bool get _changed =>
      _question.text != widget.question ||
      _answer.text != widget.answer ||
      !sameTags(splitTags(_tags.text), widget.tags);

  @override
  void initState() {
    super.initState();
    // The preview follows the text.
    _question.addListener(() => setState(() {}));
    _answer.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _question.dispose();
    _answer.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final question = _question.text.trim();
    final answer = _answer.text.trim();
    // Always sent: clearing the field removes the card's tags (#29).
    final tags = splitTags(_tags.text);
    setState(() {
      _questionError = question.isEmpty ? S.fillQuestion : null;
      _answerError = answer.isEmpty ? S.fillAnswer : null;
      _tagsError = null;
      _error = null;
    });
    if (_questionError != null || _answerError != null) return;

    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    final client = ref.read(apiClientProvider);
    try {
      final id = widget.cardId ??
          await client.createCard(widget.deckId, question: question, answer: answer, tags: tags);
      if (!_isNew) await client.updateCard(widget.deckId, id, question: question, answer: answer, tags: tags);
      if (!mounted) return;
      Navigator.of(context).pop(CardEdit.saved(cardId: id, question: question, answer: answer, tags: tags));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _questionError = e.fieldError('question');
        _answerError = e.fieldError('answer');
        _tagsError = e.fieldError('tags');
        _error = _questionError == null && _answerError == null && _tagsError == null ? e.message : null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(S.deleteCardTitle),
        content: const Text(S.deleteCardText),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text(S.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Q.dontKnow),
            child: const Text(S.delete),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).deleteCard(widget.deckId, widget.cardId!);
      if (!mounted) return;
      Navigator.of(context).pop(CardEdit.deleted(widget.cardId!));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Leaving with unsaved text asks first.
  Future<void> _leave() async {
    if (_changed && !_busy) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text(S.discardTitle),
          content: const Text(S.discardText),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text(S.keepEditing)),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text(S.discard)),
          ],
        ),
      );
      if (discard != true) return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final muted = QText.body(13, color: Q.textMuted, weight: FontWeight.w400, height: 1.45);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              Row(
                children: [
                  _SquareButton(tooltip: S.back, icon: Icons.arrow_back_rounded, onPressed: _leave),
                  const SizedBox(width: 14),
                  Expanded(child: Text(_isNew ? S.newCard : S.editCardTitle, style: QText.heading(26))),
                  if (!_isNew)
                    _SquareButton(
                      tooltip: S.deleteCard,
                      icon: Icons.delete_outline_rounded,
                      color: Q.dontKnow,
                      onPressed: _busy ? null : _delete,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(S.cardEditShared, style: muted),
              const SizedBox(height: 20),
              _field(S.questionLabel, _question, _questionError, CardEditorScreen.questionMax, minLines: 2),
              const SizedBox(height: 16),
              _field(S.answerLabel, _answer, _answerError, CardEditorScreen.answerMax, minLines: 4),
              const SizedBox(height: 8),
              Text(S.formattingHint, style: muted),
              const SizedBox(height: 20),
              _tagsField(muted),
              const SizedBox(height: 20),
              Text(S.preview, style: QText.body(14, weight: FontWeight.w700)),
              const SizedBox(height: 8),
              _Preview(question: _question.text, answer: _answer.text),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(_error!, style: QText.body(14, color: Q.dontKnow, weight: FontWeight.w700)),
                ),
              ],
              const SizedBox(height: 24),
              PrimaryButton(
                label: _isNew ? S.addCard : S.saveCard,
                icon: _isNew ? Icons.add_rounded : Icons.check_rounded,
                onPressed: _save,
                busy: _busy,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Tags typed as one text (#29); the server lowercases and checks them.
  Widget _tagsField(TextStyle muted) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(S.tagsLabel, style: QText.body(14, weight: FontWeight.w700)),
        ),
        TextField(
          controller: _tags,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.none,
          style: QText.body(16, weight: FontWeight.w600, height: 1.4),
          decoration: InputDecoration(
            errorText: _tagsError,
            errorMaxLines: 3,
            errorStyle: QText.body(13, color: Q.dontKnow, weight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 8),
        Text(S.tagsHint, style: muted),
      ],
    );
  }

  Widget _field(String label, TextEditingController controller, String? error, int max, {required int minLines}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(label, style: QText.body(14, weight: FontWeight.w700)),
        ),
        TextField(
          controller: controller,
          minLines: minLines,
          maxLines: null,
          maxLength: max,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          style: QText.body(16, weight: FontWeight.w600, height: 1.4),
          decoration: InputDecoration(
            errorText: error,
            errorStyle: QText.body(13, color: Q.dontKnow, weight: FontWeight.w700),
            counterStyle: QText.body(12, color: Q.textMuted),
          ),
        ),
      ],
    );
  }
}

/// The card face as the session shows it, with the formatting applied.
class _Preview extends StatelessWidget {
  const _Preview({required this.question, required this.answer});

  final String question;
  final String answer;

  @override
  Widget build(BuildContext context) {
    final label = QText.body(11, color: Q.cardText.withValues(alpha: 0.55), weight: FontWeight.w800);
    return Panel(
      color: Q.cardFace,
      radius: 22,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(S.question, style: label),
          const SizedBox(height: 6),
          CardText(
            question.trim().isEmpty ? '…' : question,
            style: QText.body(17, color: Q.cardText, weight: FontWeight.w800, height: 1.35),
            smallColor: Q.cardText.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 14),
          Text(S.answer, style: label),
          const SizedBox(height: 6),
          CardText(
            answer.trim().isEmpty ? '…' : answer,
            style: QText.body(15, color: Q.cardText, weight: FontWeight.w400, height: 1.45),
            smallColor: Q.cardText.withValues(alpha: 0.6),
          ),
        ],
      ),
    );
  }
}

class _SquareButton extends StatelessWidget {
  const _SquareButton({required this.tooltip, required this.icon, required this.onPressed, this.color = Q.textMuted});

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 44,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: Q.surface,
          foregroundColor: color,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: Icon(icon),
      ),
    );
  }
}
