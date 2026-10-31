using System.Net;
using System.Net.Http.Json;
using Quizly.Tests.Infrastructure;

namespace Quizly.Tests.Api;

public sealed class TightLimitsFactory(PostgresContainer postgres) : QuizlyFactory(postgres)
{
    protected override IEnumerable<KeyValuePair<string, string>> ExtraSettings =>
    [
        new($"RateLimits:{AuthLimits.Login}:PermitLimit", "2"),
        new($"RateLimits:{AuthLimits.AdminLogin}:PermitLimit", "2"),
    ];
}

public sealed class RateLimitTests(TightLimitsFactory factory) : IClassFixture<TightLimitsFactory>
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Theory]
    [InlineData("/api/auth/login")]
    [InlineData("/api/admin/auth/login")]
    public async Task Login_is_rate_limited_per_ip_with_retry_after(string path)
    {
        using var client = factory.CreateClient();
        for (var i = 0; i < 2; i++)
        {
            await client.PostAsJsonAsync(path, new { username = "someone", password = "something" }, Ct);
        }

        var limited = await client.PostAsJsonAsync(path, new { username = "someone", password = "something" }, Ct);

        await limited.AssertProblemAsync(HttpStatusCode.TooManyRequests, "rateLimited");
        Assert.True(limited.Headers.RetryAfter is not null || limited.Headers.Contains("Retry-After"));
    }
}
