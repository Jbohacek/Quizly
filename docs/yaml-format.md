# Deck YAML format v1

A whole deck as one YAML document. The admin uses it to export a deck, let an AI agent add or edit cards, and paste it back.

## 1. Example

```yaml
# Quizly balíček · formát v1
deck:
  name: C# základy
  description: Základní pojmy jazyka C#
  color: "#BAD69B"
cards:
  - id: 101
    question: Jaký je rozdíl mezi struct a class v C#?
    answer: struct je hodnotový typ, class je referenční typ.
  - id: 102
    question: Co dělá klíčové slovo async?
    answer: |
      Označí metodu, ve které můžeš použít await.
      Metoda pak vrací Task.
  - question: Co je record v C#?          # no id = new card
    answer: Typ s hodnotovou rovností pro neměnná data.
```

## 2. Schema

| Path | Type | Required | Rule |
| --- | --- | --- | --- |
| `deck` | mapping | yes | |
| `deck.name` | string | yes | 1–100 chars |
| `deck.description` | string | no | ≤ 500 chars; missing = `""` |
| `deck.color` | string | no | `#RRGGBB`; missing = keep current (new deck: `#BAD69B`) |
| `cards` | sequence | yes | may be empty (`cards: []`), ≤ 2 000 items |
| `cards[].id` | integer | no | positive; an existing card of **this** deck |
| `cards[].question` | string | yes | 1–500 chars after trim |
| `cards[].answer` | string | yes | 1–2 000 chars after trim |

- No other keys anywhere (unknown keys are errors, which catches typos like `anwser`).
- Exactly one YAML document; no anchors/aliases (`&`, `*`), no tags (`!!`). Max 1 MB.
- `id` may be written as `101` or `"101"`; anything else is an error.
- `question` / `answer` may use the light formatting of §10; it's stored as typed. Text starting with `*` or `&` must be quoted in YAML (`"*kurzíva* na začátku"`); the export does that.
- Numbers, booleans and dates in `question`/`answer` are taken as text exactly as written (`answer: 42` → `"42"`, `answer: yes` → `"yes"`). The YAML is parsed into the representation model so scalars keep their source text.

## 3. Export

- Header comment `# Quizly balíček · formát v1`, then `deck`, then `cards` in card sort order.
- Every card has `id`. `description` is always written, `color` quoted.
- Single-line text is a plain scalar; it is double-quoted when YAML needs it or when other tools could read it as a number, boolean or null (`"42"`, `"yes"`). Multi-line text uses a literal block `|-` (the importer accepts `|` too).
- UTF-8 without BOM, LF line endings, 2-space indent. Czech characters are written as is (no `\u` escapes).
- **Round trip:** exporting and re-importing without edits gives a preview with 0 changes.

## 4. Text normalization on import

1. Line endings `\r\n` / `\r` → `\n`.
2. Trim leading and trailing whitespace (this also removes the final newline a `|` block adds).
3. Compare with the stored text after the same normalization. Only real differences count as "changed".

## 5. Preview (dry run)

Import is **always** a preview first. The preview never writes anything.

```json
{
  "valid": true,
  "baseHash": "a91f…",
  "deck": { "nameChanged": false, "descriptionChanged": true, "colorChanged": false },
  "counts": { "new": 1, "changed": 2, "deleted": 3, "unchanged": 114 },
  "orderChanged": true,
  "new": [ { "line": 18, "question": "Co je record v C#?" } ],
  "changed": [ { "id": 102, "line": 12, "question": "Co dělá klíčové slovo async?",
                 "fields": ["answer"], "before": { "answer": "…" }, "after": { "answer": "…" } } ],
  "deleted": [ { "id": 77, "question": "…", "usersWithProgress": 2 } ],
  "errors": []
}
```

- **new:** cards without `id`.
- **changed:** cards with `id` whose question or answer differ. Users' progress stays.
- **deleted:** existing cards of the deck whose `id` is not in the YAML. They're deleted **together with all users' progress**.
- **unchanged:** everything else.
- **orderChanged:** card order differs; applying it updates `sort_order` (not counted as "changed").
- `baseHash` = SHA-256 of the deck's current export. Apply sends it back; if the deck changed in the meantime, apply fails with `concurrencyConflict` ("Balíček se mezitím změnil. Načti náhled znovu.").
- **kept** / `counts.kept`: always empty / 0 here. They are used by the MCP server, which keeps missing cards instead of deleting them ([mcp.md](./mcp.md) §2); there the cards that would be `deleted` are `kept` and stay untouched after the file's cards.

