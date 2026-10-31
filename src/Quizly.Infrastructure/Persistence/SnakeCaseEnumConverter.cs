using System.Text.Json;
using Microsoft.EntityFrameworkCore.Storage.ValueConversion;

namespace Quizly.Infrastructure.Persistence;

/// <summary>Stores an enum as a short lowercase string: <c>LastCall</c> → <c>last_call</c> (docs/spec.md §1).</summary>
internal sealed class SnakeCaseEnumConverter<TEnum>() : ValueConverter<TEnum, string>(
    value => Names<TEnum>.ToDb(value),
    value => Names<TEnum>.FromDb(value))
    where TEnum : struct, Enum;

internal static class Names<TEnum>
    where TEnum : struct, Enum
{
    private static readonly Dictionary<TEnum, string> ToDbMap =
        Enum.GetValues<TEnum>().ToDictionary(v => v, v => JsonNamingPolicy.SnakeCaseLower.ConvertName(v.ToString()));

    private static readonly Dictionary<string, TEnum> FromDbMap =
        ToDbMap.ToDictionary(p => p.Value, p => p.Key, StringComparer.Ordinal);

    public static string ToDb(TEnum value) => ToDbMap[value];

    public static TEnum FromDb(string value) => FromDbMap[value];
}
