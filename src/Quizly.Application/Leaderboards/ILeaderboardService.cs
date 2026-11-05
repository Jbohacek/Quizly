using Quizly.Application.Common;

namespace Quizly.Application.Leaderboards;

public interface ILeaderboardService
{
    /// <summary>Žebříček. <paramref name="period"/>: <c>week</c> (default) or <c>allTime</c>; <paramref name="metric"/>: <c>points</c> (default) or <c>streak</c>.</summary>
    Task<Result<LeaderboardResponse>> GetLeaderboardAsync(int userId, string? period, string? metric, CancellationToken ct);
}
