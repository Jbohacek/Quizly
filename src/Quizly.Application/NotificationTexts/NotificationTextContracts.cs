using Quizly.Domain;

namespace Quizly.Application.NotificationTexts;

/// <summary>A notification text as the admin sees it.</summary>
public sealed record NotificationTextResponse(
    int Id,
    NotificationCategory Category,
    string Text,
    bool IsActive,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);

/// <summary>Payload for creating or editing a notification text.</summary>
public sealed record NotificationTextRequest(NotificationCategory Category, string Text, bool IsActive = true);

/// <summary>Text to render with the sample placeholder values.</summary>
public sealed record NotificationPreviewRequest(string Text);

/// <summary>The text with placeholders replaced by sample values.</summary>
public sealed record NotificationPreviewResponse(string Rendered);

/// <summary>One active text in the app's list.</summary>
public sealed record AppNotificationText(int Id, string Text);

/// <summary>All active texts grouped by category, with a version used as the ETag.</summary>
public sealed record AppNotificationTextsResponse(
    string Version,
    IReadOnlyDictionary<string, IReadOnlyList<AppNotificationText>> Categories);
