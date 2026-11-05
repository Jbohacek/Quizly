namespace Quizly.Domain.Gamification;

/// <summary>What Žebříček ranks by (#34).</summary>
public enum LeaderboardMetric
{
    Points,
    Streak,
}

/// <summary>One user's numbers for Žebříček, before ranking.</summary>
public sealed record LeaderboardRow(int UserId, string DisplayName, int Points, int CurrentStreak, int CardsStudied);

/// <summary>Pure Žebříček rules (#34, docs/spec.md §10.1).</summary>
public static class LeaderboardRanking
{
    /// <summary>Monday of the (Prague) week that contains <paramref name="day"/>.</summary>
    public static DateOnly WeekStart(DateOnly day) => day.AddDays(-(((int)day.DayOfWeek + 6) % 7));

    /// <summary>
    /// Orders the rows best first and ranks them. Rows with the same value of <paramref name="metric"/> share a rank
    /// (1, 1, 3); the other numbers and then the name only decide the order inside a tie.
    /// </summary>
    public static IReadOnlyList<(int Rank, LeaderboardRow Row)> Rank(IEnumerable<LeaderboardRow> rows, LeaderboardMetric metric)
    {
        Func<LeaderboardRow, int> primary = metric == LeaderboardMetric.Streak ? r => r.CurrentStreak : r => r.Points;
        Func<LeaderboardRow, int> secondary = metric == LeaderboardMetric.Streak ? r => r.Points : r => r.CurrentStreak;

        var ordered = rows
            .OrderByDescending(primary)
            .ThenByDescending(secondary)
            .ThenByDescending(r => r.CardsStudied)
            .ThenBy(r => r.DisplayName, StringComparer.OrdinalIgnoreCase)
            .ThenBy(r => r.UserId)
            .ToList();

        var ranked = new List<(int, LeaderboardRow)>(ordered.Count);
        var rank = 0;
        for (var i = 0; i < ordered.Count; i++)
        {
            if (i == 0 || primary(ordered[i]) != primary(ordered[i - 1]))
            {
                rank = i + 1;
            }

            ranked.Add((rank, ordered[i]));
        }

        return ranked;
    }
}
