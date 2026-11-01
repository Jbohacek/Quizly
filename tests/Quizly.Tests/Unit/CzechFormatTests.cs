using Microsoft.Extensions.Time.Testing;
using Quizly.Web.Components;

namespace Quizly.Tests.Unit;

/// <summary>CLAUDE.md §2.12: 1 457 · 1,1× · 83 % · 31. 10. and Czech plurals.</summary>
public sealed class CzechFormatTests
{
    private const string Nbsp = " ";

    [Fact]
    public void Numbers_percent_multiplier_and_dates()
    {
        Assert.Equal($"1{Nbsp}457", Cz.Number(1457));
        Assert.Equal($"1{Nbsp}000{Nbsp}000", Cz.Number(1_000_000));
        Assert.Equal("1,1×", Cz.Multiplier(1.1m));
        Assert.Equal("2,0×", Cz.Multiplier(2m));
        Assert.Equal($"83{Nbsp}%", Cz.Percent(83));
        Assert.Equal("—", Cz.Percent(null));
        Assert.Equal($"31.{Nbsp}10.", Cz.Date(new DateOnly(2026, 10, 31)));
    }

    [Theory]
    [InlineData(1, "1 den", "1 karta", "1 kartu")]
    [InlineData(3, "3 dny", "3 karty", "3 karty")]
    [InlineData(5, "5 dní", "5 karet", "5 karet")]
    [InlineData(0, "0 dní", "0 karet", "0 karet")]
    public void Plurals(int count, string days, string cards, string cardsAccusative)
    {
        Assert.Equal(days, Cz.Days(count));
        Assert.Equal(cards, Cz.Cards(count));
        Assert.Equal(cardsAccusative, Cz.CardsAccusative(count));
    }

    [Fact]
    public void Last_active_is_relative_in_prague_time()
    {
        var time = new FakeTimeProvider(new DateTimeOffset(2026, 11, 2, 15, 0, 0, TimeSpan.Zero)); // 16:00 in Prague

        Assert.Equal("nikdy", Cz.LastActive(null, time));
        Assert.Equal($"před 5{Nbsp}min", Cz.LastActive(time.GetUtcNow().AddMinutes(-5), time));
        Assert.Equal("dnes 07:45", Cz.LastActive(new DateTimeOffset(2026, 11, 2, 6, 45, 0, TimeSpan.Zero), time));
        Assert.Equal("včera 18:10", Cz.LastActive(new DateTimeOffset(2026, 11, 1, 17, 10, 0, TimeSpan.Zero), time));
        Assert.Equal($"30.{Nbsp}10.", Cz.LastActive(new DateTimeOffset(2026, 10, 30, 12, 0, 0, TimeSpan.Zero), time));
    }
}
