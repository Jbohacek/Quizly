using System.Net.Http.Headers;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Time.Testing;
using Quizly.Application.Auth;
using Quizly.Application.Users;
using Quizly.Infrastructure.Persistence;

namespace Quizly.Tests.Infrastructure;

/// <summary>The real app on a fresh database, with a controllable clock.</summary>
public class QuizlyFactory(PostgresContainer postgres) : WebApplicationFactory<Program>
{
    public const string AdminUsername = "admin";
    public const string AdminPassword = "test-admin-password";

    private readonly string _database = $"quizly_test_{Guid.NewGuid():N}";

    /// <summary>Starts at the real current time so JWT lifetime checks (real clock) still pass.</summary>
    public FakeTimeProvider Time { get; } = new(DateTimeOffset.UtcNow);

    /// <summary>Extra settings for a derived factory, e.g. tight rate limits.</summary>
    protected virtual IEnumerable<KeyValuePair<string, string>> ExtraSettings => [];

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");
        builder.UseSetting("ConnectionStrings:Default", postgres.ConnectionString(_database));
        builder.UseSetting("Jwt:Issuer", "https://quizly.test");
        builder.UseSetting("Jwt:SigningKey", "test-signing-key-0123456789-0123456789-abcdef");
        builder.UseSetting("ADMIN_USERNAME", AdminUsername);
        builder.UseSetting("ADMIN_PASSWORD", AdminPassword);
        foreach (var name in new[] { AuthLimits.Login, AuthLimits.Refresh, AuthLimits.AdminLogin })
        {
            builder.UseSetting($"RateLimits:{name}:PermitLimit", "10000");
        }

        foreach (var (key, value) in ExtraSettings)
        {
            builder.UseSetting(key, value);
        }

        builder.ConfigureTestServices(services => services.AddSingleton<TimeProvider>(Time));
    }

    public async Task<HttpClient> AdminClientAsync()
    {
        var client = CreateClient();
        var response = await client.PostAsJsonAsync("/api/admin/auth/login", new { username = AdminUsername, password = AdminPassword });
        response.EnsureSuccessStatusCode();
        return client;
    }

    /// <summary>Creates an app user through the admin API and returns the generated password.</summary>
    public async Task<(int Id, string Username, string Password)> CreateUserAsync(string? username = null)
    {
        username ??= "u" + Guid.NewGuid().ToString("N")[..10];
        using var admin = await AdminClientAsync();
        var response = await admin.PostAsJsonAsync("/api/admin/users", new { username, displayName = "Testovací uživatel" });
        response.EnsureSuccessStatusCode();
        var created = await response.Content.ReadFromJsonAsync<CreatedUserResponse>(Json.Options);
        return (created!.User.Id, username, created.Password);
    }

    public async Task<TokenResponse> LoginAsync(string username, string password)
    {
        using var client = CreateClient();
        var response = await client.PostAsJsonAsync("/api/auth/login", new { username, password });
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<TokenResponse>(Json.Options))!;
    }

    public HttpClient AppClient(string accessToken)
    {
        var client = CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        return client;
    }

    public async Task WithDbAsync(Func<QuizlyDbContext, Task> action)
    {
        await using var scope = Services.CreateAsyncScope();
        await action(scope.ServiceProvider.GetRequiredService<QuizlyDbContext>());
    }
}

/// <summary>Rate-limit policy names as in AuthSetup.</summary>
public static class AuthLimits
{
    public const string Login = "login";
    public const string Refresh = "refresh";
    public const string AdminLogin = "admin-login";
}
