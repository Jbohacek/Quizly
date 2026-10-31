namespace Quizly.Domain.Gamification;

/// <summary>"Chytré časy": the typical study time for the evening reminder (docs/api.md §3).</summary>
public static class SmartTimes
{
    public static readonly TimeSpan SessionGap = TimeSpan.FromMinutes(30);
    public static readonly TimeOnly Earliest = new(17, 0);
    public static readonly TimeOnly Latest = new(20, 30);
    public const int MinimumSessions = 3;

    /// <summary>
    /// Median Prague start time of study sessions (a session starts after a gap of at least 30 min),
    /// rounded to 15 min and clamped to 17:00–20:30. Null with fewer than 3 sessions.
    /// </summary>
    public static TimeOnly? EveningTime(IEnumerable<DateTime> reviewTimesUtc)
    {
        var starts = new List<double>();
        DateTime? previous = null;
        foreach (var time in reviewTimesUtc.Order())
        {
            if (previous is null || time - previous.Value >= SessionGap)
            {
                starts.Add(TimeZoneInfo.ConvertTimeFromUtc(time, PragueCalendar.Zone).TimeOfDay.TotalMinutes);
            }

            previous = time;
        }

        if (starts.Count < MinimumSessions)
        {
            return null;
        }

        starts.Sort();
        var middle = starts.Count / 2;
        var median = starts.Count % 2 == 1 ? starts[middle] : (starts[middle - 1] + starts[middle]) / 2;
        var rounded = (int)Math.Round(median / 15, MidpointRounding.AwayFromZero) * 15;
        var minutes = Math.Clamp(rounded, (int)Earliest.ToTimeSpan().TotalMinutes, (int)Latest.ToTimeSpan().TotalMinutes);
        return TimeOnly.FromTimeSpan(TimeSpan.FromMinutes(minutes));
    }
}
