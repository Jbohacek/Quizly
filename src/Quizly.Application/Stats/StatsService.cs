using Microsoft.EntityFrameworkCore;
using Quizly.Application.Abstractions;
using Quizly.Application.Common;
using Quizly.Application.Decks;
using Quizly.Application.Learning;
using Quizly.Domain;
using Quizly.Domain.Gamification;

namespace Quizly.Application.Stats;

/// <summary>Streak, success rate, totals.</summary>
public sealed record StatsTilesResponse(
    int Streak,
    int BestStreak,
    int? SuccessRate30d,
    IReadOnlyList<int?> Sparkline,
    int TotalReviews,
    int TotalPointsEarned);

/// <summary>17 weeks × 7 days, Monday first; levels 0–4, null after today.</summary>
public sealed record HeatmapResponse(DateOnly From, DateOnly To, DateOnly Today, IReadOnlyList<IReadOnlyList<int?>> Weeks);

/// <summary>Graded answers on one day.</summary>
public sealed record DayCountResponse(DateOnly Date, int Graded);

/// <summary>The last 14 days and the current goal for the dashed line.</summary>
public sealed record DailyResponse(int Goal, IReadOnlyList<DayCountResponse> Days);

/// <summary>Success on one weekday (1 = Monday … 7 = Sunday).</summary>
public sealed record WeekdayResponse(int Weekday, int? SuccessRate, int Graded);

/// <summary>The best 2-hour window of the day.</summary>
public sealed record BestTimeResponse(string From, string To, int SuccessRate, int Graded);

/// <summary>Zvládnuto / Učím se / Nové counts.</summary>
public sealed record ProgressCountsResponse(int Mastered, int Learning, int New);

/// <summary>Progress of one deck.</summary>
public sealed record DeckProgressResponse(int DeckId, string Name, int Mastered, int Learning, int New);

/// <summary>Everything on the Statistiky screen (docs/api.md §7, docs/spec.md §10).</summary>
public sealed record StatsResponse(
    int? DeckId,
    StatsTilesResponse Tiles,
    HeatmapResponse Heatmap,
    DailyResponse Daily,
    IReadOnlyList<WeekdayResponse> Weekdays,
    BestTimeResponse? BestTime,
    IReadOnlyList<DeckProgressResponse> DeckProgress,
    ProgressCountsResponse TotalProgress);

public interface IStatsService
{
    Task<Result<StatsResponse>> GetAsync(int userId, int? deckId, CancellationToken ct);
}

internal sealed class StatsService(IAppDbContext db, TimeProvider time) : IStatsService
{
    internal const int HeatmapWeeks = 17;
    internal const int WeekdayMinimum = 10;
    internal const int BestTimeMinimum = 20;

    public async Task<Result<StatsResponse>> GetAsync(int userId, int? deckId, CancellationToken ct)
    {
        if (deckId is not null && !await db.Decks.VisibleTo(userId).AnyAsync(d => d.Id == deckId, ct))
        {
            return Progress.NotFoundDeck;
        }

        var today = PragueCalendar.Today(time);
        var user = await db.Users.Include(u => u.Settings).AsNoTracking().FirstAsync(u => u.Id == userId, ct);
        var currentGoal = user.Settings.DailyGoal;
        var activities = await db.DailyActivities.AsNoTracking().Where(a => a.UserId == userId).ToListAsync(ct);
        var goals = activities.ToDictionary(a => a.Date, a => a.Goal);

        // Per-day counts: from daily activity (survives card deletes), or from review logs for one deck.
        Dictionary<DateOnly, (int Graded, int Correct)> perDay;
        int totalPoints;
        if (deckId is null)
        {
            perDay = activities.ToDictionary(a => a.Date, a => (a.GradedCount, a.CorrectCount));
            totalPoints = await db.PointsEntries
                .Where(p => p.UserId == userId && (p.Reason == PointsReason.Review || p.Reason == PointsReason.Milestone))
                .SumAsync(p => (int?)p.Amount, ct) ?? 0;
        }
        else
        {
            var logs = DeckLogs(userId, deckId.Value);
            perDay = (await logs
                    .GroupBy(r => r.Day)
                    .Select(g => new { Day = g.Key, Graded = g.Count(), Correct = g.Count(r => r.Rating == Rating.Good) })
                    .ToListAsync(ct))
                .ToDictionary(x => x.Day, x => (x.Graded, x.Correct));
            totalPoints = await logs.SumAsync(r => (int?)r.PointsAwarded, ct) ?? 0;
        }

        (int Graded, int Correct) On(DateOnly day) => perDay.TryGetValue(day, out var c) ? c : (0, 0);

        var last30 = Enumerable.Range(0, 30).Select(i => today.AddDays(i - 29)).ToList();
        var graded30 = last30.Sum(d => On(d).Graded);
        var tiles = new StatsTilesResponse(
            Streaks.Displayed(user.CurrentStreak, user.LastGoalMetDate, today),
            user.BestStreak,
            Percent(last30.Sum(d => On(d).Correct), graded30),
            last30.Select(d => Percent(On(d).Correct, On(d).Graded)).ToList(),
            perDay.Values.Sum(c => c.Graded),
            totalPoints);

        // Heatmap: 17 weeks ending with the current week's Sunday.
        var weekEnd = today.AddDays(7 - IsoWeekday(today));
        var from = weekEnd.AddDays(-(HeatmapWeeks * 7) + 1);
        var weeks = Enumerable.Range(0, HeatmapWeeks)
            .Select(w => (IReadOnlyList<int?>)Enumerable.Range(0, 7)
                .Select(d => from.AddDays((w * 7) + d))
                .Select(day => day > today ? (int?)null : HeatmapLevel(On(day).Graded, goals.GetValueOrDefault(day, currentGoal)))
                .ToList())
            .ToList();

        var daily = new DailyResponse(
            currentGoal,
            Enumerable.Range(0, 14).Select(i => today.AddDays(i - 13)).Select(d => new DayCountResponse(d, On(d).Graded)).ToList());

        var last90 = Enumerable.Range(0, 90).Select(i => today.AddDays(i - 89)).ToList();
        var weekdays = Enumerable.Range(1, 7).Select(weekday =>
        {
            var days = last90.Where(d => IsoWeekday(d) == weekday).Select(On).ToList();
            var graded = days.Sum(c => c.Graded);
            return new WeekdayResponse(weekday, graded < WeekdayMinimum ? null : Percent(days.Sum(c => c.Correct), graded), graded);
        }).ToList();

        var since = PragueCalendar.StartOfDayUtc(last90[0]);
        var recent = await (deckId is null ? db.ReviewLogs.Where(r => r.UserId == userId) : DeckLogs(userId, deckId.Value))
            .Where(r => r.ReviewedAt >= since)
            .Select(r => new { r.ReviewedAt, Correct = r.Rating == Rating.Good })
            .ToListAsync(ct);
        var bestTime = BestWindow(recent.Select(r => (r.ReviewedAt, r.Correct)));

        var (deckProgress, total) = await ProgressAsync(userId, deckId, ct);
        return new StatsResponse(deckId, tiles, new HeatmapResponse(from, weekEnd, today, weeks), daily, weekdays, bestTime, deckProgress, total);
    }

