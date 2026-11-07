using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.AspNetCore.Http.Json;
using Quizly.Application;
using Quizly.Application.Auth;
using Quizly.Application.Common;
using Quizly.Infrastructure;
using Quizly.Infrastructure.Persistence;
using Quizly.Web.Api;
using Quizly.Web.Auth;
using Quizly.Web.Components;
using Quizly.Web.Mcp;
using Quizly.Web.Middleware;
using Quizly.Web.Updates;

var builder = WebApplication.CreateBuilder(args);
var config = builder.Configuration;

builder.Services.AddApplication();
builder.Services.AddInfrastructure(config);

builder.Services.Configure<JwtOptions>(config.GetSection("Jwt"));
builder.Services.Configure<AdminCredentialsOptions>(o =>
{
    o.Username = config["ADMIN_USERNAME"] ?? "";
    o.Password = config["ADMIN_PASSWORD"] ?? "";
});
builder.Services.Configure<RefreshTokenOptions>(config.GetSection("RefreshTokens"));
builder.Services.Configure<LoginThrottleOptions>(config.GetSection("LoginThrottle"));
builder.Services.AddSingleton<IAccessTokenIssuer, JwtTokenIssuer>();
builder.Services.AddQuizlyAuth(config, builder.Environment);

builder.Services.Configure<JsonOptions>(o => JsonSetup.Configure(o.SerializerOptions));
builder.Services.Configure<RouteHandlerOptions>(o => o.ThrowOnBadRequest = true);
builder.Services.AddProblemDetails(o => o.CustomizeProblemDetails = Problems.Customize);
builder.Services.AddExceptionHandler<ApiExceptionHandler>();
builder.Services.AddQuizlyOpenApi();
// The dashboard's YAML editor sends a whole deck (up to 1 MB of text, more as JSON) in one circuit
// message; SignalR's default 32 KB limit silently dropped pasted decks (#20).
builder.Services.AddRazorComponents().AddInteractiveServerComponents()
    .AddHubOptions(o => o.MaximumReceiveMessageSize = 4 * 1024 * 1024);
builder.Services.AddCascadingAuthenticationState();
builder.Services.AddHealthChecks().AddDbContextCheck<QuizlyDbContext>();
// Off unless Mcp__Enabled; refuses to start with a missing or short Mcp__Secret (docs/mcp.md).
builder.Services.AddQuizlyMcp(config);
// New APKs from GitHub's full releases, off unless Updates__Repository and Updates__GitHubToken (docs/app-updates.md).
builder.Services.AddQuizlyAppUpdates(config);

// Behind Nginx Proxy Manager: trust X-Forwarded-For/Proto from the proxy network (deploy/README-deploy.md).
builder.Services.Configure<ForwardedHeadersOptions>(o =>
{
    o.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
    o.KnownIPNetworks.Clear();
    o.KnownProxies.Clear();
});

// Cookies must survive restarts, so the Data Protection keys live on a volume.
var dataProtection = builder.Services.AddDataProtection().SetApplicationName("Quizly");
if (config["DataProtection:KeysPath"] is { Length: > 0 } keysPath)
{
    dataProtection.PersistKeysToFileSystem(new DirectoryInfo(keysPath));
}

var app = builder.Build();

app.UseForwardedHeaders();
// Strips the secret from /mcp/<secret> before routing, so nothing after this logs it.
app.UseQuizlyMcpSecret(config);
app.UseRouting();
app.UseExceptionHandler();
app.UseStatusCodePages();
app.UseAuthentication();
app.UseAuthorization();
app.UseAntiforgery();
app.UseRateLimiter();
app.MapStaticAssets();

app.MapHealthChecks("/api/health", new HealthCheckOptions
{
    ResponseWriter = (context, report) => context.Response.WriteAsJsonAsync(
        new { status = report.Status == Microsoft.Extensions.Diagnostics.HealthChecks.HealthStatus.Healthy ? "ok" : "unhealthy" }),
}).AllowAnonymous();
app.MapAppAuth();
app.MapAdminAuth();
app.MapApp();
app.MapAppUpdates();
app.MapAdmin();
app.MapDocs();
app.MapAdminDashboard();
app.MapQuizlyMcp(config);
app.MapRazorComponents<Quizly.Web.Components.App>().AddInteractiveServerRenderMode();

// Fail fast on missing secrets, then migrate and seed.
app.Services.GetRequiredService<IAdminAuthenticator>();
app.Services.GetRequiredService<Microsoft.Extensions.Options.IOptions<JwtOptions>>().Value.Key();
await using (var scope = app.Services.CreateAsyncScope())
{
    await scope.ServiceProvider.GetRequiredService<DatabaseInitializer>()
        .InitializeAsync(seedDevelopmentData: app.Environment.IsDevelopment() && config.GetValue("Seed:DevelopmentData", true));
}

await app.RunAsync();

/// <summary>Entry point; public so integration tests can use WebApplicationFactory.</summary>
public partial class Program;
