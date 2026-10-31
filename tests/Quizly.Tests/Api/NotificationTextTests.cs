using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using Quizly.Application.NotificationTexts;
using Quizly.Domain;
using Quizly.Tests.Infrastructure;

namespace Quizly.Tests.Api;

public sealed class NotificationTextTests(QuizlyFactory factory) : IClassFixture<QuizlyFactory>
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task Seed_contains_the_52_texts_from_the_docs()
    {
        using var admin = await factory.AdminClientAsync();

        var all = await (await admin.GetAsync("/api/admin/notification-texts", Ct)).ReadAsync<List<NotificationTextResponse>>();
        var lastCall = await (await admin.GetAsync("/api/admin/notification-texts?category=last_call", Ct))
            .ReadAsync<List<NotificationTextResponse>>();

        Assert.True(all.Count >= 52);
        Assert.Equal(8, lastCall.Count);
        Assert.All(lastCall, t => Assert.Equal(NotificationCategory.LastCall, t.Category));
        Assert.Contains(all, t => t.Text == "Zvládneš to! Věřím ti ❤️");
    }

    [Fact]
    public async Task Unknown_category_filter_is_a_validation_error()
    {
        using var admin = await factory.AdminClientAsync();

        var response = await admin.GetAsync("/api/admin/notification-texts?category=lunch", Ct);

        await response.AssertProblemAsync(HttpStatusCode.BadRequest, "validation");
    }

    [Theory]
    [InlineData("Ahoj {name}!")]
    [InlineData("Karty: {due")]
    [InlineData("Karty: due}")]
    [InlineData("")]
    public async Task Invalid_texts_are_rejected(string text)
    {
        using var admin = await factory.AdminClientAsync();

        var response = await admin.PostAsJsonAsync("/api/admin/notification-texts", new { category = "morning", text }, Ct);

        var problem = await response.AssertProblemAsync(HttpStatusCode.BadRequest, "validation");
        Assert.NotNull(problem["errors"]?["text"]);
    }

    [Fact]
    public async Task Texts_can_be_added_edited_and_deleted()
    {
        using var admin = await factory.AdminClientAsync();

        var create = await admin.PostAsJsonAsync("/api/admin/notification-texts",
            new { category = "evening", text = "Do cíle zbývá: {left} ✨" }, Ct);
        var created = await create.ReadAsync<NotificationTextResponse>();
        var updated = await (await admin.PutAsJsonAsync($"/api/admin/notification-texts/{created.Id}",
            new { category = "last_call", text = "Ještě je čas! ⏰", isActive = false }, Ct)).ReadAsync<NotificationTextResponse>();
        var delete = await admin.DeleteAsync($"/api/admin/notification-texts/{created.Id}", Ct);

        Assert.Equal(HttpStatusCode.Created, create.StatusCode);
        Assert.Equal((NotificationCategory.LastCall, false), (updated.Category, updated.IsActive));
        Assert.Equal(HttpStatusCode.NoContent, delete.StatusCode);
        await (await admin.GetAsync($"/api/admin/notification-texts/{created.Id}", Ct)).AssertProblemAsync(HttpStatusCode.NotFound, "notFound");
    }

    [Fact]
    public async Task Preview_fills_sample_values_in_czech_format()
    {
        using var admin = await factory.AdminClientAsync();

        var response = await admin.PostAsJsonAsync("/api/admin/notification-texts/preview",
            new { text = "Máš {done} z {goal}, body: {points}, násobič {multiplier}" }, Ct);

        var preview = await response.ReadAsync<NotificationPreviewResponse>();
        Assert.Equal("Máš 13 z 20, body: 1 457, násobič 1,2×", preview.Rendered);
    }

    [Fact]
    public async Task App_gets_active_texts_grouped_with_an_etag()
    {
        var user = await factory.CreateUserAsync();
        var tokens = await factory.LoginAsync(user.Username, user.Password);
        using var app = factory.AppClient(tokens.AccessToken);

        var first = await app.GetAsync("/api/notification-texts", Ct);
        var body = await first.ReadNodeAsync();
        var etag = first.Headers.ETag;

        Assert.NotNull(etag);
        Assert.Equal($"\"{(string?)body["version"]}\"", etag.Tag);
        foreach (var category in new[] { "morning", "evening", "last_call", "milestone", "wishlist", "comeback" })
        {
            Assert.True(body["categories"]?[category]?.AsArray().Count > 0, category);
        }

        using var conditional = new HttpRequestMessage(HttpMethod.Get, "/api/notification-texts");
        conditional.Headers.IfNoneMatch.Add(etag);
        Assert.Equal(HttpStatusCode.NotModified, (await app.SendAsync(conditional, Ct)).StatusCode);

        // Deactivating a text changes the version.
        using var admin = await factory.AdminClientAsync();
        var text = (await (await admin.GetAsync("/api/admin/notification-texts?category=comeback", Ct))
            .ReadAsync<List<NotificationTextResponse>>()).First(t => t.IsActive);
        await admin.PutAsJsonAsync($"/api/admin/notification-texts/{text.Id}",
            new { category = "comeback", text = text.Text, isActive = false }, Ct);
        using var again = new HttpRequestMessage(HttpMethod.Get, "/api/notification-texts");
        again.Headers.IfNoneMatch.Add(etag);
        var changed = await app.SendAsync(again, Ct);
        Assert.Equal(HttpStatusCode.OK, changed.StatusCode);
        var ids = (await changed.ReadNodeAsync())["categories"]!["comeback"]!.AsArray().Select(n => (int)n!["id"]!);
        Assert.DoesNotContain(text.Id, ids);
    }
}

public sealed class PlatformTests(QuizlyFactory factory) : IClassFixture<QuizlyFactory>
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task Health_is_ok_without_auth()
    {
        using var client = factory.CreateClient();

        var response = await client.GetAsync("/api/health", Ct);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("ok", (string?)(await response.ReadNodeAsync())["status"]);
    }

    [Fact]
    public async Task Api_docs_need_the_admin_cookie_outside_development()
    {
        using var anonymous = factory.CreateClient();
        using var admin = await factory.AdminClientAsync();

        var hidden = await anonymous.GetAsync("/api/openapi/v1.json", Ct);
        var document = await admin.GetAsync("/api/openapi/v1.json", Ct);
        var ui = await admin.GetAsync("/api/docs", Ct);

        Assert.Equal(HttpStatusCode.Unauthorized, hidden.StatusCode);
        var json = await document.Content.ReadAsStringAsync(Ct);
        Assert.Contains("/api/auth/login", json, StringComparison.Ordinal);
        Assert.Contains("/api/admin/shop-items/{id}", json, StringComparison.Ordinal);
        Assert.Equal(new MediaTypeHeaderValue("text/html") { CharSet = "utf-8" }, ui.Content.Headers.ContentType);
    }

    [Fact]
    public async Task Unknown_routes_are_problem_details()
    {
        using var client = factory.CreateClient();

        var response = await client.GetAsync("/api/does-not-exist", Ct);

        await response.AssertProblemAsync(HttpStatusCode.NotFound, "notFound");
    }

    [Fact]
    public async Task Instants_are_serialized_as_utc_with_z()
    {
        using var admin = await factory.AdminClientAsync();

        var body = await (await admin.PostAsJsonAsync("/api/admin/decks", new { name = "Čas" }, Ct)).Content.ReadAsStringAsync(Ct);

        Assert.Matches("\"createdAt\":\"\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(\\.\\d+)?Z\"", body);
    }
}
