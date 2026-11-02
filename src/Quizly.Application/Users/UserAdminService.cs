using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Quizly.Application.Abstractions;
using Quizly.Application.Auth;
using Quizly.Application.Common;
using Quizly.Domain;

namespace Quizly.Application.Users;

public interface IUserAdminService
{
    Task<IReadOnlyList<UserResponse>> ListAsync(CancellationToken ct);

    Task<Result<UserResponse>> GetAsync(int id, CancellationToken ct);

    Task<Result<CreatedUserResponse>> CreateAsync(CreateUserRequest request, CancellationToken ct);

    Task<Result<UserResponse>> UpdateAsync(int id, UpdateUserRequest request, CancellationToken ct);

    Task<Result<PasswordResponse>> ResetPasswordAsync(int id, CancellationToken ct);

    Task<Result> SetActiveAsync(int id, bool active, CancellationToken ct);
}

internal sealed partial class UserAdminService(
    IAppDbContext db,
    IPasswordHasher<User> hasher,
    IPasswordGenerator passwords,
    IAuthService auth,
    TimeProvider time) : IUserAdminService
{
    public async Task<IReadOnlyList<UserResponse>> ListAsync(CancellationToken ct)
    {
        var rows = await Query(db.Users.OrderBy(u => u.Username)).ToListAsync(ct);
        var today = PragueCalendar.Today(time);
        return rows.Select(r => ToResponse(r, today)).ToList();
    }

    public async Task<Result<UserResponse>> GetAsync(int id, CancellationToken ct)
    {
        var row = await Query(db.Users.Where(u => u.Id == id)).FirstOrDefaultAsync(ct);
        return row is null ? UserNotFound : ToResponse(row, PragueCalendar.Today(time));
    }

    public async Task<Result<CreatedUserResponse>> CreateAsync(CreateUserRequest request, CancellationToken ct)
    {
        var username = (request.Username ?? "").Trim().ToLowerInvariant();
        var displayName = Validator.Clean(request.DisplayName);
        var password = string.IsNullOrEmpty(request.Password) ? passwords.Generate() : request.Password;
        var dailyGoal = request.DailyGoal ?? Limits.DefaultDailyGoal;
        var newCards = request.NewCardsPerDay ?? Limits.DefaultNewCardsPerDay;

        var v = new Validator();
        if (!UsernameRegex().IsMatch(username))
        {
            v.Add("username", $"Uživatelské jméno musí mít {Limits.UsernameMin}–{Limits.UsernameMax} znaků, jen malá písmena a číslice.");
        }
        else if (await db.Users.AnyAsync(u => u.Username == username, ct))
        {
            v.Add("username", "Tohle uživatelské jméno už existuje.");
        }

        v.Text("displayName", displayName, "Zobrazované jméno", Limits.DisplayNameMax);
        v.Text("password", password, "Heslo", Limits.PasswordMax, Limits.PasswordMin);
        ValidateSettings(v, dailyGoal, newCards);
        if (!v.IsValid)
        {
            return v.ToError();
        }

        var user = new User
        {
            Username = username,
            DisplayName = displayName,
            CreatedAt = time.GetUtcNow().UtcDateTime,
            ShopEnabled = request.ShopEnabled,
            Settings = new UserSettings { DailyGoal = dailyGoal, NewCardsPerDay = newCards },
        };
        user.PasswordHash = hasher.HashPassword(user, password);
        db.Users.Add(user);
        await db.SaveChangesAsync(ct);

        var created = await GetAsync(user.Id, ct);
        return new CreatedUserResponse(created.Value!, password);
    }

    public async Task<Result<UserResponse>> UpdateAsync(int id, UpdateUserRequest request, CancellationToken ct)
    {
        var user = await db.Users.Include(u => u.Settings).FirstOrDefaultAsync(u => u.Id == id, ct);
        if (user is null)
        {
            return UserNotFound;
        }

        var displayName = Validator.Clean(request.DisplayName);
        var v = new Validator().Text("displayName", displayName, "Zobrazované jméno", Limits.DisplayNameMax);
        ValidateSettings(v, request.DailyGoal, request.NewCardsPerDay);
        if (!v.IsValid)
        {
            return v.ToError();
        }

        user.DisplayName = displayName;
        user.Settings.DailyGoal = request.DailyGoal;
        user.Settings.NewCardsPerDay = request.NewCardsPerDay;
        user.ShopEnabled = request.ShopEnabled;
        await db.SaveChangesAsync(ct);
        return await GetAsync(id, ct);
    }

    public async Task<Result<PasswordResponse>> ResetPasswordAsync(int id, CancellationToken ct)
    {
        var user = await db.Users.FirstOrDefaultAsync(u => u.Id == id, ct);
        if (user is null)
        {
            return UserNotFound;
        }

        var password = passwords.Generate();
        user.PasswordHash = hasher.HashPassword(user, password);
        await db.SaveChangesAsync(ct);
        await auth.RevokeAllAsync(id, ct);
        return new PasswordResponse(password);
    }

    public async Task<Result> SetActiveAsync(int id, bool active, CancellationToken ct)
    {
        var user = await db.Users.FirstOrDefaultAsync(u => u.Id == id, ct);
        if (user is null)
        {
            return UserNotFound;
        }

        user.IsActive = active;
        await db.SaveChangesAsync(ct);
        if (!active)
        {
            await auth.RevokeAllAsync(id, ct);
        }

        return Result.Ok();
    }

    private static AppError UserNotFound => Errors.NotFound("Uživatel neexistuje.");

    private static void ValidateSettings(Validator v, int dailyGoal, int newCards)
    {
        v.Range("dailyGoal", dailyGoal, "Denní cíl", Limits.DailyGoalMin, Limits.DailyGoalMax);
        v.Range("newCardsPerDay", newCards, "Nové karty denně", 0, Limits.NewCardsPerDayMax);
    }

    private IQueryable<UserRow> Query(IQueryable<User> users) =>
        users.Select(u => new UserRow(
            u,
            u.Settings.DailyGoal,
            u.Settings.NewCardsPerDay,
            db.PointsEntries.Where(p => p.UserId == u.Id).Sum(p => (int?)p.Amount) ?? 0,
            db.DailyActivities.Where(d => d.UserId == u.Id).Sum(d => (int?)d.GradedCount) ?? 0,
            db.DailyActivities.Where(d => d.UserId == u.Id).Sum(d => (int?)d.CorrectCount) ?? 0));

    private static UserResponse ToResponse(UserRow row, DateOnly today)
    {
        var u = row.User;
        var streakAlive = u.LastGoalMetDate is DateOnly last && last >= today.AddDays(-1);
        return new UserResponse(
            u.Id,
            u.Username,
            u.DisplayName,
            u.IsActive,
            row.DailyGoal,
            row.NewCardsPerDay,
            row.Balance,
            streakAlive ? u.CurrentStreak : 0,
            u.BestStreak,
            row.Graded,
            row.Graded == 0 ? null : row.Correct * 100 / row.Graded,
            u.CreatedAt.ToUtcOffset(),
            u.LastActiveAt.ToUtcOffset(),
            u.ShopEnabled);
    }

    [GeneratedRegex("^[a-z0-9]{3,32}$")]
    private static partial Regex UsernameRegex();

    private sealed record UserRow(User User, int DailyGoal, int NewCardsPerDay, int Balance, int Graded, int Correct);
}
