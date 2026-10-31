using System.Globalization;
using Quizly.Domain;

namespace Quizly.Web.Components;

/// <summary>Czech formatting for the dashboard (CLAUDE.md §2.12): 1 457 · 1,1× · 83 % · 31. 10.</summary>
public static class Cz
{
    private const char Nbsp = ' ';
    private static readonly CultureInfo Culture = CultureInfo.GetCultureInfo("cs-CZ");

    public static string Number(int value) => value.ToString("#,0", Culture).Replace(' ', Nbsp).Replace(' ', Nbsp);

    public static string Points(int value) => $"{Number(value)}{Nbsp}b.";

    public static string Multiplier(decimal value) => value.ToString("0.0", Culture) + "×";

    public static string Percent(int? value) => value is null ? "—" : $"{value}{Nbsp}%";

    public static string Date(DateOnly day) => $"{day.Day}.{Nbsp}{day.Month}.";

    /// <summary>1 den · 2 dny · 5 dní.</summary>
    public static string Days(int count) => $"{count}{Nbsp}{Plural(count, "den", "dny", "dní")}";

    /// <summary>1 karta · 2 karty · 5 karet.</summary>
    public static string Cards(int count) => $"{Number(count)}{Nbsp}{Plural(count, "karta", "karty", "karet")}";

    /// <summary>After a verb ("Smazat …"): 1 kartu · 2 karty · 5 karet.</summary>
    public static string CardsAccusative(int count) => $"{Number(count)}{Nbsp}{Plural(count, "kartu", "karty", "karet")}";

    public static string Plural(int count, string one, string few, string many) => count switch
    {
        1 => one,
        >= 2 and <= 4 => few,
        _ => many,
    };

    /// <summary>"před 5 min", "dnes 07:45", "včera 18:10", "31. 10.", "nikdy" in Prague time.</summary>
    public static string LastActive(DateTimeOffset? instant, TimeProvider time)
    {
        if (instant is null)
        {
            return "nikdy";
        }

        var now = time.GetUtcNow();
        var ago = now - instant.Value;
        if (ago < TimeSpan.FromMinutes(1))
        {
            return "právě teď";
        }

        if (ago < TimeSpan.FromHours(1))
        {
            return $"před {(int)ago.TotalMinutes}{Nbsp}min";
        }

        var local = TimeZoneInfo.ConvertTime(instant.Value, PragueCalendar.Zone);
        var day = DateOnly.FromDateTime(local.DateTime);
        var today = PragueCalendar.Today(time);
        var clock = local.ToString("HH:mm", CultureInfo.InvariantCulture);
        return day == today ? $"dnes {clock}"
            : day == today.AddDays(-1) ? $"včera {clock}"
            : Date(day);
    }

    public static string DateTime(DateTimeOffset instant)
    {
        var local = TimeZoneInfo.ConvertTime(instant, PragueCalendar.Zone);
        return $"{Date(DateOnly.FromDateTime(local.DateTime))} {local.ToString("HH:mm", CultureInfo.InvariantCulture)}";
    }
}
