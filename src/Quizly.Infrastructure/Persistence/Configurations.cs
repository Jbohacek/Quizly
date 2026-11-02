using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using Quizly.Domain;

namespace Quizly.Infrastructure.Persistence;

// Mapping of docs/spec.md §2. Table and column names become snake_case via UseSnakeCaseNamingConvention.

internal sealed class UserConfiguration : IEntityTypeConfiguration<User>
{
    public void Configure(EntityTypeBuilder<User> b)
    {
        b.ToTable(t => t.HasCheckConstraint("ck_users_username", "username ~ '^[a-z0-9]{3,32}$'"));
        b.Property(u => u.Username).HasMaxLength(Limits.UsernameMax);
        b.HasIndex(u => u.Username).IsUnique();
        b.Property(u => u.DisplayName).HasMaxLength(Limits.DisplayNameMax);
        b.HasOne(u => u.Settings).WithOne(s => s.User).HasForeignKey<UserSettings>(s => s.UserId).OnDelete(DeleteBehavior.Cascade);
    }
}

internal sealed class UserSettingsConfiguration : IEntityTypeConfiguration<UserSettings>
{
    public void Configure(EntityTypeBuilder<UserSettings> b)
    {
        b.HasKey(s => s.UserId);
        b.ToTable(t =>
        {
            t.HasCheckConstraint("ck_user_settings_daily_goal", $"daily_goal BETWEEN {Limits.DailyGoalMin} AND {Limits.DailyGoalMax}");
            t.HasCheckConstraint("ck_user_settings_new_cards", $"new_cards_per_day BETWEEN 0 AND {Limits.NewCardsPerDayMax}");
            t.HasCheckConstraint("ck_user_settings_quiet_hours", "quiet_from <> quiet_to");
        });
    }
}

internal sealed class RefreshTokenConfiguration : IEntityTypeConfiguration<RefreshToken>
{
    public void Configure(EntityTypeBuilder<RefreshToken> b)
    {
        b.HasIndex(t => t.TokenHash).IsUnique();
        b.HasIndex(t => t.UserId);
        b.HasOne(t => t.User).WithMany().HasForeignKey(t => t.UserId).OnDelete(DeleteBehavior.Cascade);
        b.HasOne<RefreshToken>().WithMany().HasForeignKey(t => t.ReplacedById).OnDelete(DeleteBehavior.SetNull);
    }
}

internal sealed class DeckConfiguration : IEntityTypeConfiguration<Deck>
{
    public void Configure(EntityTypeBuilder<Deck> b)
    {
        b.ToTable(t => t.HasCheckConstraint("ck_decks_color", "color ~ '^#[0-9A-Fa-f]{6}$'"));
        b.Property(d => d.Name).HasMaxLength(Limits.DeckNameMax);
        b.Property(d => d.Description).HasMaxLength(Limits.DeckDescriptionMax);
        b.Property(d => d.Color).HasMaxLength(7).IsFixedLength();
        b.HasIndex(d => new { d.SortOrder, d.Id });
    }
}

internal sealed class DeckAccessConfiguration : IEntityTypeConfiguration<DeckAccess>
{
    public void Configure(EntityTypeBuilder<DeckAccess> b)
    {
        b.HasKey(a => new { a.DeckId, a.UserId });
        b.HasOne<Deck>().WithMany(d => d.Access).HasForeignKey(a => a.DeckId).OnDelete(DeleteBehavior.Cascade);
        b.HasOne<User>().WithMany().HasForeignKey(a => a.UserId).OnDelete(DeleteBehavior.Cascade);
        b.HasIndex(a => a.UserId);
    }
}

internal sealed class CardConfiguration : IEntityTypeConfiguration<Card>
{
    public void Configure(EntityTypeBuilder<Card> b)
    {
        b.Property(c => c.Question).HasMaxLength(Limits.QuestionMax);
        b.Property(c => c.Answer).HasMaxLength(Limits.AnswerMax);
        b.HasOne(c => c.Deck).WithMany(d => d.Cards).HasForeignKey(c => c.DeckId).OnDelete(DeleteBehavior.Cascade);
        b.HasIndex(c => new { c.DeckId, c.SortOrder, c.Id });
    }
}

internal sealed class CardStateConfiguration : IEntityTypeConfiguration<CardState>
{
    public void Configure(EntityTypeBuilder<CardState> b)
    {
        b.HasKey(s => new { s.UserId, s.CardId });
        b.ToTable(t => t.HasCheckConstraint("ck_card_states_state", "state IN (1, 2, 3)"));
        b.Property(s => s.State).HasConversion<short>();
        b.HasOne<User>().WithMany().HasForeignKey(s => s.UserId).OnDelete(DeleteBehavior.Cascade);
        b.HasOne<Card>().WithMany().HasForeignKey(s => s.CardId).OnDelete(DeleteBehavior.Cascade);
        b.HasIndex(s => s.CardId);
        b.HasIndex(s => new { s.UserId, s.Due });
        b.HasIndex(s => new { s.UserId, s.FirstReview });
    }
}

