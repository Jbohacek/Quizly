using System.Text.Json;
using Microsoft.AspNetCore.Http.HttpResults;
using Quizly.Application.Common;
using Quizly.Application.Decks;
using Quizly.Application.NotificationTexts;
using Quizly.Application.Shop;
using Quizly.Application.Users;
using Quizly.Domain;
using Quizly.Web.Auth;
using Quizly.Web.Middleware;

namespace Quizly.Web.Api;

/// <summary>Admin REST endpoints (docs/api.md §12). All need the admin cookie.</summary>
internal static class AdminEndpoints
{
    public static void MapAdmin(this IEndpointRouteBuilder app)
    {
        var admin = app.MapGroup("/api/admin")
            .RequireAuthorization(AuthSetup.AdminPolicy)
            .AddEndpointFilter<JsonOnlyFilter>();

        MapUsers(admin.MapGroup("/users").WithTags("Admin: users"));
        MapDecks(admin.MapGroup("/decks").WithTags("Admin: decks"));
        MapCards(admin.MapGroup("/decks/{deckId:int}/cards").WithTags("Admin: cards"));
        MapShopItems(admin.MapGroup("/shop-items").WithTags("Admin: shop items"));
        MapNotificationTexts(admin.MapGroup("/notification-texts").WithTags("Admin: notification texts"));
    }

    private static void MapUsers(RouteGroupBuilder g)
    {
        g.MapGet("/", async (IUserAdminService users, CancellationToken ct) => TypedResults.Ok(await users.ListAsync(ct)))
            .WithName("ListUsers").WithSummary("List app users with points, streak and success");

        g.MapGet("/{id:int}", async (int id, IUserAdminService users, CancellationToken ct) =>
                (await users.GetAsync(id, ct)).OkOrProblem())
            .WithName("GetUser").WithSummary("Get an app user");

        g.MapPost("/", async (CreateUserRequest request, IUserAdminService users, CancellationToken ct) =>
                (await users.CreateAsync(request, ct)).CreatedOrProblem(r => $"/api/admin/users/{r.User.Id}"))
            .WithName("CreateUser").WithSummary("Create an app user")
            .WithDescription("Without a password one is generated. The password is returned once.");

        g.MapPut("/{id:int}", async (int id, UpdateUserRequest request, IUserAdminService users, CancellationToken ct) =>
                (await users.UpdateAsync(id, request, ct)).OkOrProblem())
            .WithName("UpdateUser").WithSummary("Edit display name, daily goal and new cards per day");

        g.MapPost("/{id:int}/reset-password", async (int id, IUserAdminService users, CancellationToken ct) =>
                (await users.ResetPasswordAsync(id, ct)).OkOrProblem())
            .WithName("ResetUserPassword").WithSummary("Generate a new password (shown once) and sign the user out");

        g.MapPost("/{id:int}/activate", async (int id, IUserAdminService users, CancellationToken ct) =>
                (await users.SetActiveAsync(id, true, ct)).NoContentOrProblem())
            .WithName("ActivateUser").WithSummary("Activate a user");

        g.MapPost("/{id:int}/deactivate", async (int id, IUserAdminService users, CancellationToken ct) =>
                (await users.SetActiveAsync(id, false, ct)).NoContentOrProblem())
            .WithName("DeactivateUser").WithSummary("Deactivate a user and revoke their sessions");
    }

    private static void MapDecks(RouteGroupBuilder g)
    {
        g.MapGet("/", async (IDeckService decks, CancellationToken ct) => TypedResults.Ok(await decks.ListAsync(ct)))
            .WithName("ListDecks").WithSummary("List decks with card counts");

        g.MapGet("/{id:int}", async (int id, IDeckService decks, CancellationToken ct) =>
                (await decks.GetAsync(id, ct)).OkOrProblem())
            .WithName("GetDeck").WithSummary("Get a deck");

        g.MapPost("/", async (DeckRequest request, IDeckService decks, CancellationToken ct) =>
                (await decks.CreateAsync(request, ct)).CreatedOrProblem(d => $"/api/admin/decks/{d.Id}"))
            .WithName("CreateDeck").WithSummary("Create a deck");

        g.MapPut("/{id:int}", async (int id, DeckRequest request, IDeckService decks, CancellationToken ct) =>
                (await decks.UpdateAsync(id, request, ct)).OkOrProblem())
            .WithName("UpdateDeck").WithSummary("Edit a deck");

        g.MapDelete("/{id:int}", async (int id, IDeckService decks, CancellationToken ct) =>
                (await decks.DeleteAsync(id, ct)).NoContentOrProblem())
            .WithName("DeleteDeck").WithSummary("Delete a deck with its cards and all users' progress on them");
    }

