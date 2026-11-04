namespace Quizly.Web.Updates;

/// <summary>
/// App updates (docs/app-updates.md) from <c>Updates__*</c>: where the server looks for new APKs and keeps the newest.
/// Off unless both <see cref="Repository"/> and <see cref="GitHubToken"/> are set.
/// </summary>
public sealed class AppUpdateOptions
{
    /// <summary>The GitHub repository whose releases carry the APK, <c>owner/name</c>.</summary>
    public string Repository { get; set; } = "";

    /// <summary>A fine-grained token with read-only Contents on <see cref="Repository"/>. Stays on the server.</summary>
    public string GitHubToken { get; set; } = "";

    /// <summary>Where the newest APK is kept (a volume, so a restart doesn't download it again).</summary>
    public string Directory { get; set; } = "/data/apk";

    /// <summary>How often GitHub is asked for a new release.</summary>
    public TimeSpan CheckInterval { get; set; } = TimeSpan.FromMinutes(15);

    public bool Enabled => Repository.Length > 0 && GitHubToken.Length > 0;
}
