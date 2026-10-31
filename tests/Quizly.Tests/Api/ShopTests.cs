using System.Net;
using System.Net.Http.Json;
using System.Text.Json.Nodes;
using Microsoft.EntityFrameworkCore;
using Quizly.Domain;
using Quizly.Tests.Infrastructure;

namespace Quizly.Tests.Api;

/// <summary>Claims, admin decisions and the wishlist (docs/spec.md §7, docs/api.md §8).</summary>
public sealed class ShopTests(QuizlyFactory factory) : IClassFixture<QuizlyFactory>
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task Claim_deducts_points_and_stock_and_is_idempotent()
    {
        var user = await factory.CreateUserAsync();
        await factory.GivePointsAsync(user.Id, 100);
        var itemId = await CreateItemAsync(price: 60, stock: 2);
        using var app = await factory.AppClientAsync(user);
        var requestId = Guid.NewGuid();

        var created = await app.PostAsJsonAsync($"/api/shop/{itemId}/claim", new { requestId }, Ct);
        var repeated = await app.PostAsJsonAsync($"/api/shop/{itemId}/claim", new { requestId }, Ct);

        Assert.Equal(HttpStatusCode.Created, created.StatusCode);
        var body = await created.ReadNodeAsync();
        Assert.Equal((40, "pending", 60), ((int)body["balance"]!, (string?)body["claim"]!["status"], (int)body["claim"]!["price"]!));
        Assert.Equal(HttpStatusCode.OK, repeated.StatusCode);
        var again = await repeated.ReadNodeAsync();
        Assert.Equal(((int)body["claim"]!["id"]!, 40), ((int)again["claim"]!["id"]!, (int)again["balance"]!));

        var shop = await (await app.GetAsync("/api/shop", Ct)).ReadNodeAsync();
        var item = shop["items"]!.AsArray().Single(i => (int)i!["id"]! == itemId)!;
        Assert.Equal((1, 2, false, 20), ((int)item["stock"]!, (int)item["initialStock"]!, (bool)item["soldOut"]!, (int)item["missing"]!));
        var claims = await (await app.GetAsync("/api/claims", Ct)).ReadNodeAsync();
        Assert.Single(claims["items"]!.AsArray());
    }

    [Fact]
    public async Task Claim_fails_without_points_stock_or_an_active_item()
    {
        var user = await factory.CreateUserAsync();
        await factory.GivePointsAsync(user.Id, 50);
        var expensive = await CreateItemAsync(price: 51, stock: 1);
        var soldOut = await CreateItemAsync(price: 10, stock: 0);
        var inactive = await CreateItemAsync(price: 10, stock: 1, active: false);
        using var app = await factory.AppClientAsync(user);

        await (await Claim(app, expensive)).AssertProblemAsync(HttpStatusCode.Conflict, "insufficientBalance");
        await (await Claim(app, soldOut)).AssertProblemAsync(HttpStatusCode.Conflict, "soldOut");
        await (await Claim(app, inactive)).AssertProblemAsync(HttpStatusCode.Conflict, "itemInactive");
        await (await Claim(app, 999999)).AssertProblemAsync(HttpStatusCode.NotFound, "notFound");
        var missingId = await app.PostAsJsonAsync($"/api/shop/{expensive}/claim", new { requestId = Guid.Empty }, Ct);
        await missingId.AssertProblemAsync(HttpStatusCode.BadRequest, "validation");

        var shop = await (await app.GetAsync("/api/shop", Ct)).ReadNodeAsync();
        Assert.DoesNotContain(shop["items"]!.AsArray(), i => (int)i!["id"]! == inactive);
        Assert.True((bool)shop["items"]!.AsArray().Single(i => (int)i!["id"]! == soldOut)!["soldOut"]!);
        Assert.Equal(50, (int)shop["balance"]!);
    }

    [Fact]
    public async Task The_last_piece_is_sold_only_once_under_concurrency()
    {
        var itemId = await CreateItemAsync(price: 10, stock: 1);
        var buyers = new List<HttpClient>();
        for (var i = 0; i < 6; i++)
        {
            var user = await factory.CreateUserAsync();
            await factory.GivePointsAsync(user.Id, 10);
            buyers.Add(await factory.AppClientAsync(user));
        }

        var responses = await Task.WhenAll(buyers.Select(b => Claim(b, itemId)));

        Assert.Single(responses, r => r.StatusCode == HttpStatusCode.Created);
        foreach (var lost in responses.Where(r => r.StatusCode != HttpStatusCode.Created))
        {
            await lost.AssertProblemAsync(HttpStatusCode.Conflict, "soldOut");
        }

        await factory.WithDbAsync(async db => Assert.Equal(0, (await db.ShopItems.SingleAsync(i => i.Id == itemId, Ct)).Stock));
        buyers.ForEach(b => b.Dispose());
    }

    [Fact]
    public async Task Parallel_claims_cannot_spend_the_same_points_twice()
    {
        var user = await factory.CreateUserAsync();
        await factory.GivePointsAsync(user.Id, 30);
        var itemId = await CreateItemAsync(price: 20, stock: 10);
        using var app = await factory.AppClientAsync(user);

        var responses = await Task.WhenAll(Enumerable.Range(0, 4).Select(_ => Claim(app, itemId)));

        Assert.Single(responses, r => r.StatusCode == HttpStatusCode.Created);
        Assert.Equal(3, responses.Count(r => r.StatusCode == HttpStatusCode.Conflict));
        var shop = await (await app.GetAsync("/api/shop", Ct)).ReadNodeAsync();
        Assert.Equal(10, (int)shop["balance"]!);
    }

    [Fact]
    public async Task Rejecting_refunds_and_restocks_and_decisions_are_final()
    {
        var user = await factory.CreateUserAsync();
        await factory.GivePointsAsync(user.Id, 100);
        var itemId = await CreateItemAsync(price: 40, stock: 2);
        using var app = await factory.AppClientAsync(user);
        var first = (int)(await (await Claim(app, itemId)).ReadNodeAsync())["claim"]!["id"]!;
        var second = (int)(await (await Claim(app, itemId)).ReadNodeAsync())["claim"]!["id"]!;
        using var admin = await factory.AdminClientAsync();

        var pending = await (await admin.GetAsync("/api/admin/claims?status=pending", Ct)).ReadNodeAsync();
        Assert.Contains(pending.AsArray(), c => (int)c!["id"]! == first && (string?)c["username"] == user.Username);
        var rejected = await (await admin.PostAsync($"/api/admin/claims/{first}/reject", null, Ct)).ReadNodeAsync();
        var confirmed = await (await admin.PostAsync($"/api/admin/claims/{second}/confirm", null, Ct)).ReadNodeAsync();

        Assert.Equal("rejected", (string?)rejected["status"]);
        Assert.Equal("confirmed", (string?)confirmed["status"]);
        Assert.NotNull(confirmed["decidedAt"]);
        await (await admin.PostAsync($"/api/admin/claims/{first}/confirm", null, Ct)).AssertProblemAsync(HttpStatusCode.Conflict, "claimNotPending");
        await (await admin.PostAsync($"/api/admin/claims/{second}/reject", null, Ct)).AssertProblemAsync(HttpStatusCode.Conflict, "claimNotPending");
        await (await admin.PostAsync("/api/admin/claims/999999/reject", null, Ct)).AssertProblemAsync(HttpStatusCode.NotFound, "notFound");
        await (await admin.GetAsync("/api/admin/claims?status=lost", Ct)).AssertProblemAsync(HttpStatusCode.BadRequest, "validation");

        var shop = await (await app.GetAsync("/api/shop", Ct)).ReadNodeAsync();
        Assert.Equal(60, (int)shop["balance"]!); // 100 − 40 − 40 + 40
        Assert.Equal(1, (int)shop["items"]!.AsArray().Single(i => (int)i!["id"]! == itemId)!["stock"]!);
        var mine = await (await app.GetAsync("/api/claims", Ct)).ReadNodeAsync();
        Assert.Equal(["confirmed", "rejected"], mine["items"]!.AsArray().Select(c => (string?)c!["status"]).Order());
        await factory.WithDbAsync(async db => Assert.Equal(1,
            await db.PointsEntries.CountAsync(p => p.UserId == user.Id && p.Reason == PointsReason.Refund, Ct)));
    }

    [Fact]
    public async Task Wishlist_hearts_are_idempotent()
    {
        var user = await factory.CreateUserAsync();
        var itemId = await CreateItemAsync(price: 500, stock: 1);
        var inactive = await CreateItemAsync(price: 5, stock: 1, active: false);
        using var app = await factory.AppClientAsync(user);

        Assert.Equal(HttpStatusCode.NoContent, (await app.PutAsync($"/api/wishlist/{itemId}", null, Ct)).StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, (await app.PutAsync($"/api/wishlist/{itemId}", null, Ct)).StatusCode);
        await (await app.PutAsync($"/api/wishlist/{inactive}", null, Ct)).AssertProblemAsync(HttpStatusCode.NotFound, "notFound");
        var shop = await (await app.GetAsync("/api/shop", Ct)).ReadNodeAsync();
        Assert.True((bool)shop["items"]!.AsArray().Single(i => (int)i!["id"]! == itemId)!["wishlisted"]!);

        Assert.Equal(HttpStatusCode.NoContent, (await app.DeleteAsync($"/api/wishlist/{itemId}", Ct)).StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, (await app.DeleteAsync($"/api/wishlist/{itemId}", Ct)).StatusCode);
        shop = await (await app.GetAsync("/api/shop", Ct)).ReadNodeAsync();
        Assert.False((bool)shop["items"]!.AsArray().Single(i => (int)i!["id"]! == itemId)!["wishlisted"]!);
    }

    private static Task<HttpResponseMessage> Claim(HttpClient app, int itemId) =>
        app.PostAsJsonAsync($"/api/shop/{itemId}/claim", new { requestId = Guid.NewGuid() }, Ct);

    private async Task<int> CreateItemAsync(int price, int stock, bool active = true)
    {
        using var admin = await factory.AdminClientAsync();
        var item = await (await admin.PostAsJsonAsync("/api/admin/shop-items",
            new { name = "Odměna " + Guid.NewGuid().ToString("N")[..6], description = "", price, initialStock = stock, isActive = active }, Ct))
            .ReadNodeAsync();
        return (int)item["id"]!;
    }
}

