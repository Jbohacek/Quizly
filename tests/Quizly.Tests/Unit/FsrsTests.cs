using System.Globalization;
using System.Text.Json;
using Quizly.Domain;
using Quizly.Domain.Scheduling;

namespace Quizly.Tests.Unit;

/// <summary>The C# scheduler must reproduce every step of docs/fsrs/fsrs6-reference-vectors.json (py-fsrs 6.3.2).</summary>
public sealed class FsrsTests
{
    private const double Tolerance = 1e-9;

    private static readonly JsonDocument Vectors = JsonDocument.Parse(
        File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "TestData", "fsrs6-reference-vectors.json")));

    public static TheoryData<string> CaseNames()
    {
        var names = new TheoryData<string>();
        foreach (var c in Vectors.RootElement.GetProperty("cases").EnumerateArray())
        {
            names.Add(c.GetProperty("name").GetString()!);
        }

        return names;
    }

    [Fact]
    public void Vectors_use_the_quizly_configuration()
    {
        var config = Vectors.RootElement.GetProperty("scheduler");
        var scheduler = FsrsScheduler.Default;

        Assert.Equal(
            config.GetProperty("parameters").EnumerateArray().Select(p => p.GetDouble()),
            FsrsScheduler.DefaultParameters);
        Assert.Equal(config.GetProperty("desired_retention").GetDouble(), scheduler.DesiredRetention);
        Assert.Equal(config.GetProperty("learning_steps").EnumerateArray().Select(s => TimeSpan.FromSeconds(s.GetInt32())), scheduler.LearningSteps);
        Assert.Equal(config.GetProperty("relearning_steps").EnumerateArray().Select(s => TimeSpan.FromSeconds(s.GetInt32())), scheduler.RelearningSteps);
        Assert.Equal(config.GetProperty("maximum_interval").GetInt32(), scheduler.MaximumInterval);
        Assert.False(config.GetProperty("enable_fuzzing").GetBoolean());
        Assert.Equal(88, Vectors.RootElement.GetProperty("cases").EnumerateArray().Sum(c => c.GetProperty("steps").GetArrayLength()));
    }

    [Theory]
    [MemberData(nameof(CaseNames))]
    public void Reproduces_reference_case(string name)
    {
        var testCase = Vectors.RootElement.GetProperty("cases").EnumerateArray()
            .First(c => c.GetProperty("name").GetString() == name);
        var steps = testCase.GetProperty("steps").EnumerateArray().ToList();
        var card = FsrsCard.New(Instant(steps[0].GetProperty("before").GetProperty("due")));

        for (var i = 0; i < steps.Count; i++)
        {
            var step = steps[i];
            var at = Instant(step.GetProperty("reviewedAt"));
            var rating = (FsrsRating)step.GetProperty("rating").GetInt32();
            AssertCard(step.GetProperty("before"), card, $"{name} step {i} before");
            AssertClose(step.GetProperty("retrievabilityBefore").GetDouble(), FsrsScheduler.Default.Retrievability(card, at), $"{name} step {i} R");
            Assert.Equal(step.GetProperty("elapsedDays").GetInt32(), FsrsScheduler.ElapsedDays(card, at));

            card = FsrsScheduler.Default.Review(card, rating, at);

            AssertCard(step.GetProperty("after"), card, $"{name} step {i} after");
            Assert.Equal(step.GetProperty("scheduledDays").GetInt32(), FsrsScheduler.ScheduledDays(card, at));
        }
    }

    [Fact]
    public void New_card_answered_know_then_know_graduates_to_review()
    {
        var start = new DateTime(2026, 11, 2, 7, 0, 0, DateTimeKind.Utc);

        var first = FsrsScheduler.Default.Review(FsrsCard.New(start), FsrsRating.Good, start);
        var second = FsrsScheduler.Default.Review(first, FsrsRating.Good, first.Due);

        Assert.Equal((FsrsState.Learning, 1, start.AddMinutes(10)), (first.State, first.Step, first.Due));
        Assert.Equal((FsrsState.Review, (int?)null, first.Due.AddDays(2)), (second.State, second.Step, second.Due));
    }

    private static void AssertCard(JsonElement expected, FsrsCard actual, string where)
    {
        Assert.True(Enum.Parse<FsrsState>(expected.GetProperty("state").GetString()!) == actual.State, $"{where}: state");
        Assert.True(Nullable(expected.GetProperty("step"), e => e.GetInt32()) == actual.Step, $"{where}: step");
        AssertClose(Nullable(expected.GetProperty("stability"), e => e.GetDouble()), actual.Stability, $"{where}: stability");
        AssertClose(Nullable(expected.GetProperty("difficulty"), e => e.GetDouble()), actual.Difficulty, $"{where}: difficulty");
        Assert.True(Instant(expected.GetProperty("due")) == actual.Due, $"{where}: due {actual.Due:O}");
        var lastReview = expected.GetProperty("lastReview");
        Assert.True((lastReview.ValueKind == JsonValueKind.Null ? null : Instant(lastReview)) == actual.LastReview, $"{where}: lastReview");
    }

    private static void AssertClose(double? expected, double? actual, string where)
    {
        if (expected is null || actual is null)
        {
            Assert.True(expected == actual, $"{where}: expected {expected}, got {actual}");
            return;
        }

        var scale = Math.Max(1, Math.Abs(expected.Value));
        Assert.True(Math.Abs(expected.Value - actual.Value) <= Tolerance * scale, $"{where}: expected {expected}, got {actual}");
    }

    private static T? Nullable<T>(JsonElement element, Func<JsonElement, T> read)
        where T : struct =>
        element.ValueKind == JsonValueKind.Null ? null : read(element);

    private static DateTime Instant(JsonElement element) =>
        DateTime.Parse(element.GetString()!, CultureInfo.InvariantCulture, DateTimeStyles.AdjustToUniversal | DateTimeStyles.AssumeUniversal);
}
