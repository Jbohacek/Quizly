using Microsoft.EntityFrameworkCore;
using Quizly.Application.Abstractions;
using Quizly.Application.Common;
using Quizly.Domain;

namespace Quizly.Application.Shop;

public interface IShopItemService
{
    Task<IReadOnlyList<ShopItemResponse>> ListAsync(CancellationToken ct);

    Task<Result<ShopItemResponse>> GetAsync(int id, CancellationToken ct);

    Task<Result<ShopItemResponse>> CreateAsync(CreateShopItemRequest request, CancellationToken ct);

    Task<Result<ShopItemResponse>> UpdateAsync(int id, UpdateShopItemRequest request, CancellationToken ct);

    Task<Result> DeleteAsync(int id, CancellationToken ct);
}

internal sealed class ShopItemService(IAppDbContext db, TimeProvider time) : IShopItemService
{
    public async Task<IReadOnlyList<ShopItemResponse>> ListAsync(CancellationToken ct) =>
        await Project(db.ShopItems.OrderBy(i => i.SortOrder).ThenBy(i => i.Id)).ToListAsync(ct);

    public async Task<Result<ShopItemResponse>> GetAsync(int id, CancellationToken ct)
    {
        var item = await Project(db.ShopItems.Where(i => i.Id == id)).FirstOrDefaultAsync(ct);
        return item is null ? ItemNotFound : item;
    }

    public async Task<Result<ShopItemResponse>> CreateAsync(CreateShopItemRequest request, CancellationToken ct)
    {
        var name = Validator.Clean(request.Name);
        var description = Validator.Clean(request.Description);
        var v = Validate(name, description, request.Price, request.InitialStock);
        if (!v.IsValid)
        {
            return v.ToError();
        }

        var now = time.GetUtcNow().UtcDateTime;
        var item = new ShopItem
        {
            Name = name,
            Description = description,
            Price = request.Price,
            InitialStock = request.InitialStock,
            Stock = request.InitialStock,
            IsActive = request.IsActive,
            SortOrder = request.SortOrder ?? (await db.ShopItems.MaxAsync(i => (int?)i.SortOrder, ct) ?? -1) + 1,
            CreatedAt = now,
            UpdatedAt = now,
        };
        db.ShopItems.Add(item);
        await db.SaveChangesAsync(ct);
        return await GetAsync(item.Id, ct);
    }

    public async Task<Result<ShopItemResponse>> UpdateAsync(int id, UpdateShopItemRequest request, CancellationToken ct)
    {
        var item = await db.ShopItems.FirstOrDefaultAsync(i => i.Id == id, ct);
        if (item is null)
        {
            return ItemNotFound;
        }

        var name = Validator.Clean(request.Name);
        var description = Validator.Clean(request.Description);
        var v = Validate(name, description, request.Price, request.InitialStock);

        // Changing the total by Δ changes what's left by Δ too (docs/spec.md §2.10).
        var newStock = item.Stock + (request.InitialStock - item.InitialStock);
        if (v.IsValid && newStock < 0)
        {
            var sold = item.InitialStock - item.Stock;
            v.Add("initialStock", $"Počet kusů nejde snížit pod počet už prodaných ({sold}).");
        }

        if (!v.IsValid)
        {
            return v.ToError();
        }

        item.Name = name;
        item.Description = description;
        item.Price = request.Price;
        item.InitialStock = request.InitialStock;
        item.Stock = newStock;
        item.IsActive = request.IsActive;
        item.SortOrder = request.SortOrder;
        item.UpdatedAt = time.GetUtcNow().UtcDateTime;

        // The version the admin read must still be the current one.
        db.Entry(item).Property(i => i.Version).OriginalValue = request.Version;
        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateConcurrencyException)
        {
            return Errors.ConcurrencyConflict;
        }

        return await GetAsync(id, ct);
    }

    public async Task<Result> DeleteAsync(int id, CancellationToken ct)
    {
        if (!await db.ShopItems.AnyAsync(i => i.Id == id, ct))
        {
            return ItemNotFound;
        }

        if (await db.Claims.AnyAsync(c => c.ShopItemId == id, ct))
        {
            return Errors.HasClaims;
        }

        await db.ShopItems.Where(i => i.Id == id).ExecuteDeleteAsync(ct);
        return Result.Ok();
    }

    private static AppError ItemNotFound => Errors.NotFound("Odměna neexistuje.");

    private static Validator Validate(string name, string description, int price, int initialStock) =>
        new Validator()
            .Text("name", name, "Název", Limits.ShopItemNameMax)
            .Text("description", description, "Popis", Limits.ShopItemDescriptionMax, min: 0)
            .Range("price", price, "Cena", Limits.PriceMin, Limits.PriceMax)
            .Range("initialStock", initialStock, "Počet kusů", 0, Limits.StockMax);

    private IQueryable<ShopItemResponse> Project(IQueryable<ShopItem> items) =>
        items.Select(i => new ShopItemResponse(
            i.Id,
            i.Name,
            i.Description,
            i.Price,
            i.InitialStock,
            i.Stock,
            i.IsActive,
            i.SortOrder,
            db.Claims.Count(c => c.ShopItemId == i.Id && c.Status == ClaimStatus.Pending),
            db.WishlistEntries.Count(w => w.ShopItemId == i.Id),
            i.Version,
            DateTime.SpecifyKind(i.CreatedAt, DateTimeKind.Utc),
            DateTime.SpecifyKind(i.UpdatedAt, DateTimeKind.Utc)));
}
