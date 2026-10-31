using Microsoft.EntityFrameworkCore;
using Quizly.Application.Abstractions;
using Quizly.Application.Common;
using Quizly.Domain;

namespace Quizly.Application.Decks;

public interface IDeckService
{
    Task<IReadOnlyList<DeckResponse>> ListAsync(CancellationToken ct);

    Task<Result<DeckResponse>> GetAsync(int id, CancellationToken ct);

    Task<Result<DeckResponse>> CreateAsync(DeckRequest request, CancellationToken ct);

    Task<Result<DeckResponse>> UpdateAsync(int id, DeckRequest request, CancellationToken ct);

    /// <summary>Deletes the deck, its cards and all users' progress on them (docs/spec.md §2.14).</summary>
    Task<Result> DeleteAsync(int id, CancellationToken ct);

    /// <summary>Counts shown in the delete confirmation.</summary>
    Task<Result<DeckDeleteImpact>> GetDeleteImpactAsync(int id, CancellationToken ct);
}

internal sealed class DeckService(IAppDbContext db, TimeProvider time) : IDeckService
{
    public async Task<IReadOnlyList<DeckResponse>> ListAsync(CancellationToken ct) =>
        await Project(db.Decks.OrderBy(d => d.SortOrder).ThenBy(d => d.Id)).ToListAsync(ct);

    public async Task<Result<DeckResponse>> GetAsync(int id, CancellationToken ct)
    {
        var deck = await Project(db.Decks.Where(d => d.Id == id)).FirstOrDefaultAsync(ct);
        return deck is null ? DeckNotFound : deck;
    }

    public async Task<Result<DeckResponse>> CreateAsync(DeckRequest request, CancellationToken ct)
    {
        var (name, description, color) = Clean(request);
        var v = Validate(name, description, color);
        if (!v.IsValid)
        {
            return v.ToError();
        }

        var now = time.GetUtcNow().UtcDateTime;
        var sortOrder = request.SortOrder ?? (await db.Decks.MaxAsync(d => (int?)d.SortOrder, ct) ?? -1) + 1;
        var deck = new Deck
        {
            Name = name,
            Description = description,
            Color = color,
            SortOrder = sortOrder,
            CreatedAt = now,
            UpdatedAt = now,
        };
        db.Decks.Add(deck);
        await db.SaveChangesAsync(ct);
        return await GetAsync(deck.Id, ct);
    }

    public async Task<Result<DeckResponse>> UpdateAsync(int id, DeckRequest request, CancellationToken ct)
    {
        var deck = await db.Decks.FirstOrDefaultAsync(d => d.Id == id, ct);
        if (deck is null)
        {
            return DeckNotFound;
        }

        var (name, description, color) = Clean(request);
        var v = Validate(name, description, color);
        if (!v.IsValid)
        {
            return v.ToError();
        }

        deck.Name = name;
        deck.Description = description;
        deck.Color = color;
        deck.SortOrder = request.SortOrder ?? deck.SortOrder;
        deck.UpdatedAt = time.GetUtcNow().UtcDateTime;
        await db.SaveChangesAsync(ct);
        return await GetAsync(id, ct);
    }

    public async Task<Result> DeleteAsync(int id, CancellationToken ct)
    {
        var deleted = await db.Decks.Where(d => d.Id == id).ExecuteDeleteAsync(ct);
        return deleted == 0 ? DeckNotFound : Result.Ok();
    }

    public async Task<Result<DeckDeleteImpact>> GetDeleteImpactAsync(int id, CancellationToken ct)
    {
        if (!await db.Decks.AnyAsync(d => d.Id == id, ct))
        {
            return DeckNotFound;
        }

        var cards = await db.Cards.CountAsync(c => c.DeckId == id, ct);
        var users = await db.CardStates
            .Where(s => db.Cards.Any(c => c.Id == s.CardId && c.DeckId == id))
            .Select(s => s.UserId).Distinct().CountAsync(ct);
        return new DeckDeleteImpact(cards, users);
    }

    internal static AppError DeckNotFound => Errors.NotFound("Balíček neexistuje.");

    private static (string Name, string Description, string Color) Clean(DeckRequest request) =>
        (Validator.Clean(request.Name),
         Validator.Clean(request.Description),
         (request.Color ?? Limits.DefaultDeckColor).Trim().ToUpperInvariant());

    private static Validator Validate(string name, string description, string color) =>
        new Validator()
            .Text("name", name, "Název", Limits.DeckNameMax)
            .Text("description", description, "Popis", Limits.DeckDescriptionMax, min: 0)
            .Color("color", color);

    private static IQueryable<DeckResponse> Project(IQueryable<Deck> decks) =>
        decks.Select(d => new DeckResponse(
            d.Id,
            d.Name,
            d.Description,
            d.Color,
            d.SortOrder,
            d.Cards.Count,
            DateTime.SpecifyKind(d.CreatedAt, DateTimeKind.Utc),
            DateTime.SpecifyKind(d.UpdatedAt, DateTimeKind.Utc)));
}
