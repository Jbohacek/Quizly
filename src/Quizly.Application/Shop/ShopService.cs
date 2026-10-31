using System.Globalization;
using Microsoft.EntityFrameworkCore;
using Quizly.Application.Abstractions;
using Quizly.Application.Common;
using Quizly.Application.Learning;
using Quizly.Domain;

namespace Quizly.Application.Shop;

public interface IShopService
{
    Task<ShopResponse> GetShopAsync(int userId, CancellationToken ct);

    /// <summary>Returns the claim and whether it was created now (false for a repeated request id).</summary>
    Task<Result<(ClaimCreatedResponse Response, bool Created)>> ClaimAsync(int userId, int itemId, ClaimRequest request, CancellationToken ct);

    Task<ClaimListResponse> GetClaimsAsync(int userId, CancellationToken ct);

    Task<Result> AddToWishlistAsync(int userId, int itemId, CancellationToken ct);

    Task RemoveFromWishlistAsync(int userId, int itemId, CancellationToken ct);
}

public interface IClaimAdminService
{
    Task<IReadOnlyList<AdminClaimResponse>> ListAsync(ClaimStatus? status, CancellationToken ct);

    Task<Result<AdminClaimResponse>> ConfirmAsync(int claimId, CancellationToken ct);

    /// <summary>Rejects a pending claim: refunds the points and puts the piece back (docs/spec.md §7.2).</summary>
    Task<Result<AdminClaimResponse>> RejectAsync(int claimId, CancellationToken ct);
}

internal static class ShopErrors
{
    public static AppError ItemNotFound => Errors.NotFound("Odměna neexistuje.");

    public static AppError ClaimNotFound => Errors.NotFound("Nákup neexistuje.");

    public static readonly AppError ItemInactive = Errors.Conflict("itemInactive", "Tahle odměna už není v nabídce.");

    public static readonly AppError SoldOut = Errors.Conflict("soldOut", "Odměna je vyprodaná.");

    public static readonly AppError InsufficientBalance = Errors.Conflict("insufficientBalance", "Na tuhle odměnu ti zatím chybí body.");

    public static readonly AppError ClaimNotPending = Errors.Conflict("claimNotPending", "O nákupu už je rozhodnuto.");
}

internal sealed class ShopService(IAppDbContext db, Progress progress, TimeProvider time) : IShopService
{
    public async Task<ShopResponse> GetShopAsync(int userId, CancellationToken ct)
    {
        var balance = await progress.BalanceAsync(userId, ct);
        var items = await db.ShopItems
            .Where(i => i.IsActive)
            .OrderBy(i => i.SortOrder).ThenBy(i => i.Id)
            .Select(i => new
            {
                Item = i,
                Wishlisted = db.WishlistEntries.Any(w => w.UserId == userId && w.ShopItemId == i.Id),
            })
            .ToListAsync(ct);

        return new ShopResponse(balance, items.Select(x => new AppShopItemResponse(
            x.Item.Id,
            x.Item.Name,
            x.Item.Description,
            x.Item.Price,
            x.Item.Stock,
            x.Item.InitialStock,
            x.Item.Stock == 0,
            x.Wishlisted,
            Math.Max(0, x.Item.Price - balance))).ToList());
    }

    public async Task<Result<(ClaimCreatedResponse Response, bool Created)>> ClaimAsync(
        int userId, int itemId, ClaimRequest request, CancellationToken ct)
    {
        if (request.RequestId == Guid.Empty)
        {
            return Errors.Validation("requestId", "Nákup potřebuje requestId (UUID).");
        }

        await using var transaction = await db.Database.BeginTransactionAsync(ct);

        // Locks in a fixed order (user, then item) so concurrent claims can't deadlock or oversell (docs/spec.md §7.1).
        await progress.LockUserAsync(userId, ct);

        var existing = await db.Claims.Include(c => c.ShopItem).FirstOrDefaultAsync(c => c.RequestId == request.RequestId, ct);
        if (existing is not null)
        {
            return existing.UserId == userId
                ? (new ClaimCreatedResponse(ToResponse(existing), await progress.BalanceAsync(userId, ct)), false)
                : Errors.Validation("requestId", "Tohle requestId už bylo použité.");
        }

        // xmin is a system column that `*` doesn't include; EF needs it as the concurrency token.
        var item = await db.ShopItems.FromSql($"SELECT *, xmin FROM shop_items WHERE id = {itemId} FOR UPDATE").FirstOrDefaultAsync(ct);
        if (item is null)
        {
            return ShopErrors.ItemNotFound;
        }

        if (!item.IsActive)
        {
            return ShopErrors.ItemInactive;
        }

        if (item.Stock < 1)
        {
            return ShopErrors.SoldOut;
        }

        if (await progress.BalanceAsync(userId, ct) < item.Price)
        {
            return ShopErrors.InsufficientBalance;
        }

        var now = time.GetUtcNow().UtcDateTime;
        var claim = new Claim
        {
            UserId = userId,
            ShopItemId = item.Id,
            ShopItem = item,
            RequestId = request.RequestId,
            Price = item.Price,
            Status = ClaimStatus.Pending,
            CreatedAt = now,
        };
        db.Claims.Add(claim);
        item.Stock--;
        await db.SaveChangesAsync(ct);

        db.PointsEntries.Add(new PointsEntry
        {
            UserId = userId,
            Amount = -item.Price,
            Reason = PointsReason.Claim,
            ReferenceId = claim.Id.ToString(CultureInfo.InvariantCulture),
            CreatedAt = now,
        });
        await db.SaveChangesAsync(ct);
        await transaction.CommitAsync(ct);

        return (new ClaimCreatedResponse(ToResponse(claim), await progress.BalanceAsync(userId, ct)), true);
    }

