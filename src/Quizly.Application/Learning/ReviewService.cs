using Microsoft.EntityFrameworkCore;
using Quizly.Application.Abstractions;
using Quizly.Application.Common;
using Quizly.Application.Decks;
using Quizly.Domain;
using Quizly.Domain.Gamification;
using Quizly.Domain.Scheduling;

namespace Quizly.Application.Learning;

public interface IReviewService
{
    Task<Result<ReviewBatchResponse>> SubmitAsync(int userId, ReviewBatchRequest request, CancellationToken ct);
}

/// <summary>
/// Applies a batch of answers in order, in one transaction under a lock on the user row
/// (docs/api.md §6, docs/spec.md §4–6). Each answer is processed at most once per client UUID.
/// </summary>
internal sealed class ReviewService(IAppDbContext db, Progress progress, TimeProvider time) : IReviewService
{
    public const int MaxBatch = 50;

    public async Task<Result<ReviewBatchResponse>> SubmitAsync(int userId, ReviewBatchRequest request, CancellationToken ct)
    {
        var reviews = request.Reviews ?? [];
        if (Validate(reviews) is AppError invalid)
        {
            return invalid;
        }

        // Server receive time; each item gets +1 µs so the batch order is strictly increasing.
        var receivedAt = time.GetUtcNow().UtcDateTime;
        await using var transaction = await db.Database.BeginTransactionAsync(ct);
        var user = await progress.LockUserAsync(userId, ct);

        var ids = reviews.Select(r => r.Id).ToList();
        var cardIds = reviews.Select(r => r.CardId).Distinct().ToList();
        var processed = await db.ReviewLogs.AsNoTracking().Where(r => ids.Contains(r.Id)).ToDictionaryAsync(r => r.Id, ct);
        // A card of a deck the user doesn't see is rejected like a deleted one.
        var existingCards = (await db.Cards.VisibleTo(userId).Where(c => cardIds.Contains(c.Id)).Select(c => c.Id).ToListAsync(ct)).ToHashSet();
        var states = await db.CardStates.Where(s => s.UserId == userId && cardIds.Contains(s.CardId)).ToDictionaryAsync(s => s.CardId, ct);
        var days = new Dictionary<DateOnly, DailyActivity>();

        var results = new List<ReviewResultResponse>(reviews.Count);
        var events = new List<EventResponse>();
        for (var i = 0; i < reviews.Count; i++)
        {
            var item = reviews[i];
            if (processed.TryGetValue(item.Id, out var log))
            {
                results.Add(log.UserId == userId
                    ? new ReviewResultResponse(item.Id, "duplicate", log.PointsAwarded, log.Multiplier)
                    : new ReviewResultResponse(item.Id, "rejected", Code: "idConflict"));
                continue;
            }

            if (!existingCards.Contains(item.CardId))
            {
                results.Add(new ReviewResultResponse(item.Id, "rejected", Code: "cardNotFound"));
                continue;
            }

            var at = receivedAt.AddTicks(i * 10L);
            var day = PragueCalendar.DayOf(at);
            var rating = item.Rating == ReviewRating.Know ? Rating.Good : Rating.Again;

            // Points use the streak just before this answer counts (docs/spec.md §6.1).
            var multiplier = Points.Multiplier(Streaks.Displayed(user.CurrentStreak, user.LastGoalMetDate, day));
            var points = Points.For(rating, multiplier);

            var stateBefore = ApplyFsrs(states, userId, item.CardId, rating, at, out var elapsedDays, out var scheduledDays);
            db.ReviewLogs.Add(new ReviewLog
            {
                Id = item.Id,
                UserId = userId,
                CardId = item.CardId,
                Rating = rating,
                StateBefore = stateBefore,
                ReviewedAt = at,
                Day = day,
                Multiplier = multiplier,
                PointsAwarded = points,
                ElapsedDays = elapsedDays,
                ScheduledDays = scheduledDays,
            });
            db.PointsEntries.Add(new PointsEntry
            {
                UserId = userId,
                Amount = points,
                Reason = PointsReason.Review,
                ReferenceId = item.Id.ToString(),
                CreatedAt = at,
            });

            var activity = await DayAsync(days, user, day, ct);
            activity.GradedCount++;
            activity.CorrectCount += rating == Rating.Good ? 1 : 0;
            activity.Points += points;
            if (!activity.GoalMet && activity.GradedCount >= activity.Goal)
            {
                progress.MarkGoalMet(user, activity, at, events);
            }

            results.Add(new ReviewResultResponse(item.Id, "applied", points, multiplier));
        }

        user.LastActiveAt = receivedAt;
        await progress.CheckWishlistAsync(userId, receivedAt, events, ct);
        await db.SaveChangesAsync(ct);
        await transaction.CommitAsync(ct);

        var summary = await progress.SummaryAsync(userId, ct);
        return new ReviewBatchResponse(results, summary, Progress.PointsFor(summary), events);
    }