    /// <summary>Level from graded ÷ goal: 0 none · 1 below · 2 up to 1.25× · 3 up to 1.5× · 4 from 1.5× (docs/spec.md §10).</summary>
    internal static int HeatmapLevel(int graded, int goal)
    {
        if (graded == 0)
        {
            return 0;
        }

        var ratio = (decimal)graded / Math.Max(goal, 1);
        return ratio switch
        {
            < 1m => 1,
            < 1.25m => 2,
            < 1.5m => 3,
            _ => 4,
        };
    }

    /// <summary>Fixed 2-hour windows (Prague hour) with at least 20 answers; best success, ties go to more answers.</summary>
    internal static BestTimeResponse? BestWindow(IEnumerable<(DateTime ReviewedAtUtc, bool Correct)> reviews)
    {
        var windows = reviews
            .GroupBy(r => TimeZoneInfo.ConvertTimeFromUtc(r.ReviewedAtUtc, PragueCalendar.Zone).Hour / 2)
            .Select(g => new { Window = g.Key, Graded = g.Count(), Correct = g.Count(r => r.Correct) })
            .Where(w => w.Graded >= BestTimeMinimum)
            .Select(w => new { w.Window, w.Graded, Rate = Percent(w.Correct, w.Graded)!.Value })
            .OrderByDescending(w => w.Rate).ThenByDescending(w => w.Graded).ThenBy(w => w.Window)
            .FirstOrDefault();
        return windows is null
            ? null
            : new BestTimeResponse($"{windows.Window * 2:00}:00", $"{(windows.Window * 2) + 2:00}:00", windows.Rate, windows.Graded);
    }

    internal static int IsoWeekday(DateOnly day) => day.DayOfWeek == DayOfWeek.Sunday ? 7 : (int)day.DayOfWeek;

    private static int? Percent(int part, int whole) => whole == 0 ? null : part * 100 / whole;

    private IQueryable<ReviewLog> DeckLogs(int userId, int deckId) =>
        db.ReviewLogs.Where(r => r.UserId == userId && db.Cards.Any(c => c.Id == r.CardId && c.DeckId == deckId));

    private async Task<(IReadOnlyList<DeckProgressResponse> Decks, ProgressCountsResponse Total)> ProgressAsync(
        int userId, int? deckId, CancellationToken ct)
    {
        var rows = await db.Decks.VisibleTo(userId)
            .Where(d => deckId == null || d.Id == deckId)
            .OrderBy(d => d.SortOrder).ThenBy(d => d.Id)
            .Select(d => new
            {
                d.Id,
                d.Name,
                Total = d.Cards.Count,
                Mastered = db.CardStates.Count(s => s.UserId == userId && s.State == FsrsState.Review
                    && s.Stability >= StudyService.MasteredStability && d.Cards.Any(c => c.Id == s.CardId)),
                Started = db.CardStates.Count(s => s.UserId == userId && d.Cards.Any(c => c.Id == s.CardId)),
            })
            .ToListAsync(ct);

        var decks = rows.Select(r => new DeckProgressResponse(r.Id, r.Name, r.Mastered, r.Started - r.Mastered, r.Total - r.Started)).ToList();
        var total = new ProgressCountsResponse(decks.Sum(d => d.Mastered), decks.Sum(d => d.Learning), decks.Sum(d => d.New));
        return (decks, total);
    }
}
