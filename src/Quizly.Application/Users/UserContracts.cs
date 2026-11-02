namespace Quizly.Application.Users;

/// <summary>An app user as the admin sees it.</summary>
public sealed record UserResponse(
    int Id,
    string Username,
    string DisplayName,
    bool IsActive,
    int DailyGoal,
    int NewCardsPerDay,
    int Balance,
    int Streak,
    int BestStreak,
    int TotalReviews,
    int? SuccessRate,
    DateTimeOffset CreatedAt,
    DateTimeOffset? LastActiveAt,
    bool ShopEnabled);

/// <summary>Payload for creating an app user. Without a password one is generated.</summary>
public sealed record CreateUserRequest(
    string Username,
    string DisplayName,
    string? Password = null,
    int? DailyGoal = null,
    int? NewCardsPerDay = null,
    bool ShopEnabled = true);

/// <summary>Payload for editing an app user.</summary>
public sealed record UpdateUserRequest(string DisplayName, int DailyGoal, int NewCardsPerDay, bool ShopEnabled = true);

/// <summary>A created user and their password, shown once.</summary>
public sealed record CreatedUserResponse(UserResponse User, string Password);

/// <summary>A newly generated password, shown once.</summary>
public sealed record PasswordResponse(string Password);
