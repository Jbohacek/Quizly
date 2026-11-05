using Microsoft.EntityFrameworkCore;
using Quizly.Application.Abstractions;
using Quizly.Application.Common;
using Quizly.Domain;
using Quizly.Domain.Gamification;

namespace Quizly.Application.Leaderboards;

/// <summary>Žebříček (#34, docs/spec.md §10.1): active users who haven't hidden themselves, ranked by points or streak.</summary>
internal sealed class LeaderboardService(IAppDbContext db, TimeProvider time) : ILeaderboardService
{
    public const string Week = "week";
    public const string AllTime = "allTime";
    public const string Points = "points";
    public const string Streak = "streak";

    public async Task<Result<LeaderboardResponse>> GetLeaderboardAsync(int userId, string? period, string? metric, CancellationToken ct)
    {
        var v = new Validator();
        var parsedMetric = (metric ?? Points) switch
        {
            Points => LeaderboardMetric.Points,
            Streak => LeaderboardMetric.Streak,
            _ => (LeaderboardMetric?)null,
        };
        if (parsedMetric is null)
        {
            v.Add("metric", "Žebříček umí jen body (points) nebo sérii (streak).");
        }

        if ((period ?? Week) is not (Week or AllTime))
        {
            v.Add("period", "Žebříček umí jen tento týden (week) nebo celkově (allTime).");
        }

        if (!v.IsValid)
        {
            return v.ToError();
        }

        // The current streak doesn't depend on a period, so a streak ranking always uses all-time numbers.
        var allTime = parsedMetric == LeaderboardMetric.Streak || period == AllTime;
        var today = PragueCalendar.Today(time);

        var users = await db.Users.AsNoTracking()
            .Where(u => u.IsActive && u.Settings.ShowInLeaderboard)
            .Select(u => new { u.Id, u.Username, u.DisplayName, u.CurrentStreak, u.LastGoalMetDate })
            .ToListAsync(ct);

        var activities = db.DailyActivities.AsNoTracking();
        if (!allTime)
        {
            var monday = LeaderboardRanking.WeekStart(today);
            activities = activities.Where(a => a.Date >= monday && a.Date <= today);
        }

        var totals = await activities
            .GroupBy(a => a.UserId)
            .Select(g => new { UserId = g.Key, Points = g.Sum(a => a.Points), Cards = g.Sum(a => a.GradedCount) })
            .ToDictionaryAsync(t => t.UserId, ct);

        var rows = users.Select(u =>
        {
            totals.TryGetValue(u.Id, out var total);
            return new LeaderboardRow(
                u.Id,
                string.IsNullOrWhiteSpace(u.DisplayName) ? u.Username : u.DisplayName,
                total?.Points ?? 0,
                Streaks.Displayed(u.CurrentStreak, u.LastGoalMetDate, today),
                total?.Cards ?? 0);
        });

        var entries = LeaderboardRanking.Rank(rows, parsedMetric!.Value)
            .Select(x => new LeaderboardEntryResponse(x.Rank, x.Row.UserId, x.Row.DisplayName, x.Row.Points, x.Row.CurrentStreak, x.Row.CardsStudied))
            .ToList();

        return new LeaderboardResponse(
            allTime ? AllTime : Week,
            parsedMetric == LeaderboardMetric.Streak ? Streak : Points,
            entries,
            entries.FirstOrDefault(e => e.UserId == userId)?.Rank);
    }
}
