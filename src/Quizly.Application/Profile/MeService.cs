using System.Globalization;
using Microsoft.EntityFrameworkCore;
using Quizly.Application.Abstractions;
using Quizly.Application.Auth;
using Quizly.Application.Common;
using Quizly.Application.Decks;
using Quizly.Application.Learning;
using Quizly.Domain;
using Quizly.Domain.Gamification;

namespace Quizly.Application.Profile;

public interface IMeService
{
    Task<MeResponse> GetAsync(int userId, CancellationToken ct);

    Task<SettingsDto> GetSettingsAsync(int userId, CancellationToken ct);

    Task<Result<SettingsUpdateResponse>> UpdateSettingsAsync(int userId, SettingsDto request, CancellationToken ct);
}

internal sealed class MeService(IAppDbContext db, Progress progress, StudyService study, TimeProvider time) : IMeService
{
    private const string TimeFormat = "HH:mm";

    public async Task<MeResponse> GetAsync(int userId, CancellationToken ct)
    {
        var now = time.GetUtcNow().UtcDateTime;
        var today = PragueCalendar.DayOf(now);
        var user = await db.Users.Include(u => u.Settings).AsNoTracking().FirstAsync(u => u.Id == userId, ct);
        var settings = user.Settings;
        var visible = db.Cards.VisibleTo(userId);
        var unseen = await study.Unseen(userId, visible).CountAsync(ct);

        // Progress on decks the user no longer sees is kept, but not counted.
        var states = db.CardStates.Where(s => s.UserId == userId && visible.Any(c => c.Id == s.CardId));
        var dueReviews = await states.CountAsync(s => s.Due <= now, ct);
        var allowanceToday = await progress.NewAllowanceLeftAsync(userId, settings.NewCardsPerDay, today, ct);

        // The next morning notification: next occurrence of morningTime in Prague.
        var pragueDate = DateOnly.FromDateTime(TimeZoneInfo.ConvertTimeFromUtc(now, PragueCalendar.Zone));
        var nextMorning = AtPrague(pragueDate, settings.MorningTime);
        if (nextMorning <= now)
        {
            nextMorning = AtPrague(pragueDate.AddDays(1), settings.MorningTime);
        }

        var dueByMorning = await states.CountAsync(s => s.Due <= nextMorning, ct);
        var allowanceThen = PragueCalendar.DayOf(nextMorning) == today ? allowanceToday : settings.NewCardsPerDay;

        var since = now.AddDays(-14);
        var recent = await db.ReviewLogs.Where(r => r.UserId == userId && r.ReviewedAt >= since).Select(r => r.ReviewedAt).ToListAsync(ct);
        var smart = SmartTimes.EveningTime(recent);

        return new MeResponse(
            new AuthUserResponse(user.Id, user.Username, user.DisplayName, user.ShopEnabled),
            await progress.SummaryAsync(userId, ct),
            dueReviews + Math.Min(unseen, allowanceToday),
            new ForecastResponse(nextMorning.ToUtcOffset(), dueByMorning + Math.Min(unseen, allowanceThen)),
            smart?.ToString(TimeFormat, CultureInfo.InvariantCulture),
            now.ToUtcOffset());
    }

    public async Task<SettingsDto> GetSettingsAsync(int userId, CancellationToken ct) =>
        ToDto(await db.UserSettings.AsNoTracking().FirstAsync(s => s.UserId == userId, ct));

    public async Task<Result<SettingsUpdateResponse>> UpdateSettingsAsync(int userId, SettingsDto request, CancellationToken ct)
    {
        var v = new Validator()
            .Range("dailyGoal", request.DailyGoal, "Denní cíl", Limits.DailyGoalMin, Limits.DailyGoalMax)
            .Range("newCardsPerDay", request.NewCardsPerDay, "Nové karty denně", 0, Limits.NewCardsPerDayMax);
        var morning = ParseTime(v, "morningTime", request.MorningTime);
        var evening = ParseTime(v, "eveningTime", request.EveningTime);
        var lastCall = ParseTime(v, "lastCallTime", request.LastCallTime);
        var quietFrom = ParseTime(v, "quietFrom", request.QuietFrom);
        var quietTo = ParseTime(v, "quietTo", request.QuietTo);
        if (quietFrom is not null && quietFrom == quietTo)
        {
            v.Add("quietTo", "Tichý režim musí začínat a končit v jiný čas.");
        }

        if (!v.IsValid)
        {
            return v.ToError();
        }

        var now = time.GetUtcNow().UtcDateTime;
        var today = PragueCalendar.DayOf(now);
        await using var transaction = await db.Database.BeginTransactionAsync(ct);
        var user = await progress.LockUserAsync(userId, ct);
        var settings = user.Settings;
        settings.DailyGoal = request.DailyGoal;
        settings.NewCardsPerDay = request.NewCardsPerDay;
        settings.NotificationsEnabled = request.NotificationsEnabled;
        settings.MorningTime = morning!.Value;
        settings.EveningTime = evening!.Value;
        settings.LastCallTime = lastCall!.Value;
        settings.QuietFrom = quietFrom!.Value;
        settings.QuietTo = quietTo!.Value;
        settings.SmartTimes = request.SmartTimes;
        settings.FourRatings = request.FourRatings;

        // A met day stays met; an open day takes the new goal and may be met right away (docs/spec.md §5.3).
        var events = new List<EventResponse>();
        var activity = await db.DailyActivities.FirstOrDefaultAsync(a => a.UserId == userId && a.Date == today, ct);
        if (activity is { GoalMet: false })
        {
            activity.Goal = request.DailyGoal;
            if (activity.GradedCount >= activity.Goal)
            {
                progress.MarkGoalMet(user, activity, now, events);
            }
        }

        await progress.CheckWishlistAsync(userId, now, events, ct);
        await db.SaveChangesAsync(ct);
        await transaction.CommitAsync(ct);

        return new SettingsUpdateResponse(ToDto(settings), await progress.SummaryAsync(userId, ct), events);
    }

    private static DateTime AtPrague(DateOnly day, TimeOnly timeOfDay) =>
        TimeZoneInfo.ConvertTimeToUtc(day.ToDateTime(timeOfDay, DateTimeKind.Unspecified), PragueCalendar.Zone);

    private static TimeOnly? ParseTime(Validator v, string field, string? value)
    {
        if (value is { Length: 5 } && TimeOnly.TryParseExact(value, TimeFormat, CultureInfo.InvariantCulture, DateTimeStyles.None, out var parsed))
        {
            return parsed;
        }

        v.Add(field, "Čas musí být ve tvaru HH:mm.");
        return null;
    }

    private static SettingsDto ToDto(UserSettings s) => new(
        s.DailyGoal,
        s.NewCardsPerDay,
        s.NotificationsEnabled,
        s.MorningTime.ToString(TimeFormat, CultureInfo.InvariantCulture),
        s.EveningTime.ToString(TimeFormat, CultureInfo.InvariantCulture),
        s.LastCallTime.ToString(TimeFormat, CultureInfo.InvariantCulture),
        s.QuietFrom.ToString(TimeFormat, CultureInfo.InvariantCulture),
        s.QuietTo.ToString(TimeFormat, CultureInfo.InvariantCulture),
        s.SmartTimes,
        s.FourRatings);
}
