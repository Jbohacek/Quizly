# MCP server for Claude

Quizly has a remote [MCP](https://modelcontextprotocol.io) server, so Claude (claude.ai and Claude Code) can read and write decks directly instead of the admin copying YAML back and forth (issue #30). It lives in the same ASP.NET Core app (`src/Quizly.Web/Mcp/`) and calls the same deck and YAML services as the dashboard; there is no new business logic.

## 1. What Claude can do

| Tool | Input | What it does |
| --- | --- | --- |
| `list_decks` | none | Every deck with `id`, `name`, `description`, `cardCount` and `archived` (hidden from app users, #28). Read-only. |
| `get_deck_yaml` | `deckId` | The deck as YAML format v1 (every card with its `id`, [yaml-format.md](./yaml-format.md) §3) plus its `baseHash`. Read-only. |
| `preview_deck_yaml` | `yaml`, `deckId?` | Dry run, saves nothing: validation errors with line numbers, or the new / changed / unchanged cards, the cards missing from the YAML (`missingKept`) and the deck's `baseHash`. Without `deckId` the YAML is checked as a new deck. |
| `apply_deck_yaml` | `yaml`, `deckId?`, `baseHash?` | Saves the YAML. With `deckId` it updates that deck (`baseHash` required); without it, it creates a new deck. **Never deletes anything.** |

Not exposed: deleting cards or decks, deck visibility, archiving and restoring decks, users, shop items, claims, points, notification texts. Archived decks are listed (so Claude doesn't create a duplicate) and can be read and edited like any other.

The tool descriptions (English, read by Claude) explain the YAML v1 rules: keep every `id`, no `id` = new card, file order = deck order, the length limits, card `tags` (#29, [yaml-format.md](./yaml-format.md) §2), the light formatting of [yaml-format.md](./yaml-format.md) §10, Czech cards, and that missing cards are kept.

## 2. Rules

- **Nothing is deleted.** `apply_deck_yaml` runs the import with missing cards **kept** (`MissingCards.Keep` in `YamlDeckService`): an existing card whose `id` isn't in the YAML stays as it is, with everyone's progress. Kept cards move after the file's cards, in their current order. Preview and apply list them in `missingKept` and count them in `counts.missingKept`. Deleting a card (and everyone's progress on it) stays in the dashboard, behind its confirmation ([yaml-format.md](./yaml-format.md) §7).
- **`baseHash` guards against lost edits.** Users edit cards in the app (#23), so a deck can change while Claude works on it. `apply_deck_yaml` for an existing deck needs the `baseHash` from `get_deck_yaml` or `preview_deck_yaml`. If the deck changed in the meantime, the tool fails ("The deck changed since baseHash was taken…") and Claude reloads the deck. The REST apply has the same check.
- **After saving, reload.** New cards get ids when they're saved. A card sent again without its `id` is added a second time, so the result tells Claude to call `get_deck_yaml` before editing that deck again.
- **Validation** is the dashboard's ([yaml-format.md](./yaml-format.md) §6): the same codes, Czech messages and line numbers. Any error saves nothing; `apply_deck_yaml` returns `saved: false` with the `errors`.
- **New decks** are "Pro všechny", like a YAML import in the dashboard. The admin can limit who sees them in the deck's Nastavení.

### Example results

`preview_deck_yaml`:

```json
{
  "valid": true,
  "errors": [],
  "baseHash": "6b4f…",
  "deck": { "nameChanged": true, "descriptionChanged": false, "colorChanged": false },
  "counts": { "new": 1, "changed": 1, "unchanged": 0, "missingKept": 2 },
  "orderChanged": false,
  "new": [ { "line": 7, "question": "Nová" } ],
  "changed": [ { "id": 14, "line": 4, "question": "Změněná", "fields": ["question"],
                 "before": { "question": "…" }, "after": { "question": "Změněná" } } ],
  "missingKept": [ { "id": 15, "question": "…" }, { "id": 16, "question": "…" } ],
  "note": "Cards missing from the YAML are not deleted: …"
}
```

`apply_deck_yaml`:

```json
{
  "saved": true,
  "deckId": 7,
  "counts": { "new": 1, "changed": 1, "unchanged": 0, "missingKept": 2 },
  "missingKept": [ { "id": 15, "question": "…" }, { "id": 16, "question": "…" } ],
  "baseHash": "e2dd…",
  "errors": [],
  "note": "… call get_deck_yaml before editing this deck again …"
}
```

An unknown deck, a missing or stale `baseHash` come back as a tool error (`isError: true`) with an English message saying what to do next.

## 3. Endpoint and security

- **Transport:** Streamable HTTP, stateless (no `Mcp-Session-Id`), official C# SDK `ModelContextProtocol.AspNetCore`.
- **URL:** `https://quizly.jbohacek.cz/mcp/<secret>`. Phase 1 has no sign-in: whoever knows the URL can read and edit decks, so the secret is the password.
- **Off by default.** With `Mcp__Enabled=false` nothing is mapped and everything under `/mcp` answers `404`.
- **The secret** (`Mcp__Secret`) is at least 48 URL-safe characters (`A–Z a–z 0–9 - _`). With MCP on and the secret missing or short, the app refuses to start. It's compared in constant time.
- **Anything else under `/mcp`** (a wrong secret, extra path segments) is a plain `404`, as if nothing was there.
- **The secret is not logged.** A middleware before routing checks it and rewrites the path to `/mcp`, so routing, the SDK and the app log only see `/mcp`. The request line that ASP.NET Core logs before any middleware runs (`Microsoft.AspNetCore.Hosting.Diagnostics`, level Information) is kept at Warning in `appsettings.json`; don't raise it in production. A test checks that no log line contains the secret.
- **Rate limit:** 60 requests per minute per IP (`RateLimits__mcp__PermitLimit`, `RateLimits__mcp__Window`), then `429`.
- **Logged:** every tool call at Information, e.g. `MCP apply_deck_yaml: deck 7, saved True, errors 0, new 1, changed 1, unchanged 0, kept 2`.
- **Known limit of phase 1:** Nginx Proxy Manager's access log on the server does contain the full URL. Treat that log like the `.env`. If the secret might have leaked, rotate it ([deploy/README-deploy.md](../deploy/README-deploy.md), Rotate secrets).
- **Later (separate issue):** proper OAuth sign-in for the connector (authorization code + PKCE) tied to the admin account, instead of the secret path.

## 4. Configuration

| Variable | Default | Meaning |
| --- | --- | --- |
| `Mcp__Enabled` | `false` | Turns the endpoint on |
| `Mcp__Secret` | (none) | The path secret, ≥ 48 URL-safe chars: `openssl rand -base64 48 \| tr '+/' '-_' \| tr -d '='` |
| `RateLimits__mcp__PermitLimit` | `60` | Requests per window per IP |
| `RateLimits__mcp__Window` | `00:01:00` | Rate-limit window |

Setup on the server and in Claude: [deploy/README-deploy.md](../deploy/README-deploy.md) §8.

## 5. Connecting Claude

- **claude.ai:** Settings → Connectors → **Add custom connector** → name `Quizly`, URL `https://quizly.jbohacek.cz/mcp/<secret>`, no authentication.
- **Claude Code:**

  ```bash
  claude mcp add --transport http quizly https://quizly.jbohacek.cz/mcp/<secret>
  ```

- **Locally:** set `Mcp__Enabled=true` and a secret (e.g. with `dotnet user-secrets` or environment variables), run the app, then use `http://localhost:5278/mcp/<secret>` in Claude Code or the MCP Inspector (`npx @modelcontextprotocol/inspector`).

A typical prompt: *"V Quizly přidej do balíčku C# základy 15 karet o LINQ. Nejdřív si balíček načti, ať nevzniknou duplicity, ukaž mi náhled a pak ho ulož."*
