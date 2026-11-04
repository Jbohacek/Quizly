using System.Collections.Concurrent;
using System.Net;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Quizly.Tests.Infrastructure;
using Quizly.Web.Updates;

namespace Quizly.Tests.Api;

/// <summary>
/// A pretend GitHub: <c>releases/latest</c> answers with <see cref="Latest"/>, assets download from <see cref="Files"/>.
/// </summary>
public sealed class FakeGitHub : HttpMessageHandler
{
    public object? Latest { get; set; }

    public ConcurrentDictionary<string, byte[]> Files { get; } = new();

    public ConcurrentQueue<HttpRequestMessage> Requests { get; } = new();

    public static object Release(string tag, params (string Name, byte[] Bytes, string? Digest)[] assets) => new
    {
        tag_name = tag,
        draft = false,
        prerelease = false,
        assets = assets.Select(a => new
        {
            name = a.Name,
            size = a.Bytes.Length,
            url = $"https://api.github.com/repos/test/quizly/releases/assets/{a.Name}",
            digest = a.Digest,
        }),
    };

    public static string Sha256(byte[] bytes) => "sha256:" + Convert.ToHexStringLower(SHA256.HashData(bytes));

    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        Requests.Enqueue(request);
        var path = request.RequestUri!.AbsolutePath;
        if (path == "/repos/test/quizly/releases/latest")
        {
            return Task.FromResult(Latest is null
                ? new HttpResponseMessage(HttpStatusCode.NotFound)
                : new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(JsonSerializer.Serialize(Latest)) });
        }

        var name = path.Split('/')[^1];
        return Task.FromResult(Files.TryGetValue(name, out var bytes)
            ? new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(bytes) }
            : new HttpResponseMessage(HttpStatusCode.NotFound));
    }
}

