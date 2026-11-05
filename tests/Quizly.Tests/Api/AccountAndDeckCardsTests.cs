using System.Net;
using System.Net.Http.Json;
using Quizly.Application.Auth;
using Quizly.Domain;
using Quizly.Tests.Infrastructure;

namespace Quizly.Tests.Api;

/// <summary>Changing my password and browsing a deck's cards (docs/api.md §3–4).</summary>
public sealed class AccountAndDeckCardsTests(QuizlyFactory factory) : IClassFixture<QuizlyFactory>
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task Changing_the_password_keeps_this_device_and_signs_out_the_others()
    {
        var user = await factory.CreateUserAsync();
        var phone = await factory.LoginAsync(user.Username, user.Password);
        var tablet = await factory.LoginAsync(user.Username, user.Password);
        using var app = factory.AppClient(phone.AccessToken);

        var response = await app.PostAsJsonAsync("/api/me/password",
            new { currentPassword = user.Password, newPassword = "nove-heslo-123" }, Ct);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var fresh = (await response.Content.ReadFromJsonAsync<TokenResponse>(Json.Options, Ct))!;
        Assert.Equal(user.Id, fresh.User.Id);

        using var anon = factory.CreateClient();
        // The other device's token is gone: a plain refreshTokenInvalid, not a theft alarm…
        await (await anon.PostAsJsonAsync("/api/auth/refresh", new { refreshToken = tablet.RefreshToken }, Ct))
            .AssertProblemAsync(HttpStatusCode.Unauthorized, "refreshTokenInvalid");
        await (await anon.PostAsJsonAsync("/api/auth/refresh", new { refreshToken = phone.RefreshToken }, Ct))
            .AssertProblemAsync(HttpStatusCode.Unauthorized, "refreshTokenInvalid");
        // …so this device's new token still rotates.
        var rotated = await anon.PostAsJsonAsync("/api/auth/refresh", new { refreshToken = fresh.RefreshToken }, Ct);
        Assert.Equal(HttpStatusCode.OK, rotated.StatusCode);

        var oldLogin = await anon.PostAsJsonAsync("/api/auth/login", new { username = user.Username, password = user.Password }, Ct);
        await oldLogin.AssertProblemAsync(HttpStatusCode.Unauthorized, "invalidCredentials");
        var newLogin = await factory.LoginAsync(user.Username, "nove-heslo-123");
        Assert.Equal(user.Id, newLogin.User.Id);
    }

    [Theory]
    [InlineData("wrong-current", "nove-heslo-123", "currentPassword")]
    [InlineData(null, "kratke", "newPassword")]
    [InlineData(null, null, "newPassword")]
    public async Task Change_password_validates_the_current_and_the_new_password(string? current, string? next, string field)
    {
        var user = await factory.CreateUserAsync();
        using var app = await factory.AppClientAsync(user);

        var response = await app.PostAsJsonAsync("/api/me/password",
            new { currentPassword = current ?? user.Password, newPassword = next ?? user.Password }, Ct);

        var problem = await response.AssertProblemAsync(HttpStatusCode.BadRequest, "validation");
        Assert.NotNull(problem["errors"]![field]);
        await factory.LoginAsync(user.Username, user.Password); // unchanged
    }

    [Fact]
    public async Task Wrong_current_passwords_count_toward_the_login_throttle()
    {
        var user = await factory.CreateUserAsync();
        using var app = await factory.AppClientAsync(user);
        for (var i = 0; i < 5; i++)
        {
            var wrong = await app.PostAsJsonAsync("/api/me/password", new { currentPassword = "nope-nope", newPassword = "nove-heslo-123" }, Ct);
            Assert.Equal(HttpStatusCode.BadRequest, wrong.StatusCode);
        }

        var blocked = await app.PostAsJsonAsync("/api/me/password", new { currentPassword = user.Password, newPassword = "nove-heslo-123" }, Ct);
        await blocked.AssertProblemAsync(HttpStatusCode.TooManyRequests, "rateLimited");
    }

    [Fact]
    public async Task Deck_cards_lists_every_card_in_order_with_my_status()
    {
        var user = await factory.CreateUserAsync();
        var (deckId, cards) = await factory.CreateDeckAsync("K" + Guid.NewGuid().ToString("N")[..6], 3);
        using var app = await factory.AppClientAsync(user);
        await StudyTests.ReviewAsync(app, (cards[0], "know"));
        await factory.WithDbAsync(async db =>
        {
            db.CardStates.Add(new CardState
            {
                UserId = user.Id,
                CardId = cards[1],
                State = FsrsState.Review,
                Stability = 30,
                Difficulty = 5,
                Due = factory.Time.GetUtcNow().UtcDateTime.AddDays(30),
                LastReview = factory.Time.GetUtcNow().UtcDateTime,
                FirstReview = factory.Time.GetUtcNow().UtcDateTime,
                Reps = 3,
                Lapses = 2,
            });
            await db.SaveChangesAsync(Ct);
        });

        var response = await app.GetAsync($"/api/decks/{deckId}/cards", Ct);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.ReadNodeAsync();
        Assert.Equal(deckId, (int)body["deck"]!["id"]!);
        Assert.Equal(3, (int)body["deck"]!["totalCards"]!);
        Assert.Equal((33, 33, 1), ((int)body["deck"]!["masteredPercent"]!, (int)body["deck"]!["learningPercent"]!, (int)body["deck"]!["unseenCards"]!));
        var items = body["cards"]!.AsArray();
        Assert.Equal(cards, items.Select(c => (int)c!["id"]!));
        Assert.Equal(["learning", "mastered", "new"], items.Select(c => (string?)c!["status"]));
        Assert.All(items, c => Assert.False(string.IsNullOrEmpty((string?)c!["answer"])));
        // Progress per card: stability out of 21 days (Vím once = 2.3065 days → 10 %), answers, next review.
        Assert.Equal([10, 100, 0], items.Select(c => (int)c!["masteryPercent"]!));
        Assert.Equal([(1, 0), (0, 0), (0, 0)], items.Select(c => ((int)c!["knowCount"]!, (int)c!["dontKnowCount"]!)));
        Assert.Equal([0, 2, 0], items.Select(c => (int)c!["lapses"]!));
        Assert.NotNull((string?)items[0]!["nextReview"]);
        Assert.Null(items[2]!["nextReview"]);

        await (await app.GetAsync("/api/decks/999999/cards", Ct)).AssertProblemAsync(HttpStatusCode.NotFound, "notFound");
    }
}
