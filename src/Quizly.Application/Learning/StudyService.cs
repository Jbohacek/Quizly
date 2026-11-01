using Microsoft.EntityFrameworkCore;
using Quizly.Application.Abstractions;
using Quizly.Application.Common;
using Quizly.Domain;

namespace Quizly.Application.Learning;

public interface IStudyService
{
    Task<Result<SessionResponse>> GetSessionAsync(int userId, int? deckId, CancellationToken ct);

    Task<AppDeckListResponse> GetDecksAsync(int userId, CancellationToken ct);

    Task<Result<DeckCardsResponse>> GetDeckCardsAsync(int userId, int deckId, CancellationToken ct);
}

/// <summary>Session queue and deck counts (docs/spec.md §4.1, docs/api.md §4–5).</summary>
internal sealed class StudyService(IAppDbContext db, Progress progress, TimeProvider time) : IStudyService
{
    /// <summary>Zvládnuto: Review with stability ≥ 21 days (docs/spec.md §3.5).</summary>
    internal const double MasteredStability = 21;

    public async Task<Result<SessionResponse>> GetSessionAsync(int userId, int? deckId, CancellationToken ct)
    {
        if (deckId is not null && !await db.Decks.AnyAsync(d => d.Id == deckId, ct))
        {
            return Progress.NotFoundDeck;
        }

        var now = time.GetUtcNow().UtcDateTime;
        var settings = await db.UserSettings.AsNoTracking().FirstAsync(s => s.UserId == userId, ct);
        var cards = db.Cards.Where(c => deckId == null || c.DeckId == deckId);

        var due = await db.CardStates
            .Where(s => s.UserId == userId && s.Due <= now)
            .Join(cards, s => s.CardId, c => c.Id, (s, c) => new { s.Due, s.State, Card = c })
            .OrderBy(x => x.Due).ThenBy(x => x.Card.Id)
            .Select(x => new SessionCardResponse(x.Card.Id, x.Card.DeckId, x.Card.Question, x.Card.Answer, KindOf(x.State)))
            .ToListAsync(ct);

        var allowance = await progress.NewAllowanceLeftAsync(userId, settings.NewCardsPerDay, PragueCalendar.DayOf(now), ct);
        var fresh = allowance == 0
            ? []
            : await Unseen(userId, cards)
                .OrderBy(c => c.Deck.SortOrder).ThenBy(c => c.DeckId).ThenBy(c => c.SortOrder).ThenBy(c => c.Id)
                .Take(allowance)
                .Select(c => new SessionCardResponse(c.Id, c.DeckId, c.Question, c.Answer, "new"))
                .ToListAsync(ct);

        var summary = await progress.SummaryAsync(userId, ct);
        return new SessionResponse(deckId, summary.Multiplier, Progress.PointsFor(summary), due.Count, fresh.Count, [.. due, .. fresh]);
    }

    public async Task<AppDeckListResponse> GetDecksAsync(int userId, CancellationToken ct)
    {
        var now = time.GetUtcNow().UtcDateTime;
        var settings = await db.UserSettings.AsNoTracking().FirstAsync(s => s.UserId == userId, ct);
        var allowance = await progress.NewAllowanceLeftAsync(userId, settings.NewCardsPerDay, PragueCalendar.DayOf(now), ct);

        var rows = await db.Decks
            .OrderBy(d => d.SortOrder).ThenBy(d => d.Id)
            .Select(d => new
            {
                Deck = d,
                Total = d.Cards.Count,
                Due = db.CardStates.Count(s => s.UserId == userId && s.Due <= now && d.Cards.Any(c => c.Id == s.CardId)),
                Mastered = db.CardStates.Count(s => s.UserId == userId && s.State == FsrsState.Review
                    && s.Stability >= MasteredStability && d.Cards.Any(c => c.Id == s.CardId)),
                Unseen = d.Cards.Count(c => !db.CardStates.Any(s => s.UserId == userId && s.CardId == c.Id)),
            })
            .ToListAsync(ct);

        var items = rows.Select(r => new AppDeckResponse(
            r.Deck.Id,
            r.Deck.Name,
            r.Deck.Description,
            r.Deck.Color,
            r.Total,
            r.Due,
            Math.Min(r.Unseen, allowance),
            r.Total == 0 ? 0 : r.Mastered * 100 / r.Total)).ToList();
        return new AppDeckListResponse(items, allowance);
    }

    public async Task<Result<DeckCardsResponse>> GetDeckCardsAsync(int userId, int deckId, CancellationToken ct)
    {
        // A handful of decks: the list query gives the deck's counts the same way the home screen sees them.
        var deck = (await GetDecksAsync(userId, ct)).Items.FirstOrDefault(d => d.Id == deckId);
        if (deck is null)
        {
            return Progress.NotFoundDeck;
        }

        var cards = await db.Cards
            .Where(c => c.DeckId == deckId)
            .OrderBy(c => c.SortOrder).ThenBy(c => c.Id)
            .Select(c => new
            {
                c.Id,
                c.Question,
                c.Answer,
                State = db.CardStates.Where(s => s.UserId == userId && s.CardId == c.Id)
                    .Select(s => new { s.State, s.Stability })
                    .FirstOrDefault(),
            })
            .ToListAsync(ct);

        var items = cards.Select(c => new DeckCardResponse(
            c.Id,
            c.Question,
            c.Answer,
            c.State is null ? "new"
            : c.State.State == FsrsState.Review && c.State.Stability >= MasteredStability ? "mastered"
            : "learning")).ToList();
        return new DeckCardsResponse(deck, items);
    }

    internal IQueryable<Card> Unseen(int userId, IQueryable<Card> cards) =>
        cards.Where(c => !db.CardStates.Any(s => s.UserId == userId && s.CardId == c.Id));

    internal static string KindOf(FsrsState state) => state switch
    {
        FsrsState.Learning => "learning",
        FsrsState.Review => "review",
        _ => "relearning",
    };
}
