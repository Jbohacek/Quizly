using Microsoft.EntityFrameworkCore;
using Quizly.Application.Abstractions;
using Quizly.Application.Common;
using Quizly.Application.Decks;
using Quizly.Domain;

namespace Quizly.Application.Yaml;

public interface IYamlDeckService
{
    Task<Result<string>> ExportAsync(int deckId, CancellationToken ct);

    /// <summary><paramref name="missingCards"/>: what happens to existing cards missing from the file (MCP keeps them).</summary>
    Task<Result<YamlPreviewResponse>> PreviewAsync(
        int deckId, YamlRequest request, CancellationToken ct, MissingCards missingCards = MissingCards.Delete);

    /// <summary><paramref name="missingCards"/>: what happens to existing cards missing from the file (MCP keeps them).</summary>
    Task<Result<YamlApplyResponse>> ApplyAsync(
        int deckId, YamlApplyRequest request, CancellationToken ct, MissingCards missingCards = MissingCards.Delete);

    Task<YamlPreviewResponse> PreviewNewDeckAsync(YamlRequest request, CancellationToken ct);

    Task<Result<DeckResponse>> ImportNewDeckAsync(YamlRequest request, CancellationToken ct);
}

/// <summary>Deck YAML export, preview and apply against the database (docs/yaml-format.md).</summary>
internal sealed class YamlDeckService(IAppDbContext db, IDeckService decks, TimeProvider time) : IYamlDeckService
{
    public async Task<Result<string>> ExportAsync(int deckId, CancellationToken ct)
    {
        var deck = await db.Decks.AsNoTracking().FirstOrDefaultAsync(d => d.Id == deckId, ct);
        return deck is null ? DeckService.DeckNotFound : DeckYaml.Write(deck, await CardsAsync(deckId, ct));
    }

    public async Task<Result<YamlPreviewResponse>> PreviewAsync(
        int deckId, YamlRequest request, CancellationToken ct, MissingCards missingCards = MissingCards.Delete)
    {
        var deck = await db.Decks.AsNoTracking().FirstOrDefaultAsync(d => d.Id == deckId, ct);
        if (deck is null)
        {
            return DeckService.DeckNotFound;
        }

        var cards = await CardsAsync(deckId, ct);
        var plan = await PlanAsync(deck, cards, request.Yaml, missingCards, ct);
        return plan.Errors.Count > 0 ? Invalid(plan.Errors) : await PreviewOfAsync(deck, cards, plan, ct);
    }

    public async Task<Result<YamlApplyResponse>> ApplyAsync(
        int deckId, YamlApplyRequest request, CancellationToken ct, MissingCards missingCards = MissingCards.Delete)
    {
        await using var transaction = await db.Database.BeginTransactionAsync(ct);

        // Lock the deck so two applies (or an apply and a card edit through this path) can't interleave.
        var deck = await db.Decks.FromSql($"SELECT * FROM decks WHERE id = {deckId} FOR UPDATE").FirstOrDefaultAsync(ct);
        if (deck is null)
        {
            return DeckService.DeckNotFound;
        }

        var cards = await db.Cards.Where(c => c.DeckId == deckId).OrderBy(c => c.SortOrder).ThenBy(c => c.Id).ToListAsync(ct);
        var plan = await PlanAsync(deck, cards, request.Yaml, missingCards, ct);
        if (plan.Errors.Count > 0)
        {
            return YamlInvalid(plan.Errors);
        }

        if (DeckYaml.Hash(DeckYaml.Write(deck, cards)) != request.BaseHash)
        {
            return new AppError("concurrencyConflict", 409, "Balíček se mezitím změnil. Načti náhled znovu.");
        }

        var toDelete = plan.Deleted.Select(c => c.Id).ToHashSet();
        if (!toDelete.SetEquals(request.ConfirmDeleteIds ?? []))
        {
            return new AppError("deleteNotConfirmed", 422, "Potvrď smazání karet, které v souboru chybí.",
                Extensions: new Dictionary<string, object?> { ["deleteIds"] = toDelete.Order().ToList() });
        }

        var now = time.GetUtcNow().UtcDateTime;
        var byId = cards.ToDictionary(c => c.Id);
        var counts = Counts(plan, cards.Count, plan.Deck.Cards.Count(c => c.Id is int id && IsChanged(byId[id], c)));
        var kept = plan.Kept.Select(c => new YamlKeptCard(c.Id, c.Question)).ToList();
        deck.Name = plan.Deck.Name;
        deck.Description = plan.Deck.Description;
        deck.Color = plan.Deck.Color ?? deck.Color;
        deck.UpdatedAt = now;

        for (var position = 0; position < plan.Deck.Cards.Count; position++)
        {
            var parsed = plan.Deck.Cards[position];
            if (parsed.Id is int id)
            {
                var card = byId[id];
                if (IsChanged(card, parsed))
                {
                    card.Question = parsed.Question;
                    card.Answer = parsed.Answer;
                    card.UpdatedAt = now;
                }

                card.SortOrder = position;
            }
            else
            {
                db.Cards.Add(new Card
                {
                    DeckId = deckId,
                    Question = parsed.Question,
                    Answer = parsed.Answer,
                    SortOrder = position,
                    CreatedAt = now,
                    UpdatedAt = now,
                });
            }
        }

        // Kept cards follow the file's cards, in their current order.
        for (var i = 0; i < plan.Kept.Count; i++)
        {
            byId[plan.Kept[i].Id].SortOrder = plan.Deck.Cards.Count + i;
        }

        await db.SaveChangesAsync(ct);
        if (toDelete.Count > 0)
        {
            // Cascades to card_states and review_logs (docs/spec.md §2.14).
            await db.Cards.Where(c => toDelete.Contains(c.Id)).ExecuteDeleteAsync(ct);
        }

        await transaction.CommitAsync(ct);
        return new YamlApplyResponse(counts, (await ExportAsync(deckId, ct)).Value!, kept);
    }

