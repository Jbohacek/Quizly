using System.Text.RegularExpressions;
using Microsoft.Extensions.Options;

namespace Quizly.Web.Updates;

/// <summary>The newest APK the server has: its version from the file name CI gives it.</summary>
/// <param name="VersionName">e.g. <c>1.0.1</c> (pubspec.yaml).</param>
/// <param name="VersionCode">The Android versionCode (the CI run number); the app compares this one.</param>
/// <param name="Path">The file on disk.</param>
/// <param name="Size">Bytes.</param>
public sealed record AppRelease(string VersionName, int VersionCode, string Path, long Size)
{
    public string FileName => System.IO.Path.GetFileName(Path);
}

/// <summary>
/// Keeps the newest APK in <see cref="AppUpdateOptions.Directory"/> and knows which one it is. Reads the directory on
/// first use, so after a restart the APK is served without asking GitHub again.
/// </summary>
public sealed partial class AppReleaseStore(IOptions<AppUpdateOptions> options, ILogger<AppReleaseStore> logger)
{
    private readonly Lock _lock = new();
    private bool _loaded;
    private AppRelease? _current;

    public string Directory => options.Value.Directory;

    /// <summary>The newest APK, or null when there's none yet (or updates are off).</summary>
    public AppRelease? Current
    {
        get
        {
            lock (_lock)
            {
                if (!_loaded)
                {
                    _current = Scan();
                    _loaded = true;
                }

                return _current;
            }
        }
    }

    /// <summary>
    /// Parses the name CI gives the APK: <c>quizly-1.0.1-58.apk</c> → (<c>1.0.1</c>, 58). Null for any other file.
    /// </summary>
    public static (string VersionName, int VersionCode)? ParseFileName(string fileName)
    {
        var match = FileNameRegex().Match(fileName);
        return match.Success && int.TryParse(match.Groups["code"].ValueSpan, out var code) && code > 0
            ? (match.Groups["name"].Value, code)
            : null;
    }

    /// <summary>
    /// Moves a downloaded file into place as the newest release and deletes the older ones. A release that isn't newer
    /// than the current one is ignored (and its file deleted).
    /// </summary>
    public AppRelease Publish(string downloadedPath, string fileName)
    {
        var (name, code) = ParseFileName(fileName) ?? throw new ArgumentException($"Not an APK name: {fileName}", nameof(fileName));
        lock (_lock)
        {
            var current = Current;
            if (current is not null && current.VersionCode >= code)
            {
                File.Delete(downloadedPath);
                return current;
            }

            var target = Path.Combine(Directory, fileName);
            File.Move(downloadedPath, target, overwrite: true);
            var release = new AppRelease(name, code, target, new FileInfo(target).Length);
            foreach (var old in System.IO.Directory.EnumerateFiles(Directory, "*.apk"))
            {
                if (!string.Equals(Path.GetFileName(old), fileName, StringComparison.Ordinal))
                {
                    TryDelete(old);
                }
            }

            _current = release;
            return release;
        }
    }

    private AppRelease? Scan()
    {
        if (!System.IO.Directory.Exists(Directory))
        {
            return null;
        }

        foreach (var part in System.IO.Directory.EnumerateFiles(Directory, "*.part"))
        {
            TryDelete(part);
        }

        return System.IO.Directory.EnumerateFiles(Directory, "*.apk")
            .Select(path => (Path: path, Version: ParseFileName(Path.GetFileName(path))))
            .Where(f => f.Version is not null)
            .OrderByDescending(f => f.Version!.Value.VersionCode)
            .Select(f => new AppRelease(f.Version!.Value.VersionName, f.Version.Value.VersionCode, f.Path, new FileInfo(f.Path).Length))
            .FirstOrDefault();
    }

    private void TryDelete(string path)
    {
        try
        {
            File.Delete(path);
        }
        catch (IOException e)
        {
            logger.LogWarning(e, "Could not delete {File}", Path.GetFileName(path));
        }
    }

    [GeneratedRegex(@"^quizly-(?<name>[0-9A-Za-z.+-]+)-(?<code>\d{1,9})\.apk$")]
    private static partial Regex FileNameRegex();
}
