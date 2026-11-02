namespace Quizly.Domain;

// Persistence model. Columns, constraints and indexes: docs/spec.md §2.
// All DateTime values are UTC; DateOnly values are Europe/Prague days.

public class User
{
    public int Id { get; set; }
    public string Username { get; set; } = "";
    public string DisplayName { get; set; } = "";
    public string PasswordHash { get; set; } = "";
    public bool IsActive { get; set; } = true;
    public DateTime CreatedAt { get; set; }
    public DateTime? LastActiveAt { get; set; }
    public int CurrentStreak { get; set; }
    public int BestStreak { get; set; }
    public DateOnly? LastGoalMetDate { get; set; }

    public UserSettings Settings { get; set; } = null!;
}

public class UserSettings
{
    public int UserId { get; set; }
    public int DailyGoal { get; set; } = Limits.DefaultDailyGoal;
    public int NewCardsPerDay { get; set; } = Limits.DefaultNewCardsPerDay;
    public bool NotificationsEnabled { get; set; } = true;
    public TimeOnly MorningTime { get; set; } = new(8, 0);
    public TimeOnly EveningTime { get; set; } = new(18, 30);
    public TimeOnly LastCallTime { get; set; } = new(21, 0);
    public TimeOnly QuietFrom { get; set; } = new(22, 0);
    public TimeOnly QuietTo { get; set; } = new(7, 0);
    public bool SmartTimes { get; set; } = true;

    /// <summary>"Těžké a Snadné": four answer buttons instead of Vím / Nevím (#19).</summary>
    public bool FourRatings { get; set; }

    public User User { get; set; } = null!;
}

public class RefreshToken
{
    public int Id { get; set; }
    public int UserId { get; set; }
    public byte[] TokenHash { get; set; } = [];
    public DateTime CreatedAt { get; set; }
    public DateTime ExpiresAt { get; set; }
    public DateTime? RevokedAt { get; set; }
    public int? ReplacedById { get; set; }

    public User User { get; set; } = null!;
}

public class Deck
{
    public int Id { get; set; }
    public string Name { get; set; } = "";
    public string Description { get; set; } = "";
    public string Color { get; set; } = Limits.DefaultDeckColor;
    public int SortOrder { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }

    /// <summary>"Pro všechny": every user sees the deck. Otherwise only the users in <see cref="Access"/>.</summary>
    public bool ForEveryone { get; set; } = true;

    public List<Card> Cards { get; set; } = [];
    public List<DeckAccess> Access { get; set; } = [];
}

/// <summary>A user who sees a deck that isn't <see cref="Deck.ForEveryone"/>.</summary>
public class DeckAccess
{
    public int DeckId { get; set; }
    public int UserId { get; set; }
}

public class Card
{
    public int Id { get; set; }
    public int DeckId { get; set; }
    public string Question { get; set; } = "";
    public string Answer { get; set; } = "";
    public int SortOrder { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }

    public Deck Deck { get; set; } = null!;
}

public class CardState
{
    public int UserId { get; set; }
    public int CardId { get; set; }
    public FsrsState State { get; set; }
    public short? Step { get; set; }
    public double Stability { get; set; }
    public double Difficulty { get; set; }
    public DateTime Due { get; set; }
    public DateTime LastReview { get; set; }
    public DateTime FirstReview { get; set; }
    public int Reps { get; set; }
    public int Lapses { get; set; }
}

public class ReviewLog
{
    public Guid Id { get; set; }
    public int UserId { get; set; }
    public int CardId { get; set; }
    public Rating Rating { get; set; }
    public FsrsState? StateBefore { get; set; }
    public DateTime ReviewedAt { get; set; }
    public DateOnly Day { get; set; }
    public decimal Multiplier { get; set; }
    public int PointsAwarded { get; set; }
    public int ElapsedDays { get; set; }
    public int ScheduledDays { get; set; }
}

public class DailyActivity
{
    public int UserId { get; set; }
    public DateOnly Date { get; set; }
    public int GradedCount { get; set; }
    public int CorrectCount { get; set; }
    public int Points { get; set; }
    public int Goal { get; set; }
    public bool GoalMet { get; set; }
    public DateTime? GoalMetAt { get; set; }
}

public class PointsEntry
{
    public long Id { get; set; }
    public int UserId { get; set; }
    public int Amount { get; set; }
    public PointsReason Reason { get; set; }
    public string ReferenceId { get; set; } = "";
    public DateTime CreatedAt { get; set; }
}

public class ShopItem
{
    public int Id { get; set; }
    public string Name { get; set; } = "";
    public string Description { get; set; } = "";
    public int Price { get; set; }
    public int InitialStock { get; set; }
    public int Stock { get; set; }
    public bool IsActive { get; set; } = true;
    public int SortOrder { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }

    /// <summary>PostgreSQL <c>xmin</c>, used as the optimistic concurrency token.</summary>
    public uint Version { get; set; }
}

public class Claim
{
    public int Id { get; set; }
    public int UserId { get; set; }
    public int ShopItemId { get; set; }
    public Guid RequestId { get; set; }
    public int Price { get; set; }
    public ClaimStatus Status { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? DecidedAt { get; set; }

    public User User { get; set; } = null!;
    public ShopItem ShopItem { get; set; } = null!;
}

public class WishlistEntry
{
    public int UserId { get; set; }
    public int ShopItemId { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? NotifiedAt { get; set; }
}

public class NotificationText
{
    public int Id { get; set; }
    public NotificationCategory Category { get; set; }
    public string Text { get; set; } = "";
    public bool IsActive { get; set; } = true;
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
}
