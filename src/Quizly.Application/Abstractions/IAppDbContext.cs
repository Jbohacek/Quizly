using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.ChangeTracking;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Quizly.Domain;

namespace Quizly.Application.Abstractions;

/// <summary>The database as the application services see it. Implemented by Infrastructure.</summary>
public interface IAppDbContext
{
    DbSet<User> Users { get; }
    DbSet<UserSettings> UserSettings { get; }
    DbSet<RefreshToken> RefreshTokens { get; }
    DbSet<Deck> Decks { get; }
    DbSet<Card> Cards { get; }
    DbSet<DeckAccess> DeckAccess { get; }
    DbSet<CardState> CardStates { get; }
    DbSet<ReviewLog> ReviewLogs { get; }
    DbSet<DailyActivity> DailyActivities { get; }
    DbSet<PointsEntry> PointsEntries { get; }
    DbSet<ShopItem> ShopItems { get; }
    DbSet<Claim> Claims { get; }
    DbSet<WishlistEntry> WishlistEntries { get; }
    DbSet<NotificationText> NotificationTexts { get; }

    DatabaseFacade Database { get; }

    EntityEntry<TEntity> Entry<TEntity>(TEntity entity)
        where TEntity : class;

    Task<int> SaveChangesAsync(CancellationToken cancellationToken = default);
}
