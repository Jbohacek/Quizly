using Microsoft.EntityFrameworkCore;
using Quizly.Application.Abstractions;
using Quizly.Domain;
using Quizly.Domain.Gamification;

namespace Quizly.Application.Leaderboards;

internal sealed class LeaderboardService(IAppDbContext db, TimeProvider time) : ILeaderboardService
{
    public async Task<LeaderboardResponse> GetLeaderboardAsync(
        int userId,
        string? period,
        string? metric,
        CancellationToken ct)
    {
        var normalizedPeriod = string.Equals(period, "alltime", StringComparison.OrdinalIgnoreCase) ? "allTime" : "week";
        var normalizedMetric = string.Equals(metric, "streak", StringComparison.OrdinalIgnoreCase) ? "streak" : "points";

        var today = PragueCalendar.Today(time);

        var users = await db.Users.AsNoTracking()
            .Where(u => u.IsActive)
            .ToListAsync(ct);

        List<DailyActivity> activities;
        if (normalizedPeriod == "week")
        {
            var fromDate = today.AddDays(-6);
            activities = await db.DailyActivities.AsNoTracking()
                .Where(a => a.Date >= fromDate && a.Date <= today)
                .ToListAsync(ct);
        }
        else
        {
            activities = await db.DailyActivities.AsNoTracking().ToListAsync(ct);
        }

        var activityMap = activities
            .GroupBy(a => a.UserId)
            .ToDictionary(
                g => g.Key,
                g => (Points: g.Sum(a => a.Points), CardsStudied: g.Sum(a => a.GradedCount)));

        var rawList = users.Select(u =>
        {
            var (pts, cards) = activityMap.TryGetValue(u.Id, out var act) ? act : (0, 0);
            var streak = Streaks.Displayed(u.CurrentStreak, u.LastGoalMetDate, today);
            return (
                UserId: u.Id,
                DisplayName: string.IsNullOrWhiteSpace(u.DisplayName) ? u.Username : u.DisplayName,
                Points: pts,
                CurrentStreak: streak,
                CardsStudied: cards
            );
        });

        var sorted = (normalizedMetric == "streak"
            ? rawList
                .OrderByDescending(x => x.CurrentStreak)
                .ThenByDescending(x => x.Points)
                .ThenByDescending(x => x.CardsStudied)
                .ThenBy(x => x.DisplayName, StringComparer.OrdinalIgnoreCase)
                .ThenBy(x => x.UserId)
            : rawList
                .OrderByDescending(x => x.Points)
                .ThenByDescending(x => x.CardsStudied)
                .ThenByDescending(x => x.CurrentStreak)
                .ThenBy(x => x.DisplayName, StringComparer.OrdinalIgnoreCase)
                .ThenBy(x => x.UserId))
            .ToList();

        var entries = new List<LeaderboardEntryResponse>(sorted.Count);
        int? currentUserRank = null;

        for (var i = 0; i < sorted.Count; i++)
        {
            var rank = i + 1;
            var item = sorted[i];
            if (item.UserId == userId)
            {
                currentUserRank = rank;
            }

            entries.Add(new LeaderboardEntryResponse(
                Rank: rank,
                UserId: item.UserId,
                DisplayName: item.DisplayName,
                Points: item.Points,
                CurrentStreak: item.CurrentStreak,
                CardsStudied: item.CardsStudied
            ));
        }

        return new LeaderboardResponse(normalizedPeriod, normalizedMetric, entries, currentUserRank);
    }
}
