using Quizly.Domain;

namespace Quizly.Application.Shop;

/// <summary>A reward in the app's shop.</summary>
public sealed record AppShopItemResponse(
    int Id,
    string Name,
    string Description,
    int Price,
    int Stock,
    int InitialStock,
    bool SoldOut,
    bool Wishlisted,
    int Missing);

/// <summary>The shop and the user's balance.</summary>
public sealed record ShopResponse(int Balance, IReadOnlyList<AppShopItemResponse> Items);

/// <summary>Buy a reward. <see cref="RequestId"/> (UUID from the phone) makes a retried purchase safe.</summary>
public sealed record ClaimRequest(Guid RequestId);

/// <summary>A purchase.</summary>
public sealed record ClaimResponse(
    int Id,
    int ItemId,
    string ItemName,
    int Price,
    ClaimStatus Status,
    DateTimeOffset CreatedAt,
    DateTimeOffset? DecidedAt);

/// <summary>A new purchase and the balance after it.</summary>
public sealed record ClaimCreatedResponse(ClaimResponse Claim, int Balance);

/// <summary>The user's purchases, newest first.</summary>
public sealed record ClaimListResponse(IReadOnlyList<ClaimResponse> Items);

/// <summary>A purchase as the admin sees it.</summary>
public sealed record AdminClaimResponse(
    int Id,
    int UserId,
    string Username,
    string DisplayName,
    int ItemId,
    string ItemName,
    int Price,
    ClaimStatus Status,
    DateTimeOffset CreatedAt,
    DateTimeOffset? DecidedAt);
