using System.Net;
using System.Net.Http.Json;
using Microsoft.EntityFrameworkCore;
using Quizly.Domain;
using Quizly.Tests.Infrastructure;

namespace Quizly.Tests.Api;

/// <summary>Těžké and Snadné next to Vím / Nevím (#19, docs/api.md §6).</summary>
public sealed class FourRatingsTests(QuizlyFactory factory) : IClassFixture<QuizlyFactory>
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task Hard_and_easy_run_fsrs_count_as_correct_and_pay_like_know()
    {
        var user = await factory.CreateUserAsync();
        var (deck, cards) = await factory.CreateDeckAsync("F" + Guid.NewGuid().ToString("N")[..6], 3);
        using var app = await factory.AppClientAsync(user);

        var response = await app.PostAsJsonAsync("/api/reviews", new
        {
            reviews = new[]
            {
                new { id = Guid.NewGuid(), cardId = cards[0], rating = "hard" },
                new { id = Guid.NewGuid(), cardId = cards[1], rating = "easy" },
                new { id = Guid.NewGuid(), cardId = cards[2], rating = "dontKnow" },
            },
        }, Ct);
        var body = await response.ReadNodeAsync();

        Assert.Equal([10, 10, 2], body["results"]!.AsArray().Select(r => (int)r!["pointsAwarded"]!));
        Assert.Equal((3, 2), ((int)body["summary"]!["today"]!["graded"]!, (int)body["summary"]!["today"]!["correct"]!));
        Assert.Equal((10, 2, 10, 10), ((int)body["points"]!["know"]!, (int)body["points"]!["dontKnow"]!,
            (int)body["points"]!["hard"]!, (int)body["points"]!["easy"]!));

        await factory.WithDbAsync(async db =>
        {
            var states = await db.CardStates.Where(s => s.UserId == user.Id).OrderBy(s => s.CardId).ToListAsync(Ct);
            // py-fsrs 6.3.2: Hard on a new card stays on step 0; Easy skips the learning steps.
            Assert.Equal((FsrsState.Learning, (short?)0), (states[0].State, states[0].Step));
            Assert.Equal(FsrsState.Review, states[1].State);
            var logs = await db.ReviewLogs.Where(r => r.UserId == user.Id).Select(r => r.Rating).ToListAsync(Ct);
            Assert.Equal([Rating.Again, Rating.Hard, Rating.Easy], logs.Order());
        });

        // The deck detail counts Těžké and Snadné as Vím.
        var deckCards = await (await app.GetAsync($"/api/decks/{deck}/cards", Ct)).ReadNodeAsync();
        Assert.Equal([1, 1, 0], deckCards["cards"]!.AsArray().Select(c => (int)c!["knowCount"]!));
        var stats = await (await app.GetAsync($"/api/stats?deckId={deck}", Ct)).ReadNodeAsync();
        Assert.Equal(66, (int)stats["tiles"]!["successRate30d"]!);
    }

    [Fact]
    public async Task The_four_buttons_setting_is_saved_and_off_by_default()
    {
        var user = await factory.CreateUserAsync();
        using var app = await factory.AppClientAsync(user);

        var settings = await (await app.GetAsync("/api/me/settings", Ct)).ReadNodeAsync();
        Assert.False((bool)settings["fourRatings"]!);

        settings["fourRatings"] = true;
        var saved = await app.PutAsJsonAsync("/api/me/settings", settings, Ct);
        Assert.Equal(HttpStatusCode.OK, saved.StatusCode);
        Assert.True((bool)(await (await app.GetAsync("/api/me/settings", Ct)).ReadNodeAsync())["fourRatings"]!);
        // The session tells the app which buttons to show.
        Assert.True((bool)(await (await app.GetAsync("/api/session", Ct)).ReadNodeAsync())["fourRatings"]!);

        // An older app that doesn't know the field turns it off when it saves its settings.
        settings.AsObject().Remove("fourRatings");
        await app.PutAsJsonAsync("/api/me/settings", settings, Ct);
        Assert.False((bool)(await (await app.GetAsync("/api/me/settings", Ct)).ReadNodeAsync())["fourRatings"]!);
    }
}
