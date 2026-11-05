namespace Quizly.Application.Leaderboards;

public sealed record LeaderboardEntryResponse(
    int Rank,
    int UserId,
    string DisplayName,
    int Points,
    int CurrentStreak,
    int CardsStudied
);

public sealed record LeaderboardResponse(
    string Period,
    string Metric,
    IReadOnlyList<LeaderboardEntryResponse> Entries,
    int? CurrentUserRank
);
