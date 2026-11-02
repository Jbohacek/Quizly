using System.Net;
using System.Net.Http.Json;
using System.Text.Json.Nodes;
using Microsoft.EntityFrameworkCore;
using Quizly.Domain;
using Quizly.Tests.Infrastructure;

namespace Quizly.Tests.Api;

/// <summary>Session queue, reviews, idempotency and FSRS persistence (docs/api.md §4–6).</summary>
public sealed class StudyTests(QuizlyFactory factory) : IClassFixture<QuizlyFactory>
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task Session_lists_due_cards_first_then_new_cards_up_to_the_daily_allowance()
    {
        var user = await factory.CreateUserAsync(newCardsPerDay: 3);
        var (deckA, cardsA) = await factory.CreateDeckAsync("A" + Guid.NewGuid().ToString("N")[..6], 4, sortOrder: -20);
        var (deckB, cardsB) = await factory.CreateDeckAsync("B" + Guid.NewGuid().ToString("N")[..6], 2, sortOrder: -10);
        using var app = await factory.AppClientAsync(user);

        var first = await GetSessionAsync(app);
        Assert.Equal(cardsA.Take(3), CardIds(first));
        Assert.All(first["cards"]!.AsArray(), c => Assert.Equal("new", (string?)c!["kind"]));

        await ReviewAsync(app, (cardsA[0], "know"), (cardsA[1], "dontKnow"));
        var right = await GetSessionAsync(app);
        Assert.Equal([cardsA[2]], CardIds(right)); // learning cards aren't due yet, allowance 1 left

        factory.Time.Advance(TimeSpan.FromMinutes(11));
        using var later = await factory.AppClientAsync(user);
        var afterSteps = await GetSessionAsync(later);
        // Nevím was due after 1 min, Vím after 10 min: most overdue first, then the one new card left.
        Assert.Equal([cardsA[1], cardsA[0], cardsA[2]], CardIds(afterSteps));
        Assert.Equal((2, 1), ((int)afterSteps["dueCount"]!, (int)afterSteps["newCount"]!));
        Assert.Equal("learning", (string?)afterSteps["cards"]![0]!["kind"]);

        var onlyB = await GetSessionAsync(later, deckB);
        Assert.Equal([cardsB[0]], CardIds(onlyB)); // new allowance is shared across decks

        var decks = await (await later.GetAsync("/api/decks", Ct)).ReadNodeAsync();
        Assert.Equal(1, (int)decks["newAllowanceLeft"]!);
        var a = decks["items"]!.AsArray().First(d => (int)d!["id"]! == deckA)!;
        Assert.Equal((4, 2, 1, 0), ((int)a["totalCards"]!, (int)a["dueNow"]!, (int)a["newAvailable"]!, (int)a["masteredPercent"]!));
        Assert.Equal((50, 2), ((int)a["learningPercent"]!, (int)a["unseenCards"]!));

        await (await later.GetAsync("/api/session?deckId=999999", Ct)).AssertProblemAsync(HttpStatusCode.NotFound, "notFound");
    }

    [Fact]
    public async Task Extra_new_cards_go_past_the_daily_allowance()
    {
        var user = await factory.CreateUserAsync(newCardsPerDay: 1);
        var (deck, cards) = await factory.CreateDeckAsync("X" + Guid.NewGuid().ToString("N")[..6], 4);
        using var app = await factory.AppClientAsync(user);

        await ReviewAsync(app, (cards[0], "know"));
        Assert.Empty(CardIds(await GetSessionAsync(app, deck)));

        var more = await (await app.GetAsync($"/api/session?deckId={deck}&extraNew=2", Ct)).ReadNodeAsync();
        Assert.Equal([cards[1], cards[2]], CardIds(more));
        Assert.Equal(2, (int)more["newCount"]!);

        await (await app.GetAsync("/api/session?extraNew=51", Ct)).AssertProblemAsync(HttpStatusCode.BadRequest, "validation");
    }

    [Fact]
    public async Task Review_applies_fsrs_points_and_daily_progress()
    {
        var user = await factory.CreateUserAsync();
        var (_, cards) = await factory.CreateDeckAsync("R" + Guid.NewGuid().ToString("N")[..6], 2);
        using var app = await factory.AppClientAsync(user);

        var response = await ReviewAsync(app, (cards[0], "know"), (cards[1], "dontKnow"));

        var results = response["results"]!.AsArray();
        Assert.Equal(["applied", "applied"], results.Select(r => (string?)r!["status"]));
        Assert.Equal([10, 2], results.Select(r => (int)r!["pointsAwarded"]!));
        Assert.Equal(1.0m, (decimal)results[0]!["multiplier"]!);
        var summary = response["summary"]!;
        Assert.Equal(12, (int)summary["balance"]!);
        Assert.Equal((2, 1, 12, false), ((int)summary["today"]!["graded"]!, (int)summary["today"]!["correct"]!,
            (int)summary["today"]!["points"]!, (bool)summary["today"]!["goalMet"]!));
        Assert.Equal((10, 2), ((int)response["points"]!["know"]!, (int)response["points"]!["dontKnow"]!));

        await factory.WithDbAsync(async db =>
        {
            var states = await db.CardStates.Where(s => s.UserId == user.Id).OrderBy(s => s.CardId).ToListAsync(Ct);
            Assert.Equal((FsrsState.Learning, (short?)1, 2.3065), (states[0].State, states[0].Step, states[0].Stability));
            Assert.Equal((FsrsState.Learning, (short?)0, 0.212), (states[1].State, states[1].Step, states[1].Stability));
            Assert.Equal(TimeSpan.FromMinutes(10), states[0].Due - states[0].LastReview);
            var logs = await db.ReviewLogs.Where(r => r.UserId == user.Id).ToListAsync(Ct);
            Assert.All(logs, l => Assert.Null(l.StateBefore));
            Assert.Equal(2, await db.PointsEntries.CountAsync(p => p.UserId == user.Id && p.Reason == PointsReason.Review, Ct));
        });
    }

    [Fact]
    public async Task Repeated_review_ids_are_duplicates_and_award_nothing_twice()
    {
        var user = await factory.CreateUserAsync();
        var other = await factory.CreateUserAsync();
        var (_, cards) = await factory.CreateDeckAsync("I" + Guid.NewGuid().ToString("N")[..6], 1);
        using var app = await factory.AppClientAsync(user);
        using var otherApp = await factory.AppClientAsync(other);
        var id = Guid.NewGuid();

        await ReviewAsync(app, [(id, cards[0], "know")]);
        var retry = await ReviewAsync(app, [(id, cards[0], "know"), (Guid.NewGuid(), 999999, "know")]);
        var stolen = await ReviewAsync(otherApp, [(id, cards[0], "know")]);

        Assert.Equal(("duplicate", 10), ((string?)retry["results"]![0]!["status"], (int)retry["results"]![0]!["pointsAwarded"]!));
        Assert.Equal(("rejected", "cardNotFound"), ((string?)retry["results"]![1]!["status"], (string?)retry["results"]![1]!["code"]));
        Assert.Equal(10, (int)retry["summary"]!["balance"]!);
        Assert.Equal(1, (int)retry["summary"]!["today"]!["graded"]!);
        Assert.Equal(("rejected", "idConflict"), ((string?)stolen["results"]![0]!["status"], (string?)stolen["results"]![0]!["code"]));
        Assert.Equal(0, (int)stolen["summary"]!["balance"]!);
    }

    [Theory]
    [InlineData("{\"reviews\":[]}")]
    [InlineData("{\"reviews\":[{\"id\":\"00000000-0000-0000-0000-000000000000\",\"cardId\":1,\"rating\":\"know\"}]}")]
    [InlineData("{\"reviews\":[{\"id\":\"6f1c2a7e-3b0c-4f6e-9d51-0a2b7c9e1f42\",\"cardId\":1,\"rating\":\"know\"},{\"id\":\"6f1c2a7e-3b0c-4f6e-9d51-0a2b7c9e1f42\",\"cardId\":1,\"rating\":\"know\"}]}")]
    [InlineData("{\"reviews\":[{\"id\":\"6f1c2a7e-3b0c-4f6e-9d51-0a2b7c9e1f42\",\"cardId\":1,\"rating\":\"maybe\"}]}")]
    public async Task Invalid_batches_are_validation_errors(string body)
    {
        var user = await factory.CreateUserAsync();
        using var app = await factory.AppClientAsync(user);

        var response = await app.PostAsync("/api/reviews", new StringContent(body, System.Text.Encoding.UTF8, "application/json"), Ct);

        await response.AssertProblemAsync(HttpStatusCode.BadRequest, "validation");
    }

    [Fact]
    public async Task Batch_over_fifty_answers_is_rejected()
    {
        var user = await factory.CreateUserAsync();
        using var app = await factory.AppClientAsync(user);
        var reviews = Enumerable.Range(0, 51).Select(_ => new { id = Guid.NewGuid(), cardId = 1, rating = "know" });

        var response = await app.PostAsJsonAsync("/api/reviews", new { reviews }, Ct);

        await response.AssertProblemAsync(HttpStatusCode.BadRequest, "validation");
    }

    [Fact]
    public async Task Lapse_in_review_counts_and_relearns()
    {
        var user = await factory.CreateUserAsync();
        var (_, cards) = await factory.CreateDeckAsync("L" + Guid.NewGuid().ToString("N")[..6], 1);
        using var app = await factory.AppClientAsync(user);

        await ReviewAsync(app, (cards[0], "know"), (cards[0], "know")); // graduates to Review (same batch, 1 µs apart)
        factory.Time.Advance(TimeSpan.FromMinutes(1));
        await ReviewAsync(app, (cards[0], "dontKnow"));

        await factory.WithDbAsync(async db =>
        {
            var state = await db.CardStates.SingleAsync(s => s.UserId == user.Id, Ct);
            Assert.Equal((FsrsState.Relearning, 3, 1), (state.State, state.Reps, state.Lapses));
            var last = await db.ReviewLogs.Where(r => r.UserId == user.Id).OrderByDescending(r => r.ReviewedAt).FirstAsync(Ct);
            Assert.Equal(FsrsState.Review, last.StateBefore);
        });
    }

    private static async Task<JsonNode> GetSessionAsync(HttpClient app, int? deckId = null)
    {
        var response = await app.GetAsync(deckId is null ? "/api/session" : $"/api/session?deckId={deckId}", Ct);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        return await response.ReadNodeAsync();
    }

    private static List<int> CardIds(JsonNode session) =>
        session["cards"]!.AsArray().Select(c => (int)c!["cardId"]!).ToList();

    internal static Task<JsonNode> ReviewAsync(HttpClient app, params (int CardId, string Rating)[] answers) =>
        ReviewAsync(app, answers.Select(a => (Guid.NewGuid(), a.CardId, a.Rating)).ToArray());

    internal static async Task<JsonNode> ReviewAsync(HttpClient app, (Guid Id, int CardId, string Rating)[] answers)
    {
        var response = await app.PostAsJsonAsync("/api/reviews",
            new { reviews = answers.Select(a => new { id = a.Id, cardId = a.CardId, rating = a.Rating }) }, Ct);
        var body = await response.Content.ReadAsStringAsync(Ct);
        Assert.True(response.StatusCode == HttpStatusCode.OK, body);
        return JsonNode.Parse(body)!;
    }
}
