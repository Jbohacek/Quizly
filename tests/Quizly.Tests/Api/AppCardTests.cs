using System.Net;
using System.Net.Http.Json;
using Microsoft.EntityFrameworkCore;
using Quizly.Tests.Infrastructure;

namespace Quizly.Tests.Api;

/// <summary>Cards added, edited and deleted from the app (#23, docs/api.md §4).</summary>
public sealed class AppCardTests(QuizlyFactory factory) : IClassFixture<QuizlyFactory>
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task Any_user_adds_and_edits_cards_and_progress_is_kept()
    {
        var user = await factory.CreateUserAsync();
        var other = await factory.CreateUserAsync();
        var (deck, cards) = await factory.CreateDeckAsync("E" + Guid.NewGuid().ToString("N")[..6], 1);
        using var app = await factory.AppClientAsync(user);
        using var otherApp = await factory.AppClientAsync(other);
        var review = await otherApp.PostAsJsonAsync("/api/reviews",
            new { reviews = new[] { new { id = Guid.NewGuid(), cardId = cards[0], rating = "know" } } }, Ct);
        Assert.Equal(HttpStatusCode.OK, review.StatusCode);

        var created = await app.PostAsJsonAsync($"/api/decks/{deck}/cards", new { question = "  Nová otázka ", answer = "Odpověď" }, Ct);
        Assert.Equal(HttpStatusCode.Created, created.StatusCode);
        var card = await created.ReadNodeAsync();
        Assert.Equal(("Nová otázka", deck), ((string?)card["question"], (int)card["deckId"]!));

        var edited = await (await app.PutAsJsonAsync($"/api/decks/{deck}/cards/{cards[0]}",
            new { question = "**Opravená** otázka", answer = "- a\n- b" }, Ct)).ReadNodeAsync();
        Assert.Equal("**Opravená** otázka", (string?)edited["question"]);

        // The other user sees the edit and keeps their progress on the card.
        var list = await (await otherApp.GetAsync($"/api/decks/{deck}/cards", Ct)).ReadNodeAsync();
        var items = list["cards"]!.AsArray();
        Assert.Equal(["**Opravená** otázka", "Nová otázka"], items.Select(c => (string?)c!["question"]));
        Assert.Equal(("learning", 1), ((string?)items[0]!["status"], (int)items[0]!["knowCount"]!));
    }

    [Fact]
    public async Task Deleting_a_card_removes_it_with_everyones_progress()
    {
        var user = await factory.CreateUserAsync();
        var (deck, cards) = await factory.CreateDeckAsync("D" + Guid.NewGuid().ToString("N")[..6], 2);
        using var app = await factory.AppClientAsync(user);
        await app.PostAsJsonAsync("/api/reviews",
            new { reviews = new[] { new { id = Guid.NewGuid(), cardId = cards[0], rating = "know" } } }, Ct);

        var deleted = await app.DeleteAsync($"/api/decks/{deck}/cards/{cards[0]}", Ct);

        Assert.Equal(HttpStatusCode.NoContent, deleted.StatusCode);
        await factory.WithDbAsync(async db =>
        {
            Assert.False(await db.Cards.AnyAsync(c => c.Id == cards[0], Ct));
            Assert.False(await db.CardStates.AnyAsync(s => s.CardId == cards[0], Ct));
        });
        await (await app.DeleteAsync($"/api/decks/{deck}/cards/{cards[0]}", Ct)).AssertProblemAsync(HttpStatusCode.NotFound, "notFound");
    }

    [Fact]
    public async Task Invalid_text_and_decks_the_user_does_not_see_are_refused()
    {
        var user = await factory.CreateUserAsync();
        var (deck, cards) = await factory.CreateDeckAsync("V" + Guid.NewGuid().ToString("N")[..6], 1);
        var (hidden, hiddenCards) = await factory.CreateDeckAsync("Z" + Guid.NewGuid().ToString("N")[..6], 1);
        using (var admin = await factory.AdminClientAsync())
        {
            var access = await admin.PutAsJsonAsync($"/api/admin/decks/{hidden}/access", new { forEveryone = false, userIds = Array.Empty<int>() }, Ct);
            Assert.Equal(HttpStatusCode.OK, access.StatusCode);
        }

        using var app = await factory.AppClientAsync(user);

        var invalid = await (await app.PutAsJsonAsync($"/api/decks/{deck}/cards/{cards[0]}",
            new { question = "", answer = new string('a', 2001) }, Ct)).AssertProblemAsync(HttpStatusCode.BadRequest, "validation");
        Assert.NotNull(invalid["errors"]!["question"]);
        Assert.NotNull(invalid["errors"]!["answer"]);

        await (await app.PostAsJsonAsync($"/api/decks/{hidden}/cards", new { question = "q", answer = "a" }, Ct))
            .AssertProblemAsync(HttpStatusCode.NotFound, "notFound");
        await (await app.PutAsJsonAsync($"/api/decks/{hidden}/cards/{hiddenCards[0]}", new { question = "q", answer = "a" }, Ct))
            .AssertProblemAsync(HttpStatusCode.NotFound, "notFound");
        await (await app.DeleteAsync($"/api/decks/{hidden}/cards/{hiddenCards[0]}", Ct))
            .AssertProblemAsync(HttpStatusCode.NotFound, "notFound");
        // A card of another deck isn't reachable through this one.
        await (await app.PutAsJsonAsync($"/api/decks/{deck}/cards/{hiddenCards[0]}", new { question = "q", answer = "a" }, Ct))
            .AssertProblemAsync(HttpStatusCode.NotFound, "notFound");
    }
}
