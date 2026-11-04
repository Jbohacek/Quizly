using Microsoft.EntityFrameworkCore;
using Quizly.Application.Abstractions;
using Quizly.Application.Common;

namespace Quizly.Application.Decks;

/// <summary>
/// Cards edited from the app (#23): any user may add, edit and delete cards of the decks they see.
/// The same rules as the dashboard; a deck the user doesn't see is not found.
/// </summary>
public interface IAppCardService
{
    Task<Result<CardResponse>> CreateAsync(int userId, int deckId, AppCardRequest request, CancellationToken ct);

    Task<Result<CardResponse>> UpdateAsync(int userId, int deckId, int cardId, AppCardRequest request, CancellationToken ct);

    /// <summary>Deletes the card and every user's progress on it (docs/spec.md §2.14).</summary>
    Task<Result> DeleteAsync(int userId, int deckId, int cardId, CancellationToken ct);
}

internal sealed class AppCardService(IAppDbContext db, ICardService cards) : IAppCardService
{
    public async Task<Result<CardResponse>> CreateAsync(int userId, int deckId, AppCardRequest request, CancellationToken ct) =>
        await SeesAsync(userId, deckId, ct)
            ? await cards.CreateAsync(deckId, new CardRequest(request.Question, request.Answer, Tags: request.Tags), ct)
            : DeckService.DeckNotFound;

    public async Task<Result<CardResponse>> UpdateAsync(int userId, int deckId, int cardId, AppCardRequest request, CancellationToken ct) =>
        await SeesAsync(userId, deckId, ct)
            ? await cards.UpdateAsync(deckId, cardId, new CardRequest(request.Question, request.Answer, Tags: request.Tags), ct)
            : DeckService.DeckNotFound;

    public async Task<Result> DeleteAsync(int userId, int deckId, int cardId, CancellationToken ct) =>
        await SeesAsync(userId, deckId, ct)
            ? await cards.DeleteAsync(deckId, cardId, ct)
            : DeckService.DeckNotFound;

    private Task<bool> SeesAsync(int userId, int deckId, CancellationToken ct) =>
        db.Decks.VisibleTo(userId).AnyAsync(d => d.Id == deckId, ct);
}
