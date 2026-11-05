using Quizly.Application.Leaderboards;

namespace Quizly.Tests.Unit;

public sealed class LeaderboardUnitTests
{
    [Fact]
    public void LeaderboardResponse_holds_correct_properties()
    {
        var entries = new List<LeaderboardEntryResponse>
        {
            new(Rank: 1, UserId: 10, DisplayName: "Alice", Points: 150, CurrentStreak: 5, CardsStudied: 30),
            new(Rank: 2, UserId: 20, DisplayName: "Bob", Points: 100, CurrentStreak: 3, CardsStudied: 20),
        };

        var response = new LeaderboardResponse(
            Period: "week",
            Metric: "points",
            Entries: entries,
            CurrentUserRank: 2
        );

        Assert.Equal("week", response.Period);
        Assert.Equal("points", response.Metric);
        Assert.Equal(2, response.Entries.Count);
        Assert.Equal(2, response.CurrentUserRank);

        var first = response.Entries[0];
        Assert.Equal(1, first.Rank);
        Assert.Equal(10, first.UserId);
        Assert.Equal("Alice", first.DisplayName);
        Assert.Equal(150, first.Points);
        Assert.Equal(5, first.CurrentStreak);
        Assert.Equal(30, first.CardsStudied);
    }
}