/// <summary>The checker and store on their own, with a pretend GitHub and a temporary folder.</summary>
public sealed class AppUpdateCheckerTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "quizly-apk-" + Guid.NewGuid().ToString("N"));
    private readonly FakeGitHub _github = new();
    private readonly AppUpdateOptions _options;

    public AppUpdateCheckerTests()
    {
        _options = new AppUpdateOptions { Repository = "test/quizly", GitHubToken = "secret-token", Directory = _dir };
    }

    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    public void Dispose()
    {
        if (Directory.Exists(_dir))
        {
            Directory.Delete(_dir, recursive: true);
        }
    }

    [Theory]
    [InlineData("quizly-1.0.1-58.apk", "1.0.1", 58)]
    [InlineData("quizly-1.0.0-beta.6-41.apk", "1.0.0-beta.6", 41)]
    [InlineData("quizly-2.0.0+3-120.apk", "2.0.0+3", 120)]
    public void The_version_comes_from_the_file_name_CI_gives_the_APK(string file, string name, int code) =>
        Assert.Equal((name, code), AppReleaseStore.ParseFileName(file));

    [Theory]
    [InlineData("app-release.apk")]
    [InlineData("quizly-1.0.1.apk")]
    [InlineData("quizly-1.0.1-58.apk.sha256")]
    [InlineData("quizly-1.0.1-0.apk")]
    [InlineData("../quizly-1.0.1-58.apk")]
    public void Other_files_are_not_APKs(string file) => Assert.Null(AppReleaseStore.ParseFileName(file));

    [Fact]
    public async Task A_full_release_is_downloaded_and_checked_against_GitHubs_size_and_digest()
    {
        var (store, checker) = Create();
        var apk = "APK v58"u8.ToArray();
        _github.Files["quizly-1.0.1-58.apk"] = apk;
        _github.Latest = FakeGitHub.Release("v1.0.1", ("quizly-1.0.1-58.apk", apk, FakeGitHub.Sha256(apk)));

        var release = await checker.CheckAsync(Ct);

        Assert.Equal(("1.0.1", 58, (long)apk.Length), (release!.VersionName, release.VersionCode, release.Size));
        Assert.Equal(apk, await File.ReadAllBytesAsync(Path.Combine(_dir, "quizly-1.0.1-58.apk"), Ct));
        Assert.Same(release, store.Current);
        Assert.Empty(Directory.EnumerateFiles(_dir, "*.part"));
        // The token goes to GitHub, and the asset is asked for as a file.
        Assert.All(_github.Requests, r => Assert.Equal(new AuthenticationHeaderValue("Bearer", "secret-token"), r.Headers.Authorization));
        Assert.Contains(_github.Requests, r => r.Headers.Accept.ToString() == "application/octet-stream");

        // The same release again: nothing is downloaded.
        var requests = _github.Requests.Count;
        Assert.Same(release, await checker.CheckAsync(Ct));
        Assert.Equal(requests + 1, _github.Requests.Count);
    }

    [Fact]
    public async Task A_newer_release_replaces_the_old_APK_and_a_restart_finds_it_on_disk()
    {
        var (_, checker) = Create();
        Publish("v1.0.0", "quizly-1.0.0-50.apk");
        await checker.CheckAsync(Ct);
        Publish("v1.0.1", "quizly-1.0.1-58.apk");
        await checker.CheckAsync(Ct);

        Assert.Equal(["quizly-1.0.1-58.apk"], Directory.EnumerateFiles(_dir).Select(Path.GetFileName));

        // A restart (a new store over the same volume) serves it without asking GitHub.
        var restarted = new AppReleaseStore(Options.Create(_options), NullLogger<AppReleaseStore>.Instance);
        Assert.Equal(58, restarted.Current!.VersionCode);
    }

    [Fact]
    public async Task An_older_or_equal_release_is_ignored()
    {
        var (store, checker) = Create();
        Publish("v1.0.1", "quizly-1.0.1-58.apk");
        await checker.CheckAsync(Ct);
        Publish("v1.0.0", "quizly-1.0.0-50.apk");

        Assert.Equal(58, (await checker.CheckAsync(Ct))!.VersionCode);
        Assert.Equal(58, store.Current!.VersionCode);
        Assert.DoesNotContain(_github.Requests, r => r.RequestUri!.AbsolutePath.EndsWith("quizly-1.0.0-50.apk", StringComparison.Ordinal));
    }

    [Fact]
    public async Task Nothing_to_offer_without_a_full_release_or_before_the_APK_is_attached()
    {
        var (store, checker) = Create();
        Assert.Null(await checker.CheckAsync(Ct));

        // CI creates the release first and uploads the APK a moment later.
        _github.Latest = FakeGitHub.Release("v1.0.1", ("notes.txt", "x"u8.ToArray(), null));
        Assert.Null(await checker.CheckAsync(Ct));

        // GitHub's "latest" never is a pre-release, but if it were, it's skipped.
        var apk = "beta"u8.ToArray();
        _github.Files["quizly-1.1.0-beta.1-60.apk"] = apk;
        _github.Latest = new
        {
            tag_name = "v1.1.0-beta.1",
            draft = false,
            prerelease = true,
            assets = new[] { new { name = "quizly-1.1.0-beta.1-60.apk", size = apk.Length, url = "https://api.github.com/x/quizly-1.1.0-beta.1-60.apk", digest = (string?)null } },
        };
        Assert.Null(await checker.CheckAsync(Ct));
        Assert.Null(store.Current);
    }

    [Theory]
    [InlineData("size")]
    [InlineData("digest")]
    public async Task A_broken_download_is_thrown_away_and_the_old_APK_stays(string broken)
    {
        var (store, checker) = Create();
        Publish("v1.0.0", "quizly-1.0.0-50.apk");
        await checker.CheckAsync(Ct);

        var apk = "APK v58"u8.ToArray();
        _github.Files["quizly-1.0.1-58.apk"] = broken == "size" ? apk[..3] : apk;
        _github.Latest = FakeGitHub.Release("v1.0.1",
            ("quizly-1.0.1-58.apk", apk, broken == "digest" ? FakeGitHub.Sha256("other"u8.ToArray()) : FakeGitHub.Sha256(apk)));

        await Assert.ThrowsAsync<InvalidDataException>(() => checker.CheckAsync(Ct));
        Assert.Equal(50, store.Current!.VersionCode);
        Assert.Equal(["quizly-1.0.0-50.apk"], Directory.EnumerateFiles(_dir).Select(Path.GetFileName));
    }

    [Fact]
    public async Task Without_a_token_GitHub_is_never_asked()
    {
        _options.GitHubToken = "";
        var (store, checker) = Create();
        Assert.Null(await checker.CheckAsync(Ct));
        Assert.Empty(_github.Requests);
        Assert.Null(store.Current);
    }

    /// <summary>GitHub's latest full release becomes <paramref name="tag"/> with one APK.</summary>
    private void Publish(string tag, string file)
    {
        var bytes = System.Text.Encoding.UTF8.GetBytes(file);
        _github.Files[file] = bytes;
        _github.Latest = FakeGitHub.Release(tag, (file, bytes, FakeGitHub.Sha256(bytes)));
    }

    private (AppReleaseStore Store, GitHubReleaseChecker Checker) Create()
    {
        var options = Options.Create(_options);
        var store = new AppReleaseStore(options, NullLogger<AppReleaseStore>.Instance);
        var checker = new GitHubReleaseChecker(new FakeHttpFactory(_github), store, options, NullLogger<GitHubReleaseChecker>.Instance);
        return (store, checker);
    }

    private sealed class FakeHttpFactory(FakeGitHub github) : IHttpClientFactory
    {
        public HttpClient CreateClient(string name) =>
            new(github, disposeHandler: false) { BaseAddress = new Uri("https://api.github.com/") };
    }
}

