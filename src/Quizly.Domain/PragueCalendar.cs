namespace Quizly.Domain;

/// <summary>
/// Converts UTC instants to Europe/Prague calendar days. Never uses the server's local zone.
/// </summary>
public static class PragueCalendar
{
    public static readonly TimeZoneInfo Zone = TimeZoneInfo.FindSystemTimeZoneById("Europe/Prague");

    public static DateOnly Today(TimeProvider time) => DayOf(time.GetUtcNow().UtcDateTime);

    public static DateOnly DayOf(DateTime utc)
    {
        if (utc.Kind != DateTimeKind.Utc)
        {
            throw new ArgumentException("Expected a UTC DateTime.", nameof(utc));
        }

        return DateOnly.FromDateTime(TimeZoneInfo.ConvertTimeFromUtc(utc, Zone));
    }

    /// <summary>The UTC instant when the given Prague day starts (00:00 local).</summary>
    public static DateTime StartOfDayUtc(DateOnly day) =>
        TimeZoneInfo.ConvertTimeToUtc(day.ToDateTime(TimeOnly.MinValue, DateTimeKind.Unspecified), Zone);
}
