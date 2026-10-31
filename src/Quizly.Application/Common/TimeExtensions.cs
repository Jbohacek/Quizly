namespace Quizly.Application.Common;

public static class TimeExtensions
{
    /// <summary>A stored UTC instant as a <see cref="DateTimeOffset"/> with offset 0.</summary>
    public static DateTimeOffset ToUtcOffset(this DateTime utc) =>
        new(DateTime.SpecifyKind(utc, DateTimeKind.Utc));

    public static DateTimeOffset? ToUtcOffset(this DateTime? utc) => utc?.ToUtcOffset();
}
