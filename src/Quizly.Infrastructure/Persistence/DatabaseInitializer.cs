using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Quizly.Domain;

namespace Quizly.Infrastructure.Persistence;

/// <summary>Applies migrations and seeds data on startup.</summary>
public sealed class DatabaseInitializer(QuizlyDbContext db, TimeProvider time, ILogger<DatabaseInitializer> logger)
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public async Task InitializeAsync(bool seedDemoDeck, CancellationToken ct = default)
    {
        await db.Database.MigrateAsync(ct);
        await SeedNotificationTextsAsync(ct);
        if (seedDemoDeck)
        {
            await SeedDemoDeckAsync(ct);
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

    /// <summary>A small deck for local development when there are no decks yet.</summary>
    private async Task SeedDemoDeckAsync(CancellationToken ct)
    {
        if (await db.Decks.AnyAsync(ct))
        {
            return;
        }

        var now = time.GetUtcNow().UtcDateTime;
        (string Question, string Answer)[] cards =
        [
            ("Jaký je rozdíl mezi struct a class v C#?", "struct je hodnotový typ, class je referenční typ."),
            ("Co dělá klíčové slovo async?", "Označí metodu, ve které můžeš použít await.\nMetoda pak vrací Task."),
            ("Co je record v C#?", "Typ s hodnotovou rovností pro neměnná data."),
            ("K čemu slouží using deklarace?", "Zavolá Dispose na konci bloku, i když nastane výjimka."),
            ("Co vrací LINQ metoda Where?", "Líně vyhodnocovanou sekvenci prvků, které splňují podmínku."),
        ];
        db.Decks.Add(new Deck
        {
            Name = "C# základy",
            Description = "Ukázkový balíček pro vývoj",
            Color = Limits.DefaultDeckColor,
            CreatedAt = now,
            UpdatedAt = now,
            Cards = cards.Select((c, i) => new Card
            {
                Question = c.Question,
                Answer = c.Answer,
                SortOrder = i,
                CreatedAt = now,
                UpdatedAt = now,
            }).ToList(),
        });
        await db.SaveChangesAsync(ct);
        logger.LogInformation("Seeded the demo deck");
    }

    private sealed record SeedText(string Category, string Text);
}