## 6. Validation errors

Every error has a 1-based `line` (and `column` where known) and a Czech message. **Any error blocks saving.** All errors are reported at once, not just the first.

| Code | Message (Czech UI) |
| --- | --- |
| `syntax` | Neplatný YAML: {detail} (řádek {line}) |
| `notMapping` | Kořen souboru musí obsahovat klíče „deck“ a „cards“. |
| `missingKey` | Chybí povinný klíč „{key}“. |
| `unknownKey` | Neznámý klíč „{key}“. |
| `wrongType` | „{key}“ musí být {type}. |
| `emptyText` | „{key}“ nesmí být prázdné. |
| `tooLong` | „{key}“ má {length} znaků, maximum je {max}. |
| `invalidColor` | Barva musí být ve tvaru #RRGGBB. |
| `invalidId` | „id“ musí být kladné celé číslo. |
| `duplicateId` | Karta s id {id} je v souboru víckrát (také na řádku {otherLine}). |
| `foreignId` | Karta {id} patří do jiného balíčku ({deckName}). |
| `unknownId` | Karta {id} neexistuje. Smaž „id“, pokud má vzniknout nová karta. |
| `idInNewDeck` | Při importu nového balíčku karty nesmí mít „id“. |
| `aliasNotAllowed` | Kotvy, aliasy a tagy nejsou povolené. |
| `tooManyCards` | Balíček může mít nejvýš 2 000 karet. |
| `fileTooLarge` | Soubor je větší než 1 MB. |

`unknownId` covers ids that don't exist at all (e.g. a card deleted meanwhile or an id the AI made up).

## 7. Apply

`PUT /api/admin/decks/{id}/yaml` with `{ yaml, baseHash, confirmDeleteIds }`.

1. Re-run the full validation and diff (the YAML is not trusted from the preview).
2. `baseHash` must match the current export (`concurrencyConflict`).
3. `confirmDeleteIds` must equal the set of cards that would be deleted (`deleteNotConfirmed` otherwise). The dashboard shows the confirm dialog **"Smazat 3 karty i s postupem uživatelů?"** (Czech plural: 1 kartu · 2–4 karty · 5+ karet) listing those cards, and only sends their ids after the admin confirms.
4. In one transaction: update deck fields, update changed cards (`updated_at`), insert new cards, delete removed cards (cascades to progress), set `sort_order` = position in the file (0, 1, 2, …).
5. Response: counts as in the preview plus the new export.

## 8. Import as a new deck

"Importovat YAML" on the deck list: `POST /api/admin/decks/import/preview`, then `POST /api/admin/decks/import`.
- Same schema; cards must **not** have `id` (`idInNewDeck`).
- Creates the deck (sort order = last + 1) and all cards. Nothing is deleted, so no confirmation.

## 9. Workflow with an AI agent

1. Balíčky → deck → **YAML** tab → **Kopírovat** (or **Stáhnout**).
2. Give it to an AI agent with an instruction such as: *"Přidej 20 karet o LINQ. Existující karty a jejich `id` nech beze změny. Nové karty piš bez `id`. Formátování jen `**tučně**`, `*kurzíva*`, `<small>malé</small>` a seznamy `- ` / `1. `."*
3. Paste the result → **Náhled** → check new / changed / deleted → **Uložit** (confirm deletes if any).

With the MCP server on, Claude can do steps 1–3 itself: read the deck, preview the change and save it, without deleting any cards ([mcp.md](./mcp.md)).

## 10. Formatting

Questions and answers are text with a little formatting, drawn by the app (issue #10). Anything else is shown as typed.

| Write | Shows as |
| --- | --- |
| `**tučně**` | **bold** |
| `*kurzíva*` | *italic* (no space just inside the stars, so `2 * 3 * 4` stays as is) |
| `<small>malé písmo</small>` | smaller, muted text (a note, a source) |
| a line starting with `- ` (or `• `) | bullet list item |
| a line starting with `1. ` (or `1) `) | numbered list item, the number as written |
| an empty line | a gap |

Styles nest (`**tučně a *kurzíva***`). Markup counts toward the length limits. Screen readers and the app's card search use the text without the markup.

```yaml
  - question: Jaké typy má C#?
    answer: |-
      **Hodnotové** a **referenční**:
      - struct, enum
      - class, record
      <small>(record struct je hodnotový)</small>
```

