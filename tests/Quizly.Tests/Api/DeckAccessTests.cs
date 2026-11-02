using System.Net;
using System.Net.Http.Json;
using System.Text.Json.Nodes;
using Microsoft.EntityFrameworkCore;
using Quizly.Tests.Infrastructure;

namespace Quizly.Tests.Api;

/// <summary>Decks "Pro všechny" or for chosen users only (#18, docs/spec.md §2.4).</summary>
public sealed class DeckAccessTests(QuizlyFactory factory) : IClassFixture<QuizlyFactory>
{
    private static readonly int[] UnknownUser = [999999];

    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task Decks_are_for_everyone_until_the_admin_picks_users()
    {
        using var admin = await factory.AdminClientAsync();
        var (deck, _) = await factory.CreateDeckAsync("P" + Guid.NewGuid().ToString("N")[..6], 1);

        var access = await (await admin.GetAsync($"/api/admin/decks/{deck}/access", Ct)).ReadNodeAsync();
        Assert.True((bool)access["forEveryone"]!);
        Assert.Empty(access["userIds"]!.AsArray());

        var user = await factory.CreateUserAsync();
        var set = await admin.PutAsJsonAsync($"/api/admin/decks/{deck}/access", new { forEveryone = false, userIds = new[] { user.Id, user.Id } }, Ct);
        var saved = await set.ReadNodeAsync();
        Assert.False((bool)saved["forEveryone"]!);
        Assert.Equal([user.Id], saved["userIds"]!.AsArray().Select(u => (int)u!));

        var listed = (await (await admin.GetAsync("/api/admin/decks", Ct)).ReadNodeAsync()).AsArray().First(d => (int)d!["id"]! == deck)!;
        Assert.Equal((false, 1), ((bool)listed["forEveryone"]!, (int)listed["userCount"]!));

        // Back to everyone keeps the chosen users for next time.
        var back = await (await admin.PutAsJsonAsync($"/api/admin/decks/{deck}/access", new { forEveryone = true, userIds = new[] { user.Id } }, Ct)).ReadNodeAsync();
        Assert.Equal((true, 1), ((bool)back["forEveryone"]!, back["userIds"]!.AsArray().Count));

        await (await admin.PutAsJsonAsync($"/api/admin/decks/{deck}/access", new { forEveryone = false, userIds = UnknownUser }, Ct))
            .AssertProblemAsync(HttpStatusCode.BadRequest, "validation");
        await (await admin.GetAsync("/api/admin/decks/999999/access", Ct)).AssertProblemAsync(HttpStatusCode.NotFound, "notFound");
    }

    [Fact]
    public async Task A_user_without_access_does_not_see_or_study_the_deck()
    {
        var member = await factory.CreateUserAsync(newCardsPerDay: 50);
        var outsider = await factory.CreateUserAsync(newCardsPerDay: 50);
        var (deck, cards) = await factory.CreateDeckAsync("H" + Guid.NewGuid().ToString("N")[..6], 2);
        await SetAccessAsync(deck, forEveryone: false, member.Id);
        using var memberApp = await factory.AppClientAsync(member);
        using var outsiderApp = await factory.AppClientAsync(outsider);

        Assert.Contains(deck, await DeckIdsAsync(memberApp));
        Assert.Equal(cards, CardIds(await (await memberApp.GetAsync($"/api/session?deckId={deck}", Ct)).ReadNodeAsync()));

        Assert.DoesNotContain(deck, await DeckIdsAsync(outsiderApp));
        await (await outsiderApp.GetAsync($"/api/session?deckId={deck}", Ct)).AssertProblemAsync(HttpStatusCode.NotFound, "notFound");
        await (await outsiderApp.GetAsync($"/api/decks/{deck}/cards", Ct)).AssertProblemAsync(HttpStatusCode.NotFound, "notFound");
        await (await outsiderApp.GetAsync($"/api/stats?deckId={deck}", Ct)).AssertProblemAsync(HttpStatusCode.NotFound, "notFound");

        // "Učit se vše" and the stats' deck progress leave it out too.
        var all = CardIds(await (await outsiderApp.GetAsync("/api/session", Ct)).ReadNodeAsync());
        Assert.DoesNotContain(cards[0], all);
        var stats = await (await outsiderApp.GetAsync("/api/stats", Ct)).ReadNodeAsync();
        Assert.DoesNotContain(deck, stats["deckProgress"]!.AsArray().Select(d => (int)d!["deckId"]!));

        // An answer to its card is rejected like a deleted card's.
        var review = await outsiderApp.PostAsJsonAsync("/api/reviews",
            new { reviews = new[] { new { id = Guid.NewGuid(), cardId = cards[0], rating = "know" } } }, Ct);
        var result = (await review.ReadNodeAsync())["results"]![0]!;
        Assert.Equal(("rejected", "cardNotFound"), ((string?)result["status"], (string?)result["code"]));
    }

    [Fact]
    public async Task Losing_access_hides_progress_and_getting_it_back_restores_it()
    {
        // No new cards, so "due now" counts only reviews.
        var user = await factory.CreateUserAsync(newCardsPerDay: 0);
        var (deck, cards) = await factory.CreateDeckAsync("L" + Guid.NewGuid().ToString("N")[..6], 2);
        await SetAccessAsync(deck, forEveryone: false, user.Id);
        using var app = await factory.AppClientAsync(user);
        var review = await app.PostAsJsonAsync("/api/reviews",
            new { reviews = new[] { new { id = Guid.NewGuid(), cardId = cards[0], rating = "dontKnow" } } }, Ct);
        Assert.Equal(HttpStatusCode.OK, review.StatusCode);
        factory.Time.Advance(TimeSpan.FromMinutes(2));
        Assert.Equal(1, (int)(await (await app.GetAsync("/api/me", Ct)).ReadNodeAsync())["dueNow"]!);

        await SetAccessAsync(deck, forEveryone: false);
        var me = await (await app.GetAsync("/api/me", Ct)).ReadNodeAsync();
        Assert.Equal(0, (int)me["dueNow"]!);
        Assert.Equal(2, (int)me["summary"]!["balance"]!); // points for the Nevím stay
        await factory.WithDbAsync(async db =>
            Assert.True(await db.CardStates.AnyAsync(s => s.UserId == user.Id && s.CardId == cards[0], Ct)));

        await SetAccessAsync(deck, forEveryone: false, user.Id);
        var session = CardIds(await (await app.GetAsync($"/api/session?deckId={deck}", Ct)).ReadNodeAsync());
        Assert.Equal([cards[0]], session); // the card is due again where it left off
    }

    private async Task SetAccessAsync(int deck, bool forEveryone, params int[] userIds)
    {
        using var admin = await factory.AdminClientAsync();
        var response = await admin.PutAsJsonAsync($"/api/admin/decks/{deck}/access", new { forEveryone, userIds }, Ct);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    private static async Task<List<int>> DeckIdsAsync(HttpClient app) =>
        [.. (await (await app.GetAsync("/api/decks", Ct)).ReadNodeAsync())["items"]!.AsArray().Select(d => (int)d!["id"]!)];

    private static List<int> CardIds(JsonNode session) => [.. session["cards"]!.AsArray().Select(c => (int)c!["cardId"]!)];
}
