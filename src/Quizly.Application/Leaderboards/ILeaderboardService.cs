namespace Quizly.Application.Leaderboards;

public interface ILeaderboardService
{
    Task<LeaderboardResponse> GetLeaderboardAsync(int userId, string? period, string? metric, CancellationToken ct);
}
