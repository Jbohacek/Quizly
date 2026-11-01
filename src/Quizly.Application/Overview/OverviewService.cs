using Microsoft.EntityFrameworkCore;
using Quizly.Application.Abstractions;
using Quizly.Application.Common;
using Quizly.Application.Shop;
using Quizly.Domain;
using Quizly.Domain.Gamification;

namespace Quizly.Application.Overview;

/// <summary>Tiles on Přehled (docs/spec.md §11).</summary>
public sealed record OverviewTilesResponse(int PendingClaims, int ActiveUsersToday, int ReviewsToday, int? SuccessToday, int PointsLast7Days);

/// <summary>One row of "Uživatelé dnes".</summary>
public sealed record UserTodayResponse(
    int Id,
    string Username,
    string DisplayName,
    int Streak,
    decimal Multiplier,
    int Graded,
    int Goal,
    bool GoalMet,
    int PointsToday,
    int Balance,
    DateTimeOffset? LastActiveAt);

/// <summary>Everything on Přehled.</summary>
public sealed record OverviewResponse(
    DateOnly Today,
    OverviewTilesResponse Tiles,
    IReadOnlyList<AdminClaimResponse> PendingClaims,
    IReadOnlyList<UserTodayResponse> UsersToday);

public interface IOverviewService
{
    Task<OverviewResponse> GetAsync(CancellationToken ct);
}

internal sealed class OverviewService(IAppDbContext db, IClaimAdminService claims, TimeProvider time) : IOverviewService
{
    public async Task<OverviewResponse> GetAsync(CancellationToken ct)
    {
        var today = PragueCalendar.Today(time);
        var weekStart = PragueCalendar.StartOfDayUtc(today.AddDays(-6));
        var todayRows = await db.DailyActivities.AsNoTracking().Where(a => a.Date == today).ToListAsync(ct);
        var graded = todayRows.Sum(a => a.GradedCount);
        var points7 = await db.PointsEntries
            .Where(p => p.CreatedAt >= weekStart && (p.Reason == PointsReason.Review || p.Reason == PointsReason.Milestone))
            .SumAsync(p => (int?)p.Amount, ct) ?? 0;
        var pending = await claims.ListAsync(ClaimStatus.Pending, ct);

        var users = await db.Users.AsNoTracking()
            .Where(u => u.IsActive)
            .OrderBy(u => u.DisplayName).ThenBy(u => u.Username)
            .Select(u => new
            {
                User = u,
                u.Settings.DailyGoal,
                Balance = db.PointsEntries.Where(p => p.UserId == u.Id).Sum(p => (int?)p.Amount) ?? 0,
            })
            .ToListAsync(ct);
        var byUser = todayRows.ToDictionary(a => a.UserId);

        var usersToday = users.Select(x =>
        {
            var streak = Streaks.Displayed(x.User.CurrentStreak, x.User.LastGoalMetDate, today);
            var activity = byUser.GetValueOrDefault(x.User.Id);
            return new UserTodayResponse(
                x.User.Id,
                x.User.Username,
                x.User.DisplayName,
                streak,
                Points.Multiplier(streak),
                activity?.GradedCount ?? 0,
                activity?.Goal ?? x.DailyGoal,
                activity?.GoalMet ?? false,
                activity?.Points ?? 0,
                x.Balance,
                x.User.LastActiveAt.ToUtcOffset());
        }).ToList();

        var tiles = new OverviewTilesResponse(
            pending.Count,
            todayRows.Count(a => a.GradedCount > 0),
            graded,
            graded == 0 ? null : todayRows.Sum(a => a.CorrectCount) * 100 / graded,
            points7);
        return new OverviewResponse(today, tiles, pending, usersToday);
    }
}
