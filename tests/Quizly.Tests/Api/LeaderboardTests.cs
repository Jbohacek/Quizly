using System.Net;
using System.Net.Http.Json;
using Quizly.Application.Leaderboards;
using Quizly.Tests.Infrastructure;
using static Quizly.Tests.Api.StudyTests;

namespace Quizly.Tests.Api;

/// <summary>Žebříček (#34, docs/api.md GET /leaderboard).</summary>
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
    public async Task This_week_starts_on_Monday_and_all_time_counts_everything()
    {
        var (_, cards) = await factory.CreateDeckAsync("L" + Guid.NewGuid().ToString("N")[..6], 3);
        var early = await factory.CreateUserAsync(dailyGoal: 10);
        var late = await factory.CreateUserAsync(dailyGoal: 10);

        // A Sunday: "early" studies two cards in the previous week.
        AdvanceToWeekday(DayOfWeek.Sunday);
        using (var app = await factory.AppClientAsync(early))
        {
            await ReviewAsync(app, (cards[0], "know"), (cards[1], "know"));
        }

        // The next day is Monday, a new week: "late" studies one card.
        factory.AdvanceToPrague(new TimeOnly(11, 0));
        using var lateApp = await factory.AppClientAsync(late);
        await ReviewAsync(lateApp, (cards[0], "know"));

        var week = await GetAsync(lateApp, "/api/leaderboard");
        Assert.Equal(("week", "points"), (week.Period, week.Metric));
        var (earlyWeek, lateWeek) = (Entry(week, early.Id), Entry(week, late.Id));
        Assert.Equal((0, 0), (earlyWeek.Points, earlyWeek.CardsStudied));
        Assert.Equal((10, 1), (lateWeek.Points, lateWeek.CardsStudied));
        Assert.True(lateWeek.Rank < earlyWeek.Rank);
        Assert.Equal(lateWeek.Rank, week.CurrentUserRank);

        var allTime = await GetAsync(lateApp, "/api/leaderboard?period=allTime");
        var (earlyAll, lateAll) = (Entry(allTime, early.Id), Entry(allTime, late.Id));
        Assert.Equal((20, 2), (earlyAll.Points, earlyAll.CardsStudied));
        Assert.True(earlyAll.Rank < lateAll.Rank);
    }

    [Fact]
    public async Task Equal_streaks_share_a_rank_and_the_period_does_not_apply()
    {
        factory.AdvanceToPrague(new TimeOnly(11, 0));
        var (_, cards) = await factory.CreateDeckAsync("L" + Guid.NewGuid().ToString("N")[..6], 2);
        var first = await factory.CreateUserAsync(dailyGoal: 1);
        var second = await factory.CreateUserAsync(dailyGoal: 1);
        using var firstApp = await factory.AppClientAsync(first);
        using var secondApp = await factory.AppClientAsync(second);
        await ReviewAsync(firstApp, (cards[0], "know"), (cards[1], "know"));
        await ReviewAsync(secondApp, (cards[0], "know"));

        var streak = await GetAsync(firstApp, "/api/leaderboard?period=week&metric=streak");

        // A streak isn't counted per week, so the numbers are all-time.
        Assert.Equal(("allTime", "streak"), (streak.Period, streak.Metric));
        var (a, b) = (Entry(streak, first.Id), Entry(streak, second.Id));
        Assert.Equal((1, 1), (a.CurrentStreak, b.CurrentStreak));
        Assert.Equal(a.Rank, b.Rank);
        // Inside the tie the one with more points comes first.
        Assert.True(streak.Entries.ToList().FindIndex(e => e.UserId == first.Id) < streak.Entries.ToList().FindIndex(e => e.UserId == second.Id));
    }

    [Fact]
    public async Task A_user_who_hides_themselves_is_not_in_the_leaderboard()
    {
        var hidden = await factory.CreateUserAsync();
        var other = await factory.CreateUserAsync();
        using var hiddenApp = await factory.AppClientAsync(hidden);
        using var otherApp = await factory.AppClientAsync(other);

        var settings = await (await hiddenApp.GetAsync("/api/me/settings", Ct)).ReadNodeAsync();
        Assert.True((bool)settings["showInLeaderboard"]!);
        settings["showInLeaderboard"] = false;
        Assert.Equal(HttpStatusCode.OK, (await hiddenApp.PutAsJsonAsync("/api/me/settings", settings, Ct)).StatusCode);

        Assert.DoesNotContain((await GetAsync(otherApp, "/api/leaderboard")).Entries, e => e.UserId == hidden.Id);
        var own = await GetAsync(hiddenApp, "/api/leaderboard");
        Assert.DoesNotContain(own.Entries, e => e.UserId == hidden.Id);
        Assert.Null(own.CurrentUserRank);

        // An older app that doesn't know the field keeps the user hidden when it saves its settings.
        settings.AsObject().Remove("showInLeaderboard");
        await hiddenApp.PutAsJsonAsync("/api/me/settings", settings, Ct);
        Assert.False((bool)(await (await hiddenApp.GetAsync("/api/me/settings", Ct)).ReadNodeAsync())["showInLeaderboard"]!);

        settings["showInLeaderboard"] = true;
        await hiddenApp.PutAsJsonAsync("/api/me/settings", settings, Ct);
        Assert.Contains((await GetAsync(otherApp, "/api/leaderboard")).Entries, e => e.UserId == hidden.Id);
    }

    [Theory]
    [InlineData("period=month", "period")]
    [InlineData("metric=cards", "metric")]
    public async Task Unknown_period_or_metric_is_rejected(string query, string field)
    {
        using var app = await factory.AppClientAsync(await factory.CreateUserAsync());

        var response = await app.GetAsync($"/api/leaderboard?{query}", Ct);

        Assert.NotNull((await response.AssertProblemAsync(HttpStatusCode.BadRequest, "validation"))["errors"]?[field]);
    }

    private static async Task<LeaderboardResponse> GetAsync(HttpClient app, string url) =>
        await (await app.GetAsync(url, Ct)).ReadAsync<LeaderboardResponse>();

    private static LeaderboardEntryResponse Entry(LeaderboardResponse board, int userId) =>
        board.Entries.Single(e => e.UserId == userId);

    private void AdvanceToWeekday(DayOfWeek day)
    {
        do
        {
            factory.AdvanceToPrague(new TimeOnly(11, 0));
        }
        while (factory.PragueToday.DayOfWeek != day);
    }
}
