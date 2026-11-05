using System.Globalization;

namespace Quizly.Application.Learning;

/// <summary>Formats FSRS time spans into compact button tokens: 10m, 1d, 1.5mo, 2y (#31).</summary>
public static class ReviewIntervalFormatter
{
    public static string Format(TimeSpan span)
    {
        if (span <= TimeSpan.Zero)
        {
            return "1m";
        }

        if (span.TotalDays >= 365)
        {
            var years = Math.Round(span.TotalDays / 365.0, 1, MidpointRounding.AwayFromZero);
            return $"{years.ToString("0.#", CultureInfo.InvariantCulture)}y";
        }

        if (span.TotalDays >= 30)
        {
            var months = Math.Round(span.TotalDays / 30.0, 1, MidpointRounding.AwayFromZero);
            return $"{months.ToString("0.#", CultureInfo.InvariantCulture)}mo";
        }

        if (span.TotalDays >= 1)
        {
            var days = (int)Math.Round(span.TotalDays, MidpointRounding.AwayFromZero);
            return $"{days}d";
        }

        if (span.TotalHours >= 1)
        {
            var hours = (int)Math.Round(span.TotalHours, MidpointRounding.AwayFromZero);
            return $"{hours}h";
        }

        var minutes = (int)Math.Round(span.TotalMinutes, MidpointRounding.AwayFromZero);
        return $"{Math.Max(1, minutes)}m";
    }
}
