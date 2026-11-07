namespace Quizly.Application.Leaderboards;

/// <summary>One row of Žebříček. Users with the same ranked value share a rank.</summary>
public sealed record LeaderboardEntryResponse(
    int Rank,
    int UserId,
    string DisplayName,
    int Points,
    int CurrentStreak,
    int CardsStudied);

/// <summary>
/// Žebříček (docs/api.md). <see cref="CurrentUserRank"/> is null when the caller hides themselves
/// ("Zobrazit mě v žebříčku" off), so they aren't in <see cref="Entries"/> either.
/// </summary>
public sealed record LeaderboardResponse(
    string Period,
    string Metric,
    IReadOnlyList<LeaderboardEntryResponse> Entries,
    int? CurrentUserRank);
