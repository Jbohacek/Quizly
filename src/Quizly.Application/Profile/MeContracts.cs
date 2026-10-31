using Quizly.Application.Auth;
using Quizly.Application.Learning;

namespace Quizly.Application.Profile;

/// <summary>When the next morning notification fires and how many cards will wait then.</summary>
public sealed record ForecastResponse(DateTimeOffset NextMorning, int DueByNextMorning);

/// <summary>Profile, summary, due counts and the smart evening time (docs/api.md §3).</summary>
public sealed record MeResponse(
    AuthUserResponse User,
    SummaryResponse Summary,
    int DueNow,
    ForecastResponse Forecast,
    string? SmartEveningTime,
    DateTimeOffset ServerTime);

/// <summary>User settings. Times are <c>HH:mm</c> in Europe/Prague.</summary>
public sealed record SettingsDto(
    int DailyGoal,
    int NewCardsPerDay,
    bool NotificationsEnabled,
    string MorningTime,
    string EveningTime,
    string LastCallTime,
    string QuietFrom,
    string QuietTo,
    bool SmartTimes);

/// <summary>Saved settings with the summary and events (lowering the goal can complete today).</summary>
public sealed record SettingsUpdateResponse(SettingsDto Settings, SummaryResponse Summary, IReadOnlyList<EventResponse> Events);
