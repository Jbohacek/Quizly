using System.Net;
using System.Net.Http.Json;
using System.Text.Json.Nodes;
using Quizly.Application.Leaderboards;
using Quizly.Tests.Infrastructure;
using static Quizly.Tests.Api.StudyTests;

namespace Quizly.Tests.Api;

public sealed class LeaderboardTests(QuizlyFactory factory) : IClassFixture<QuizlyFactory>
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task Leaderboard_requires_authorization()
    {
        var client = factory.CreateClient();
        var response = await client.GetAsync("/api/leaderboard", Ct);
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Leaderboard_returns_rankings_and_identifies_current_user()
    {
        factory.AdvanceToPrague(new TimeOnly(11, 0));
        var user1 = await factory.CreateUserAsync(username: "lead_u1_" + Guid.NewGuid().ToString("N")[..6], dailyGoal: 10);
        var user2 = await factory.CreateUserAsync(username: "lead_u2_" + Guid.NewGuid().ToString("N")[..6], dailyGoal: 10);
        var (_, cards) = await factory.CreateDeckAsync("L" + Guid.NewGuid().ToString("N")[..6], 5);

        using var app1 = await factory.AppClientAsync(user1);
        using var app2 = await factory.AppClientAsync(user2);

        // User1 does 2 reviews
        await ReviewAsync(app1, (cards[0], "know"), (cards[1], "know"));

        // User2 does 1 review
        await ReviewAsync(app2, (cards[0], "know"));

        // User1 queries leaderboard (default period=week, metric=points)
        var res1 = await (await app1.GetAsync("/api/leaderboard", Ct)).ReadAsync<LeaderboardResponse>();
        Assert.Equal("week", res1.Period);
        Assert.Equal("points", res1.Metric);
        Assert.NotNull(res1.CurrentUserRank);
        Assert.Contains(res1.Entries, e => e.UserId == user1.Id);
        Assert.Contains(res1.Entries, e => e.UserId == user2.Id);

        var entry1 = res1.Entries.Single(e => e.UserId == user1.Id);
        var entry2 = res1.Entries.Single(e => e.UserId == user2.Id);

        Assert.True(entry1.Points > entry2.Points);
        Assert.True(entry1.Rank < entry2.Rank);
        Assert.Equal(entry1.Rank, res1.CurrentUserRank);

        // User2 queries leaderboard (allTime period, streak metric)
        var res2 = await (await app2.GetAsync("/api/leaderboard?period=allTime&metric=streak", Ct)).ReadAsync<LeaderboardResponse>();
        Assert.Equal("allTime", res2.Period);
        Assert.Equal("streak", res2.Metric);
        Assert.NotNull(res2.CurrentUserRank);

        var entry2InRes2 = res2.Entries.Single(e => e.UserId == user2.Id);
        Assert.Equal(entry2InRes2.Rank, res2.CurrentUserRank);
    }
}
