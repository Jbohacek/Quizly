using System.Text.RegularExpressions;

namespace Quizly.Domain;

/// <summary>
/// Tag names (#29, docs/spec.md §2.5): lowercase letters (Czech ones too), digits, <c>_</c> and <c>-</c>, at most
/// <see cref="Limits.TagNameMax"/> characters, at most <see cref="Limits.TagsPerCardMax"/> per card.
/// Input is trimmed and lowercased; duplicates are dropped and the result is sorted.
/// </summary>
public static partial class TagNames
{
    /// <summary>Separators accepted where tags are typed as one text: <c>ai_gen ; prednaska_01</c>.</summary>
    private static readonly char[] Separators = [';', ',', ' ', '\t', '\n', '\r'];

    /// <summary>Splits typed text into tag names, e.g. "ai_gen ; prednaska_01" → [ai_gen, prednaska_01].</summary>
    public static IReadOnlyList<string> Split(string? text) =>
        (text ?? "").Split(Separators, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

    /// <summary>
    /// The normalized, sorted, distinct names, or the names that break the rules (<c>Invalid</c>) and whether there
    /// are too many (<c>TooMany</c>).
    /// </summary>
    public static (IReadOnlyList<string> Names, IReadOnlyList<string> Invalid, bool TooMany) Normalize(IEnumerable<string?> names)
    {
        var cleaned = names
            .Select(n => (n ?? "").Trim().ToLowerInvariant())
            .Where(n => n.Length > 0)
            .Distinct(StringComparer.Ordinal)
            .Order(StringComparer.Ordinal)
            .ToList();
        var invalid = cleaned.Where(n => !IsValid(n)).ToList();
        return (cleaned, invalid, cleaned.Count > Limits.TagsPerCardMax);
    }

    public static bool IsValid(string name) => name.Length <= Limits.TagNameMax && NameRegex().IsMatch(name);

    [GeneratedRegex(@"^[\p{Ll}\p{Lo}\p{Nd}_-]+$")]
    private static partial Regex NameRegex();
}