    public async Task<ClaimListResponse> GetClaimsAsync(int userId, CancellationToken ct)
    {
        var claims = await db.Claims.Include(c => c.ShopItem)
            .Where(c => c.UserId == userId)
            .OrderByDescending(c => c.CreatedAt).ThenByDescending(c => c.Id)
            .ToListAsync(ct);
        return new ClaimListResponse(claims.Select(ToResponse).ToList());
    }

    public async Task<Result> AddToWishlistAsync(int userId, int itemId, CancellationToken ct)
    {
        var item = await db.ShopItems.FirstOrDefaultAsync(i => i.Id == itemId && i.IsActive, ct);
        if (item is null)
        {
            return ShopErrors.ItemNotFound;
        }

        if (await db.WishlistEntries.AnyAsync(w => w.UserId == userId && w.ShopItemId == itemId, ct))
        {
            return Result.Ok();
        }

        // Already affordable when hearted: no "reached" event later, the user can see it (docs/spec.md §6.4).
        var now = time.GetUtcNow().UtcDateTime;
        var affordable = await progress.BalanceAsync(userId, ct) >= item.Price;
        db.WishlistEntries.Add(new WishlistEntry { UserId = userId, ShopItemId = itemId, CreatedAt = now, NotifiedAt = affordable ? now : null });
        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException)
        {
            // A parallel PUT of the same heart won; PUT is idempotent.
        }

        return Result.Ok();
    }

    public async Task RemoveFromWishlistAsync(int userId, int itemId, CancellationToken ct) =>
        await db.WishlistEntries.Where(w => w.UserId == userId && w.ShopItemId == itemId).ExecuteDeleteAsync(ct);

    internal static ClaimResponse ToResponse(Claim c) =>
        new(c.Id, c.ShopItemId, c.ShopItem.Name, c.Price, c.Status, c.CreatedAt.ToUtcOffset(), c.DecidedAt.ToUtcOffset());
}

internal sealed class ClaimAdminService(IAppDbContext db, TimeProvider time) : IClaimAdminService
{
    public async Task<IReadOnlyList<AdminClaimResponse>> ListAsync(ClaimStatus? status, CancellationToken ct)
    {
        var claims = await db.Claims.Include(c => c.User).Include(c => c.ShopItem)
            .Where(c => status == null || c.Status == status)
            .OrderByDescending(c => c.CreatedAt).ThenByDescending(c => c.Id)
            .ToListAsync(ct);
        return claims.Select(ToResponse).ToList();
    }

    public Task<Result<AdminClaimResponse>> ConfirmAsync(int claimId, CancellationToken ct) =>
        DecideAsync(claimId, ClaimStatus.Confirmed, ct);

    public Task<Result<AdminClaimResponse>> RejectAsync(int claimId, CancellationToken ct) =>
        DecideAsync(claimId, ClaimStatus.Rejected, ct);

    private async Task<Result<AdminClaimResponse>> DecideAsync(int claimId, ClaimStatus decision, CancellationToken ct)
    {
        await using var transaction = await db.Database.BeginTransactionAsync(ct);
        var claim = await db.Claims.FromSql($"SELECT * FROM claims WHERE id = {claimId} FOR UPDATE").FirstOrDefaultAsync(ct);
        if (claim is null)
        {
            return ShopErrors.ClaimNotFound;
        }

        if (claim.Status != ClaimStatus.Pending)
        {
            return ShopErrors.ClaimNotPending;
        }

        var now = time.GetUtcNow().UtcDateTime;
        claim.Status = decision;
        claim.DecidedAt = now;
        if (decision == ClaimStatus.Rejected)
        {
            db.PointsEntries.Add(new PointsEntry
            {
                UserId = claim.UserId,
                Amount = claim.Price,
                Reason = PointsReason.Refund,
                ReferenceId = claim.Id.ToString(CultureInfo.InvariantCulture),
                CreatedAt = now,
            });
            await db.ShopItems.Where(i => i.Id == claim.ShopItemId)
                .ExecuteUpdateAsync(s => s.SetProperty(i => i.Stock, i => i.Stock + 1), ct);
        }

        await db.SaveChangesAsync(ct);
        await transaction.CommitAsync(ct);

        await db.Entry(claim).Reference(c => c.User).LoadAsync(ct);
        await db.Entry(claim).Reference(c => c.ShopItem).LoadAsync(ct);
        return ToResponse(claim);
    }

    private static AdminClaimResponse ToResponse(Claim c) => new(
        c.Id,
        c.UserId,
        c.User.Username,
        c.User.DisplayName,
        c.ShopItemId,
        c.ShopItem.Name,
        c.Price,
        c.Status,
        c.CreatedAt.ToUtcOffset(),
        c.DecidedAt.ToUtcOffset());
}
