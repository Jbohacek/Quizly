namespace Quizly.Application.Decks;

/// <summary>A deck with its card count.</summary>
public sealed record DeckResponse(
    int Id,
    string Name,
    string Description,
    string Color,
    int SortOrder,
    int CardCount,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);

/// <summary>Payload for creating or editing a deck. Omitted color and sort order get defaults on create.</summary>
public sealed record DeckRequest(string Name, string? Description = null, string? Color = null, int? SortOrder = null);

/// <summary>What deleting a deck removes: its cards and the progress of this many users.</summary>
public sealed record DeckDeleteImpact(int Cards, int UsersWithProgress);

/// <summary>A flashcard.</summary>
public sealed record CardResponse(
    int Id,
    int DeckId,
    string Question,
    string Answer,
    int SortOrder,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);

/// <summary>Payload for creating or editing a card. Omitted sort order puts a new card at the end.</summary>
public sealed record CardRequest(string Question, string Answer, int? SortOrder = null);
