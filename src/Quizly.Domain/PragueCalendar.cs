namespace Quizly.Domain;

/// <summary>
/// Converts UTC instants to Europe/Prague study days. A day runs from 03:00 to 03:00 local time (#40).
/// Never uses the server's local zone.
/// </summary>
public static class PragueCalendar
{
    public const int RolloverHour = 3;

    public static readonly TimeZoneInfo Zone = TimeZoneInfo.FindSystemTimeZoneById("Europe/Prague");

    public static DateOnly Today(TimeProvider time) => DayOf(time.GetUtcNow().UtcDateTime);

    public static DateOnly DayOf(DateTime utc)
    {
        if (utc.Kind != DateTimeKind.Utc)
        {
            throw new ArgumentException("Expected a UTC DateTime.", nameof(utc));
        }

        return DateOnly.FromDateTime(TimeZoneInfo.ConvertTimeFromUtc(utc, Zone).AddHours(-RolloverHour));
    }

    /// <summary>The UTC instant when the given Prague study day starts (03:00 local).</summary>
    public static DateTime StartOfDayUtc(DateOnly day) =>
        TimeZoneInfo.ConvertTimeToUtc(day.ToDateTime(new TimeOnly(RolloverHour, 0), DateTimeKind.Unspecified), Zone);
}
