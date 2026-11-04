using System.Text.RegularExpressions;

namespace Quizly.Application.Common;

/// <summary>Collects field errors (camelCase keys, Czech messages) for a validation ProblemDetails.</summary>
public sealed partial class Validator
{
    private readonly Dictionary<string, List<string>> _errors = [];

    public bool IsValid => _errors.Count == 0;

    public Validator Add(string field, string message)
    {
        if (!_errors.TryGetValue(field, out var list))
        {
            list = [];
            _errors[field] = list;
        }

        list.Add(message);
        return this;
    }

    public Validator Text(string field, string? value, string label, int max, int min = 1)
    {
        var length = value?.Length ?? 0;
        if (length < min)
        {
            Add(field, min <= 1 ? $"Pole „{label}“ je povinné." : $"Pole „{label}“ musí mít aspoň {min} znaků.");
        }
        else if (length > max)
        {
            Add(field, $"Pole „{label}“ má {length} znaků, maximum je {max}.");
        }

        return this;
    }

    public Validator Range(string field, int value, string label, int min, int max)
    {
        if (value < min || value > max)
        {
            Add(field, $"Pole „{label}“ musí být mezi {min} a {max}.");
        }

        return this;
    }

    public Validator Color(string field, string? value)
    {
        if (value is null || !ColorRegex().IsMatch(value))
        {
            Add(field, "Barva musí být ve tvaru #RRGGBB.");
        }

        return this;
    }

    /// <summary>Card tags (#29): every name valid and not too many.</summary>
    public Validator Tags(string field, IReadOnlyList<string> invalid, bool tooMany)
    {
        foreach (var name in invalid)
        {
            Add(field, Decks.CardTagging.InvalidMessage(name));
        }

        if (tooMany)
        {
            Add(field, Decks.CardTagging.TooManyMessage);
        }

        return this;
    }

    public AppError ToError() =>
        Errors.Validation(_errors.ToDictionary(e => e.Key, e => e.Value.ToArray()));

    /// <summary>Trims and normalizes line endings to <c>\n</c> (docs/spec.md §1).</summary>
    public static string Clean(string? value) =>
        (value ?? "").Replace("\r\n", "\n", StringComparison.Ordinal).Replace('\r', '\n').Trim();

    [GeneratedRegex("^#[0-9A-Fa-f]{6}$")]
    private static partial Regex ColorRegex();
}
