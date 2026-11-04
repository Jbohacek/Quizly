using System.Net;
using System.Net.Http.Json;
using System.Text.Json.Nodes;
using Microsoft.EntityFrameworkCore;
using Quizly.Tests.Infrastructure;

namespace Quizly.Tests.Api;

/// <summary>Card tags (#29) in the admin and app APIs, the session and deck YAML.</summary>
public sealed class TagTests(QuizlyFactory factory) : IClassFixture<QuizlyFactory>
{
    private static readonly string[] MixedCase = ["Prednaska_01", "ai_gen", "ai_gen"];
    private static readonly string[] WithInvalid = ["dvě slova", "ok"];
    private static readonly string[] TwoTags = ["prednaska_01", "ai_gen"];
    private static readonly string[] OldTag = ["stary"];

    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task Admin_sets_tags_omitted_tags_are_kept_and_an_empty_list_clears_them()
    {
        var (deck, cards) = await factory.CreateDeckAsync("T" + Guid.NewGuid().ToString("N")[..6], 1);
        using var admin = await factory.AdminClientAsync();
        var url = $"/api/admin/decks/{deck}/cards/{cards[0]}";

        var tagged = await (await admin.PutAsJsonAsync(url, new { question = "Q", answer = "A", sortOrder = 0, tags = MixedCase }, Ct)).ReadNodeAsync();
        var kept = await (await admin.PutAsJsonAsync(url, new { question = "Q2", answer = "A", sortOrder = 0 }, Ct)).ReadNodeAsync();
        var cleared = await (await admin.PutAsJsonAsync(url, new { question = "Q3", answer = "A", sortOrder = 0, tags = Array.Empty<string>() }, Ct)).ReadNodeAsync();

        Assert.Equal(["ai_gen", "prednaska_01"], Tags(tagged));
        Assert.Equal(["ai_gen", "prednaska_01"], Tags(kept));
        Assert.Empty(Tags(cleared));
    }

    [Fact]
    public async Task Invalid_tags_are_a_validation_error()
    {
        var (deck, _) = await factory.CreateDeckAsync("I" + Guid.NewGuid().ToString("N")[..6], 0);
        using var admin = await factory.AdminClientAsync();

        var response = await admin.PostAsJsonAsync($"/api/admin/decks/{deck}/cards",
            new { question = "Q", answer = "A", tags = WithInvalid }, Ct);

        var problem = await response.AssertProblemAsync(HttpStatusCode.BadRequest, "validation");
        Assert.Contains("„dvě slova“", (string)problem["errors"]!["tags"]![0]!, StringComparison.Ordinal);
    }

    [Fact]
    public async Task App_users_tag_cards_and_see_tags_in_the_deck_and_the_session()
    {
        var user = await factory.CreateUserAsync(newCardsPerDay: 50);
        var (deck, _) = await factory.CreateDeckAsync("A" + Guid.NewGuid().ToString("N")[..6], 0);
        using var app = await factory.AppClientAsync(user);

        var created = await (await app.PostAsJsonAsync($"/api/decks/{deck}/cards",
            new { question = "Q", answer = "A", tags = TwoTags }, Ct)).ReadNodeAsync();
        var id = (int)created["id"]!;
        // An app without tag editing sends no tags: they stay.
        await app.PutAsJsonAsync($"/api/decks/{deck}/cards/{id}", new { question = "Q opravená", answer = "A" }, Ct);

        var deckCards = await (await app.GetAsync($"/api/decks/{deck}/cards", Ct)).ReadNodeAsync();
        var session = await (await app.GetAsync($"/api/session?deckId={deck}", Ct)).ReadNodeAsync();

        Assert.Equal(["ai_gen", "prednaska_01"], Tags(deckCards["cards"]![0]!));
        var card = session["cards"]!.AsArray().Single(c => (int)c!["cardId"]! == id)!;
        Assert.Equal(("Q opravená", deck), ((string?)card["question"], (int)card["deckId"]!));
        Assert.Equal(["ai_gen", "prednaska_01"], Tags(card));
    }

