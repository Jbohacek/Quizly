using Microsoft.EntityFrameworkCore;
using Quizly.Application.Abstractions;
using Quizly.Application.Common;
using Quizly.Domain;
using Quizly.Domain.Gamification;

namespace Quizly.Application.Learning;

/// <summary>
/// Shared progress logic for reviews and settings: goal met → streak → milestone,
/// the wishlist check, and the summary (docs/spec.md §5–6).
/// </summary>
internal sealed class Progress(IAppDbContext db, TimeProvider time)
{
    /// <summary>Locks the user row for the rest of the transaction, so two requests of one user never interleave.</summary>
    public async Task<User> LockUserAsync(int userId, CancellationToken ct)
    {
        var user = await db.Users.FromSql($"SELECT * FROM users WHERE id = {userId} FOR UPDATE").FirstAsync(ct);
        await db.Entry(user).Reference(u => u.Settings).LoadAsync(ct);
        return user;
    }

    /// <summary>Marks the day met, extends the streak and books a milestone bonus. Call when graded ≥ goal for the first time.</summary>
    public void MarkGoalMet(User user, DailyActivity day, DateTime now, List<EventResponse> events)
    {
        day.GoalMet = true;
        day.GoalMetAt = now;
        events.Add(EventResponse.GoalMet());

        var streak = Streaks.MarkDayMet(user, day.Date);
        if (Milestones.BonusFor(streak) is int bonus)
        {
            db.PointsEntries.Add(new PointsEntry
            {
                UserId = user.Id,
                Amount = bonus,
                Reason = PointsReason.Milestone,
                ReferenceId = Milestones.ReferenceId(streak, day.Date),
                CreatedAt = now,
            });
            day.Points += bonus;
            events.Add(EventResponse.Milestone(streak, bonus));
        }
    }

    /// <summary>Wishlist items whose price the balance reached for the first time (docs/spec.md §6.4). Saves first.</summary>
    public async Task CheckWishlistAsync(int userId, DateTime now, List<EventResponse> events, CancellationToken ct)
    {
        await db.SaveChangesAsync(ct);
        var balance = await BalanceAsync(userId, ct);
        var reached = await db.WishlistEntries
            .Where(w => w.UserId == userId && w.NotifiedAt == null)
            .Join(db.ShopItems, w => w.ShopItemId, i => i.Id, (w, i) => new { Entry = w, Item = i })
            .Where(x => x.Item.IsActive && x.Item.Price <= balance)
            .OrderBy(x => x.Item.Price)
            .ToListAsync(ct);
        foreach (var x in reached)
        {
            x.Entry.NotifiedAt = now;
            events.Add(EventResponse.WishlistReached(x.Item.Id, x.Item.Name, x.Item.Price));
        }
    }

    public async Task<int> BalanceAsync(int userId, CancellationToken ct) =>
        await db.PointsEntries.Where(p => p.UserId == userId).SumAsync(p => (int?)p.Amount, ct) ?? 0;

    public async Task<SummaryResponse> SummaryAsync(int userId, CancellationToken ct)
    {
        var user = await db.Users.Include(u => u.Settings).AsNoTracking().FirstAsync(u => u.Id == userId, ct);
        var today = PragueCalendar.Today(time);
        var activity = await db.DailyActivities.AsNoTracking().FirstOrDefaultAsync(a => a.UserId == userId && a.Date == today, ct);
        var streak = Streaks.Displayed(user.CurrentStreak, user.LastGoalMetDate, today);
        var next = Points.NextMultiplier(streak);
        var broken = Streaks.Broken(user.CurrentStreak, user.LastGoalMetDate, today);

        return new SummaryResponse(
            await BalanceAsync(userId, ct),
            streak,
            user.BestStreak,
            Points.Multiplier(streak),
            next is var (value, inDays) ? new NextMultiplierResponse(value, inDays) : null,
            new TodayResponse(
                today,
                activity?.GradedCount ?? 0,
                activity?.CorrectCount ?? 0,
                activity?.Goal ?? user.Settings.DailyGoal,
                activity?.GoalMet ?? false,
                activity?.Points ?? 0),
            broken is var (previous, brokenOn) ? new StreakBrokenResponse(previous, brokenOn) : null);
    }

    /// <summary>What Vím/Nevím are worth now.</summary>
    public static PointsValueResponse PointsFor(SummaryResponse summary) =>
        new(Points.For(Rating.Good, summary.Multiplier), Points.For(Rating.Again, summary.Multiplier));

    /// <summary>New cards the user may still start today, across all decks (docs/spec.md §4.1).</summary>
    public async Task<int> NewAllowanceLeftAsync(int userId, int newCardsPerDay, DateOnly day, CancellationToken ct)
    {
        var dayStart = PragueCalendar.StartOfDayUtc(day);
        var dayEnd = PragueCalendar.StartOfDayUtc(day.AddDays(1));
        var introduced = await db.CardStates.CountAsync(s => s.UserId == userId && s.FirstReview >= dayStart && s.FirstReview < dayEnd, ct);
        return Math.Max(0, newCardsPerDay - introduced);
    }

    public static AppError NotFoundDeck => Errors.NotFound("Balíček neexistuje.");
}