internal sealed class ReviewLogConfiguration : IEntityTypeConfiguration<ReviewLog>
{
    public void Configure(EntityTypeBuilder<ReviewLog> b)
    {
        b.Property(r => r.Id).ValueGeneratedNever();
        b.ToTable(t => t.HasCheckConstraint("ck_review_logs_rating", "rating IN (1, 3)"));
        b.Property(r => r.Rating).HasConversion<short>();
        b.Property(r => r.StateBefore).HasConversion<short>();
        b.Property(r => r.Multiplier).HasPrecision(3, 1);
        b.HasOne<User>().WithMany().HasForeignKey(r => r.UserId).OnDelete(DeleteBehavior.Cascade);
        b.HasOne<Card>().WithMany().HasForeignKey(r => r.CardId).OnDelete(DeleteBehavior.Cascade);
        b.HasIndex(r => r.CardId);
        b.HasIndex(r => new { r.UserId, r.Day });
        b.HasIndex(r => new { r.UserId, r.ReviewedAt });
    }
}

internal sealed class DailyActivityConfiguration : IEntityTypeConfiguration<DailyActivity>
{
    public void Configure(EntityTypeBuilder<DailyActivity> b)
    {
        b.HasKey(a => new { a.UserId, a.Date });
        b.HasOne<User>().WithMany().HasForeignKey(a => a.UserId).OnDelete(DeleteBehavior.Cascade);
    }
}

internal sealed class PointsEntryConfiguration : IEntityTypeConfiguration<PointsEntry>
{
    public void Configure(EntityTypeBuilder<PointsEntry> b)
    {
        b.ToTable(t => t.HasCheckConstraint("ck_points_entries_amount", "amount <> 0"));
        b.Property(p => p.Reason).HasConversion<SnakeCaseEnumConverter<PointsReason>>().HasMaxLength(16);
        b.Property(p => p.ReferenceId).HasMaxLength(64);
        b.HasOne<User>().WithMany().HasForeignKey(p => p.UserId).OnDelete(DeleteBehavior.Cascade);
        b.HasIndex(p => new { p.UserId, p.Reason, p.ReferenceId }).IsUnique();
    }
}

internal sealed class ShopItemConfiguration : IEntityTypeConfiguration<ShopItem>
{
    public void Configure(EntityTypeBuilder<ShopItem> b)
    {
        b.ToTable(t =>
        {
            t.HasCheckConstraint("ck_shop_items_price", $"price BETWEEN {Limits.PriceMin} AND {Limits.PriceMax}");
            t.HasCheckConstraint("ck_shop_items_initial_stock", $"initial_stock BETWEEN 0 AND {Limits.StockMax}");
            t.HasCheckConstraint("ck_shop_items_stock", "stock >= 0");
        });
        b.Property(i => i.Name).HasMaxLength(Limits.ShopItemNameMax);
        b.Property(i => i.Description).HasMaxLength(Limits.ShopItemDescriptionMax);
        b.Property(i => i.Version).IsRowVersion();
        b.HasIndex(i => new { i.SortOrder, i.Id });
    }
}

internal sealed class ClaimConfiguration : IEntityTypeConfiguration<Claim>
{
    public void Configure(EntityTypeBuilder<Claim> b)
    {
        b.Property(c => c.Status).HasConversion<SnakeCaseEnumConverter<ClaimStatus>>().HasMaxLength(16);
        b.HasOne(c => c.User).WithMany().HasForeignKey(c => c.UserId).OnDelete(DeleteBehavior.Restrict);
        b.HasOne(c => c.ShopItem).WithMany().HasForeignKey(c => c.ShopItemId).OnDelete(DeleteBehavior.Restrict);
        b.HasIndex(c => c.RequestId).IsUnique();
        b.HasIndex(c => c.ShopItemId);
        b.HasIndex(c => new { c.Status, c.CreatedAt });
        b.HasIndex(c => new { c.UserId, c.CreatedAt });
    }
}

internal sealed class WishlistEntryConfiguration : IEntityTypeConfiguration<WishlistEntry>
{
    public void Configure(EntityTypeBuilder<WishlistEntry> b)
    {
        b.HasKey(w => new { w.UserId, w.ShopItemId });
        b.HasOne<User>().WithMany().HasForeignKey(w => w.UserId).OnDelete(DeleteBehavior.Cascade);
        b.HasOne<ShopItem>().WithMany().HasForeignKey(w => w.ShopItemId).OnDelete(DeleteBehavior.Cascade);
        b.HasIndex(w => w.ShopItemId);
    }
}

internal sealed class NotificationTextConfiguration : IEntityTypeConfiguration<NotificationText>
{
    public void Configure(EntityTypeBuilder<NotificationText> b)
    {
        b.Property(t => t.Category).HasConversion<SnakeCaseEnumConverter<NotificationCategory>>().HasMaxLength(16);
        b.Property(t => t.Text).HasMaxLength(Limits.NotificationTextMax);
        b.HasIndex(t => t.Category);
    }
}
