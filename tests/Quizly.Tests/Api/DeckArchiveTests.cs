using System.Net;
using System.Net.Http.Json;
using System.Text.Json.Nodes;
using Microsoft.EntityFrameworkCore;
using Quizly.Tests.Infrastructure;

namespace Quizly.Tests.Api;

/// <summary>Archived decks: hidden from every app user, nothing deleted, can be restored (#28, docs/spec.md §2.4).</summary>
public sealed class DeckArchiveTests(QuizlyFactory factory) : IClassFixture<QuizlyFactory>
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task Admin_archives_and_restores_a_deck()
    {
        using var admin = await factory.AdminClientAsync();
        var (deck, _) = await factory.CreateDeckAsync("A" + Guid.NewGuid().ToString("N")[..6], 1);

        var active = await (await admin.GetAsync($"/api/admin/decks/{deck}", Ct)).ReadNodeAsync();
        Assert.Null(active["archivedAt"]);

        var archived = await (await admin.PostAsync($"/api/admin/decks/{deck}/archive", null, Ct)).ReadNodeAsync();
        var archivedAt = (string?)archived["archivedAt"];
        Assert.NotNull(archivedAt);
        Assert.Equal((string?)active["updatedAt"], (string?)archived["updatedAt"]); // "Upraveno" stays

        // Archiving again keeps the original date.
        factory.Time.Advance(TimeSpan.FromHours(1));
        var again = await (await admin.PostAsync($"/api/admin/decks/{deck}/archive", null, Ct)).ReadNodeAsync();
        Assert.Equal(archivedAt, (string?)again["archivedAt"]);

        // The admin still lists it.
        var listed = (await (await admin.GetAsync("/api/admin/decks", Ct)).ReadNodeAsync()).AsArray().Single(d => (int)d!["id"]! == deck)!;
        Assert.Equal(archivedAt, (string?)listed["archivedAt"]);

        var restored = await (await admin.PostAsync($"/api/admin/decks/{deck}/restore", null, Ct)).ReadNodeAsync();
        Assert.Null(restored["archivedAt"]);

        await (await admin.PostAsync("/api/admin/decks/999999/archive", null, Ct)).AssertProblemAsync(HttpStatusCode.NotFound, "notFound");
        await (await admin.PostAsync("/api/admin/decks/999999/restore", null, Ct)).AssertProblemAsync(HttpStatusCode.NotFound, "notFound");
    }

    [Fact]
    public async Task Dashboard_shows_archived_decks_in_a_separate_section_and_header()
    {
        using var admin = await factory.AdminClientAsync();
        var name = "Archiv " + Guid.NewGuid().ToString("N")[..6];
        var (deck, _) = await factory.CreateDeckAsync(name, 1);
        await ArchiveAsync(deck, archive: true);

        var listHtml = WebUtility.HtmlDecode(await admin.GetStringAsync("/admin/balicky", Ct));
        Assert.Contains("Archivované (", listHtml, StringComparison.Ordinal);
        Assert.Contains(name, listHtml, StringComparison.Ordinal);

        var detailHtml = WebUtility.HtmlDecode(await admin.GetStringAsync($"/admin/balicky/{deck}", Ct));
        Assert.Contains("Archivováno ", detailHtml, StringComparison.Ordinal);
        Assert.Contains("v aplikaci skrytý", detailHtml, StringComparison.Ordinal);
    }

    [Fact]
    public async Task An_archived_deck_is_hidden_from_every_app_endpoint()
    {
        var user = await factory.CreateUserAsync(newCardsPerDay: 50);
        var (deck, cards) = await factory.CreateDeckAsync("H" + Guid.NewGuid().ToString("N")[..6], 2);
        using var app = await factory.AppClientAsync(user);
        Assert.Contains(deck, await DeckIdsAsync(app));

        await ArchiveAsync(deck, archive: true);

        Assert.DoesNotContain(deck, await DeckIdsAsync(app));
        await (await app.GetAsync($"/api/decks/{deck}/cards", Ct)).AssertProblemAsync(HttpStatusCode.NotFound, "notFound");
        await (await app.GetAsync($"/api/session?deckId={deck}", Ct)).AssertProblemAsync(HttpStatusCode.NotFound, "notFound");
        await (await app.GetAsync($"/api/stats?deckId={deck}", Ct)).AssertProblemAsync(HttpStatusCode.NotFound, "notFound");
        await (await app.PostAsJsonAsync($"/api/decks/{deck}/cards", new { question = "q", answer = "a" }, Ct))
            .AssertProblemAsync(HttpStatusCode.NotFound, "notFound");

        // "Učit se vše" and the stats' deck progress leave it out too.
        Assert.DoesNotContain(cards[0], CardIds(await (await app.GetAsync("/api/session", Ct)).ReadNodeAsync()));
        var stats = await (await app.GetAsync("/api/stats", Ct)).ReadNodeAsync();
        Assert.DoesNotContain(deck, stats["deckProgress"]!.AsArray().Select(d => (int)d!["deckId"]!));

        // An answer from a session started before archiving is rejected like a deleted card's.
        var review = await app.PostAsJsonAsync("/api/reviews",
            new { reviews = new[] { new { id = Guid.NewGuid(), cardId = cards[0], rating = "know" } } }, Ct);
        var result = (await review.ReadNodeAsync())["results"]![0]!;
        Assert.Equal(("rejected", "cardNotFound"), ((string?)result["status"], (string?)result["code"]));
    }

    [Fact]
    public async Task Archiving_hides_a_deck_even_from_users_with_access()
    {
        var user = await factory.CreateUserAsync();
        var (deck, _) = await factory.CreateDeckAsync("X" + Guid.NewGuid().ToString("N")[..6], 1);
        using (var admin = await factory.AdminClientAsync())
        {
            var access = await admin.PutAsJsonAsync($"/api/admin/decks/{deck}/access", new { forEveryone = false, userIds = new[] { user.Id } }, Ct);
            Assert.Equal(HttpStatusCode.OK, access.StatusCode);
        }

        using var app = await factory.AppClientAsync(user);
        await ArchiveAsync(deck, archive: true);
        Assert.DoesNotContain(deck, await DeckIdsAsync(app));

        // Restoring keeps the access list.
        await ArchiveAsync(deck, archive: false);
        Assert.Contains(deck, await DeckIdsAsync(app));
        using var check = await factory.AdminClientAsync();
        var kept = await (await check.GetAsync($"/api/admin/decks/{deck}/access", Ct)).ReadNodeAsync();
        Assert.Equal([user.Id], kept["userIds"]!.AsArray().Select(u => (int)u!));
    }

    [Fact]
    public async Task Restoring_brings_back_the_deck_with_progress()
    {
        // No new cards, so "due now" counts only reviews.
        var user = await factory.CreateUserAsync(newCardsPerDay: 0);
        var (deck, cards) = await factory.CreateDeckAsync("R" + Guid.NewGuid().ToString("N")[..6], 2);
        using var app = await factory.AppClientAsync(user);
        var review = await app.PostAsJsonAsync("/api/reviews",
            new { reviews = new[] { new { id = Guid.NewGuid(), cardId = cards[0], rating = "dontKnow" } } }, Ct);
        Assert.Equal(HttpStatusCode.OK, review.StatusCode);
        factory.Time.Advance(TimeSpan.FromMinutes(2));
        Assert.Equal(1, (int)(await (await app.GetAsync("/api/me", Ct)).ReadNodeAsync())["dueNow"]!);

        await ArchiveAsync(deck, archive: true);
        var me = await (await app.GetAsync("/api/me", Ct)).ReadNodeAsync();
        Assert.Equal(0, (int)me["dueNow"]!);
        Assert.Equal(2, (int)me["summary"]!["balance"]!); // points for the Nevím stay
        await factory.WithDbAsync(async db =>
            Assert.True(await db.CardStates.AnyAsync(s => s.UserId == user.Id && s.CardId == cards[0], Ct)));

        await ArchiveAsync(deck, archive: false);
        var session = CardIds(await (await app.GetAsync($"/api/session?deckId={deck}", Ct)).ReadNodeAsync());
        Assert.Equal([cards[0]], session); // the card is due again where it left off
    }

    private async Task ArchiveAsync(int deck, bool archive)
    {
        using var admin = await factory.AdminClientAsync();
        var response = await admin.PostAsync($"/api/admin/decks/{deck}/{(archive ? "archive" : "restore")}", null, Ct);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    private static async Task<List<int>> DeckIdsAsync(HttpClient app) =>
        [.. (await (await app.GetAsync("/api/decks", Ct)).ReadNodeAsync())["items"]!.AsArray().Select(d => (int)d!["id"]!)];

    private static List<int> CardIds(JsonNode session) => [.. session["cards"]!.AsArray().Select(c => (int)c!["cardId"]!)];
}