    [Fact]
    public async Task Cards_share_tags_and_deleting_a_card_removes_only_its_links()
    {
        var (deck, cards) = await factory.CreateDeckAsync("S" + Guid.NewGuid().ToString("N")[..6], 2);
        var tag = "spolecny_" + Guid.NewGuid().ToString("N")[..6];
        using var admin = await factory.AdminClientAsync();
        foreach (var card in cards)
        {
            await admin.PutAsJsonAsync($"/api/admin/decks/{deck}/cards/{card}", new { question = "Q", answer = "A", sortOrder = 0, tags = new[] { tag } }, Ct);
        }

        await admin.DeleteAsync($"/api/admin/decks/{deck}/cards/{cards[0]}", Ct);

        await factory.WithDbAsync(async db =>
        {
            Assert.Equal(1, await db.Tags.CountAsync(t => t.Name == tag, Ct));
            Assert.Equal([cards[1]], await db.CardTags.Where(ct => db.Tags.Any(t => t.Id == ct.TagId && t.Name == tag)).Select(ct => ct.CardId).ToListAsync(Ct));
        });
    }

    [Fact]
    public async Task Yaml_exports_previews_and_applies_tags()
    {
        var (deck, cards) = await factory.CreateDeckAsync("Y" + Guid.NewGuid().ToString("N")[..6], 2);
        using var admin = await factory.AdminClientAsync();
        await admin.PutAsJsonAsync($"/api/admin/decks/{deck}/cards/{cards[0]}", new { question = "Q1", answer = "A1", sortOrder = 0, tags = OldTag }, Ct);
        var export = await (await admin.GetAsync($"/api/admin/decks/{deck}/yaml", Ct)).Content.ReadAsStringAsync(Ct);
        Assert.Contains("    answer: A1\n    tags: [stary]\n", export, StringComparison.Ordinal);

        // Only the tags change: the first card swaps its tag, the second gets two.
        var yaml = export.Replace("tags: [stary]", "tags: [novy]", StringComparison.Ordinal)
            .Replace("    answer: Odpověď 2\n", "    answer: Odpověď 2\n    tags: ai_gen ; prednaska_01\n", StringComparison.Ordinal);
        var preview = await (await admin.PostAsJsonAsync($"/api/admin/decks/{deck}/yaml/preview", new { yaml }, Ct)).ReadNodeAsync();

        Assert.True((bool)preview["valid"]!);
        Assert.Equal(2, (int)preview["counts"]!["changed"]!);
        var first = preview["changed"]![0]!;
        Assert.Equal(["tags"], first["fields"]!.AsArray().Select(f => (string?)f));
        Assert.Equal(["stary"], Tags(first["before"]!));
        Assert.Equal(["novy"], Tags(first["after"]!));
        Assert.Null(first["before"]!["question"]);

        var applied = await admin.PutAsJsonAsync($"/api/admin/decks/{deck}/yaml", new { yaml, baseHash = (string)preview["baseHash"]! }, Ct);
        Assert.Equal(HttpStatusCode.OK, applied.StatusCode);
        var list = await (await admin.GetAsync($"/api/admin/decks/{deck}/cards", Ct)).ReadNodeAsync();
        Assert.Equal([["novy"], ["ai_gen", "prednaska_01"]], list.AsArray().Select(c => Tags(c!).ToArray()));

        // The new export round-trips with no changes.
        var again = await (await admin.GetAsync($"/api/admin/decks/{deck}/yaml", Ct)).Content.ReadAsStringAsync(Ct);
        var noChange = await (await admin.PostAsJsonAsync($"/api/admin/decks/{deck}/yaml/preview", new { yaml = again }, Ct)).ReadNodeAsync();
        Assert.Equal(0, (int)noChange["counts"]!["changed"]!);
    }

    [Fact]
    public async Task Yaml_import_creates_a_deck_with_tags()
    {
        using var admin = await factory.AdminClientAsync();
        var yaml = "deck:\n  name: Tagovaný\ncards:\n  - question: Q1\n    answer: A1\n    tags: [ai_gen, prednaska_01]\n  - question: Q2\n    answer: A2\n";

        var created = await (await admin.PostAsJsonAsync("/api/admin/decks/import", new { yaml }, Ct)).ReadNodeAsync();

        var list = await (await admin.GetAsync($"/api/admin/decks/{(int)created["id"]!}/cards", Ct)).ReadNodeAsync();
        Assert.Equal([["ai_gen", "prednaska_01"], []], list.AsArray().Select(c => Tags(c!).ToArray()));
    }

    private static List<string?> Tags(JsonNode node) => node["tags"]!.AsArray().Select(t => (string?)t).ToList();
}
