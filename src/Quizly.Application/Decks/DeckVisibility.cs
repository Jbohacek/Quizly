using Quizly.Domain;

namespace Quizly.Application.Decks;

/// <summary>
/// What an app user sees: decks "Pro všechny" plus the decks the admin gave them (docs/spec.md §2.4).
/// Every app query over decks or cards goes through these filters.
/// </summary>
internal static class DeckVisibility
{
    public static IQueryable<Deck> VisibleTo(this IQueryable<Deck> decks, int userId) =>
        decks.Where(d => d.ForEveryone || d.Access.Any(a => a.UserId == userId));

    public static IQueryable<Card> VisibleTo(this IQueryable<Card> cards, int userId) =>
        cards.Where(c => c.Deck.ForEveryone || c.Deck.Access.Any(a => a.UserId == userId));
}
