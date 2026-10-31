using Microsoft.EntityFrameworkCore;
using Quizly.Application.Abstractions;
using Quizly.Application.Common;
using Quizly.Domain;

namespace Quizly.Application.Decks;

public interface ICardService
{
    Task<Result<IReadOnlyList<CardResponse>>> ListAsync(int deckId, CancellationToken ct);

    Task<Result<CardResponse>> GetAsync(int deckId, int cardId, CancellationToken ct);

    Task<Result<CardResponse>> CreateAsync(int deckId, CardRequest request, CancellationToken ct);

    Task<Result<CardResponse>> UpdateAsync(int deckId, int cardId, CardRequest request, CancellationToken ct);

    /// <summary>Deletes the card and all users' progress on it (docs/spec.md §2.14).</summary>
    Task<Result> DeleteAsync(int deckId, int cardId, CancellationToken ct);
}

internal sealed class CardService(IAppDbContext db, TimeProvider time) : ICardService
{
    public async Task<Result<IReadOnlyList<CardResponse>>> ListAsync(int deckId, CancellationToken ct)
    {
        if (!await db.Decks.AnyAsync(d => d.Id == deckId, ct))
        {
            return DeckService.DeckNotFound;
        }

        var cards = await db.Cards
            .Where(c => c.DeckId == deckId)
            .OrderBy(c => c.SortOrder).ThenBy(c => c.Id)
            .ToListAsync(ct);
        return cards.Select(ToResponse).ToList();
    }

    public async Task<Result<CardResponse>> GetAsync(int deckId, int cardId, CancellationToken ct)
    {
        var card = await db.Cards.FirstOrDefaultAsync(c => c.Id == cardId && c.DeckId == deckId, ct);
        return card is null ? CardNotFound : ToResponse(card);
    }

    public async Task<Result<CardResponse>> CreateAsync(int deckId, CardRequest request, CancellationToken ct)
    {
        var deck = await db.Decks.FirstOrDefaultAsync(d => d.Id == deckId, ct);
        if (deck is null)
        {
            return DeckService.DeckNotFound;
        }

        var (question, answer) = (Validator.Clean(request.Question), Validator.Clean(request.Answer));
        var v = Validate(question, answer);
        if (!v.IsValid)
        {
            return v.ToError();
        }

        var now = time.GetUtcNow().UtcDateTime;
        var sortOrder = request.SortOrder
            ?? (await db.Cards.Where(c => c.DeckId == deckId).MaxAsync(c => (int?)c.SortOrder, ct) ?? -1) + 1;
        var card = new Card
        {
            DeckId = deckId,
            Question = question,
            Answer = answer,
            SortOrder = sortOrder,
            CreatedAt = now,
            UpdatedAt = now,
        };
        db.Cards.Add(card);
        deck.UpdatedAt = now;
        await db.SaveChangesAsync(ct);
        return ToResponse(card);
    }

    public async Task<Result<CardResponse>> UpdateAsync(int deckId, int cardId, CardRequest request, CancellationToken ct)
    {
        var card = await db.Cards.Include(c => c.Deck).FirstOrDefaultAsync(c => c.Id == cardId && c.DeckId == deckId, ct);
        if (card is null)
        {
            return CardNotFound;
        }

        var (question, answer) = (Validator.Clean(request.Question), Validator.Clean(request.Answer));
        var v = Validate(question, answer);
        if (!v.IsValid)
        {
            return v.ToError();
        }

        var now = time.GetUtcNow().UtcDateTime;
        card.Question = question;
        card.Answer = answer;
        card.SortOrder = request.SortOrder ?? card.SortOrder;
        card.UpdatedAt = now;
        card.Deck.UpdatedAt = now;
        await db.SaveChangesAsync(ct);
        return ToResponse(card);
    }

    public async Task<Result> DeleteAsync(int deckId, int cardId, CancellationToken ct)
    {
        var deleted = await db.Cards.Where(c => c.Id == cardId && c.DeckId == deckId).ExecuteDeleteAsync(ct);
        if (deleted == 0)
        {
            return CardNotFound;
        }

        await db.Decks.Where(d => d.Id == deckId)
            .ExecuteUpdateAsync(s => s.SetProperty(d => d.UpdatedAt, time.GetUtcNow().UtcDateTime), ct);
        return Result.Ok();
    }

    private static AppError CardNotFound => Errors.NotFound("Karta neexistuje.");

    private static Validator Validate(string question, string answer) =>
        new Validator()
            .Text("question", question, "Otázka", Limits.QuestionMax)
            .Text("answer", answer, "Odpověď", Limits.AnswerMax);

    private static CardResponse ToResponse(Card c) =>
        new(c.Id, c.DeckId, c.Question, c.Answer, c.SortOrder, c.CreatedAt.ToUtcOffset(), c.UpdatedAt.ToUtcOffset());
}
