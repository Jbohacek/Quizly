using System.ComponentModel;
using ModelContextProtocol;
using ModelContextProtocol.Server;
using Quizly.Application.Decks;
using Quizly.Application.Yaml;

namespace Quizly.Web.Mcp;

/// <summary>
/// Deck tools for Claude (docs/mcp.md): list, export, preview and save deck YAML on top of the same services as the
/// dashboard. Nothing is ever deleted: cards missing from the YAML are kept (<see cref="MissingCards.Keep"/>).
/// </summary>
[McpServerToolType]
internal sealed class DeckTools(IDeckService decks, IYamlDeckService yamlDecks, ILogger<DeckTools> logger)
{
    private const string Format =
        """
        Quizly deck YAML format v1: a mapping with `deck` (`name` 1–100 chars, optional `description` ≤ 500 chars, optional `color` "#RRGGBB") and `cards`, a list of { id, question, answer, tags }.
        Rules:
        - Keep every existing card's `id` exactly as exported. A card with an `id` is updated in place and users keep their learning progress on it.
        - A card without `id` is a new card. Never invent ids.
        - Card order in the file is the order in the deck.
        - `question` 1–500 chars, `answer` 1–2000 chars, no other keys. Multi-line text uses a block scalar (`|`). Quote text that starts with `*` or `&`.
        - `tags` is optional: a list like `tags: [ai_gen, prednaska_01]` for organizing cards (where a card comes from, which lecture). Lowercase letters, digits, `_` and `-`, at most 30 chars each, at most 10 per card. Keep the tags of existing cards; a card without `tags` has none.
        - Text is plain, with only this light formatting: **bold**, *italic*, <small>small note</small>, and lines starting with "- " or "1. " for lists. No images, links, headings or other Markdown/HTML.
        - The app is Czech: write cards in Czech unless asked otherwise.
        - Cards missing from the YAML are never deleted through this server; they stay untouched (deleting is dashboard-only).
        """;

    private const string KeptNote =
        "Cards missing from the YAML are not deleted: they stay untouched after the file's cards (missingKept). Deleting cards is only possible in the Quizly dashboard.";

    private const string SavedNote =
        KeptNote + " New cards now have ids: call get_deck_yaml before editing this deck again, or cards without ids are added twice.";

    [McpServerTool(Name = "list_decks", Title = "List decks", ReadOnly = true, Idempotent = true, OpenWorld = false)]
    [Description("Lists all Quizly flashcard decks with id, name, description, card count and whether the deck is archived. Call this first to find an existing deck instead of creating a duplicate. Archived decks are hidden from app users (archiving and restoring is dashboard-only); edit them only when asked to.")]
    public async Task<IReadOnlyList<McpDeck>> ListDecks(CancellationToken ct)
    {
        var list = (await decks.ListAsync(ct)).Select(d => new McpDeck(d.Id, d.Name, d.Description, d.CardCount, d.ArchivedAt is not null)).ToList();
        logger.LogInformation("MCP list_decks: {Count} decks", list.Count);
        return list;
    }

    [McpServerTool(Name = "get_deck_yaml", Title = "Export a deck as YAML", ReadOnly = true, Idempotent = true, OpenWorld = false)]
    [Description($"""
        Exports one deck as YAML (format v1) with every card's id, plus the deck's baseHash. Edit this YAML and pass it to preview_deck_yaml / apply_deck_yaml together with the baseHash.

        {Format}
        """)]
    public async Task<McpDeckYaml> GetDeckYaml(
        [Description("Deck id from list_decks.")] int deckId,
        CancellationToken ct)
    {
        var export = await yamlDecks.ExportAsync(deckId, ct);
        if (!export.IsSuccess)
        {
            throw DeckNotFound(deckId);
        }

        logger.LogInformation("MCP get_deck_yaml: deck {DeckId}", deckId);
        return new McpDeckYaml(deckId, DeckYaml.Hash(export.Value!), export.Value!);
    }

    [McpServerTool(Name = "preview_deck_yaml", Title = "Preview deck YAML", ReadOnly = true, Idempotent = true, OpenWorld = false)]
    [Description($"""
        Dry run of saving deck YAML; saves nothing. Returns validation errors with line numbers, or the new / changed / unchanged cards, the cards missing from the YAML that stay untouched, and the deck's current baseHash.
        Without deckId the YAML is checked as a new deck (its cards must not have ids).

        {Format}
        """)]
    public async Task<McpPreview> PreviewDeckYaml(
        [Description("The whole deck as YAML format v1.")] string yaml,
        [Description("Id of the deck to update. Omit to check the YAML as a new deck.")] int? deckId = null,
        CancellationToken ct = default)
    {
        var request = new YamlRequest(yaml);
        var preview = deckId is int id
            ? await yamlDecks.PreviewAsync(id, request, ct, MissingCards.Keep)
            : await yamlDecks.PreviewNewDeckAsync(request, ct);
        if (!preview.IsSuccess)
        {
            throw DeckNotFound(deckId);
        }

        var p = preview.Value!;
        var result = new McpPreview(
            p.Valid,
            p.Errors,
            p.BaseHash,
            p.Deck,
            Counts(p.Counts),
            p.OrderChanged,
            p.New,
            p.Changed,
            p.Kept,
            p.Valid ? KeptNote : "The YAML has errors; fix them (see line numbers) and preview again.");
        logger.LogInformation(
            "MCP preview_deck_yaml: deck {DeckId}, valid {Valid}, errors {Errors}, new {New}, changed {Changed}, unchanged {Unchanged}, kept {Kept}",
            deckId, p.Valid, p.Errors.Count, p.Counts.New, p.Counts.Changed, p.Counts.Unchanged, p.Counts.Kept);
        return result;
    }

