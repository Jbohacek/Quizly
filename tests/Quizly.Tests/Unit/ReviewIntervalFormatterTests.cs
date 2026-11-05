using Quizly.Application.Learning;

namespace Quizly.Tests.Unit;

public sealed class ReviewIntervalFormatterTests
{
    [Theory]
    [InlineData(-10, "1m")]
    [InlineData(0, "1m")]
    [InlineData(30, "1m")]
    public void Format_sub_minute_or_non_positive_clamps_to_1m(int seconds, string expected)
    {
        var formatted = ReviewIntervalFormatter.Format(TimeSpan.FromSeconds(seconds));
        Assert.Equal(expected, formatted);
    }

    [Theory]
    [InlineData(1.0, "1m")]
    [InlineData(5.5, "6m")]
    [InlineData(10.0, "10m")]
    [InlineData(15.0, "15m")]
    [InlineData(59.0, "59m")]
    public void Format_minutes(double minutes, string expected)
    {
        var formatted = ReviewIntervalFormatter.Format(TimeSpan.FromMinutes(minutes));
        Assert.Equal(expected, formatted);
    }

    [Theory]
    [InlineData(1, "1h")]
    [InlineData(2, "2h")]
    [InlineData(12, "12h")]
    [InlineData(23, "23h")]
    public void Format_hours(int hours, string expected)
    {
        var formatted = ReviewIntervalFormatter.Format(TimeSpan.FromHours(hours));
        Assert.Equal(expected, formatted);
    }

    [Theory]
    [InlineData(1, "1d")]
    [InlineData(2, "2d")]
    [InlineData(8, "8d")]
    [InlineData(15, "15d")]
    [InlineData(29, "29d")]
    public void Format_days(int days, string expected)
    {
        var formatted = ReviewIntervalFormatter.Format(TimeSpan.FromDays(days));
        Assert.Equal(expected, formatted);
    }

    [Theory]
    [InlineData(30, "1mo")]
    [InlineData(45, "1.5mo")]
    [InlineData(60, "2mo")]
    [InlineData(90, "3mo")]
    public void Format_months(int days, string expected)
    {
        var formatted = ReviewIntervalFormatter.Format(TimeSpan.FromDays(days));
        Assert.Equal(expected, formatted);
    }

    [Theory]
    [InlineData(365, "1y")]
    [InlineData(730, "2y")]
    public void Format_years(int days, string expected)
    {
        var formatted = ReviewIntervalFormatter.Format(TimeSpan.FromDays(days));
        Assert.Equal(expected, formatted);
    }
}
