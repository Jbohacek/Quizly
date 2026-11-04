using Microsoft.EntityFrameworkCore;
using Quizly.Application.Abstractions;
using Quizly.Domain;

namespace Quizly.Application.Decks;

/// <summary>Setting and reading card tags (#29); names follow <see cref="TagNames"/>.</summary>
internal static class CardTagging
{
    public static string InvalidMessage(string name) =>
        $"Tag „{name}“ není platný: jen malá písmena, číslice, _ a -, nejvýš {Limits.TagNameMax} znaků.";

    public static string TooManyMessage => $"Karta může mít nejvýš {Limits.TagsPerCardMax} tagů.";

    /// <summary>
    /// The tag rows for <paramref name="names"/>, creating missing ones. <c>ON CONFLICT</c> lets two writers add the
    /// same new tag at once. Tags no card uses any more are kept: nothing lists them.
    /// </summary>
    public static async Task<Dictionary<string, Tag>> ResolveAsync(IAppDbContext db, IEnumerable<string> names, CancellationToken ct)
    {
        var list = names.Distinct(StringComparer.Ordinal).ToArray();
        if (list.Length == 0)
        {
            return [];
        }

        await db.Database.ExecuteSqlAsync($"INSERT INTO tags (name) SELECT unnest({list}) ON CONFLICT (name) DO NOTHING", ct);
        return await db.Tags.Where(t => list.Contains(t.Name)).ToDictionaryAsync(t => t.Name, StringComparer.Ordinal, ct);
    }

    /// <summary>Makes the card's tags exactly <paramref name="names"/> (the card's tags must be loaded).</summary>
    public static void Set(Card card, IReadOnlyCollection<string> names, IReadOnlyDictionary<string, Tag> tags)
    {
        card.Tags.RemoveAll(t => !names.Contains(t.Name));
        card.Tags.AddRange(names.Where(n => card.Tags.All(t => t.Name != n)).Select(n => tags[n]));
    }

    /// <summary>The card's tag names, sorted (the card's tags must be loaded).</summary>
    public static IReadOnlyList<string> Names(Card card) => card.Tags.Select(t => t.Name).Order(StringComparer.Ordinal).ToList();

    public static bool SameAs(Card card, IReadOnlyList<string> names) => Names(card).SequenceEqual(names, StringComparer.Ordinal);
}
