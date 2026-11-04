using Microsoft.Extensions.Options;
using Quizly.Application.Common;
using Quizly.Web.Api;
using Quizly.Web.Auth;

namespace Quizly.Web.Updates;

/// <summary>Checks GitHub on startup and then every <see cref="AppUpdateOptions.CheckInterval"/>.</summary>
public sealed class AppUpdateWorker(
    GitHubReleaseChecker checker,
    IOptions<AppUpdateOptions> options,
    TimeProvider time,
    ILogger<AppUpdateWorker> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(options.Value.CheckInterval, time);
        do
        {
            try
            {
                await checker.CheckAsync(stoppingToken);
            }
            catch (Exception e) when (e is not OperationCanceledException || !stoppingToken.IsCancellationRequested)
            {
                // GitHub down, an expired token, a broken download: the old APK stays, the next tick tries again.
                logger.LogWarning(e, "App update check failed");
            }
        }
        while (await timer.WaitForNextTickAsync(stoppingToken));
    }
}

/// <summary><c>GET /api/app/latest</c>: the newest version the server can hand out.</summary>
/// <param name="Latest">Null when there's no APK (updates off, or no full release yet).</param>
public sealed record AppLatestResponse(AppLatest? Latest);

/// <param name="VersionName">e.g. <c>1.0.1</c>.</param>
/// <param name="VersionCode">Compare with the app's own versionCode: higher means an update.</param>
/// <param name="Size">Bytes of the APK.</param>
public sealed record AppLatest(string VersionName, int VersionCode, long Size);

internal static class AppUpdates
{
    public static IServiceCollection AddQuizlyAppUpdates(this IServiceCollection services, IConfiguration config)
    {
        services.Configure<AppUpdateOptions>(config.GetSection("Updates"));
        services.AddSingleton<AppReleaseStore>();
        services.AddSingleton<GitHubReleaseChecker>();
        services.AddHttpClient(GitHubReleaseChecker.HttpClientName, http =>
        {
            http.BaseAddress = new Uri("https://api.github.com/");
            http.DefaultRequestHeaders.UserAgent.ParseAdd("Quizly-Server");
            http.Timeout = TimeSpan.FromMinutes(5);
        });
        if (config.GetSection("Updates").Get<AppUpdateOptions>() is { Enabled: true })
        {
            services.AddHostedService<AppUpdateWorker>();
        }

        return services;
    }

    /// <summary>docs/api.md §15: the app asks here, never GitHub (the repository is private).</summary>
    public static void MapAppUpdates(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/app").RequireAuthorization(AuthSetup.AppPolicy).WithTags("App updates");

        group.MapGet("/latest", (AppReleaseStore store) =>
                TypedResults.Ok(new AppLatestResponse(store.Current is { } r ? new AppLatest(r.VersionName, r.VersionCode, r.Size) : null)))
            .WithName("GetLatestApp")
            .WithSummary("The newest app version the server has (full releases only)")
            .WithDescription("latest is null when there's nothing to offer. The app shows \"Je dostupná nová verze\" when versionCode is higher than its own.");

        group.MapGet("/apk", IResult (AppReleaseStore store) =>
                store.Current is { } release && File.Exists(release.Path)
                    ? TypedResults.PhysicalFile(release.Path, "application/vnd.android.package-archive", release.FileName,
                        enableRangeProcessing: true)
                    : Errors.NotFound("Novou verzi aplikace teď nemáme.").ToProblem())
            .WithName("DownloadApp")
            .WithSummary("Download the newest APK")
            .WithDescription("Supports Range requests. 404 notFound when there's no APK.");
    }
}
