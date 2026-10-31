namespace Quizly.Domain.Scheduling;

/// <summary>FSRS rating as in the reference implementation. Quizly only produces Again and Good.</summary>
public enum FsrsRating
{
    Again = 1,
    Hard = 2,
    Good = 3,
    Easy = 4,
}

/// <summary>
/// FSRS memory state of one card. A never-reviewed card is <see cref="New"/>:
/// Learning, step 0, no stability/difficulty, no last review.
/// </summary>
public readonly record struct FsrsCard(
    FsrsState State,
    int? Step,
    double? Stability,
    double? Difficulty,
    DateTime Due,
    DateTime? LastReview)
{
    public static FsrsCard New(DateTime due) => new(FsrsState.Learning, 0, null, null, due, null);
}

/// <summary>
/// FSRS-6 scheduler, a line-by-line port of py-fsrs 6.3.2 <c>Scheduler.review_card</c>
/// (docs/spec.md §3). Fuzz is off. All instants are UTC.
/// </summary>
public sealed class FsrsScheduler
{
    public static readonly IReadOnlyList<double> DefaultParameters =
    [
        0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722, 0.1666, 0.796,
        1.4835, 0.0614, 0.2629, 1.6483, 0.6014, 1.8729, 0.5425, 0.0912, 0.0658, 0.1542,
    ];

    private const double StabilityMin = 0.001;
    private const double MinDifficulty = 1.0;
    private const double MaxDifficulty = 10.0;

    private readonly double[] _w;
    private readonly double _decay;
    private readonly double _factor;

    public FsrsScheduler(
        IReadOnlyList<double>? parameters = null,
        double desiredRetention = 0.9,
        IReadOnlyList<TimeSpan>? learningSteps = null,
        IReadOnlyList<TimeSpan>? relearningSteps = null,
        int maximumInterval = 36500)
    {
        _w = [.. parameters ?? DefaultParameters];
        if (_w.Length != 21)
        {
            throw new ArgumentException("FSRS-6 needs 21 parameters.", nameof(parameters));
        }

        DesiredRetention = desiredRetention;
        LearningSteps = learningSteps ?? [TimeSpan.FromMinutes(1), TimeSpan.FromMinutes(10)];
        RelearningSteps = relearningSteps ?? [TimeSpan.FromMinutes(10)];
        MaximumInterval = maximumInterval;
        _decay = -_w[20];
        _factor = Math.Pow(0.9, 1 / _decay) - 1;
    }

    /// <summary>The Quizly configuration: default parameters, retention 0.9, steps 1 m/10 m, relearning 10 m.</summary>
    public static FsrsScheduler Default { get; } = new();

    public double DesiredRetention { get; }

    public IReadOnlyList<TimeSpan> LearningSteps { get; }

    public IReadOnlyList<TimeSpan> RelearningSteps { get; }

    public int MaximumInterval { get; }

    /// <summary>Probability of recall at <paramref name="now"/> (0 for a card without a review).</summary>
    public double Retrievability(FsrsCard card, DateTime now)
    {
        if (card.LastReview is not DateTime last || card.Stability is not double stability)
        {
            return 0;
        }

        var elapsedDays = Math.Max(0, WholeDays(now - last));
        return Math.Pow(1 + (_factor * elapsedDays / stability), _decay);
    }

    public FsrsCard Review(FsrsCard card, FsrsRating rating, DateTime reviewedAt)
    {
        int? daysSinceLastReview = card.LastReview is DateTime last ? WholeDays(reviewedAt - last) : null;
        var state = card.State;
        var step = card.Step;
        double stability;
        double difficulty;
        TimeSpan interval;

        switch (state)
        {
            case FsrsState.Learning:
            {
                if (card.Stability is null || card.Difficulty is null)
                {
                    stability = InitialStability(rating);
                    difficulty = InitialDifficulty(rating, clamp: true);
                }
                else if (daysSinceLastReview < 1)
                {
                    stability = ShortTermStability(card.Stability.Value, rating);
                    difficulty = NextDifficulty(card.Difficulty.Value, rating);
                }
                else
                {
                    stability = NextStability(card.Difficulty.Value, card.Stability.Value, Retrievability(card, reviewedAt), rating);
                    difficulty = NextDifficulty(card.Difficulty.Value, rating);
                }

                (state, step, interval) = StepInterval(LearningSteps, step!.Value, rating, stability);
                break;
            }

            case FsrsState.Review:
            {
                var s = card.Stability!.Value;
                var d = card.Difficulty!.Value;
                stability = daysSinceLastReview < 1
                    ? ShortTermStability(s, rating)
                    : NextStability(d, s, Retrievability(card, reviewedAt), rating);
                difficulty = NextDifficulty(d, rating);

                if (rating == FsrsRating.Again && RelearningSteps.Count > 0)
                {
                    state = FsrsState.Relearning;
                    step = 0;
                    interval = RelearningSteps[0];
                }
                else
                {
                    interval = TimeSpan.FromDays(NextInterval(stability));
                }

                break;
            }

            case FsrsState.Relearning:
            {
                var s = card.Stability!.Value;
                var d = card.Difficulty!.Value;
                stability = daysSinceLastReview < 1
                    ? ShortTermStability(s, rating)
                    : NextStability(d, s, Retrievability(card, reviewedAt), rating);
                difficulty = NextDifficulty(d, rating);

                (state, step, interval) = StepInterval(RelearningSteps, step!.Value, rating, stability, relearning: true);
                break;
            }

            default:
                throw new ArgumentOutOfRangeException(nameof(card), card.State, "Unknown card state.");
        }

        return new FsrsCard(state, step, stability, difficulty, reviewedAt + interval, reviewedAt);
    }