    private static AppError? Validate(IReadOnlyList<ReviewItemRequest> reviews)
    {
        var v = new Validator();
        if (reviews.Count is 0 or > MaxBatch)
        {
            v.Add("reviews", $"Pošli 1 až {MaxBatch} odpovědí najednou.");
        }

        if (reviews.Any(r => r.Id == Guid.Empty))
        {
            v.Add("reviews", "Každá odpověď potřebuje id (UUID).");
        }

        if (reviews.Select(r => r.Id).Distinct().Count() != reviews.Count)
        {
            v.Add("reviews", "Stejné id je v dávce víckrát.");
        }

        if (reviews.Any(r => !Enum.IsDefined(r.Rating)))
        {
            v.Add("reviews", "Hodnocení musí být know nebo dontKnow.");
        }

        return v.IsValid ? null : v.ToError();
    }

    /// <summary>Runs FSRS on the user's card state (creating it for a new card). Returns the state before.</summary>
    private FsrsState? ApplyFsrs(
        Dictionary<int, CardState> states, int userId, int cardId, Rating rating, DateTime at,
        out int elapsedDays, out int scheduledDays)
    {
        var fsrsRating = rating == Rating.Good ? FsrsRating.Good : FsrsRating.Again;
        if (!states.TryGetValue(cardId, out var state))
        {
            var created = FsrsScheduler.Default.Review(FsrsCard.New(at), fsrsRating, at);
            state = new CardState { UserId = userId, CardId = cardId, FirstReview = at };
            Copy(created, state);
            state.Reps = 1;
            states[cardId] = state;
            db.CardStates.Add(state);
            elapsedDays = 0;
            scheduledDays = FsrsScheduler.ScheduledDays(created, at);
            return null;
        }

        var before = new FsrsCard(state.State, state.Step, state.Stability, state.Difficulty, state.Due, state.LastReview);
        var after = FsrsScheduler.Default.Review(before, fsrsRating, at);
        var stateBefore = state.State;
        Copy(after, state);
        state.Reps++;
        state.Lapses += stateBefore == FsrsState.Review && rating == Rating.Again ? 1 : 0;
        elapsedDays = FsrsScheduler.ElapsedDays(before, at);
        scheduledDays = FsrsScheduler.ScheduledDays(after, at);
        return stateBefore;
    }

    private static void Copy(FsrsCard card, CardState state)
    {
        state.State = card.State;
        state.Step = (short?)card.Step;
        state.Stability = card.Stability!.Value;
        state.Difficulty = card.Difficulty!.Value;
        state.Due = card.Due;
        state.LastReview = card.LastReview!.Value;
    }

    /// <summary>The day's activity row; created with the current daily goal on the first answer (docs/spec.md §5.2).</summary>
    private async Task<DailyActivity> DayAsync(Dictionary<DateOnly, DailyActivity> cache, User user, DateOnly day, CancellationToken ct)
    {
        if (cache.TryGetValue(day, out var activity))
        {
            return activity;
        }

        activity = await db.DailyActivities.FirstOrDefaultAsync(a => a.UserId == user.Id && a.Date == day, ct);
        if (activity is null)
        {
            activity = new DailyActivity { UserId = user.Id, Date = day, Goal = user.Settings.DailyGoal };
            db.DailyActivities.Add(activity);
        }

        cache[day] = activity;
        return activity;
    }
}
