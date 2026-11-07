using Quizly.Application.Learning;
using Quizly.Domain;
using Quizly.Domain.Scheduling;

namespace Quizly.Tests.Unit;

/// <summary>The times shown under the answer buttons (#31) are what a review at that moment schedules.</summary>
public sealed class ReviewIntervalsTests
{
    private const long Minute = 60;
    private const long Day = 86_400;

    private static readonly DateTime Now = new(2026, 11, 5, 9, 0, 0, DateTimeKind.Utc);

    [Fact]
    public void A_new_card_uses_the_learning_steps_and_Easy_graduates()
    {
        var (intervals, relearn) = ReviewIntervals.For(FsrsCard.New(Now), Now);

        // Steps 1 min and 10 min: Hard on the first step is their average, 5.5 min.
        Assert.Equal(new CardIntervalsResponse(1 * Minute, 330, 10 * Minute, 8 * Day), intervals);

        // After a Nevím the card is back on the first step.
        Assert.Equal(1 * Minute, relearn.DontKnow);
        Assert.Equal(330, relearn.Hard);
        Assert.Equal(10 * Minute, relearn.Know);
        AssertWholeDays(relearn.Easy);
    }

    [Fact]
    public void A_review_card_relearns_on_Nevim_and_otherwise_moves_by_days()
    {
        var card = Graduated(out var due);
        var at = due.AddHours(3);

        var (intervals, relearn) = ReviewIntervals.For(card, at);

        Assert.Equal(10 * Minute, intervals.DontKnow);
        AssertWholeDays(intervals.Hard);
        AssertWholeDays(intervals.Know);
        AssertWholeDays(intervals.Easy);
        Assert.True(intervals.Hard <= intervals.Know && intervals.Know <= intervals.Easy);

        // Relearning has one 10 min step: Again repeats it, Hard is 1.5× it, Good and Easy graduate.
        Assert.Equal(10 * Minute, relearn.DontKnow);
        Assert.Equal(15 * Minute, relearn.Hard);
        AssertWholeDays(relearn.Know);
        AssertWholeDays(relearn.Easy);
    }

    [Fact]
    public void The_intervals_match_what_the_review_then_schedules()
    {
        var card = Graduated(out var due);
        var at = due.AddDays(2);

        var (intervals, relearn) = ReviewIntervals.For(card, at);
        var afterGood = FsrsScheduler.Default.Review(card, FsrsRating.Good, at);
        var afterAgain = FsrsScheduler.Default.Review(card, FsrsRating.Again, at);
        var secondGood = FsrsScheduler.Default.Review(afterAgain, FsrsRating.Good, at.AddMinutes(7));

        Assert.Equal((long)(afterGood.Due - at).TotalSeconds, intervals.Know);
        // The second showing comes minutes later; same-day reviews don't depend on that gap.
        Assert.Equal((long)(secondGood.Due - at.AddMinutes(7)).TotalSeconds, relearn.Know);
    }

    /// <summary>A card answered Vím twice: through both learning steps into Review.</summary>
    private static FsrsCard Graduated(out DateTime due)
    {
        var first = FsrsScheduler.Default.Review(FsrsCard.New(Now), FsrsRating.Good, Now);
        var second = FsrsScheduler.Default.Review(first, FsrsRating.Good, first.Due);
        Assert.Equal(FsrsState.Review, second.State);
        due = second.Due;
        return second;
    }

    private static void AssertWholeDays(long seconds)
    {
        Assert.True(seconds >= Day, $"{seconds} s is less than a day");
        Assert.Equal(0, seconds % Day);
    }
}
