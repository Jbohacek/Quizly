namespace Quizly.Domain;

/// <summary>
/// "Problémové" cards (#27, docs/spec.md §3.6): cards a user keeps answering Nevím lately.
/// Only the user's last <see cref="RecentWindow"/> answers to the card count, so a card stops being problematic
/// once it's learned, and a mastered card never is.
/// </summary>
public static class ProblemCards
{
    /// <summary>How many of the newest answers to a card are looked at.</summary>
    public const int RecentWindow = 10;

    /// <summary>At least this many Nevím among the recent answers.</summary>
    public const int MinimumDontKnow = 2;

    /// <summary>And at least this share of them (in %) is Nevím.</summary>
    public const int MinimumDontKnowPercent = 30;

    /// <summary>
    /// Whether a card is problematic: not mastered, and at least 2 of its recent answers (≥ 30 %) are Nevím.
    /// </summary>
    /// <param name="recentDontKnow">Nevím among the last <see cref="RecentWindow"/> answers.</param>
    /// <param name="recentAnswers">Graded answers among them (at most <see cref="RecentWindow"/>).</param>
    /// <param name="mastered">The card is Zvládnuto (spec §3.5).</param>
    public static bool IsProblematic(int recentDontKnow, int recentAnswers, bool mastered) =>
        !mastered
        && recentDontKnow >= MinimumDontKnow
        && recentDontKnow * 100 >= recentAnswers * MinimumDontKnowPercent;
}
