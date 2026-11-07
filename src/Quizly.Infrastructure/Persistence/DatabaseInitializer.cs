using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Quizly.Domain;
using Quizly.Infrastructure.Seed;

namespace Quizly.Infrastructure.Persistence;

/// <summary>Applies migrations and seeds data on startup.</summary>
public sealed class DatabaseInitializer(
    QuizlyDbContext db, TimeProvider time, DevelopmentSeeder developmentSeeder, ILogger<DatabaseInitializer> logger)
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    /// <summary>Migrates, seeds the notification texts, and (Development only) the sample users, decks and shop (#44).</summary>
    public async Task InitializeAsync(bool seedDevelopmentData, CancellationToken ct = default)
    {
        await db.Database.MigrateAsync(ct);
        await SeedNotificationTextsAsync(ct);
        if (seedDevelopmentData)
        {
            await developmentSeeder.SeedAsync(ct);
        }
    }

    /// <summary>Seeds docs/notification-texts.md only into an empty table, so admin edits are never overwritten.</summary>
    private async Task SeedNotificationTextsAsync(CancellationToken ct)
    {
        if (await db.NotificationTexts.AnyAsync(ct))
        {
            return;
        }

        await using var stream = typeof(DatabaseInitializer).Assembly.GetManifestResourceStream("Quizly.Seed.notification-texts.json")
            ?? throw new InvalidOperationException("Seed file notification-texts.json is missing.");
        var seeds = await JsonSerializer.DeserializeAsync<List<SeedText>>(stream, JsonOptions, ct) ?? [];
        var now = time.GetUtcNow().UtcDateTime;
        db.NotificationTexts.AddRange(seeds.Select(s => new NotificationText
        {
            Category = Names<NotificationCategory>.FromDb(s.Category),
            Text = s.Text,
            IsActive = true,
            CreatedAt = now,
            UpdatedAt = now,
        }));
        await db.SaveChangesAsync(ct);
        logger.LogInformation("Seeded {Count} notification texts", seeds.Count);
    }

    private sealed record SeedText(string Category, string Text);
}
