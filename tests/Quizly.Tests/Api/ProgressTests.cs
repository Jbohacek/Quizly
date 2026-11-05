using System.Net;
using System.Net.Http.Json;
using System.Text.Json.Nodes;
using Quizly.Tests.Infrastructure;
using static Quizly.Tests.Api.StudyTests;

namespace Quizly.Tests.Api;

/// <summary>Daily goal, streak, milestones, multiplier and settings over several Prague days (docs/spec.md §5–6).</summary>
public sealed class ProgressTests(QuizlyFactory factory) : IClassFixture<QuizlyFactory>
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task Seven_met_days_give_the_milestone_and_a_higher_multiplier()
    {
        var user = await factory.CreateUserAsync(dailyGoal: 2);
        var (_, cards) = await factory.CreateDeckAsync("S" + Guid.NewGuid().ToString("N")[..6], 1);

        JsonNode? last = null;
        for (var day = 1; day <= 7; day++)
        {
            factory.AdvanceToPrague(new TimeOnly(12, 0));
            using var app = await factory.AppClientAsync(user);
            var first = await ReviewAsync(app, (cards[0], "know"));
            Assert.Empty(first["events"]!.AsArray());
            Assert.Equal(day - 1, (int)first["summary"]!["streak"]!); // yesterday still counts while today is open

            last = await ReviewAsync(app, (cards[0], "know"));
            var types = last["events"]!.AsArray().Select(e => (string?)e!["type"]).ToList();
            Assert.Contains("goalMet", types);
            Assert.Equal(day, (int)last["summary"]!["streak"]!);
            Assert.Equal(day == 7, types.Contains("milestone"));
        }

        var milestone = last!["events"]!.AsArray().Single(e => (string?)e!["type"] == "milestone")!;
        Assert.Equal((7, 50), ((int)milestone["days"]!, (int)milestone["bonus"]!));
        // 7 days × 2 × 10 points + 50 bonus; the 7th day's answers still used 1,0×.
        Assert.Equal(190, (int)last["summary"]!["balance"]!);
        Assert.Equal(1.1m, (decimal)last["summary"]!["multiplier"]!);
        Assert.Equal((11, 2), ((int)last["points"]!["know"]!, (int)last["points"]!["dontKnow"]!));
        Assert.Equal((1.2m, 7), ((decimal)last["summary"]!["nextMultiplier"]!["value"]!, (int)last["summary"]!["nextMultiplier"]!["inDays"]!));

        factory.AdvanceToPrague(new TimeOnly(9, 0));
        using var day8 = await factory.AppClientAsync(user);
        var boosted = await ReviewAsync(day8, (cards[0], "know"));
        Assert.Equal((11, 1.1m), ((int)boosted["results"]![0]!["pointsAwarded"]!, (decimal)boosted["results"]![0]!["multiplier"]!));
        Assert.Equal(7, (int)boosted["summary"]!["bestStreak"]!);
    }

    [Fact]
    public async Task A_missed_day_breaks_the_streak_and_reports_when()
    {
        var user = await factory.CreateUserAsync(dailyGoal: 1);
        var (_, cards) = await factory.CreateDeckAsync("M" + Guid.NewGuid().ToString("N")[..6], 1);
        factory.AdvanceToPrague(new TimeOnly(10, 0));
        using (var app = await factory.AppClientAsync(user))
        {
            await ReviewAsync(app, (cards[0], "know"));
        }

        var metDay = factory.PragueToday;
        factory.AdvanceToPrague(new TimeOnly(10, 0)); // the next day: no reviews
        factory.AdvanceToPrague(new TimeOnly(8, 0));  // the day after

        using var later = await factory.AppClientAsync(user);
        var me = await (await later.GetAsync("/api/me", Ct)).ReadNodeAsync();
        Assert.Equal(0, (int)me["summary"]!["streak"]!);
        Assert.Equal(1, (int)me["summary"]!["streakBroken"]!["previousStreak"]!);
        Assert.Equal(metDay.AddDays(2).ToString("yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture), (string?)me["summary"]!["streakBroken"]!["brokenOn"]);

        var restart = await ReviewAsync(later, (cards[0], "know"));
        Assert.Equal(1, (int)restart["summary"]!["streak"]!);
        Assert.Null(restart["summary"]!["streakBroken"]);
    }

    [Fact]
    public async Task Answers_after_midnight_still_count_for_today_until_3_am()
    {
        var user = await factory.CreateUserAsync(dailyGoal: 2);
        var (_, cards) = await factory.CreateDeckAsync("P" + Guid.NewGuid().ToString("N")[..6], 1);
        factory.AdvanceToPrague(new TimeOnly(23, 59, 59));
        using var app = await factory.AppClientAsync(user);
        var beforeMidnight = await ReviewAsync(app, (cards[0], "know"));
        var day1 = DateOnly.Parse((string)beforeMidnight["summary"]!["today"]!["date"]!, System.Globalization.CultureInfo.InvariantCulture);

        // 00:00:01 Prague is still day1 (rollover is at 03:00, #40): the 2nd answer completes day1's goal.
        factory.Time.Advance(TimeSpan.FromSeconds(2));
        var afterMidnight = await ReviewAsync(app, (cards[0], "know"));
        Assert.Equal(day1.ToString("yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture), (string?)afterMidnight["summary"]!["today"]!["date"]);
        Assert.Equal((2, true), ((int)afterMidnight["summary"]!["today"]!["graded"]!, (bool)afterMidnight["summary"]!["today"]!["goalMet"]!));

        // 03:00:01 Prague is the new study day.
        factory.AdvanceToPrague(new TimeOnly(3, 0, 1));
        using var nextDay = await factory.AppClientAsync(user); // the 3-hour jump outlives the 60-min access token
        var afterRollover = await ReviewAsync(nextDay, (cards[0], "know"));
        Assert.Equal(day1.AddDays(1).ToString("yyyy-MM-dd", System.Globalization.CultureInfo.InvariantCulture), (string?)afterRollover["summary"]!["today"]!["date"]);
        Assert.Equal((1, false), ((int)afterRollover["summary"]!["today"]!["graded"]!, (bool)afterRollover["summary"]!["today"]!["goalMet"]!));
        Assert.Empty(afterRollover["events"]!.AsArray());
    }

    [Fact]
    public async Task Lowering_the_goal_completes_today_and_raising_it_keeps_a_met_day()
    {
        var user = await factory.CreateUserAsync(dailyGoal: 5);
        var (_, cards) = await factory.CreateDeckAsync("G" + Guid.NewGuid().ToString("N")[..6], 1);
        factory.AdvanceToPrague(new TimeOnly(15, 0));
        using var app = await factory.AppClientAsync(user);
        await ReviewAsync(app, (cards[0], "know"), (cards[0], "know"), (cards[0], "dontKnow"));
        var settings = await (await app.GetAsync("/api/me/settings", Ct)).ReadNodeAsync();
        Assert.Equal(("08:00", "22:00", true), ((string?)settings["morningTime"], (string?)settings["quietFrom"], (bool)settings["smartTimes"]!));

        settings["dailyGoal"] = 3;
        var lowered = await (await app.PutAsJsonAsync("/api/me/settings", settings, Ct)).ReadNodeAsync();

        Assert.Equal("goalMet", (string?)lowered["events"]![0]!["type"]);
        Assert.Equal((3, true, 1), ((int)lowered["summary"]!["today"]!["goal"]!, (bool)lowered["summary"]!["today"]!["goalMet"]!,
            (int)lowered["summary"]!["streak"]!));

        settings["dailyGoal"] = 10;
        var raised = await (await app.PutAsJsonAsync("/api/me/settings", settings, Ct)).ReadNodeAsync();
        Assert.Empty(raised["events"]!.AsArray());
        Assert.Equal((10, 3, true), ((int)raised["settings"]!["dailyGoal"]!, (int)raised["summary"]!["today"]!["goal"]!,
            (bool)raised["summary"]!["today"]!["goalMet"]!));
    }

    [Theory]
    [InlineData("morningTime", "8:00")]
    [InlineData("eveningTime", "25:00")]
    [InlineData("dailyGoal", 0)]
    [InlineData("newCardsPerDay", 101)]
    public async Task Invalid_settings_are_rejected(string field, object value)
    {
        var user = await factory.CreateUserAsync();
        using var app = await factory.AppClientAsync(user);
        var settings = await (await app.GetAsync("/api/me/settings", Ct)).ReadNodeAsync();
        settings[field] = System.Text.Json.JsonSerializer.SerializeToNode(value);

        var response = await app.PutAsJsonAsync("/api/me/settings", settings, Ct);

        Assert.NotNull((await response.AssertProblemAsync(HttpStatusCode.BadRequest, "validation"))["errors"]?[field]);
    }

    [Fact]
    public async Task Quiet_hours_must_not_start_and_end_at_the_same_time()
    {
        var user = await factory.CreateUserAsync();
        using var app = await factory.AppClientAsync(user);
        var settings = await (await app.GetAsync("/api/me/settings", Ct)).ReadNodeAsync();
        settings["quietTo"] = settings["quietFrom"]!.GetValue<string>();

        var response = await app.PutAsJsonAsync("/api/me/settings", settings, Ct);

        Assert.NotNull((await response.AssertProblemAsync(HttpStatusCode.BadRequest, "validation"))["errors"]?["quietTo"]);
    }

    [Fact]
    public async Task Wishlist_item_reached_is_announced_once()
    {
        var user = await factory.CreateUserAsync();
        var (_, cards) = await factory.CreateDeckAsync("W" + Guid.NewGuid().ToString("N")[..6], 1);
        using var admin = await factory.AdminClientAsync();
        var item = await (await admin.PostAsJsonAsync("/api/admin/shop-items",
            new { name = "Kafe", description = "", price = 20, initialStock = 5 }, Ct)).ReadNodeAsync();
        using var app = await factory.AppClientAsync(user);
        Assert.Equal(HttpStatusCode.NoContent, (await app.PutAsync($"/api/wishlist/{(int)item["id"]!}", null, Ct)).StatusCode);

        var below = await ReviewAsync(app, (cards[0], "know"));
        var reached = await ReviewAsync(app, (cards[0], "know"));
        var again = await ReviewAsync(app, (cards[0], "know"));

        Assert.Empty(below["events"]!.AsArray());
        var wish = reached["events"]!.AsArray().Single(e => (string?)e!["type"] == "wishlistReached")!;
        Assert.Equal(((int)item["id"]!, "Kafe", 20), ((int)wish["itemId"]!, (string?)wish["name"], (int)wish["price"]!));
        Assert.DoesNotContain(again["events"]!.AsArray(), e => (string?)e!["type"] == "wishlistReached");
    }

    [Fact]
    public async Task Me_reports_due_counts_and_the_next_morning_forecast()
    {
        var user = await factory.CreateUserAsync(newCardsPerDay: 2);
        var (_, cards) = await factory.CreateDeckAsync("F" + Guid.NewGuid().ToString("N")[..6], 3);
        factory.AdvanceToPrague(new TimeOnly(20, 0));
        using var app = await factory.AppClientAsync(user);

        await ReviewAsync(app, (cards[0], "dontKnow"));
        factory.Time.Advance(TimeSpan.FromMinutes(2));
        var me = await (await app.GetAsync("/api/me", Ct)).ReadNodeAsync();

        // Due now: the Nevím card (1 min step) + 1 new card left today (2 per day, 1 used; there are 2 unseen).
        Assert.Equal(2, (int)me["dueNow"]!);
        // Tomorrow 08:00: the same due card + a fresh allowance of 2 (2 unseen).
        Assert.Equal(3, (int)me["forecast"]!["dueByNextMorning"]!);
        var nextMorning = DateTime.Parse((string)me["forecast"]!["nextMorning"]!, System.Globalization.CultureInfo.InvariantCulture,
            System.Globalization.DateTimeStyles.AdjustToUniversal);
        Assert.Equal(new TimeOnly(8, 0), TimeOnly.FromDateTime(TimeZoneInfo.ConvertTimeFromUtc(nextMorning, Domain.PragueCalendar.Zone)));
        Assert.Null(me["smartEveningTime"]);
        Assert.Equal(user.Username, (string?)me["user"]!["username"]);
    }
}
