namespace Quizly.Domain.Gamification;

/// <summary>Points and multiplier (docs/spec.md §6).</summary>
public static class Points
{
    public const int KnowBase = 10;
    public const int DontKnowBase = 2;
    public const decimal MaxMultiplier = 2.0m;

    /// <summary><c>min(2.0, 1.0 + 0.1 × floor(streak / 7))</c>.</summary>
    public static decimal Multiplier(int streak) =>
        Math.Min(MaxMultiplier, 1.0m + (0.1m * (Math.Max(streak, 0) / 7)));

    /// <summary><c>round(base × multiplier)</c>, halves away from zero.</summary>
    public static int For(Rating rating, decimal multiplier) =>
        (int)Math.Round((rating == Rating.Good ? KnowBase : DontKnowBase) * multiplier, MidpointRounding.AwayFromZero);

    /// <summary>The next multiplier and how many more met days it takes, or null at 2,0×.</summary>
    public static (decimal Value, int InDays)? NextMultiplier(int streak)
    {
        var current = Multiplier(streak);
        return current >= MaxMultiplier ? null : (current + 0.1m, 7 - (Math.Max(streak, 0) % 7));
    }
}

/// <summary>Streak milestones and their bonus points (docs/spec.md §6.3).</summary>
public static class Milestones
{
    public static readonly IReadOnlyDictionary<int, int> Bonuses = new Dictionary<int, int>
    {
        [7] = 50,
        [30] = 200,
        [100] = 1_000,
        [365] = 5_000,
    };

    public static int? BonusFor(int streak) => Bonuses.TryGetValue(streak, out var bonus) ? bonus : null;

    /// <summary>Ledger reference: one milestone per user and day, e.g. <c>7:2026-11-08</c>.</summary>
    public static string ReferenceId(int days, DateOnly day) =>
        $"{days}:{day:yyyy-MM-dd}";
}

/// <summary>Streak rules (docs/spec.md §5.4–5.5). Pure functions over the cached user fields.</summary>
public static class Streaks
{
    /// <summary>The streak to show and to use for the multiplier: alive while the last met day is today or yesterday.</summary>
    public static int Displayed(int currentStreak, DateOnly? lastGoalMetDate, DateOnly today) =>
        lastGoalMetDate is DateOnly last && last >= today.AddDays(-1) ? currentStreak : 0;

    /// <summary>When the cached streak broke: a positive streak whose last met day is before yesterday.</summary>
    public static (int PreviousStreak, DateOnly BrokenOn)? Broken(int currentStreak, DateOnly? lastGoalMetDate, DateOnly today) =>
        currentStreak > 0 && lastGoalMetDate is DateOnly last && last < today.AddDays(-1)
            ? (currentStreak, last.AddDays(2))
            : null;

    /// <summary>Updates the cached streak when <paramref name="today"/> becomes met. Returns the new streak.</summary>
    public static int MarkDayMet(User user, DateOnly today)
    {
        user.CurrentStreak = user.LastGoalMetDate == today.AddDays(-1) ? user.CurrentStreak + 1 : 1;
        user.LastGoalMetDate = today;
        user.BestStreak = Math.Max(user.BestStreak, user.CurrentStreak);
        return user.CurrentStreak;
    }
}
