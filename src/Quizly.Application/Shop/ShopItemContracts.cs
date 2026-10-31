namespace Quizly.Application.Shop;

/// <summary>A shop reward as the admin sees it.</summary>
public sealed record ShopItemResponse(
    int Id,
    string Name,
    string Description,
    int Price,
    int InitialStock,
    int Stock,
    bool IsActive,
    int SortOrder,
    int PendingClaims,
    int OnWishlists,
    uint Version,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt);

/// <summary>Payload for creating a shop reward.</summary>
public sealed record CreateShopItemRequest(
    string Name,
    string? Description,
    int Price,
    int InitialStock,
    bool IsActive = true,
    int? SortOrder = null);

/// <summary>Payload for editing a shop reward. <see cref="Version"/> must match the version that was read.</summary>
public sealed record UpdateShopItemRequest(
    string Name,
    string? Description,
    int Price,
    int InitialStock,
    bool IsActive,
    int SortOrder,
    uint Version);
