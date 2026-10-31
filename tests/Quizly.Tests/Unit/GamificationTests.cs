using Quizly.Domain;
using Quizly.Domain.Gamification;

namespace Quizly.Tests.Unit;

public sealed class PointsTests
{
    // Table from docs/spec.md §6.2.
    [Theory]
    [InlineData(0, "1.0", 10, 2)]
    [InlineData(6, "1.0", 10, 2)]
    [InlineData(7, "1.1", 11, 2)]
    [InlineData(13, "1.1", 11, 2)]
    [InlineData(14, "1.2", 12, 2)]
    [InlineData(21, "1.3", 13, 3)]
    [InlineData(28, "1.4", 14, 3)]
    [InlineData(35, "1.5", 15, 3)]
    [InlineData(42, "1.6", 16, 3)]
    [InlineData(49, "1.7", 17, 3)]
    [InlineData(56, "1.8", 18, 4)]
    [InlineData(63, "1.9", 19, 4)]
    [InlineData(70, "2.0", 20, 4)]
    [InlineData(400, "2.0", 20, 4)]
    public void Multiplier_and_points_follow_the_table(int streak, string multiplier, int know, int dontKnow)
    {
        var m = Points.Multiplier(streak);

        Assert.Equal(decimal.Parse(multiplier, System.Globalization.CultureInfo.InvariantCulture), m);
        Assert.Equal(know, Points.For(Rating.Good, m));
        Assert.Equal(dontKnow, Points.For(Rating.Again, m));
    }

    [Theory]
    [InlineData(0, "1.1", 7)]
    [InlineData(12, "1.2", 2)]
    [InlineData(13, "1.2", 1)]
    [InlineData(14, "1.3", 7)]
    [InlineData(69, "2.0", 1)]
    public void Next_multiplier_counts_remaining_met_days(int streak, string value, int inDays)
    {
        var next = Points.NextMultiplier(streak);

        Assert.Equal((decimal.Parse(value, System.Globalization.CultureInfo.InvariantCulture), inDays), next);
    }

    [Fact]
    public void No_next_multiplier_at_the_maximum() => Assert.Null(Points.NextMultiplier(70));

    [Fact]
    public void Worked_example_from_the_spec()
    {
        // spec §6.5: streak 13, first 19 answers 13 Vím + 6 Nevím, then Vím (old multiplier), streak 14, then Vím.
        var before = Points.Multiplier(13);
        var first19 = (13 * Points.For(Rating.Good, before)) + (6 * Points.For(Rating.Again, before));
        var twentieth = Points.For(Rating.Good, before);
        var twentyFirst = Points.For(Rating.Good, Points.Multiplier(14));

        Assert.Equal((155, 11, 12, 178), (first19, twentieth, twentyFirst, first19 + twentieth + twentyFirst));
    }
}

public sealed class StreakTests
{
    private static readonly DateOnly Today = new(2026, 11, 4);

    [Theory]
    [InlineData("2026-11-04", 5, 5)] // met today
    [InlineData("2026-11-03", 5, 5)] // met yesterday, today still open
    [InlineData("2026-11-02", 5, 0)] // yesterday missed
    [InlineData(null, 0, 0)]
    public void Displayed_streak(string? lastMet, int cached, int expected) =>
        Assert.Equal(expected, Streaks.Displayed(cached, Parse(lastMet), Today));

    [Fact]
    public void Broken_streak_reports_the_first_morning_after_the_missed_day()
    {
        Assert.Equal((12, new DateOnly(2026, 11, 4)), Streaks.Broken(12, new DateOnly(2026, 11, 2), Today));
        Assert.Null(Streaks.Broken(12, new DateOnly(2026, 11, 3), Today));
        Assert.Null(Streaks.Broken(0, new DateOnly(2026, 10, 1), Today));
    }

    [Fact]
    public void Met_day_extends_or_restarts_the_streak_and_keeps_the_record()
    {
        var user = new User { CurrentStreak = 6, BestStreak = 9, LastGoalMetDate = Today.AddDays(-1) };

        Assert.Equal(7, Streaks.MarkDayMet(user, Today));
        Assert.Equal((Today, 9), (user.LastGoalMetDate!.Value, user.BestStreak));

        Assert.Equal(1, Streaks.MarkDayMet(user, Today.AddDays(5)));
        Assert.Equal(9, user.BestStreak);
    }

    [Fact]
    public void Milestones_are_7_30_100_365()
    {
        Assert.Equal(50, Milestones.BonusFor(7));
        Assert.Equal(200, Milestones.BonusFor(30));
        Assert.Equal(1_000, Milestones.BonusFor(100));
        Assert.Equal(5_000, Milestones.BonusFor(365));
        Assert.Null(Milestones.BonusFor(8));
        Assert.Equal("7:2026-11-08", Milestones.ReferenceId(7, new DateOnly(2026, 11, 8)));
    }

    private static DateOnly? Parse(string? day) =>
        day is null ? null : DateOnly.Parse(day, System.Globalization.CultureInfo.InvariantCulture);
}

public sealed class SmartTimesTests
{
    private static DateTime Prague(int day, int hour, int minute) =>
        TimeZoneInfo.ConvertTimeToUtc(new DateTime(2026, 11, day, hour, minute, 0), PragueCalendar.Zone);

    [Fact]
    public void Median_session_start_rounded_to_15_minutes()
    {
        DateTime[] reviews =
        [
            Prague(2, 19, 2), Prague(2, 19, 5), Prague(2, 19, 20), // one session starting 19:02
            Prague(3, 19, 10),
            Prague(4, 19, 40), Prague(4, 20, 30), // gap ≥ 30 min → second session 20:30 the same day
        ];

        // Starts 19:02, 19:10, 19:40, 20:30 → median 19:25 → 19:30.
        Assert.Equal(new TimeOnly(19, 30), SmartTimes.EveningTime(reviews));
    }

    [Fact]
    public void Clamped_to_the_evening_window()
    {
        Assert.Equal(new TimeOnly(17, 0), SmartTimes.EveningTime([Prague(2, 7, 0), Prague(3, 7, 15), Prague(4, 8, 0)]));
        Assert.Equal(new TimeOnly(20, 30), SmartTimes.EveningTime([Prague(2, 22, 0), Prague(3, 22, 15), Prague(4, 23, 0)]));
    }

    [Fact]
    public void Needs_three_sessions() =>
        Assert.Null(SmartTimes.EveningTime([Prague(2, 19, 0), Prague(3, 19, 0)]));
}