    public Task<YamlPreviewResponse> PreviewNewDeckAsync(YamlRequest request, CancellationToken ct)
    {
        var (parsed, errors) = ParseNew(request.Yaml);
        return Task.FromResult(parsed is null
            ? Invalid(errors)
            : new YamlPreviewResponse(
                true,
                null,
                null,
                new YamlCounts(parsed.Cards.Count, 0, 0, 0),
                false,
                parsed.Cards.Select(c => new YamlNewCard(c.Line, c.Question)).ToList(),
                [],
                [],
                [],
                []));
    }

    public async Task<Result<DeckResponse>> ImportNewDeckAsync(YamlRequest request, CancellationToken ct)
    {
        var (parsed, errors) = ParseNew(request.Yaml);
        if (parsed is null)
        {
            return YamlInvalid(errors);
        }

        var now = time.GetUtcNow().UtcDateTime;
        var deck = new Deck
        {
            Name = parsed.Name,
            Description = parsed.Description,
            Color = parsed.Color ?? Limits.DefaultDeckColor,
            SortOrder = (await db.Decks.MaxAsync(d => (int?)d.SortOrder, ct) ?? -1) + 1,
            CreatedAt = now,
            UpdatedAt = now,
            Cards = parsed.Cards.Select((c, i) => new Card
            {
                Question = c.Question,
                Answer = c.Answer,
                SortOrder = i,
                CreatedAt = now,
                UpdatedAt = now,
            }).ToList(),
        };
        db.Decks.Add(deck);
        await db.SaveChangesAsync(ct);
        return await decks.GetAsync(deck.Id, ct);
    }

    private static (ParsedDeck? Deck, IReadOnlyList<YamlIssue> Errors) ParseNew(string yaml)
    {
        var (parsed, errors) = DeckYaml.Parse(yaml);
        if (parsed is null)
        {
            return (null, errors);
        }

        var withIds = parsed.Cards.Where(c => c.Id is not null)
            .Select(c => new YamlIssue("idInNewDeck", "Při importu nového balíčku karty nesmí mít „id“.", c.Line))
            .ToList();
        return withIds.Count > 0 ? (null, withIds) : (parsed, []);
    }

    /// <summary>Parses the file and checks every id against the database.</summary>
    private async Task<Plan> PlanAsync(Deck deck, IReadOnlyList<Card> cards, string yaml, MissingCards missingCards, CancellationToken ct)
    {
        var (parsed, errors) = DeckYaml.Parse(yaml);
        if (parsed is null)
        {
            return new Plan(null!, [], [], errors);
        }

        var own = cards.Select(c => c.Id).ToHashSet();
        var foreignIds = parsed.Cards.Where(c => c.Id is int id && !own.Contains(id)).Select(c => c.Id!.Value).ToList();
        var foreign = await db.Cards.AsNoTracking()
            .Where(c => foreignIds.Contains(c.Id))
            .Select(c => new { c.Id, DeckName = c.Deck.Name })
            .ToDictionaryAsync(c => c.Id, c => c.DeckName, ct);

        var idErrors = new List<YamlIssue>();
        foreach (var card in parsed.Cards.Where(c => c.Id is int id && !own.Contains(id)))
        {
            var id = card.Id!.Value;
            idErrors.Add(foreign.TryGetValue(id, out var deckName)
                ? new YamlIssue("foreignId", $"Karta {id} patří do jiného balíčku ({deckName}).", card.Line)
                : new YamlIssue("unknownId", $"Karta {id} neexistuje. Smaž „id“, pokud má vzniknout nová karta.", card.Line));
        }

        if (idErrors.Count > 0)
        {
            return new Plan(null!, [], [], idErrors);
        }

        var inFile = parsed.Cards.Where(c => c.Id is not null).Select(c => c.Id!.Value).ToHashSet();
        var missing = cards.Where(c => !inFile.Contains(c.Id)).ToList();
        return missingCards == MissingCards.Keep
            ? new Plan(parsed, [], missing, [])
            : new Plan(parsed, missing, [], []);
    }

