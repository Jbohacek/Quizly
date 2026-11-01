using System.Net;
using System.Net.Http.Json;
using System.Text.Json.Nodes;
using Microsoft.EntityFrameworkCore;
using Quizly.Domain;
using Quizly.Tests.Infrastructure;

namespace Quizly.Tests.Api;

/// <summary>Deck YAML against the database: preview, apply, conflicts, deletes, new-deck import (docs/yaml-format.md §5–8).</summary>
public sealed class YamlTests(QuizlyFactory factory) : IClassFixture<QuizlyFactory>
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task Export_and_reimport_without_edits_changes_nothing()
    {
        var (deckId, _) = await factory.CreateDeckAsync("Y" + Guid.NewGuid().ToString("N")[..6], 3);
        using var admin = await factory.AdminClientAsync();

        var export = await admin.GetAsync($"/api/admin/decks/{deckId}/yaml", Ct);
        var yaml = await export.Content.ReadAsStringAsync(Ct);
        var preview = await PreviewAsync(admin, deckId, yaml);

        Assert.Equal("text/yaml", export.Content.Headers.ContentType?.MediaType);
        Assert.StartsWith("# Quizly balíček · formát v1\n", yaml, StringComparison.Ordinal);
        Assert.True((bool)preview["valid"]!);
        Assert.Equal((0, 0, 0, 3), Counts(preview));
        Assert.False((bool)preview["orderChanged"]!);
        Assert.False((bool)preview["deck"]!["nameChanged"]!);
    }

    [Fact]
    public async Task Preview_lists_new_changed_and_deleted_cards_with_progress_counts()
    {
        var (deckId, ids) = await factory.CreateDeckAsync("D" + Guid.NewGuid().ToString("N")[..6], 3);
        var user = await factory.CreateUserAsync();
        using (var app = await factory.AppClientAsync(user))
        {
            await StudyTests.ReviewAsync(app, (ids[2], "know"));
        }

        using var admin = await factory.AdminClientAsync();
        var yaml = $"""
            deck:
              name: Přejmenovaný
              description: Nový popis
            cards:
              - id: {ids[1]}
                question: Otázka 2 upravená
                answer: Odpověď 2
              - id: {ids[0]}
                question: {(await CardAsync(ids[0])).Question}
                answer: {(await CardAsync(ids[0])).Answer}
              - question: Úplně nová karta
                answer: Nová odpověď
            """;

        var preview = await PreviewAsync(admin, deckId, yaml);

        Assert.True((bool)preview["valid"]!);
        Assert.Equal((1, 1, 1, 1), Counts(preview));
        Assert.True((bool)preview["orderChanged"]!);
        Assert.Equal((true, true, false), ((bool)preview["deck"]!["nameChanged"]!, (bool)preview["deck"]!["descriptionChanged"]!, (bool)preview["deck"]!["colorChanged"]!));
        var changed = preview["changed"]![0]!;
        Assert.Equal((ids[1], 5, "question"), ((int)changed["id"]!, (int)changed["line"]!, (string?)changed["fields"]![0]));
        Assert.Null(changed["before"]!["answer"]);
        Assert.Equal((11, "Úplně nová karta"), ((int)preview["new"]![0]!["line"]!, (string?)preview["new"]![0]!["question"]));
        var deleted = preview["deleted"]![0]!;
        Assert.Equal((ids[2], 1), ((int)deleted["id"]!, (int)deleted["usersWithProgress"]!));
    }

    [Fact]
    public async Task Apply_needs_the_confirmed_deletes_and_keeps_progress_of_edited_cards()
    {
        var (deckId, ids) = await factory.CreateDeckAsync("A" + Guid.NewGuid().ToString("N")[..6], 2);
        var user = await factory.CreateUserAsync();
        using (var app = await factory.AppClientAsync(user))
        {
            await StudyTests.ReviewAsync(app, (ids[0], "know"), (ids[1], "know"));
        }

        using var admin = await factory.AdminClientAsync();
        var yaml = $"deck:\n  name: Upravený\ncards:\n  - id: {ids[0]}\n    question: Nové znění\n    answer: |\n      Dvě\n      řádky\n  - question: Přidaná\n    answer: Ano\n";
        var preview = await PreviewAsync(admin, deckId, yaml);
        var baseHash = (string)preview["baseHash"]!;

        var unconfirmed = await admin.PutAsJsonAsync($"/api/admin/decks/{deckId}/yaml", new { yaml, baseHash, confirmDeleteIds = Array.Empty<int>() }, Ct);
        await unconfirmed.AssertProblemAsync(HttpStatusCode.UnprocessableEntity, "deleteNotConfirmed");

        var applied = await admin.PutAsJsonAsync($"/api/admin/decks/{deckId}/yaml", new { yaml, baseHash, confirmDeleteIds = new[] { ids[1] } }, Ct);

        Assert.Equal(HttpStatusCode.OK, applied.StatusCode);
        var body = await applied.ReadNodeAsync();
        Assert.Equal((1, 1, 1, 0), Counts(body));
        Assert.Contains("name: Upravený", (string)body["yaml"]!, StringComparison.Ordinal);
        await factory.WithDbAsync(async db =>
        {
            var cards = await db.Cards.Where(c => c.DeckId == deckId).OrderBy(c => c.SortOrder).ToListAsync(Ct);
            Assert.Equal(["Nové znění", "Přidaná"], cards.Select(c => c.Question));
            Assert.Equal("Dvě\nřádky", cards[0].Answer);
            Assert.Equal([0, 1], cards.Select(c => c.SortOrder));
            Assert.True(await db.CardStates.AnyAsync(s => s.CardId == ids[0], Ct));   // edited card keeps progress
            Assert.False(await db.CardStates.AnyAsync(s => s.CardId == ids[1], Ct));  // deleted card's progress is gone
        });

        // The base changed, so the old preview can't be applied again.
        var stale = await admin.PutAsJsonAsync($"/api/admin/decks/{deckId}/yaml", new { yaml, baseHash, confirmDeleteIds = Array.Empty<int>() }, Ct);
        await stale.AssertProblemAsync(HttpStatusCode.Conflict, "concurrencyConflict");
    }

    [Fact]
    public async Task Ids_of_other_decks_or_unknown_cards_are_errors()
    {
        var (deckId, _) = await factory.CreateDeckAsync("O" + Guid.NewGuid().ToString("N")[..6], 1);
        var (_, otherIds) = await factory.CreateDeckAsync("Cizí balíček", 1);
        using var admin = await factory.AdminClientAsync();
        var yaml = $"deck:\n  name: X\ncards:\n  - id: {otherIds[0]}\n    question: q\n    answer: a\n  - id: 999999\n    question: q\n    answer: a\n";

        var preview = await PreviewAsync(admin, deckId, yaml);
        var apply = await admin.PutAsJsonAsync($"/api/admin/decks/{deckId}/yaml", new { yaml, baseHash = "x" }, Ct);

        Assert.False((bool)preview["valid"]!);
        var errors = preview["errors"]!.AsArray();
        Assert.Equal(("foreignId", 4), ((string?)errors[0]!["code"], (int)errors[0]!["line"]!));
        Assert.Contains("Cizí balíček", (string)errors[0]!["message"]!, StringComparison.Ordinal);
        Assert.Equal(("unknownId", 7), ((string?)errors[1]!["code"], (int)errors[1]!["line"]!));
        var problem = await apply.AssertProblemAsync(HttpStatusCode.UnprocessableEntity, "yamlInvalid");
        Assert.Equal(2, problem["yamlErrors"]!.AsArray().Count);
    }

    [Fact]
    public async Task Syntax_errors_come_back_in_the_preview()
    {
        var (deckId, _) = await factory.CreateDeckAsync("E" + Guid.NewGuid().ToString("N")[..6], 1);
        using var admin = await factory.AdminClientAsync();

        var preview = await PreviewAsync(admin, deckId, "deck:\n  name: A\n   bad: x\ncards: []\n");

        Assert.False((bool)preview["valid"]!);
        Assert.Equal(("syntax", 3), ((string?)preview["errors"]![0]!["code"], (int)preview["errors"]![0]!["line"]!));
        Assert.Null(preview["baseHash"]);
    }

    [Fact]
    public async Task Import_creates_a_new_deck_and_refuses_ids()
    {
        using var admin = await factory.AdminClientAsync();
        var yaml = "deck:\n  name: Importovaný\n  color: \"#8fc7f0\"\ncards:\n  - question: Q1\n    answer: A1\n  - question: Q2\n    answer: A2\n";

        var preview = await (await admin.PostAsJsonAsync("/api/admin/decks/import/preview", new { yaml }, Ct)).ReadNodeAsync();
        var created = await admin.PostAsJsonAsync("/api/admin/decks/import", new { yaml }, Ct);
        var withIds = await admin.PostAsJsonAsync("/api/admin/decks/import", new { yaml = yaml.Replace("  - question: Q1", "  - id: 5\n    question: Q1", StringComparison.Ordinal) }, Ct);

        Assert.Equal(2, (int)preview["counts"]!["new"]!);
        Assert.Equal(HttpStatusCode.Created, created.StatusCode);
        var deck = await created.ReadNodeAsync();
        Assert.Equal(("Importovaný", "#8FC7F0", 2), ((string?)deck["name"], (string?)deck["color"], (int)deck["cardCount"]!));
        var problem = await withIds.AssertProblemAsync(HttpStatusCode.UnprocessableEntity, "yamlInvalid");
        Assert.Equal("idInNewDeck", (string?)problem["yamlErrors"]![0]!["code"]);
    }

    [Fact]
    public async Task Delete_impact_counts_cards_and_users()
    {
        var (deckId, ids) = await factory.CreateDeckAsync("I" + Guid.NewGuid().ToString("N")[..6], 2);
        foreach (var _ in Enumerable.Range(0, 2))
        {
            var user = await factory.CreateUserAsync();
            using var app = await factory.AppClientAsync(user);
            await StudyTests.ReviewAsync(app, (ids[0], "know"), (ids[1], "dontKnow"));
        }

        using var admin = await factory.AdminClientAsync();
        var impact = await (await admin.GetAsync($"/api/admin/decks/{deckId}/delete-impact", Ct)).ReadNodeAsync();

        Assert.Equal((2, 2), ((int)impact["cards"]!, (int)impact["usersWithProgress"]!));
    }

    [Fact]
    public async Task Overview_shows_tiles_pending_claims_and_users_today()
    {
        var user = await factory.CreateUserAsync(dailyGoal: 2);
        var (_, ids) = await factory.CreateDeckAsync("V" + Guid.NewGuid().ToString("N")[..6], 1);
        using var app = await factory.AppClientAsync(user);
        await StudyTests.ReviewAsync(app, (ids[0], "know"), (ids[0], "dontKnow"));
        using var admin = await factory.AdminClientAsync();
        var item = await (await admin.PostAsJsonAsync("/api/admin/shop-items", new { name = "Odměna", description = "", price = 5, initialStock = 1 }, Ct)).ReadNodeAsync();
        await app.PostAsJsonAsync($"/api/shop/{(int)item["id"]!}/claim", new { requestId = Guid.NewGuid() }, Ct);

        var overview = await (await admin.GetAsync("/api/admin/overview", Ct)).ReadNodeAsync();

        Assert.True((int)overview["tiles"]!["pendingClaims"]! >= 1);
        Assert.True((int)overview["tiles"]!["activeUsersToday"]! >= 1);
        Assert.Contains(overview["pendingClaims"]!.AsArray(), c => (string?)c!["username"] == user.Username);
        var row = overview["usersToday"]!.AsArray().Single(u => (string?)u!["username"] == user.Username)!;
        Assert.Equal((2, 2, true, 12, 7), ((int)row["graded"]!, (int)row["goal"]!, (bool)row["goalMet"]!, (int)row["pointsToday"]!, (int)row["balance"]!));
        Assert.Equal(1, (int)row["streak"]!);
    }

    private static async Task<JsonNode> PreviewAsync(HttpClient admin, int deckId, string yaml)
    {
        var response = await admin.PostAsJsonAsync($"/api/admin/decks/{deckId}/yaml/preview", new { yaml }, Ct);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        return await response.ReadNodeAsync();
    }

    private static (int New, int Changed, int Deleted, int Unchanged) Counts(JsonNode body) =>
        ((int)body["counts"]!["new"]!, (int)body["counts"]!["changed"]!, (int)body["counts"]!["deleted"]!, (int)body["counts"]!["unchanged"]!);

    private async Task<Card> CardAsync(int id)
    {
        Card? card = null;
        await factory.WithDbAsync(async db => card = await db.Cards.AsNoTracking().SingleAsync(c => c.Id == id, Ct));
        return card!;
    }
}
