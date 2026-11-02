using System.Net;
using System.Net.Http.Json;
using Quizly.Tests.Infrastructure;

namespace Quizly.Tests.Api;

/// <summary>The admin can keep a user out of the shop (docs/api.md §8).</summary>
public sealed class ShopAccessTests(QuizlyFactory factory) : IClassFixture<QuizlyFactory>
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task A_user_without_the_shop_gets_no_shop_claims_or_wishlist()
    {
        var user = await factory.CreateUserAsync();
        using var app = await factory.AppClientAsync(user);
        var item = await CreateItemAsync(price: 10);
        Assert.Equal(HttpStatusCode.NoContent, (await app.PutAsync($"/api/wishlist/{item}", null, Ct)).StatusCode);

        await SetShopAsync(user.Id, enabled: false);

        Assert.False((bool)(await (await app.GetAsync("/api/me", Ct)).ReadNodeAsync())["user"]!["shopEnabled"]!);
        var login = await factory.LoginAsync(user.Username, user.Password);
        Assert.False(login.User.ShopEnabled);
        await (await app.GetAsync("/api/shop", Ct)).AssertProblemAsync(HttpStatusCode.Forbidden, "shopDisabled");
        await (await app.GetAsync("/api/claims", Ct)).AssertProblemAsync(HttpStatusCode.Forbidden, "shopDisabled");
        await (await app.PostAsJsonAsync($"/api/shop/{item}/claim", new { requestId = Guid.NewGuid() }, Ct))
            .AssertProblemAsync(HttpStatusCode.Forbidden, "shopDisabled");
        await (await app.DeleteAsync($"/api/wishlist/{item}", Ct)).AssertProblemAsync(HttpStatusCode.Forbidden, "shopDisabled");

        // Points still come, but no "you can afford your wish" news.
        var (_, cards) = await factory.CreateDeckAsync("S" + Guid.NewGuid().ToString("N")[..6], 1);
        var review = await (await app.PostAsJsonAsync("/api/reviews",
            new { reviews = new[] { new { id = Guid.NewGuid(), cardId = cards[0], rating = "know" } } }, Ct)).ReadNodeAsync();
        Assert.Equal(10, (int)review["summary"]!["balance"]!);
        Assert.DoesNotContain(review["events"]!.AsArray(), e => (string?)e!["type"] == "wishlistReached");

        await SetShopAsync(user.Id, enabled: true);
        Assert.Equal(HttpStatusCode.OK, (await app.GetAsync("/api/shop", Ct)).StatusCode);
    }

    [Fact]
    public async Task The_admin_sees_and_sets_the_shop_flag()
    {
        using var admin = await factory.AdminClientAsync();
        var created = await (await admin.PostAsJsonAsync("/api/admin/users",
            new { username = "s" + Guid.NewGuid().ToString("N")[..10], displayName = "Host", shopEnabled = false }, Ct)).ReadNodeAsync();
        Assert.False((bool)created["user"]!["shopEnabled"]!);

        var other = await factory.CreateUserAsync();
        var listed = (await (await admin.GetAsync("/api/admin/users", Ct)).ReadNodeAsync()).AsArray()
            .First(u => (int)u!["id"]! == other.Id)!;
        Assert.True((bool)listed["shopEnabled"]!);
    }

    private async Task SetShopAsync(int userId, bool enabled)
    {
        using var admin = await factory.AdminClientAsync();
        var response = await admin.PutAsJsonAsync($"/api/admin/users/{userId}",
            new { displayName = "Testovací uživatel", dailyGoal = 20, newCardsPerDay = 5, shopEnabled = enabled }, Ct);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    private async Task<int> CreateItemAsync(int price)
    {
        using var admin = await factory.AdminClientAsync();
        var response = await admin.PostAsJsonAsync("/api/admin/shop-items",
            new { name = "Odměna " + Guid.NewGuid().ToString("N")[..6], description = "", price, initialStock = 3, isActive = true }, Ct);
        return (int)(await response.ReadNodeAsync())["id"]!;
    }
}