    private async Task<YamlPreviewResponse> PreviewOfAsync(Deck deck, List<Card> cards, Plan plan, CancellationToken ct)
    {
        var byId = cards.ToDictionary(c => c.Id);
        var changed = new List<YamlChangedCard>();
        foreach (var parsed in plan.Deck.Cards.Where(c => c.Id is not null))
        {
            var current = byId[parsed.Id!.Value];
            if (!IsChanged(current, parsed))
            {
                continue;
            }

            var questionChanged = current.Question != parsed.Question;
            var answerChanged = current.Answer != parsed.Answer;

            changed.Add(new YamlChangedCard(
                current.Id,
                parsed.Line,
                parsed.Question,
                [.. questionChanged ? ["question"] : Array.Empty<string>(), .. answerChanged ? ["answer"] : Array.Empty<string>()],
                new YamlCardText(questionChanged ? current.Question : null, answerChanged ? current.Answer : null),
                new YamlCardText(questionChanged ? parsed.Question : null, answerChanged ? parsed.Answer : null)));
        }

        var deletedIds = plan.Deleted.Select(c => c.Id).ToList();
        var progress = await db.CardStates
            .Where(s => deletedIds.Contains(s.CardId))
            .GroupBy(s => s.CardId)
            .Select(g => new { CardId = g.Key, Users = g.Count() })
            .ToDictionaryAsync(x => x.CardId, x => x.Users, ct);

        // Order of the existing cards that stay: file order (kept cards after it) vs. current order.
        var newOrder = plan.Deck.Cards.Where(c => c.Id is not null).Select(c => c.Id!.Value)
            .Concat(plan.Kept.Select(c => c.Id)).ToList();
        var currentOrder = cards.Select(c => c.Id).Where(newOrder.Contains).ToList();

        return new YamlPreviewResponse(
            true,
            DeckYaml.Hash(DeckYaml.Write(deck, cards)),
            new YamlDeckChanges(
                deck.Name != plan.Deck.Name,
                deck.Description != plan.Deck.Description,
                plan.Deck.Color is not null && plan.Deck.Color != deck.Color),
            Counts(plan, cards.Count, changed.Count),
            !newOrder.SequenceEqual(currentOrder),
            plan.Deck.Cards.Where(c => c.Id is null).Select(c => new YamlNewCard(c.Line, c.Question)).ToList(),
            changed,
            plan.Deleted.Select(c => new YamlDeletedCard(c.Id, c.Question, progress.GetValueOrDefault(c.Id))).ToList(),
            [],
            plan.Kept.Select(c => new YamlKeptCard(c.Id, c.Question)).ToList());
    }

    /// <summary>Stored text is already normalized, so a plain comparison finds real changes only (docs/yaml-format.md §4).</summary>
    private static bool IsChanged(Card current, ParsedCard parsed) =>
        current.Question != parsed.Question || current.Answer != parsed.Answer;

    private static YamlCounts Counts(Plan plan, int existing, int changed)
    {
        var inFile = existing - plan.Deleted.Count - plan.Kept.Count;
        return new YamlCounts(plan.Deck.Cards.Count(c => c.Id is null), changed, plan.Deleted.Count, inFile - changed, plan.Kept.Count);
    }

    private async Task<List<Card>> CardsAsync(int deckId, CancellationToken ct) =>
        await db.Cards.AsNoTracking().Where(c => c.DeckId == deckId).OrderBy(c => c.SortOrder).ThenBy(c => c.Id).ToListAsync(ct);

    private static YamlPreviewResponse Invalid(IReadOnlyList<YamlIssue> errors) =>
        new(false, null, null, new YamlCounts(0, 0, 0, 0), false, [], [], [], errors, []);

    private static AppError YamlInvalid(IReadOnlyList<YamlIssue> errors) =>
        new("yamlInvalid", 422, "YAML obsahuje chyby. Oprav je a zkus to znovu.",
            Extensions: new Dictionary<string, object?> { ["yamlErrors"] = errors });

    /// <summary>The parsed file; existing cards missing from it are either <c>Deleted</c> or <c>Kept</c>.</summary>
    private sealed record Plan(ParsedDeck Deck, IReadOnlyList<Card> Deleted, IReadOnlyList<Card> Kept, IReadOnlyList<YamlIssue> Errors);
}
