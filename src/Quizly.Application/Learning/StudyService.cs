using Microsoft.EntityFrameworkCore;
using Quizly.Application.Abstractions;
using Quizly.Application.Common;
using Quizly.Application.Decks;
using Quizly.Domain;
using Quizly.Domain.Scheduling;

namespace Quizly.Application.Learning;

public interface IStudyService
{
    Task<Result<SessionResponse>> GetSessionAsync(int userId, int? deckId, int extraNew, CancellationToken ct);

    Task<AppDeckListResponse> GetDecksAsync(int userId, CancellationToken ct);

    Task<Result<DeckCardsResponse>> GetDeckCardsAsync(int userId, int deckId, CancellationToken ct);
}

/// <summary>Session queue and deck counts (docs/spec.md §4.1, docs/api.md §4–5).</summary>
internal sealed class StudyService(IAppDbContext db, Progress progress, TimeProvider time) : IStudyService
{
    /// <summary>Zvládnuto: Review with stability ≥ 21 days (docs/spec.md §3.5).</summary>
    internal const double MasteredStability = 21;

    /// <summary>"Ještě 5 nových karet" asks for this many at most, over the daily allowance.</summary>
    internal const int MaxExtraNew = 50;

    public async Task<Result<SessionResponse>> GetSessionAsync(int userId, int? deckId, int extraNew, CancellationToken ct)
    {
        if (extraNew is < 0 or > MaxExtraNew)
        {
            return new Validator().Range("extraNew", extraNew, "Nové karty navíc", 0, MaxExtraNew).ToError();
        }

        if (deckId is not null && !await db.Decks.VisibleTo(userId).AnyAsync(d => d.Id == deckId, ct))
        {
            return Progress.NotFoundDeck;
        }

        var now = time.GetUtcNow().UtcDateTime;
        var settings = await db.UserSettings.AsNoTracking().FirstAsync(s => s.UserId == userId, ct);
        var cards = db.Cards.VisibleTo(userId).Where(c => deckId == null || c.DeckId == deckId);

        var dueRows = await db.CardStates
            .Where(s => s.UserId == userId && s.Due <= now)
            .Join(cards, s => s.CardId, c => c.Id, (s, c) => new
            {
                c.Id,
                c.DeckId,
                c.Question,
                c.Answer,
                Tags = c.Tags.Select(t => t.Name).ToList(),
                s.State,
                s.Step,
                s.Stability,
                s.Difficulty,
                s.Due,
                s.LastReview,
            })
            .OrderBy(x => x.Due).ThenBy(x => x.Id)
            .ToListAsync(ct);

        var due = dueRows.Select(x =>
        {
            var fsrsCard = new FsrsCard(x.State, x.Step, x.Stability, x.Difficulty, x.Due, x.LastReview);
            var (intervals, relearnIntervals) = CalculateCardIntervals(fsrsCard, now);
            return new SessionCardResponse(x.Id, x.DeckId, x.Question, x.Answer, KindOf(x.State), Sorted(x.Tags), intervals, relearnIntervals);
        }).ToList();

        // Extra new cards are on top of what's left today; they still count as today's new cards.
        var allowance = extraNew + await progress.NewAllowanceLeftAsync(userId, settings.NewCardsPerDay, PragueCalendar.DayOf(now), ct);
        var freshCards = allowance == 0
            ? []
            : await Unseen(userId, cards)
                .OrderBy(c => c.Deck.SortOrder).ThenBy(c => c.DeckId).ThenBy(c => c.SortOrder).ThenBy(c => c.Id)
                .Take(allowance)
                .Select(c => new
                {
                    c.Id,
                    c.DeckId,
                    c.Question,
                    c.Answer,
                    Tags = c.Tags.Select(t => t.Name).ToList(),
                })
                .ToListAsync(ct);

        var (freshIntervals, freshRelearnIntervals) = CalculateCardIntervals(FsrsCard.New(now), now);
        var fresh = freshCards.Select(c =>
            new SessionCardResponse(c.Id, c.DeckId, c.Question, c.Answer, "new", Sorted(c.Tags), freshIntervals, freshRelearnIntervals)
        ).ToList();

        var summary = await progress.SummaryAsync(userId, ct);
        var queue = due.Concat(fresh).ToList();
        return new SessionResponse(deckId, summary.Multiplier, Progress.PointsFor(summary), due.Count, fresh.Count, queue, settings.FourRatings);
    }

