using Quizly.Domain.Scheduling;

namespace Quizly.Application.Learning;

/// <summary>
/// The time to the next review each answer would give a card (#31, docs/api.md §5), in whole seconds.
/// The app formats them in Czech; the server only does the FSRS math.
/// </summary>
internal static class ReviewIntervals
{
    /// <summary>
    /// Intervals for the card as it is now, and for its second showing in the same session.
    /// Only a Nevím card comes back in a session, so the second set is the card after Again. FSRS same-day
    /// steps and short-term stability don't depend on how long ago the card was shown, so computing it at
    /// <paramref name="now"/> gives what the second answer will schedule.
    /// </summary>
    public static (CardIntervalsResponse Intervals, CardIntervalsResponse RelearnIntervals) For(FsrsCard card, DateTime now) =>
        (Of(card, now), Of(FsrsScheduler.Default.Review(card, FsrsRating.Again, now), now));

    private static CardIntervalsResponse Of(FsrsCard card, DateTime now) => new(
        Seconds(card, FsrsRating.Again, now),
        Seconds(card, FsrsRating.Hard, now),
        Seconds(card, FsrsRating.Good, now),
        Seconds(card, FsrsRating.Easy, now));

    private static long Seconds(FsrsCard card, FsrsRating rating, DateTime now) =>
        Math.Max(0, (long)Math.Round((FsrsScheduler.Default.Review(card, rating, now).Due - now).TotalSeconds));
}
