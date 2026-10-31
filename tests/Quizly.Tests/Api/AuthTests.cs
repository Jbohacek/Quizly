using System.Net;
using System.Net.Http.Json;
using Microsoft.EntityFrameworkCore;
using Quizly.Application.Auth;
using Quizly.Tests.Infrastructure;

namespace Quizly.Tests.Api;

public sealed class AuthTests(QuizlyFactory factory) : IClassFixture<QuizlyFactory>
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task Login_returns_tokens_that_work_on_app_endpoints()
    {
        var user = await factory.CreateUserAsync();

        var tokens = await factory.LoginAsync(user.Username.ToUpperInvariant(), user.Password);

        Assert.Equal(user.Id, tokens.User.Id);
        Assert.Equal(user.Username, tokens.User.Username);
        Assert.InRange(tokens.AccessTokenExpiresAt - factory.Time.GetUtcNow(), TimeSpan.FromMinutes(59), TimeSpan.FromMinutes(61));
        Assert.InRange(tokens.RefreshTokenExpiresAt - factory.Time.GetUtcNow(), TimeSpan.FromDays(89), TimeSpan.FromDays(91));
        using var app = factory.AppClient(tokens.AccessToken);
        var texts = await app.GetAsync("/api/notification-texts", Ct);
        Assert.Equal(HttpStatusCode.OK, texts.StatusCode);
    }

    [Fact]
    public async Task Access_token_lifetime_follows_the_app_clock()
    {
        // Issuing and validating must use the same clock, wherever the shared fake clock currently is.
        factory.Time.Advance(TimeSpan.FromMinutes(10));
        var user = await factory.CreateUserAsync();
        var tokens = await factory.LoginAsync(user.Username, user.Password);
        using var app = factory.AppClient(tokens.AccessToken);

        var fresh = await app.GetAsync("/api/notification-texts", Ct);
        factory.Time.Advance(TimeSpan.FromMinutes(62));
        var expired = await app.GetAsync("/api/notification-texts", Ct);

        Assert.Equal(HttpStatusCode.OK, fresh.StatusCode);
        await expired.AssertProblemAsync(HttpStatusCode.Unauthorized, "unauthorized");
    }

    [Theory]
    [InlineData("wrong-password")]
    [InlineData("")]
    public async Task Wrong_password_is_invalid_credentials(string password)
    {
        var user = await factory.CreateUserAsync();
        using var client = factory.CreateClient();

        var response = await client.PostAsJsonAsync("/api/auth/login", new { username = user.Username, password }, Ct);

        await response.AssertProblemAsync(HttpStatusCode.Unauthorized, "invalidCredentials");
    }

    [Fact]
    public async Task Unknown_user_gets_the_same_error_as_a_wrong_password()
    {
        using var client = factory.CreateClient();

        var response = await client.PostAsJsonAsync("/api/auth/login", new { username = "nobodyhere", password = "whatever-123" }, Ct);

        await response.AssertProblemAsync(HttpStatusCode.Unauthorized, "invalidCredentials");
    }

    [Fact]
    public async Task Five_failed_logins_block_the_username()
    {
        var user = await factory.CreateUserAsync();
        using var client = factory.CreateClient();
        for (var i = 0; i < 5; i++)
        {
            var failed = await client.PostAsJsonAsync("/api/auth/login", new { username = user.Username, password = "nope-nope" }, Ct);
            Assert.Equal(HttpStatusCode.Unauthorized, failed.StatusCode);
        }

        var blocked = await client.PostAsJsonAsync("/api/auth/login", new { username = user.Username, password = user.Password }, Ct);
        await blocked.AssertProblemAsync(HttpStatusCode.TooManyRequests, "rateLimited");

        factory.Time.Advance(TimeSpan.FromMinutes(5));
        var allowed = await client.PostAsJsonAsync("/api/auth/login", new { username = user.Username, password = user.Password }, Ct);
        Assert.Equal(HttpStatusCode.OK, allowed.StatusCode);
    }

    [Fact]
    public async Task Refresh_rotates_the_token()
    {
        var user = await factory.CreateUserAsync();
        var first = await factory.LoginAsync(user.Username, user.Password);
        using var client = factory.CreateClient();

        var response = await client.PostAsJsonAsync("/api/auth/refresh", new { refreshToken = first.RefreshToken }, Ct);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var second = await response.ReadAsync<TokenResponse>();
        Assert.NotEqual(first.RefreshToken, second.RefreshToken);
        var again = await client.PostAsJsonAsync("/api/auth/refresh", new { refreshToken = second.RefreshToken }, Ct);
        Assert.Equal(HttpStatusCode.OK, again.StatusCode);
    }

    [Fact]
    public async Task Repeating_a_refresh_within_the_grace_period_works_once_more()
    {
        var user = await factory.CreateUserAsync();
        var first = await factory.LoginAsync(user.Username, user.Password);
        using var client = factory.CreateClient();
        var lost = await (await client.PostAsJsonAsync("/api/auth/refresh", new { refreshToken = first.RefreshToken }, Ct))
            .ReadAsync<TokenResponse>();

        // The phone never got `lost` and retries with the old token 30 s later.
        factory.Time.Advance(TimeSpan.FromSeconds(30));
        var retry = await client.PostAsJsonAsync("/api/auth/refresh", new { refreshToken = first.RefreshToken }, Ct);

        Assert.Equal(HttpStatusCode.OK, retry.StatusCode);
        var current = await retry.ReadAsync<TokenResponse>();
        var next = await client.PostAsJsonAsync("/api/auth/refresh", new { refreshToken = current.RefreshToken }, Ct);
        Assert.Equal(HttpStatusCode.OK, next.StatusCode);

        // `lost` was replaced and that replacement is used now, so presenting `lost` is reuse.
        var lostUse = await client.PostAsJsonAsync("/api/auth/refresh", new { refreshToken = lost.RefreshToken }, Ct);
        await lostUse.AssertProblemAsync(HttpStatusCode.Unauthorized, "refreshTokenInvalid");
    }

    [Fact]
    public async Task Reusing_a_rotated_token_after_the_grace_period_revokes_all_sessions()
    {
        var user = await factory.CreateUserAsync();
        var first = await factory.LoginAsync(user.Username, user.Password);
        var otherDevice = await factory.LoginAsync(user.Username, user.Password);
        using var client = factory.CreateClient();
        var second = await (await client.PostAsJsonAsync("/api/auth/refresh", new { refreshToken = first.RefreshToken }, Ct))
            .ReadAsync<TokenResponse>();

        factory.Time.Advance(TimeSpan.FromSeconds(61));
        var reuse = await client.PostAsJsonAsync("/api/auth/refresh", new { refreshToken = first.RefreshToken }, Ct);

        await reuse.AssertProblemAsync(HttpStatusCode.Unauthorized, "refreshTokenInvalid");
        foreach (var token in new[] { second.RefreshToken, otherDevice.RefreshToken })
        {
            var response = await client.PostAsJsonAsync("/api/auth/refresh", new { refreshToken = token }, Ct);
            await response.AssertProblemAsync(HttpStatusCode.Unauthorized, "refreshTokenInvalid");
        }
    }

    [Fact]
    public async Task Expired_refresh_token_is_rejected()
    {
        var user = await factory.CreateUserAsync();
        var tokens = await factory.LoginAsync(user.Username, user.Password);
        await factory.WithDbAsync(db => db.RefreshTokens
            .Where(t => t.UserId == user.Id)
            .ExecuteUpdateAsync(s => s.SetProperty(t => t.ExpiresAt, DateTime.UtcNow.AddMinutes(-1)), Ct));
        using var client = factory.CreateClient();

        var response = await client.PostAsJsonAsync("/api/auth/refresh", new { refreshToken = tokens.RefreshToken }, Ct);

        await response.AssertProblemAsync(HttpStatusCode.Unauthorized, "refreshTokenInvalid");
    }

    [Fact]
    public async Task Logout_revokes_the_refresh_token()
    {
        var user = await factory.CreateUserAsync();
        var tokens = await factory.LoginAsync(user.Username, user.Password);
        using var client = factory.CreateClient();

        var logout = await client.PostAsJsonAsync("/api/auth/logout", new { refreshToken = tokens.RefreshToken }, Ct);
        var unknown = await client.PostAsJsonAsync("/api/auth/logout", new { refreshToken = "not-a-token" }, Ct);

        Assert.Equal(HttpStatusCode.NoContent, logout.StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, unknown.StatusCode);
        var refresh = await client.PostAsJsonAsync("/api/auth/refresh", new { refreshToken = tokens.RefreshToken }, Ct);
        await refresh.AssertProblemAsync(HttpStatusCode.Unauthorized, "refreshTokenInvalid");
    }

    [Fact]
    public async Task Deactivated_user_cannot_use_tokens_or_log_in()
    {
        var user = await factory.CreateUserAsync();
        var tokens = await factory.LoginAsync(user.Username, user.Password);
        using var admin = await factory.AdminClientAsync();

        var deactivate = await admin.PostAsync($"/api/admin/users/{user.Id}/deactivate", null, Ct);

        Assert.Equal(HttpStatusCode.NoContent, deactivate.StatusCode);
        using var app = factory.AppClient(tokens.AccessToken);
        await (await app.GetAsync("/api/notification-texts", Ct)).AssertProblemAsync(HttpStatusCode.Unauthorized, "accountDisabled");
        using var client = factory.CreateClient();
        var login = await client.PostAsJsonAsync("/api/auth/login", new { username = user.Username, password = user.Password }, Ct);
        await login.AssertProblemAsync(HttpStatusCode.Unauthorized, "accountDisabled");
        var refresh = await client.PostAsJsonAsync("/api/auth/refresh", new { refreshToken = tokens.RefreshToken }, Ct);
        await refresh.AssertProblemAsync(HttpStatusCode.Unauthorized, "accountDisabled");

        await admin.PostAsync($"/api/admin/users/{user.Id}/activate", null, Ct);
        var loginAgain = await client.PostAsJsonAsync("/api/auth/login", new { username = user.Username, password = user.Password }, Ct);
        Assert.Equal(HttpStatusCode.OK, loginAgain.StatusCode);
    }

    [Fact]
    public async Task Reset_password_replaces_the_password_and_signs_the_user_out()
    {
        var user = await factory.CreateUserAsync();
        var tokens = await factory.LoginAsync(user.Username, user.Password);
        using var admin = await factory.AdminClientAsync();

        var reset = await (await admin.PostAsync($"/api/admin/users/{user.Id}/reset-password", null, Ct))
            .ReadAsync<Quizly.Application.Users.PasswordResponse>();

        Assert.Equal(12, reset.Password.Length);
        using var client = factory.CreateClient();
        var oldLogin = await client.PostAsJsonAsync("/api/auth/login", new { username = user.Username, password = user.Password }, Ct);
        await oldLogin.AssertProblemAsync(HttpStatusCode.Unauthorized, "invalidCredentials");
        var refresh = await client.PostAsJsonAsync("/api/auth/refresh", new { refreshToken = tokens.RefreshToken }, Ct);
        await refresh.AssertProblemAsync(HttpStatusCode.Unauthorized, "refreshTokenInvalid");
        Assert.Equal(user.Id, (await factory.LoginAsync(user.Username, reset.Password)).User.Id);
    }

    [Fact]
    public async Task App_endpoint_without_token_is_unauthorized()
    {
        using var client = factory.CreateClient();

        var response = await client.GetAsync("/api/notification-texts", Ct);

        await response.AssertProblemAsync(HttpStatusCode.Unauthorized, "unauthorized");
    }

    [Fact]
    public async Task Admin_endpoints_need_the_admin_cookie()
    {
        var user = await factory.CreateUserAsync();
        var tokens = await factory.LoginAsync(user.Username, user.Password);
        using var anonymous = factory.CreateClient();
        using var appUser = factory.AppClient(tokens.AccessToken);

        await (await anonymous.GetAsync("/api/admin/users", Ct)).AssertProblemAsync(HttpStatusCode.Unauthorized, "unauthorized");
        await (await appUser.GetAsync("/api/admin/users", Ct)).AssertProblemAsync(HttpStatusCode.Unauthorized, "unauthorized");
        var badLogin = await anonymous.PostAsJsonAsync("/api/admin/auth/login", new { username = "admin", password = "wrong" }, Ct);
        await badLogin.AssertProblemAsync(HttpStatusCode.Unauthorized, "invalidCredentials");

        using var admin = await factory.AdminClientAsync();
        var me = await (await admin.GetAsync("/api/admin/auth/me", Ct)).ReadNodeAsync();
        Assert.Equal(QuizlyFactory.AdminUsername, (string?)me["username"]);
        await admin.PostAsync("/api/admin/auth/logout", null, Ct);
        Assert.Equal(HttpStatusCode.Unauthorized, (await admin.GetAsync("/api/admin/users", Ct)).StatusCode);
    }
}
