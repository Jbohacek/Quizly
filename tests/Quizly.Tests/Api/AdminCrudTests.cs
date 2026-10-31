using System.Net;
using System.Net.Http.Json;
using System.Text;
using Microsoft.EntityFrameworkCore;
using Quizly.Application.Decks;
using Quizly.Application.Shop;
using Quizly.Application.Users;
using Quizly.Domain;
using Quizly.Tests.Infrastructure;

namespace Quizly.Tests.Api;

public sealed class AdminCrudTests(QuizlyFactory factory) : IClassFixture<QuizlyFactory>
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task Users_can_be_created_listed_and_edited()
    {
        using var admin = await factory.AdminClientAsync();

        var create = await admin.PostAsJsonAsync("/api/admin/users",
            new { username = "  Petra7 ", displayName = " Petra ", dailyGoal = 30, newCardsPerDay = 8 }, Ct);

        Assert.Equal(HttpStatusCode.Created, create.StatusCode);
        var created = await create.ReadAsync<CreatedUserResponse>();
        Assert.Equal($"/api/admin/users/{created.User.Id}", create.Headers.Location?.ToString());
        Assert.Equal("petra7", created.User.Username);
        Assert.Equal("Petra", created.User.DisplayName);
        Assert.Equal(30, created.User.DailyGoal);
        Assert.Equal(8, created.User.NewCardsPerDay);
        Assert.Equal(12, created.Password.Length);
        Assert.True(created.User.IsActive);
        Assert.Equal(0, created.User.Balance);
        Assert.Null(created.User.SuccessRate);

        var list = await (await admin.GetAsync("/api/admin/users", Ct)).ReadAsync<List<UserResponse>>();
        Assert.Contains(list, u => u.Id == created.User.Id);

        var update = await admin.PutAsJsonAsync($"/api/admin/users/{created.User.Id}",
            new { displayName = "Petra N.", dailyGoal = 25, newCardsPerDay = 0 }, Ct);
        var updated = await update.ReadAsync<UserResponse>();
        Assert.Equal(("Petra N.", 25, 0), (updated.DisplayName, updated.DailyGoal, updated.NewCardsPerDay));
    }

    [Fact]
    public async Task User_with_own_password_can_log_in()
    {
        using var admin = await factory.AdminClientAsync();

        var create = await admin.PostAsJsonAsync("/api/admin/users",
            new { username = "ownpass", displayName = "Own", password = "my-own-password" }, Ct);

        Assert.Equal("my-own-password", (await create.ReadAsync<CreatedUserResponse>()).Password);
        Assert.Equal("ownpass", (await factory.LoginAsync("ownpass", "my-own-password")).User.Username);
    }

    [Theory]
    [InlineData("ab", "username")]
    [InlineData("has space", "username")]
    [InlineData("čeština", "username")]
    public async Task Invalid_username_is_a_validation_error(string username, string field)
    {
        using var admin = await factory.AdminClientAsync();

        var response = await admin.PostAsJsonAsync("/api/admin/users", new { username, displayName = "X" }, Ct);

        var problem = await response.AssertProblemAsync(HttpStatusCode.BadRequest, "validation");
        Assert.NotNull(problem["errors"]?[field]);
    }

    [Fact]
    public async Task Duplicate_username_and_out_of_range_settings_are_reported_together()
    {
        var existing = await factory.CreateUserAsync();
        using var admin = await factory.AdminClientAsync();

        var response = await admin.PostAsJsonAsync("/api/admin/users",
            new { username = existing.Username, displayName = "", dailyGoal = 0, newCardsPerDay = 101, password = "short" }, Ct);

        var problem = await response.AssertProblemAsync(HttpStatusCode.BadRequest, "validation");
        foreach (var field in new[] { "username", "displayName", "dailyGoal", "newCardsPerDay", "password" })
        {
            Assert.NotNull(problem["errors"]?[field]);
        }
    }

    [Fact]
    public async Task Unknown_user_is_not_found()
    {
        using var admin = await factory.AdminClientAsync();

        await (await admin.GetAsync("/api/admin/users/999999", Ct)).AssertProblemAsync(HttpStatusCode.NotFound, "notFound");
        await (await admin.PostAsync("/api/admin/users/999999/deactivate", null, Ct)).AssertProblemAsync(HttpStatusCode.NotFound, "notFound");
    }

    [Fact]
    public async Task Decks_get_defaults_and_validate_color()
    {
        using var admin = await factory.AdminClientAsync();

        var first = await (await admin.PostAsJsonAsync("/api/admin/decks", new { name = "Angličtina" }, Ct)).ReadAsync<DeckResponse>();
        var second = await (await admin.PostAsJsonAsync("/api/admin/decks",
            new { name = "Dějepis", description = "Data a události", color = "#8fc7f0" }, Ct)).ReadAsync<DeckResponse>();
        var badColor = await admin.PostAsJsonAsync("/api/admin/decks", new { name = "X", color = "blue" }, Ct);
        var emptyName = await admin.PostAsJsonAsync("/api/admin/decks", new { name = "   " }, Ct);

        Assert.Equal("#BAD69B", first.Color);
        Assert.Equal("#8FC7F0", second.Color);
        Assert.True(second.SortOrder > first.SortOrder);
        Assert.Equal(0, first.CardCount);
        Assert.NotNull((await badColor.AssertProblemAsync(HttpStatusCode.BadRequest, "validation"))["errors"]?["color"]);
        Assert.NotNull((await emptyName.AssertProblemAsync(HttpStatusCode.BadRequest, "validation"))["errors"]?["name"]);

        var updated = await (await admin.PutAsJsonAsync($"/api/admin/decks/{first.Id}",
            new { name = "Angličtina B2", description = "", color = "#BAD69B", sortOrder = 10 }, Ct)).ReadAsync<DeckResponse>();
        Assert.Equal(("Angličtina B2", 10), (updated.Name, updated.SortOrder));
    }

    [Fact]
    public async Task Cards_keep_order_trim_text_and_check_their_deck()
    {
        using var admin = await factory.AdminClientAsync();
        var deck = await (await admin.PostAsJsonAsync("/api/admin/decks", new { name = "Karty" }, Ct)).ReadAsync<DeckResponse>();
        var otherDeck = await (await admin.PostAsJsonAsync("/api/admin/decks", new { name = "Jiný" }, Ct)).ReadAsync<DeckResponse>();

        var a = await (await admin.PostAsJsonAsync($"/api/admin/decks/{deck.Id}/cards",
            new { question = "  Otázka 1 ", answer = "Řádek 1\r\nŘádek 2\n" }, Ct)).ReadAsync<CardResponse>();
        var b = await (await admin.PostAsJsonAsync($"/api/admin/decks/{deck.Id}/cards",
            new { question = "Otázka 2", answer = "Odpověď 2" }, Ct)).ReadAsync<CardResponse>();

        Assert.Equal("Otázka 1", a.Question);
        Assert.Equal("Řádek 1\nŘádek 2", a.Answer);
        Assert.Equal(a.SortOrder + 1, b.SortOrder);
        var cards = await (await admin.GetAsync($"/api/admin/decks/{deck.Id}/cards", Ct)).ReadAsync<List<CardResponse>>();
        Assert.Equal([a.Id, b.Id], cards.Select(c => c.Id));
        Assert.Equal(2, (await (await admin.GetAsync($"/api/admin/decks/{deck.Id}", Ct)).ReadAsync<DeckResponse>()).CardCount);

        var updated = await (await admin.PutAsJsonAsync($"/api/admin/decks/{deck.Id}/cards/{a.Id}",
            new { question = "Otázka 1 upravená", answer = "Nová odpověď" }, Ct)).ReadAsync<CardResponse>();
        Assert.Equal((a.Id, a.SortOrder), (updated.Id, updated.SortOrder));

        var wrongDeck = await admin.GetAsync($"/api/admin/decks/{otherDeck.Id}/cards/{a.Id}", Ct);
        await wrongDeck.AssertProblemAsync(HttpStatusCode.NotFound, "notFound");
        var tooLong = await admin.PostAsJsonAsync($"/api/admin/decks/{deck.Id}/cards",
            new { question = new string('x', 501), answer = "ok" }, Ct);
        Assert.NotNull((await tooLong.AssertProblemAsync(HttpStatusCode.BadRequest, "validation"))["errors"]?["question"]);
        var missingDeck = await admin.PostAsJsonAsync("/api/admin/decks/999999/cards", new { question = "q", answer = "a" }, Ct);
        await missingDeck.AssertProblemAsync(HttpStatusCode.NotFound, "notFound");
    }

    [Fact]
    public async Task Deleting_a_deck_deletes_its_cards_and_progress()
    {
        using var admin = await factory.AdminClientAsync();
        var user = await factory.CreateUserAsync();
        var deck = await (await admin.PostAsJsonAsync("/api/admin/decks", new { name = "Ke smazání" }, Ct)).ReadAsync<DeckResponse>();
        var card = await (await admin.PostAsJsonAsync($"/api/admin/decks/{deck.Id}/cards",
            new { question = "q", answer = "a" }, Ct)).ReadAsync<CardResponse>();
        await factory.WithDbAsync(async db =>
        {
            var now = DateTime.UtcNow;
            db.CardStates.Add(new CardState
            {
                UserId = user.Id, CardId = card.Id, State = FsrsState.Review, Stability = 3, Difficulty = 5,
                Due = now, LastReview = now, FirstReview = now, Reps = 1,
            });
            db.ReviewLogs.Add(new ReviewLog
            {
                Id = Guid.NewGuid(), UserId = user.Id, CardId = card.Id, Rating = Rating.Good,
                ReviewedAt = now, Day = PragueCalendar.DayOf(now), Multiplier = 1.0m, PointsAwarded = 10,
            });
            await db.SaveChangesAsync(Ct);
        });

        var delete = await admin.DeleteAsync($"/api/admin/decks/{deck.Id}", Ct);

        Assert.Equal(HttpStatusCode.NoContent, delete.StatusCode);
        await factory.WithDbAsync(async db =>
        {
            Assert.False(await db.Cards.AnyAsync(c => c.Id == card.Id, Ct));
            Assert.False(await db.CardStates.AnyAsync(s => s.CardId == card.Id, Ct));
            Assert.False(await db.ReviewLogs.AnyAsync(r => r.CardId == card.Id, Ct));
        });
        await (await admin.DeleteAsync($"/api/admin/decks/{deck.Id}", Ct)).AssertProblemAsync(HttpStatusCode.NotFound, "notFound");
    }

    [Fact]
    public async Task Shop_item_edits_use_optimistic_concurrency()
    {
        using var admin = await factory.AdminClientAsync();
        var item = await (await admin.PostAsJsonAsync("/api/admin/shop-items",
            new { name = "Jít na pizzu", description = "Pizza dle výběru", price = 1500, initialStock = 3 }, Ct)).ReadAsync<ShopItemResponse>();
        Assert.Equal((3, 3, true, 0, 0), (item.InitialStock, item.Stock, item.IsActive, item.PendingClaims, item.OnWishlists));

        var first = await admin.PutAsJsonAsync($"/api/admin/shop-items/{item.Id}", UpdateBody(item, price: 1400), Ct);
        var stale = await admin.PutAsJsonAsync($"/api/admin/shop-items/{item.Id}", UpdateBody(item, price: 1300), Ct);

        var updated = await first.ReadAsync<ShopItemResponse>();
        Assert.Equal(1400, updated.Price);
        Assert.NotEqual(item.Version, updated.Version);
        await stale.AssertProblemAsync(HttpStatusCode.Conflict, "concurrencyConflict");
    }

    [Fact]
    public async Task Shop_item_stock_follows_initial_stock_and_cannot_drop_below_sold()
    {
        using var admin = await factory.AdminClientAsync();
        var item = await (await admin.PostAsJsonAsync("/api/admin/shop-items",
            new { name = "Kino", description = (string?)null, price = 1200, initialStock = 2 }, Ct)).ReadAsync<ShopItemResponse>();
        var user = await factory.CreateUserAsync();
        await AddClaimAsync(user.Id, item.Id, soldPieces: 1);
        item = await (await admin.GetAsync($"/api/admin/shop-items/{item.Id}", Ct)).ReadAsync<ShopItemResponse>();
        Assert.Equal((1, 1), (item.Stock, item.PendingClaims));

        var raised = await (await admin.PutAsJsonAsync($"/api/admin/shop-items/{item.Id}", UpdateBody(item, initialStock: 5), Ct))
            .ReadAsync<ShopItemResponse>();
        Assert.Equal((5, 4), (raised.InitialStock, raised.Stock));

        var tooLow = await admin.PutAsJsonAsync($"/api/admin/shop-items/{item.Id}", UpdateBody(raised, initialStock: 0), Ct);
        Assert.NotNull((await tooLow.AssertProblemAsync(HttpStatusCode.BadRequest, "validation"))["errors"]?["initialStock"]);
    }

    [Fact]
    public async Task Shop_item_with_claims_cannot_be_deleted()
    {
        using var admin = await factory.AdminClientAsync();
        var sold = await (await admin.PostAsJsonAsync("/api/admin/shop-items",
            new { name = "Prodaná", description = "", price = 10, initialStock = 1 }, Ct)).ReadAsync<ShopItemResponse>();
        var unsold = await (await admin.PostAsJsonAsync("/api/admin/shop-items",
            new { name = "Neprodaná", description = "", price = 10, initialStock = 1 }, Ct)).ReadAsync<ShopItemResponse>();
        await AddClaimAsync((await factory.CreateUserAsync()).Id, sold.Id, soldPieces: 1);

        await (await admin.DeleteAsync($"/api/admin/shop-items/{sold.Id}", Ct)).AssertProblemAsync(HttpStatusCode.Conflict, "hasClaims");
        Assert.Equal(HttpStatusCode.NoContent, (await admin.DeleteAsync($"/api/admin/shop-items/{unsold.Id}", Ct)).StatusCode);
    }

    [Fact]
    public async Task Shop_item_price_and_stock_are_validated()
    {
        using var admin = await factory.AdminClientAsync();

        var response = await admin.PostAsJsonAsync("/api/admin/shop-items",
            new { name = "", description = "", price = 0, initialStock = 10001 }, Ct);

        var problem = await response.AssertProblemAsync(HttpStatusCode.BadRequest, "validation");
        foreach (var field in new[] { "name", "price", "initialStock" })
        {
            Assert.NotNull(problem["errors"]?[field]);
        }
    }

    [Fact]
    public async Task Admin_writes_must_be_json()
    {
        using var admin = await factory.AdminClientAsync();

        var form = await admin.PostAsync("/api/admin/decks",
            new FormUrlEncodedContent([new("name", "Formulář")]), Ct);
        var text = await admin.PostAsync("/api/admin/decks", new StringContent("{\"name\":\"x\"}", Encoding.UTF8, "text/plain"), Ct);

        await form.AssertProblemAsync(HttpStatusCode.UnsupportedMediaType, "unsupportedMediaType");
        await text.AssertProblemAsync(HttpStatusCode.UnsupportedMediaType, "unsupportedMediaType");
    }

    [Theory]
    [InlineData("{\"name\": 42}")]
    [InlineData("{\"name\": \"a\", \"name\": \"b\"}")]
    [InlineData("{\"description\": \"no name\"}")]
    [InlineData("{not json")]
    public async Task Unreadable_bodies_are_validation_errors(string body)
    {
        using var admin = await factory.AdminClientAsync();

        var response = await admin.PostAsync("/api/admin/decks", new StringContent(body, Encoding.UTF8, "application/json"), Ct);

        await response.AssertProblemAsync(HttpStatusCode.BadRequest, "validation");
    }

    private static object UpdateBody(ShopItemResponse item, int? price = null, int? initialStock = null) => new
    {
        name = item.Name,
        description = item.Description,
        price = price ?? item.Price,
        initialStock = initialStock ?? item.InitialStock,
        isActive = item.IsActive,
        sortOrder = item.SortOrder,
        version = item.Version,
    };

    /// <summary>Simulates a purchase (the claim flow itself arrives in Etapa 3).</summary>
    private Task AddClaimAsync(int userId, int itemId, int soldPieces) => factory.WithDbAsync(async db =>
    {
        var item = await db.ShopItems.FirstAsync(i => i.Id == itemId, Ct);
        for (var i = 0; i < soldPieces; i++)
        {
            db.Claims.Add(new Claim
            {
                UserId = userId, ShopItemId = itemId, RequestId = Guid.NewGuid(), Price = item.Price,
                Status = ClaimStatus.Pending, CreatedAt = DateTime.UtcNow,
            });
        }

        item.Stock -= soldPieces;
        await db.SaveChangesAsync(Ct);
    });
}