/// <summary>The app with updates on, a pretend GitHub, and no background worker (tests check by hand).</summary>
public sealed class AppUpdateFactory(PostgresContainer postgres) : QuizlyFactory(postgres)
{
    public string Directory { get; } = Path.Combine(Path.GetTempPath(), "quizly-apk-" + Guid.NewGuid().ToString("N"));

    public FakeGitHub GitHub { get; } = new();

    protected override IEnumerable<KeyValuePair<string, string>> ExtraSettings =>
    [
        new("Updates:Repository", "test/quizly"),
        new("Updates:GitHubToken", "secret-token"),
        new("Updates:Directory", Directory),
    ];

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        base.ConfigureWebHost(builder);
        builder.ConfigureTestServices(services =>
        {
            services.AddHttpClient(GitHubReleaseChecker.HttpClientName).ConfigurePrimaryHttpMessageHandler(() => GitHub);
            services.RemoveAll<IHostedService>();
        });
    }

    public override async ValueTask DisposeAsync()
    {
        await base.DisposeAsync();
        if (System.IO.Directory.Exists(Directory))
        {
            System.IO.Directory.Delete(Directory, recursive: true);
        }
    }
}

/// <summary><c>GET /api/app/latest</c> and <c>/api/app/apk</c> (docs/api.md §15).</summary>
public sealed class AppUpdateTests(AppUpdateFactory factory) : IClassFixture<AppUpdateFactory>
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task The_app_learns_about_a_new_version_and_downloads_it_from_the_server()
    {
        var user = await factory.CreateUserAsync();
        using var app = await factory.AppClientAsync(user);

        // Nothing yet.
        var none = await (await app.GetAsync("/api/app/latest", Ct)).ReadNodeAsync();
        Assert.Null(none["latest"]);
        await (await app.GetAsync("/api/app/apk", Ct)).AssertProblemAsync(HttpStatusCode.NotFound, "notFound");

        // A full release appears on GitHub; the server fetches it.
        var apk = Enumerable.Range(0, 1000).Select(i => (byte)i).ToArray();
        factory.GitHub.Files["quizly-1.0.1-58.apk"] = apk;
        factory.GitHub.Latest = FakeGitHub.Release("v1.0.1", ("quizly-1.0.1-58.apk", apk, FakeGitHub.Sha256(apk)));
        await factory.Services.GetRequiredService<GitHubReleaseChecker>().CheckAsync(Ct);

        var latest = (await (await app.GetAsync("/api/app/latest", Ct)).ReadNodeAsync())["latest"]!;
        Assert.Equal(("1.0.1", 58, 1000), ((string)latest["versionName"]!, (int)latest["versionCode"]!, (int)latest["size"]!));

        var download = await app.GetAsync("/api/app/apk", Ct);
        Assert.Equal(HttpStatusCode.OK, download.StatusCode);
        Assert.Equal("application/vnd.android.package-archive", download.Content.Headers.ContentType!.MediaType);
        Assert.Equal("quizly-1.0.1-58.apk", download.Content.Headers.ContentDisposition!.FileName);
        Assert.Equal(apk, await download.Content.ReadAsByteArrayAsync(Ct));

        // A broken connection can resume.
        using var range = new HttpRequestMessage(HttpMethod.Get, "/api/app/apk");
        range.Headers.Range = new RangeHeaderValue(900, null);
        var rest = await app.SendAsync(range, Ct);
        Assert.Equal(HttpStatusCode.PartialContent, rest.StatusCode);
        Assert.Equal(apk[900..], await rest.Content.ReadAsByteArrayAsync(Ct));
    }

    [Fact]
    public async Task Only_signed_in_users_see_or_download_the_app()
    {
        using var anonymous = factory.CreateClient();
        Assert.Equal(HttpStatusCode.Unauthorized, (await anonymous.GetAsync("/api/app/latest", Ct)).StatusCode);
        Assert.Equal(HttpStatusCode.Unauthorized, (await anonymous.GetAsync("/api/app/apk", Ct)).StatusCode);

        using var admin = await factory.AdminClientAsync();
        Assert.NotEqual(HttpStatusCode.OK, (await admin.GetAsync("/api/app/latest", Ct)).StatusCode);
    }
}

/// <summary>With no <c>Updates__*</c> settings the endpoints still answer, with nothing to offer.</summary>
public sealed class AppUpdateDisabledTests(QuizlyFactory factory) : IClassFixture<QuizlyFactory>
{
    [Fact]
    public async Task Updates_off_means_no_worker_and_nothing_to_offer()
    {
        Assert.DoesNotContain(factory.Services.GetServices<IHostedService>(), s => s is AppUpdateWorker);
        var user = await factory.CreateUserAsync();
        using var app = await factory.AppClientAsync(user);
        var body = await (await app.GetAsync("/api/app/latest", TestContext.Current.CancellationToken)).ReadNodeAsync();
        Assert.Null(body["latest"]);
    }
}