    [McpServerTool(Name = "apply_deck_yaml", Title = "Save deck YAML", Destructive = false, Idempotent = false, OpenWorld = false)]
    [Description($"""
        Saves deck YAML. With deckId it updates that deck: new cards are added, changed cards are updated (users keep their progress), and baseHash (from get_deck_yaml or preview_deck_yaml) must match the deck's current state. Without deckId it creates a new deck (cards must not have ids).
        Never deletes anything: cards missing from the YAML stay untouched and are listed in missingKept.
        Call preview_deck_yaml first and check the result. On validation errors nothing is saved.
        After saving, call get_deck_yaml before editing the deck again: new cards get ids, and a card sent again without its id is added twice.

        {Format}
        """)]
    public async Task<McpApplyResult> ApplyDeckYaml(
        [Description("The whole deck as YAML format v1.")] string yaml,
        [Description("Id of the deck to update. Omit to create a new deck.")] int? deckId = null,
        [Description("Required with deckId: the baseHash returned by get_deck_yaml or preview_deck_yaml for this deck.")] string? baseHash = null,
        CancellationToken ct = default)
    {
        var result = deckId is int id ? await UpdateAsync(id, yaml, baseHash, ct) : await CreateAsync(yaml, ct);
        logger.LogInformation(
            "MCP apply_deck_yaml: deck {DeckId}, saved {Saved}, errors {Errors}, new {New}, changed {Changed}, unchanged {Unchanged}, kept {Kept}",
            result.DeckId ?? deckId, result.Saved, result.Errors.Count,
            result.Counts.New, result.Counts.Changed, result.Counts.Unchanged, result.Counts.MissingKept);
        return result;
    }

    private async Task<McpApplyResult> UpdateAsync(int deckId, string text, string? baseHash, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(baseHash))
        {
            throw new McpException("baseHash is required when updating a deck. Call get_deck_yaml or preview_deck_yaml for this deck first.");
        }

        var applied = await yamlDecks.ApplyAsync(deckId, new YamlApplyRequest(text, baseHash), ct, MissingCards.Keep);
        if (applied.IsSuccess)
        {
            var a = applied.Value!;
            return new McpApplyResult(true, deckId, Counts(a.Counts), a.Kept, DeckYaml.Hash(a.Yaml), [], SavedNote);
        }

        return applied.Error.Code switch
        {
            "yamlInvalid" => NotSaved(deckId, applied.Error.Extensions),
            "concurrencyConflict" => throw new McpException(
                "The deck changed since baseHash was taken (someone edited it). Call get_deck_yaml again, redo the edit on the new YAML, preview and apply."),
            _ => throw DeckNotFound(deckId),
        };
    }

    private async Task<McpApplyResult> CreateAsync(string text, CancellationToken ct)
    {
        var created = await yamlDecks.ImportNewDeckAsync(new YamlRequest(text), ct);
        if (!created.IsSuccess)
        {
            return NotSaved(null, created.Error.Extensions);
        }

        var deck = created.Value!;
        var export = (await yamlDecks.ExportAsync(deck.Id, ct)).Value!;
        return new McpApplyResult(true, deck.Id, new McpCounts(deck.CardCount, 0, 0, 0), [], DeckYaml.Hash(export), [],
            "A new deck was created. It is visible to every app user (Pro všechny); the admin can limit that in the dashboard. "
            + "Call get_deck_yaml before editing it: its cards now have ids.");
    }

    private static McpApplyResult NotSaved(int? deckId, IReadOnlyDictionary<string, object?>? extensions) =>
        new(false, deckId, new McpCounts(0, 0, 0, 0), [], null,
            extensions?.GetValueOrDefault("yamlErrors") as IReadOnlyList<YamlIssue> ?? [],
            "Nothing was saved. Fix the errors (see line numbers) and try again.");

    private static McpCounts Counts(YamlCounts c) => new(c.New, c.Changed, c.Unchanged, c.Kept);

    private static McpException DeckNotFound(int? deckId) =>
        new($"Deck {deckId} does not exist. Call list_decks to see the decks.");
}

/// <summary>A deck in <c>list_decks</c>; <c>Archived</c> decks are hidden from app users (#28).</summary>
internal sealed record McpDeck(int Id, string Name, string Description, int CardCount, bool Archived);

/// <summary>A deck's YAML export and the hash to send back when saving it.</summary>
internal sealed record McpDeckYaml(int DeckId, string BaseHash, string Yaml);

/// <summary>Card counts; <c>MissingKept</c> are existing cards missing from the YAML that stay untouched.</summary>
internal sealed record McpCounts(int New, int Changed, int Unchanged, int MissingKept);

/// <summary>The dry run of saving deck YAML.</summary>
internal sealed record McpPreview(
    bool Valid,
    IReadOnlyList<YamlIssue> Errors,
    string? BaseHash,
    YamlDeckChanges? Deck,
    McpCounts Counts,
    bool OrderChanged,
    IReadOnlyList<YamlNewCard> New,
    IReadOnlyList<YamlChangedCard> Changed,
    IReadOnlyList<YamlKeptCard> MissingKept,
    string Note);

/// <summary>What <c>apply_deck_yaml</c> saved, or the errors that stopped it.</summary>
internal sealed record McpApplyResult(
    bool Saved,
    int? DeckId,
    McpCounts Counts,
    IReadOnlyList<YamlKeptCard> MissingKept,
    string? BaseHash,
    IReadOnlyList<YamlIssue> Errors,
    string Note);