/// <summary>Statistiky (docs/spec.md §10).</summary>
public sealed class StatsTests(QuizlyFactory factory) : IClassFixture<QuizlyFactory>
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task Stats_reflect_todays_answers_with_and_without_a_deck_filter()
    {
        var user = await factory.CreateUserAsync(dailyGoal: 4);
        var (deckA, cardsA) = await factory.CreateDeckAsync("SA" + Guid.NewGuid().ToString("N")[..6], 2);
        var (deckB, cardsB) = await factory.CreateDeckAsync("SB" + Guid.NewGuid().ToString("N")[..6], 1);
        factory.AdvanceToPrague(new TimeOnly(18, 30));
        using var app = await factory.AppClientAsync(user);
        await StudyTests.ReviewAsync(app, (cardsA[0], "know"), (cardsA[1], "dontKnow"), (cardsB[0], "know"),
            (cardsA[0], "know"), (cardsA[0], "know"));

        var all = await (await app.GetAsync("/api/stats", Ct)).ReadNodeAsync();
        var onlyA = await (await app.GetAsync($"/api/stats?deckId={deckA}", Ct)).ReadNodeAsync();

        var tiles = all["tiles"]!;
        Assert.Equal((1, 1, 80, 5), ((int)tiles["streak"]!, (int)tiles["bestStreak"]!, (int)tiles["successRate30d"]!, (int)tiles["totalReviews"]!));
        Assert.Equal(42, (int)tiles["totalPointsEarned"]!); // 4 × 10 + 2
        Assert.Equal(30, tiles["sparkline"]!.AsArray().Count);
        Assert.Equal(80, (int)tiles["sparkline"]![29]!);

        var heatmap = all["heatmap"]!;
        Assert.Equal(17, heatmap["weeks"]!.AsArray().Count);
        Assert.All(heatmap["weeks"]!.AsArray(), w => Assert.Equal(7, w!.AsArray().Count));
        var today = DateOnly.Parse((string)heatmap["today"]!, System.Globalization.CultureInfo.InvariantCulture);
        var from = DateOnly.Parse((string)heatmap["from"]!, System.Globalization.CultureInfo.InvariantCulture);
        Assert.Equal(DayOfWeek.Monday, from.DayOfWeek);
        var offset = today.DayNumber - from.DayNumber;
        Assert.Equal(3, (int)heatmap["weeks"]![offset / 7]![offset % 7]!); // 5 ÷ 4 = 1,25× → level 3

        var daily = all["daily"]!;
        Assert.Equal((4, 14, 5), ((int)daily["goal"]!, daily["days"]!.AsArray().Count, (int)daily["days"]![13]!["graded"]!));
        Assert.Equal(7, all["weekdays"]!.AsArray().Count);
        Assert.Null(all["bestTime"]); // fewer than 20 answers

        Assert.Equal(4, (int)onlyA["tiles"]!["totalReviews"]!);
        Assert.Equal(32, (int)onlyA["tiles"]!["totalPointsEarned"]!);
        var progressA = onlyA["deckProgress"]!.AsArray().Single()!;
        Assert.Equal((deckA, 0, 2, 0), ((int)progressA["deckId"]!, (int)progressA["mastered"]!, (int)progressA["learning"]!, (int)progressA["new"]!));
        var progressB = all["deckProgress"]!.AsArray().Single(d => (int)d!["deckId"]! == deckB)!;
        Assert.Equal((0, 1, 0), ((int)progressB["mastered"]!, (int)progressB["learning"]!, (int)progressB["new"]!));
    }

    [Fact]
    public void Heatmap_levels_follow_the_goal_ratio()
    {
        Assert.Equal(0, Application.Stats.StatsService.HeatmapLevel(0, 20));
        Assert.Equal(1, Application.Stats.StatsService.HeatmapLevel(19, 20));
        Assert.Equal(2, Application.Stats.StatsService.HeatmapLevel(20, 20));
        Assert.Equal(3, Application.Stats.StatsService.HeatmapLevel(25, 20));
        Assert.Equal(4, Application.Stats.StatsService.HeatmapLevel(30, 20));
    }

    [Fact]
    public void Best_window_needs_20_answers_and_prefers_success()
    {
        static DateTime At(int hour) => TimeZoneInfo.ConvertTimeToUtc(new DateTime(2026, 11, 2, hour, 15, 0), PragueCalendar.Zone);
        var reviews = Enumerable.Range(0, 20).Select(i => (At(18), i < 18))      // 18:00–20:00: 90 %
            .Concat(Enumerable.Range(0, 30).Select(i => (At(8), i < 24)))        // 08:00–10:00: 80 %
            .Concat(Enumerable.Range(0, 19).Select(_ => (At(22), true)));         // too few

        var best = Application.Stats.StatsService.BestWindow(reviews);

        Assert.Equal(("18:00", "20:00", 90, 20), (best!.From, best.To, best.SuccessRate, best.Graded));
    }

    [Fact]
    public async Task Unknown_deck_filter_is_not_found()
    {
        var user = await factory.CreateUserAsync();
        using var app = await factory.AppClientAsync(user);

        await (await app.GetAsync("/api/stats?deckId=999999", Ct)).AssertProblemAsync(HttpStatusCode.NotFound, "notFound");
    }
}
