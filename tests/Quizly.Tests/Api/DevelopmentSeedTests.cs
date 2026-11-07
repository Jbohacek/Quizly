using System.Net;
using System.Net.Http.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Quizly.Application.Profile;
using Quizly.Domain;
using Quizly.Infrastructure.Persistence;
using Quizly.Infrastructure.Seed;
using Quizly.Tests.Infrastructure;

namespace Quizly.Tests.Api;

/// <summary>The development data (#44): one seeded database, checked from the outside and against the ledger.</summary>
public sealed class DevelopmentSeedTests(QuizlyFactory factory) : IClassFixture<QuizlyFactory>, IAsyncLifetime
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    public async ValueTask InitializeAsync()
    {
        // The test environment never seeds on its own; the first test class run does it once.
        await using var scope = factory.Services.CreateAsyncScope();
        await scope.ServiceProvider.GetRequiredService<DevelopmentSeeder>().SeedAsync(Ct);
    }

    public ValueTask DisposeAsync() => ValueTask.CompletedTask;

    [Fact]
    public async Task Seeding_twice_changes_nothing()
    {
        await using var scope = factory.Services.CreateAsyncScope();
        var users = await scope.ServiceProvider.GetRequiredService<QuizlyDbContext>().Users.CountAsync(Ct);

        Assert.False(await scope.ServiceProvider.GetRequiredService<DevelopmentSeeder>().SeedAsync(Ct));
        Assert.Equal(users, await scope.ServiceProvider.GetRequiredService<QuizlyDbContext>().Users.CountAsync(Ct));
    }

    [Fact]
    public async Task Anna_has_a_running_streak_and_a_balance_that_matches_the_ledger()
    {
        using var app = await LoginAsync("anna");
        var me = await (await app.GetAsync("/api/me", Ct)).ReadAsync<MeResponse>();

        Assert.Equal(16, me.Summary.Streak);
        Assert.Equal(16, me.Summary.BestStreak);
        Assert.Equal(1.2m, me.Summary.Multiplier);
        Assert.False(me.Summary.Today.GoalMet);
        Assert.Equal(12, me.Summary.Today.Graded);

        var ledger = 0;
        await factory.WithDbAsync(async db =>
            ledger = await db.PointsEntries.Where(p => p.UserId == me.User.Id).SumAsync(p => p.Amount, Ct));
        Assert.Equal(ledger, me.Summary.Balance);
        Assert.True(me.Summary.Balance > 0);
    }

    [Fact]
    public async Task Petrs_streak_has_broken_and_Novacek_starts_from_nothing()
    {
        using var petr = await LoginAsync("petr");
        var petrMe = await (await petr.GetAsync("/api/me", Ct)).ReadAsync<MeResponse>();
        Assert.Equal(0, petrMe.Summary.Streak);
        Assert.Equal(10, petrMe.Summary.BestStreak);
        Assert.NotNull(petrMe.Summary.StreakBroken);

        using var novacek = await LoginAsync("novacek");
        var newMe = await (await novacek.GetAsync("/api/me", Ct)).ReadAsync<MeResponse>();
        Assert.Equal((0, 0, 0), (newMe.Summary.Balance, newMe.Summary.Streak, newMe.Summary.Today.Graded));
    }

    [Fact]
    public async Task A_deactivated_user_cannot_log_in()
    {
        using var client = factory.CreateClient();
        var response = await client.PostAsJsonAsync("/api/auth/login",
            new { username = "stary", password = DevelopmentSeeder.Password }, Ct);
        Assert.False(response.IsSuccessStatusCode);
    }

    [Fact]
    public async Task Decks_follow_access_and_archiving()
    {
        async Task<List<string>> DeckNamesAsync(string username)
        {
            using var app = await LoginAsync(username);
            var decks = await (await app.GetAsync("/api/decks", Ct)).ReadNodeAsync();
            return decks["items"]!.AsArray().Select(d => (string)d!["name"]!).ToList();
        }

        var anna = await DeckNamesAsync("anna");
        var petr = await DeckNamesAsync("petr");
        Assert.Contains(DevelopmentSeeder.RestrictedDeckName, anna);
        Assert.DoesNotContain(DevelopmentSeeder.RestrictedDeckName, petr);
        Assert.DoesNotContain(DevelopmentSeeder.ArchivedDeckName, anna);
        Assert.Contains("C# základy", petr);
    }

    [Fact]
    public async Task The_shop_shows_every_kind_of_claim_and_respects_the_per_user_switch()
    {
        using var anna = await LoginAsync("anna");
        var claims = (await (await anna.GetAsync("/api/claims", Ct)).ReadNodeAsync())["items"]!.AsArray();
        Assert.Equal(["confirmed", "confirmed", "pending"], claims.Select(c => (string)c!["status"]!).Order().ToArray());

        var shop = await (await anna.GetAsync("/api/shop", Ct)).ReadNodeAsync();
        var items = shop["items"]!.AsArray();
        Assert.Contains(items, i => (int)i!["stock"]! == 0);
        Assert.DoesNotContain(items, i => (string)i!["name"]! == "Skrytá odměna");

        using var eva = await LoginAsync("eva");
        await (await eva.GetAsync("/api/shop", Ct)).AssertProblemAsync(HttpStatusCode.Forbidden, "shopDisabled");
    }

    [Fact]
    public async Task Every_day_adds_up_from_the_review_logs_and_milestones()
    {
        await factory.WithDbAsync(async db =>
        {
            var activities = await db.DailyActivities.AsNoTracking().ToListAsync(Ct);
            var logs = (await db.ReviewLogs.AsNoTracking().ToListAsync(Ct))
                .GroupBy(l => (l.UserId, l.Day)).ToDictionary(g => g.Key, g => g.ToList());
            var milestones = (await db.PointsEntries.AsNoTracking().Where(p => p.Reason == PointsReason.Milestone).ToListAsync(Ct))
                .GroupBy(p => (p.UserId, Day: DateOnly.ParseExact(p.ReferenceId[(p.ReferenceId.IndexOf(':') + 1)..], "yyyy-MM-dd")))
                .ToDictionary(g => g.Key, g => g.Sum(p => p.Amount));

            Assert.NotEmpty(activities);
            foreach (var a in activities)
            {
                var day = logs[(a.UserId, a.Date)];
                Assert.Equal(day.Count, a.GradedCount);
                Assert.Equal(day.Count(l => l.Rating != Rating.Again), a.CorrectCount);
                Assert.Equal(day.Sum(l => l.PointsAwarded) + milestones.GetValueOrDefault((a.UserId, a.Date)), a.Points);
                Assert.Equal(a.GradedCount >= a.Goal, a.GoalMet);
            }

            Assert.All(logs.Values.SelectMany(l => l), l => Assert.Equal(l.Day, PragueCalendar.DayOf(l.ReviewedAt)));
        });
    }

    [Fact]
    public async Task Stats_and_a_study_session_work_on_the_seeded_history()
    {
        using var anna = await LoginAsync("anna");
        (await anna.GetAsync("/api/stats", Ct)).EnsureSuccessStatusCode();
        (await anna.GetAsync("/api/leaderboard", Ct)).EnsureSuccessStatusCode();

        using var novacek = await LoginAsync("novacek");
        var session = await (await novacek.GetAsync("/api/session", Ct)).ReadNodeAsync();
        Assert.Equal(5, session["cards"]!.AsArray().Count);
    }

    private async Task<HttpClient> LoginAsync(string username) =>
        factory.AppClient((await factory.LoginAsync(username, DevelopmentSeeder.Password)).AccessToken);
}
