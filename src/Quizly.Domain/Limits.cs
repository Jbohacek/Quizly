namespace Quizly.Domain;

/// <summary>Validation limits and defaults from docs/spec.md §8.</summary>
public static class Limits
{
    public const int UsernameMin = 3;
    public const int UsernameMax = 32;
    public const int DisplayNameMax = 50;
    public const int PasswordMin = 8;
    public const int PasswordMax = 128;
    public const int GeneratedPasswordLength = 12;

    public const int DeckNameMax = 100;
    public const int DeckDescriptionMax = 500;
    public const string DefaultDeckColor = "#BAD69B";

    public const int QuestionMax = 500;
    public const int AnswerMax = 2000;
    public const int TagNameMax = 30;
    public const int TagsPerCardMax = 10;

    public const int ShopItemNameMax = 100;
    public const int ShopItemDescriptionMax = 500;
    public const int PriceMin = 1;
    public const int PriceMax = 1_000_000;
    public const int StockMax = 10_000;

    public const int NotificationTextMax = 300;

    public const int DailyGoalMin = 1;
    public const int DailyGoalMax = 500;
    public const int DefaultDailyGoal = 20;
    public const int NewCardsPerDayMax = 100;
    public const int DefaultNewCardsPerDay = 5;

    public static readonly IReadOnlyList<string> Placeholders =
        ["due", "left", "done", "goal", "streak", "multiplier", "item", "points"];
}
