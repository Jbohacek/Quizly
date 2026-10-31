using Microsoft.Extensions.Options;
using Microsoft.Extensions.Time.Testing;
using Quizly.Application.Auth;
using Quizly.Application.Common;
using Quizly.Application.NotificationTexts;
using Quizly.Domain;

namespace Quizly.Tests.Unit;

public sealed class PragueCalendarTests
{
    // Boundaries from docs/spec.md §5.1, including both DST switches.
    [Theory]
    [InlineData("2026-10-24T21:59:59Z", "2026-10-24")]
    [InlineData("2026-10-24T22:00:00Z", "2026-10-25")]
    [InlineData("2026-10-25T00:59:59Z", "2026-10-25")]
    [InlineData("2026-10-25T01:00:00Z", "2026-10-25")]
    [InlineData("2026-10-25T22:59:59Z", "2026-10-25")]
    [InlineData("2026-10-25T23:00:00Z", "2026-10-26")]
    [InlineData("2027-03-27T22:59:59Z", "2027-03-27")]
    [InlineData("2027-03-27T23:00:00Z", "2027-03-28")]
    [InlineData("2027-03-28T21:59:59Z", "2027-03-28")]
    [InlineData("2027-03-28T22:00:00Z", "2027-03-29")]
    public void Utc_instants_map_to_prague_days(string utc, string expectedDay)
    {
        var instant = DateTime.Parse(utc, System.Globalization.CultureInfo.InvariantCulture,
            System.Globalization.DateTimeStyles.AdjustToUniversal | System.Globalization.DateTimeStyles.AssumeUniversal);

        Assert.Equal(DateOnly.Parse(expectedDay, System.Globalization.CultureInfo.InvariantCulture), PragueCalendar.DayOf(instant));
    }

    [Theory]
    [InlineData("2026-10-25", 25)]
    [InlineData("2027-03-28", 23)]
    [InlineData("2026-11-02", 24)]
    public void Day_lengths_follow_dst(string day, int hours)
    {
        var date = DateOnly.Parse(day, System.Globalization.CultureInfo.InvariantCulture);

        var length = PragueCalendar.StartOfDayUtc(date.AddDays(1)) - PragueCalendar.StartOfDayUtc(date);

        Assert.Equal(TimeSpan.FromHours(hours), length);
    }

    [Fact]
    public void Non_utc_input_is_rejected() =>
        Assert.Throws<ArgumentException>(() => PragueCalendar.DayOf(new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Local)));
}

public sealed class LoginThrottleTests
{
    [Fact]
    public void Blocks_after_max_failures_and_releases_after_the_window()
    {
        var time = new FakeTimeProvider(new DateTimeOffset(2026, 11, 2, 7, 0, 0, TimeSpan.Zero));
        var throttle = new LoginThrottle(time, Options.Create(new LoginThrottleOptions { MaxFailures = 3, Window = TimeSpan.FromMinutes(5) }));

        for (var i = 0; i < 3; i++)
        {
            Assert.False(throttle.IsBlocked("petra"));
            throttle.RecordFailure("petra");
            time.Advance(TimeSpan.FromMinutes(1));
        }

        Assert.True(throttle.IsBlocked("petra"));
        Assert.False(throttle.IsBlocked("jakub"));
        time.Advance(TimeSpan.FromMinutes(2)); // the first failure is now 5 min old
        Assert.False(throttle.IsBlocked("petra"));
    }

    [Fact]
    public void Reset_clears_failures()
    {
        var throttle = new LoginThrottle(new FakeTimeProvider(), Options.Create(new LoginThrottleOptions { MaxFailures = 1 }));
        throttle.RecordFailure("petra");

        throttle.Reset("petra");

        Assert.False(throttle.IsBlocked("petra"));
    }
}

public sealed class PasswordGeneratorTests
{
    [Fact]
    public void Generates_12_unambiguous_characters()
    {
        var generator = new PasswordGenerator();

        var passwords = Enumerable.Range(0, 200).Select(_ => generator.Generate()).ToList();

        Assert.All(passwords, p =>
        {
            Assert.Equal(12, p.Length);
            Assert.All(p, c => Assert.Contains(c, PasswordGenerator.Alphabet));
        });
        Assert.Equal(passwords.Count, passwords.Distinct().Count());
        Assert.DoesNotContain(PasswordGenerator.Alphabet, c => "0O1lI".Contains(c, StringComparison.Ordinal));
    }
}

public sealed class ValidationTests
{
    [Theory]
    [InlineData("  text  ", "text")]
    [InlineData("a\r\nb\rc\n", "a\nb\nc")]
    [InlineData(null, "")]
    public void Clean_trims_and_normalizes_line_endings(string? input, string expected) =>
        Assert.Equal(expected, Validator.Clean(input));

    [Theory]
    [InlineData("Karty na dnešek: {due}. Série: {streak} 🔥", true)]
    [InlineData("Bez zástupných symbolů 🙂", true)]
    [InlineData("{due}{left}{done}{goal}{streak}{multiplier}{item}{points}", true)]
    [InlineData("Ahoj {jmeno}", false)]
    [InlineData("Otevřená { závorka", false)]
    [InlineData("Zavřená } závorka", false)]
    [InlineData("{{due}}", false)]
    public void Notification_text_placeholders(string text, bool valid)
    {
        var v = new Validator();

        NotificationTextService.ValidateText(v, text);

        Assert.Equal(valid, v.IsValid);
    }

    [Fact]
    public void Text_over_the_limit_reports_its_length()
    {
        var v = new Validator().Text("question", new string('x', 501), "Otázka", Limits.QuestionMax);

        var error = v.ToError();

        Assert.Equal("validation", error.Code);
        Assert.Equal(["Pole „Otázka“ má 501 znaků, maximum je 500."], error.Errors!["question"]);
    }

    [Theory]
    [InlineData(NotificationCategory.LastCall, "last_call")]
    [InlineData(NotificationCategory.Morning, "morning")]
    public void Categories_use_snake_case_names(NotificationCategory category, string name) =>
        Assert.Equal(name, NotificationTextService.CategoryName(category));
}
