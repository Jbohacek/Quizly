using System.Globalization;
using Quizly.Domain.Gamification;

namespace Quizly.Tests.Unit;

/// <summary>Žebříček rules (#34, docs/spec.md §10.1).</summary>
public sealed class LeaderboardUnitTests
{
    [Theory]
    [InlineData("2026-11-02", "2026-11-02")] // Monday
    [InlineData("2026-11-05", "2026-11-02")] // Thursday
    [InlineData("2026-11-08", "2026-11-02")] // Sunday
    [InlineData("2026-11-09", "2026-11-09")] // the next Monday
    [InlineData("2027-01-01", "2026-12-28")] // over a year
    public void A_week_starts_on_Monday(string day, string monday) =>
        Assert.Equal(DateOnly.Parse(monday, CultureInfo.InvariantCulture), LeaderboardRanking.WeekStart(DateOnly.Parse(day, CultureInfo.InvariantCulture)));

    [Fact]
    public void Points_rank_with_shared_ranks_for_ties()
    {
        var ranked = LeaderboardRanking.Rank(
        [
            Row(1, "Cyril", points: 50),
            Row(2, "Adam", points: 120),
            Row(3, "Bára", points: 50),
            Row(4, "Dana", points: 0),
        ], LeaderboardMetric.Points);

        Assert.Equal([(1, 2), (2, 3), (2, 1), (4, 4)], ranked.Select(r => (r.Rank, r.Row.UserId)));
    }

    [Fact]
    public void Inside_a_tie_the_other_numbers_then_the_name_decide_the_order()
    {
        var ranked = LeaderboardRanking.Rank(
        [
            Row(1, "Bára", points: 30, streak: 2, cards: 5),
            Row(2, "Adam", points: 30, streak: 2, cards: 5),
            Row(3, "Cyril", points: 30, streak: 2, cards: 9),
            Row(4, "Dana", points: 30, streak: 7, cards: 1),
        ], LeaderboardMetric.Points);

        Assert.All(ranked, r => Assert.Equal(1, r.Rank));
        Assert.Equal([4, 3, 2, 1], ranked.Select(r => r.Row.UserId));
    }

    [Fact]
    public void Streak_ranks_by_the_current_streak_then_points()
    {
        var ranked = LeaderboardRanking.Rank(
        [
            Row(1, "Adam", points: 900, streak: 3),
            Row(2, "Bára", points: 10, streak: 14),
            Row(3, "Cyril", points: 40, streak: 3),
            Row(4, "Dana", points: 0, streak: 0),
        ], LeaderboardMetric.Streak);

        Assert.Equal([(1, 2), (2, 1), (2, 3), (4, 4)], ranked.Select(r => (r.Rank, r.Row.UserId)));
    }

    [Fact]
    public void Everyone_at_zero_shares_the_first_place()
    {
        var ranked = LeaderboardRanking.Rank([Row(1, "Adam"), Row(2, "Bára"), Row(3, "Cyril")], LeaderboardMetric.Points);

        Assert.All(ranked, r => Assert.Equal(1, r.Rank));
    }

    [Fact]
    public void No_users_no_rows() =>
        Assert.Empty(LeaderboardRanking.Rank([], LeaderboardMetric.Streak));

    private static LeaderboardRow Row(int id, string name, int points = 0, int streak = 0, int cards = 0) =>
        new(id, name, points, streak, cards);
}