    /// <summary>Interval in whole days for a stability (round half to even, as Python's round).</summary>
    public int NextInterval(double stability)
    {
        var days = stability / _factor * (Math.Pow(DesiredRetention, 1 / _decay) - 1);
        var rounded = (int)Math.Round(days, MidpointRounding.ToEven);
        return Math.Min(Math.Max(rounded, 1), MaximumInterval);
    }

    /// <summary>The learning/relearning step logic shared by both states.</summary>
    private (FsrsState State, int? Step, TimeSpan Interval) StepInterval(
        IReadOnlyList<TimeSpan> steps, int step, FsrsRating rating, double stability, bool relearning = false)
    {
        var current = relearning ? FsrsState.Relearning : FsrsState.Learning;
        TimeSpan ToReview() => TimeSpan.FromDays(NextInterval(stability));

        // A card scheduled with more steps than the current configuration has graduates.
        if (steps.Count == 0 || (step >= steps.Count && rating != FsrsRating.Again))
        {
            return (FsrsState.Review, null, ToReview());
        }

        switch (rating)
        {
            case FsrsRating.Again:
                return (current, 0, steps[0]);

            case FsrsRating.Hard:
                if (step == 0 && steps.Count == 1)
                {
                    return (current, step, steps[0] * 1.5);
                }

                if (step == 0 && steps.Count >= 2)
                {
                    return (current, step, (steps[0] + steps[1]) / 2.0);
                }

                return (current, step, steps[step]);

            case FsrsRating.Good:
                return step + 1 == steps.Count
                    ? (FsrsState.Review, null, ToReview())
                    : (current, step + 1, steps[step + 1]);

            case FsrsRating.Easy:
                return (FsrsState.Review, null, ToReview());

            default:
                throw new ArgumentOutOfRangeException(nameof(rating), rating, "Unknown rating.");
        }
    }

    private double InitialStability(FsrsRating rating) => Math.Max(_w[(int)rating - 1], StabilityMin);

    private double InitialDifficulty(FsrsRating rating, bool clamp)
    {
        var difficulty = _w[4] - Math.Exp(_w[5] * ((int)rating - 1)) + 1;
        return clamp ? ClampDifficulty(difficulty) : difficulty;
    }

    private double ShortTermStability(double stability, FsrsRating rating)
    {
        var increase = Math.Exp(_w[17] * ((int)rating - 3 + _w[18])) * Math.Pow(stability, -_w[19]);
        if (rating != FsrsRating.Again)
        {
            increase = Math.Max(increase, 1.0);
        }

        return Math.Max(stability * increase, StabilityMin);
    }

    private double NextDifficulty(double difficulty, FsrsRating rating)
    {
        var easy = InitialDifficulty(FsrsRating.Easy, clamp: false);
        var delta = -(_w[6] * ((int)rating - 3));
        var damped = difficulty + ((10.0 - difficulty) * delta / 9.0);
        var meanReverted = (_w[7] * easy) + ((1 - _w[7]) * damped);
        return ClampDifficulty(meanReverted);
    }

    private double NextStability(double difficulty, double stability, double retrievability, FsrsRating rating)
    {
        var next = rating == FsrsRating.Again
            ? NextForgetStability(difficulty, stability, retrievability)
            : NextRecallStability(difficulty, stability, retrievability, rating);
        return Math.Max(next, StabilityMin);
    }

    private double NextForgetStability(double difficulty, double stability, double retrievability)
    {
        var longTerm = _w[11]
            * Math.Pow(difficulty, -_w[12])
            * (Math.Pow(stability + 1, _w[13]) - 1)
            * Math.Exp((1 - retrievability) * _w[14]);
        var shortTerm = stability / Math.Exp(_w[17] * _w[18]);
        return Math.Min(longTerm, shortTerm);
    }

    private double NextRecallStability(double difficulty, double stability, double retrievability, FsrsRating rating)
    {
        var hardPenalty = rating == FsrsRating.Hard ? _w[15] : 1;
        var easyBonus = rating == FsrsRating.Easy ? _w[16] : 1;
        return stability * (1
            + (Math.Exp(_w[8])
               * (11 - difficulty)
               * Math.Pow(stability, -_w[9])
               * (Math.Exp((1 - retrievability) * _w[10]) - 1)
               * hardPenalty
               * easyBonus));
    }

    private static double ClampDifficulty(double difficulty) => Math.Min(Math.Max(difficulty, MinDifficulty), MaxDifficulty);

    /// <summary>Python <c>timedelta.days</c>: whole days, floored.</summary>
    public static int WholeDays(TimeSpan span) => (int)Math.Floor(span.TotalDays);

    /// <summary>Review-log <c>elapsed_days</c>: whole days since the previous review, 0 for the first.</summary>
    public static int ElapsedDays(FsrsCard before, DateTime reviewedAt) =>
        before.LastReview is DateTime last ? WholeDays(reviewedAt - last) : 0;

    /// <summary>Review-log <c>scheduled_days</c>: whole days until the new due if the card is in Review, else 0.</summary>
    public static int ScheduledDays(FsrsCard after, DateTime reviewedAt) =>
        after.State == FsrsState.Review ? WholeDays(after.Due - reviewedAt) : 0;
}
