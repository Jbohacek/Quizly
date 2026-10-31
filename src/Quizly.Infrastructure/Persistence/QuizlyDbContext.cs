using Microsoft.EntityFrameworkCore;
using Quizly.Application.Abstractions;
using Quizly.Domain;

namespace Quizly.Infrastructure.Persistence;

public sealed class QuizlyDbContext(DbContextOptions<QuizlyDbContext> options) : DbContext(options), IAppDbContext
{
    public DbSet<User> Users => Set<User>();
    public DbSet<UserSettings> UserSettings => Set<UserSettings>();
    public DbSet<RefreshToken> RefreshTokens => Set<RefreshToken>();
    public DbSet<Deck> Decks => Set<Deck>();
    public DbSet<Card> Cards => Set<Card>();
    public DbSet<CardState> CardStates => Set<CardState>();
    public DbSet<ReviewLog> ReviewLogs => Set<ReviewLog>();
    public DbSet<DailyActivity> DailyActivities => Set<DailyActivity>();
    public DbSet<PointsEntry> PointsEntries => Set<PointsEntry>();
    public DbSet<ShopItem> ShopItems => Set<ShopItem>();
    public DbSet<Claim> Claims => Set<Claim>();
    public DbSet<WishlistEntry> WishlistEntries => Set<WishlistEntry>();
    public DbSet<NotificationText> NotificationTexts => Set<NotificationText>();

    protected override void OnModelCreating(ModelBuilder modelBuilder) =>
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(QuizlyDbContext).Assembly);
}
