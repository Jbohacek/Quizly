# Handoff: card tags (#29), Flutter app part

**Delete this file in the app PR.** It exists only to hand this issue to the next agent. Jakub's notebook has no Android tooling, so the API part was done first, on its own (branch `etapa-8-tags`).

Read `CLAUDE.md` first (rules, §5.1, §9, §12, §14), then this file.

---

## 1. The issue

[#29](https://github.com/Jbohacek/Quizly/issues/29) "feat: možnost tagovat otázky tagama", in Jakub's words:

> je nutné rozšířit otázky o tagy, je to kvůli organizaci · je potřebné pozměnit aplikaci, pro zobrazení těch tagů · aby bylo možné tagovat otázku například `ai_gen ; prednaska_01` · Otázka v aplikace bude vidět kam patří > půjde to pod názvem předmětu bez barevného rámečku šedivým písmem napsaný. tagy menším písmem · N:N tabulka opět

In English: cards get tags for organizing them (e.g. `ai_gen`, `prednaska_01`). In the app, a card shows where it belongs: **the deck's name in grey text, without the colored frame**, and **the tags below it in smaller text**.

## 2. What the API already does (merged before you start)

Details: `docs/api.md` §4–5, `docs/spec.md` §2.5.1, `docs/yaml-format.md` §2.

- **Tag rules:** names are trimmed and lowercased, then only lowercase letters (Czech too), digits, `_` and `-`, 1–30 characters, at most 10 per card. Duplicates are dropped, and **lists always come back sorted**.
- **`GET /api/session`:** every card has `"tags": ["ai_gen", "prednaska_01"]` (always present, may be `[]`). The deck name is *not* in the session; the app already maps `deckId` to its deck from `GET /api/decks` (`session_screen.dart`, `_decks[card.deckId]`).
- **`GET /api/decks/{id}/cards`:** every card has `"tags": [...]`.
- **`POST /api/decks/{id}/cards`** and **`PUT /api/decks/{id}/cards/{cardId}`** take an optional `"tags": [...]`:
  - **omitted / `null`:** the card keeps its tags (none on a new card). That's why the current app, which never sends tags, can't wipe them.
  - **`[]`:** removes them all.
  - **a list:** replaces them.
  - The response card has `tags`.
  - An invalid name or more than 10 → `400 validation` with `errors.tags` (Czech messages, show them as they are, like `errors.question`).
- The admin sets tags in the dashboard (card form field "Tagy", separated by `;`) and in deck YAML. Claude sets them over MCP.

## 3. What the app needs

Files are under `app/lib/`. Keep the existing structure, Riverpod, strings in `core/strings.dart`, and design tokens in `core/theme/tokens.dart`.

1. **Models** (`core/api/models.dart`): add `final List<String> tags` to `SessionCard` and `DeckCard`. Parse with `(j['tags'] as List?)?.cast<String>() ?? const []`, so an older server without the field still works.
2. **API client** (`core/api/api_client.dart`): `createCard` / `updateCard` take `List<String>? tags` and put `'tags': tags` in the body when it isn't null. The editor (point 5) always sends its list, so clearing the field clears the tags.
3. **Session screen** (`features/session/session_screen.dart`, `_buildStudy`): today the deck name is a colored `Tag(label: deck.name, color: deckColor)` chip, left of "✎ Upravit".
   - Replace it with the deck name as **plain grey text** (`Q.textMuted`, body font, no border or background).
   - Put the card's **tags under it in smaller grey text**, e.g. `ai_gen · prednaska_01`, one line, ellipsis when long.
   - With "Učit se vše" the name is per card (`_decks[card.deckId]`), as today. No tags → no second line.
   - Mind the name clash: the app already has a widget called `Tag` (`core/widgets/widgets.dart:103`), so don't name a model `Tag`.
4. **Deck detail** (`features/home/deck_screen.dart`, `_CardTile`): show the card's tags in small grey text under the question. Make the search (`_shown`, `foldForSearch`) also match tags, so typing `prednaska_01` finds those cards.
5. **Card editor** (`features/cards/card_editor.dart`):
   - Add a **"Tagy"** text field under the answer, prefilled as `ai_gen ; prednaska_01`.
   - Hint: "Odděl středníkem, např. ai_gen ; prednaska_01".
   - Split the text at `;`, `,` and whitespace, and send the list. The server lowercases and validates; show `errors.tags` under the field.
   - Pass `tags` through `editCard(...)` / `CardEdit.saved(...)`, so the session (`_editCurrent`) and the deck list show the new tags without a reload.
   - Count a tags change in `_changed`.
6. **Strings:** put all new Czech texts in `core/strings.dart` (gender-neutral, CLAUDE.md §2.11). Suggested: `tagsLabel = 'Tagy'`, `tagsHint = 'Odděl středníkem, např. ai_gen ; prednaska_01'`.
7. **Tests** (`app/test/`):
   - model parsing with and without `tags`;
   - the session shows the grey deck name without a colored chip, plus the tags;
   - the editor sends `tags` and shows `errors.tags`;
   - the deck search matches a tag;
   - keep the accessibility checks green: 44 px touch targets; contrast ≥ 4.5:1 (`Q.textMuted` `#A0A4B5` on `#111218` is fine; don't go dimmer for the small tag text).
   
   `flutter analyze` and `flutter test` must pass.
8. **Wrap-up in the same PR:**
   - bump `pubspec.yaml` (now `1.0.0-beta.5+1` → `1.0.0-beta.6+1`);
   - add a line to CLAUDE.md §14 and §9.4 screens 2 (Balíček) and 3 (Učení) about the grey deck name and tags;
   - tick the "#29 card tags, app part" line in `STAGES.md`;
   - **delete this file**.

## 4. Open points to confirm with Jakub

- **Where exactly.** I read "pod názvem předmětu" as the session screen: the deck name row above the card becomes grey text, and the tags go under it. If Jakub meant the card face itself (under the question), move it there. Ask when unsure, and show a screenshot.
- **Tag look:** plain small text (`ai_gen · prednaska_01`) fits "menším písmem" best. Not chips: Jakub asked for no frame.
- **Filtering by tag** in the deck detail (beyond search) isn't in the issue. Put it under "Ideas for later".

## 5. Trying it locally

```bash
docker compose -f deploy/docker-compose.dev.yml up -d
```

```bash
dotnet run --project src/Quizly.Web
```

Tag a card in the dashboard (http://localhost:5278/admin → Balíčky → deck → Upravit → Tagy), then run the app against it:

```bash
cd app && flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5278
```