    private static void MapCards(RouteGroupBuilder g)
    {
        g.MapGet("/", async (int deckId, ICardService cards, CancellationToken ct) =>
                (await cards.ListAsync(deckId, ct)).OkOrProblem())
            .WithName("ListCards").WithSummary("List a deck's cards in order");

        g.MapGet("/{cardId:int}", async (int deckId, int cardId, ICardService cards, CancellationToken ct) =>
                (await cards.GetAsync(deckId, cardId, ct)).OkOrProblem())
            .WithName("GetCard").WithSummary("Get a card");

        g.MapPost("/", async (int deckId, CardRequest request, ICardService cards, CancellationToken ct) =>
                (await cards.CreateAsync(deckId, request, ct)).CreatedOrProblem(c => $"/api/admin/decks/{deckId}/cards/{c.Id}"))
            .WithName("CreateCard").WithSummary("Add a card (at the end unless sortOrder is given)");

        g.MapPut("/{cardId:int}", async (int deckId, int cardId, CardRequest request, ICardService cards, CancellationToken ct) =>
                (await cards.UpdateAsync(deckId, cardId, request, ct)).OkOrProblem())
            .WithName("UpdateCard").WithSummary("Edit a card; users' progress is kept");

        g.MapDelete("/{cardId:int}", async (int deckId, int cardId, ICardService cards, CancellationToken ct) =>
                (await cards.DeleteAsync(deckId, cardId, ct)).NoContentOrProblem())
            .WithName("DeleteCard").WithSummary("Delete a card and all users' progress on it");
    }

    private static void MapShopItems(RouteGroupBuilder g)
    {
        g.MapGet("/", async (IShopItemService items, CancellationToken ct) => TypedResults.Ok(await items.ListAsync(ct)))
            .WithName("ListShopItems").WithSummary("List rewards with pending claims and wishlist counts");

        g.MapGet("/{id:int}", async (int id, IShopItemService items, CancellationToken ct) =>
                (await items.GetAsync(id, ct)).OkOrProblem())
            .WithName("GetShopItem").WithSummary("Get a reward");

        g.MapPost("/", async (CreateShopItemRequest request, IShopItemService items, CancellationToken ct) =>
                (await items.CreateAsync(request, ct)).CreatedOrProblem(i => $"/api/admin/shop-items/{i.Id}"))
            .WithName("CreateShopItem").WithSummary("Create a reward");

        g.MapPut("/{id:int}", async (int id, UpdateShopItemRequest request, IShopItemService items, CancellationToken ct) =>
                (await items.UpdateAsync(id, request, ct)).OkOrProblem())
            .WithName("UpdateShopItem").WithSummary("Edit a reward")
            .WithDescription("Send the version you read; a changed row returns 409 concurrencyConflict. Changing initialStock by N changes stock by N.");

        g.MapDelete("/{id:int}", async (int id, IShopItemService items, CancellationToken ct) =>
                (await items.DeleteAsync(id, ct)).NoContentOrProblem())
            .WithName("DeleteShopItem").WithSummary("Delete a reward without claims (else 409 hasClaims)");
    }

    private static void MapNotificationTexts(RouteGroupBuilder g)
    {
        g.MapGet("/", async Task<Results<Ok<IReadOnlyList<NotificationTextResponse>>, ProblemHttpResult>> (
                string? category, INotificationTextService texts, CancellationToken ct) =>
            {
                NotificationCategory? parsed = null;
                if (category is not null)
                {
                    parsed = ParseCategory(category);
                    if (parsed is null)
                    {
                        return Errors.Validation("category", "Neznámá kategorie.").ToProblem();
                    }
                }

                return TypedResults.Ok(await texts.ListAsync(parsed, ct));
            })
            .WithName("ListNotificationTexts").WithSummary("List texts, optionally of one category (e.g. last_call)");

        g.MapGet("/{id:int}", async (int id, INotificationTextService texts, CancellationToken ct) =>
                (await texts.GetAsync(id, ct)).OkOrProblem())
            .WithName("GetNotificationText").WithSummary("Get a text");

        g.MapPost("/", async (NotificationTextRequest request, INotificationTextService texts, CancellationToken ct) =>
                (await texts.CreateAsync(request, ct)).CreatedOrProblem(t => $"/api/admin/notification-texts/{t.Id}"))
            .WithName("CreateNotificationText").WithSummary("Add a text");

        g.MapPut("/{id:int}", async (int id, NotificationTextRequest request, INotificationTextService texts, CancellationToken ct) =>
                (await texts.UpdateAsync(id, request, ct)).OkOrProblem())
            .WithName("UpdateNotificationText").WithSummary("Edit or (de)activate a text");

        g.MapDelete("/{id:int}", async (int id, INotificationTextService texts, CancellationToken ct) =>
                (await texts.DeleteAsync(id, ct)).NoContentOrProblem())
            .WithName("DeleteNotificationText").WithSummary("Delete a text");

        g.MapPost("/preview", (NotificationPreviewRequest request, INotificationTextService texts) =>
                texts.Preview(request).OkOrProblem())
            .WithName("PreviewNotificationText").WithSummary("Render a text with sample placeholder values");
    }

    private static NotificationCategory? ParseCategory(string value) =>
        Enum.GetValues<NotificationCategory>()
            .Select(c => (NotificationCategory?)c)
            .FirstOrDefault(c => JsonNamingPolicy.SnakeCaseLower.ConvertName(c!.Value.ToString()) == value);
}