    public async Task<AppDeckListResponse> GetDecksAsync(int userId, CancellationToken ct)
    {
        var now = time.GetUtcNow().UtcDateTime;
        var settings = await db.UserSettings.AsNoTracking().FirstAsync(s => s.UserId == userId, ct);
        var allowance = await progress.NewAllowanceLeftAsync(userId, settings.NewCardsPerDay, PragueCalendar.DayOf(now), ct);

        var rows = await db.Decks.VisibleTo(userId)
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
            Percent(r.Mastered, r.Total),
            Percent(r.Total - r.Unseen - r.Mastered, r.Total),
            r.Unseen)).ToList();
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
                Tags = c.Tags.Select(t => t.Name).ToList(),
                State = db.CardStates.Where(s => s.UserId == userId && s.CardId == c.Id)
                    .Select(s => new { s.State, s.Stability, s.Due })
                    .FirstOrDefault(),
                Know = db.ReviewLogs.Count(r => r.UserId == userId && r.CardId == c.Id && r.Rating != Rating.Again),
                DontKnow = db.ReviewLogs.Count(r => r.UserId == userId && r.CardId == c.Id && r.Rating == Rating.Again),
            })
            .ToListAsync(ct);

        var items = cards.Select(c =>
        {
            var mastered = c.State is { State: FsrsState.Review } && c.State.Stability >= MasteredStability;
            return new DeckCardResponse(
                c.Id,
                c.Question,
                c.Answer,
                c.State is null ? "new" : mastered ? "mastered" : "learning",
                // How far the memory is on the way to Zvládnuto: stability out of 21 days.
                c.State is null ? 0 : mastered ? 100 : (int)Math.Min(99, c.State.Stability * 100 / MasteredStability),
                c.Know,
                c.DontKnow,
                c.State is null ? null : new DateTimeOffset(DateTime.SpecifyKind(c.State.Due, DateTimeKind.Utc)),
                Sorted(c.Tags));
        }).ToList();
        return new DeckCardsResponse(deck, items);
    }

    private static int Percent(int part, int total) => total == 0 ? 0 : part * 100 / total;

    /// <summary>Tags in the same (ordinal) order everywhere, whatever the database collation.</summary>
    private static List<string> Sorted(List<string> tags) => [.. tags.Order(StringComparer.Ordinal)];

    private static (CardIntervalsResponse Intervals, CardIntervalsResponse RelearnIntervals) CalculateCardIntervals(
        FsrsCard card, DateTime now)
    {
        var intervals = ComputeIntervals(card, now);
        var afterAgain = FsrsScheduler.Default.Review(card, FsrsRating.Again, now);
        var relearnIntervals = ComputeIntervals(afterAgain, now);
        return (intervals, relearnIntervals);
    }

    private static CardIntervalsResponse ComputeIntervals(FsrsCard card, DateTime now)
    {
        var again = FsrsScheduler.Default.Review(card, FsrsRating.Again, now);
        var hard = FsrsScheduler.Default.Review(card, FsrsRating.Hard, now);
        var good = FsrsScheduler.Default.Review(card, FsrsRating.Good, now);
        var easy = FsrsScheduler.Default.Review(card, FsrsRating.Easy, now);

        return new CardIntervalsResponse(
            ReviewIntervalFormatter.Format(again.Due - now),
            ReviewIntervalFormatter.Format(hard.Due - now),
            ReviewIntervalFormatter.Format(good.Due - now),
            ReviewIntervalFormatter.Format(easy.Due - now));
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
