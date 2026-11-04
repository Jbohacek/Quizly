using System.Net;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Options;

namespace Quizly.Web.Updates;

/// <summary>
/// Asks GitHub for the newest full release (<c>releases/latest</c> skips pre-releases and drafts, so beta tags never
/// reach phones) and downloads its APK into the <see cref="AppReleaseStore"/> when it's newer than the one kept.
/// The token is only ever sent to GitHub.
/// </summary>
public sealed class GitHubReleaseChecker(
    IHttpClientFactory httpFactory,
    AppReleaseStore store,
    IOptions<AppUpdateOptions> options,
    ILogger<GitHubReleaseChecker> logger) : IDisposable
{
    public const string HttpClientName = "github";

    private readonly SemaphoreSlim _gate = new(1, 1);

    /// <summary>One check; returns the newest release the server has afterwards (null if none).</summary>
    public async Task<AppRelease?> CheckAsync(CancellationToken ct)
    {
        var settings = options.Value;
        if (!settings.Enabled)
        {
            return store.Current;
        }

        await _gate.WaitAsync(ct);
        try
        {
            var http = httpFactory.CreateClient(HttpClientName);
            using var request = Request(HttpMethod.Get, $"repos/{settings.Repository}/releases/latest", settings.GitHubToken);
            request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
            using var response = await http.SendAsync(request, ct);
            if (response.StatusCode == HttpStatusCode.NotFound)
            {
                // No full release yet (only betas), or the token can't see the repository.
                logger.LogInformation("No full release found in {Repository}", settings.Repository);
                return store.Current;
            }

            response.EnsureSuccessStatusCode();
            var release = await response.Content.ReadFromJsonAsync<GitHubRelease>(ct);
            if (release is null || release.Draft || release.Prerelease)
            {
                return store.Current;
            }

            // CI creates the release first and attaches the APK a moment later: no APK yet → next check.
            var asset = release.Assets
                .Select(a => (Asset: a, Version: AppReleaseStore.ParseFileName(a.Name)))
                .Where(a => a.Version is not null)
                .OrderByDescending(a => a.Version!.Value.VersionCode)
                .Select(a => a.Asset)
                .FirstOrDefault();
            if (asset is null)
            {
                logger.LogInformation("Release {Tag} has no APK yet", release.TagName);
                return store.Current;
            }

            var code = AppReleaseStore.ParseFileName(asset.Name)!.Value.VersionCode;
            if (store.Current is { } current && current.VersionCode >= code)
            {
                return current;
            }

            var downloaded = await DownloadAsync(http, asset, settings, ct);
            var published = store.Publish(downloaded, asset.Name);
            logger.LogInformation("App update {Version} ({Code}) is ready", published.VersionName, published.VersionCode);
            return published;
        }
        finally
        {
            _gate.Release();
        }
    }

    private async Task<string> DownloadAsync(HttpClient http, GitHubAsset asset, AppUpdateOptions settings, CancellationToken ct)
    {
        Directory.CreateDirectory(store.Directory);
        var part = Path.Combine(store.Directory, asset.Name + ".part");
        try
        {
            // The asset API redirects to a signed storage URL; HttpClient drops the Authorization header on redirects.
            using var request = Request(HttpMethod.Get, asset.Url, settings.GitHubToken);
            request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/octet-stream"));
            using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, ct);
            response.EnsureSuccessStatusCode();

            await using (var file = File.Create(part))
            await using (var body = await response.Content.ReadAsStreamAsync(ct))
            {
                await body.CopyToAsync(file, ct);
            }

            var length = new FileInfo(part).Length;
            if (length != asset.Size)
            {
                throw new InvalidDataException($"{asset.Name}: got {length} bytes, GitHub says {asset.Size}.");
            }

            if (asset.Digest is { } digest && digest.StartsWith("sha256:", StringComparison.OrdinalIgnoreCase))
            {
                await using var file = File.OpenRead(part);
                var hash = Convert.ToHexStringLower(await SHA256.HashDataAsync(file, ct));
                if (!string.Equals(hash, digest["sha256:".Length..], StringComparison.OrdinalIgnoreCase))
                {
                    throw new InvalidDataException($"{asset.Name}: SHA-256 doesn't match GitHub's digest.");
                }
            }

            return part;
        }
        catch
        {
            File.Delete(part);
            throw;
        }
    }

    public void Dispose() => _gate.Dispose();

    private static HttpRequestMessage Request(HttpMethod method, string url, string token)
    {
        var request = new HttpRequestMessage(method, url);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        request.Headers.Add("X-GitHub-Api-Version", "2022-11-28");
        return request;
    }

    private sealed record GitHubRelease(
        [property: JsonPropertyName("tag_name")] string TagName,
        [property: JsonPropertyName("draft")] bool Draft,
        [property: JsonPropertyName("prerelease")] bool Prerelease,
        [property: JsonPropertyName("assets")] List<GitHubAsset> Assets);

    private sealed record GitHubAsset(
        [property: JsonPropertyName("name")] string Name,
        [property: JsonPropertyName("size")] long Size,
        [property: JsonPropertyName("url")] string Url,
        [property: JsonPropertyName("digest")] string? Digest);
}
