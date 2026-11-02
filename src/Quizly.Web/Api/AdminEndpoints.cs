using System.Text.Json;
using Microsoft.AspNetCore.Http.HttpResults;
using Quizly.Application.Common;
using Quizly.Application.Decks;
using Quizly.Application.NotificationTexts;
using Quizly.Application.Overview;
using Quizly.Application.Shop;
using Quizly.Application.Users;
using Quizly.Application.Yaml;
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

        admin.MapGet("/overview", async (IOverviewService overview, CancellationToken ct) => TypedResults.Ok(await overview.GetAsync(ct)))
            .WithTags("Admin: overview").WithName("GetOverview").WithSummary("Tiles, pending purchases and users today");

        MapUsers(admin.MapGroup("/users").WithTags("Admin: users"));
        MapDecks(admin.MapGroup("/decks").WithTags("Admin: decks"));
        MapCards(admin.MapGroup("/decks/{deckId:int}/cards").WithTags("Admin: cards"));
        MapYaml(admin.MapGroup("/decks").WithTags("Admin: deck YAML"));
        MapShopItems(admin.MapGroup("/shop-items").WithTags("Admin: shop items"));
        MapNotificationTexts(admin.MapGroup("/notification-texts").WithTags("Admin: notification texts"));
        MapClaims(admin.MapGroup("/claims").WithTags("Admin: claims"));
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

        g.MapGet("/{id:int}/access", async (int id, IDeckService decks, CancellationToken ct) =>
                (await decks.GetAccessAsync(id, ct)).OkOrProblem())
            .WithName("GetDeckAccess").WithSummary("Who sees the deck in the app");

        g.MapPut("/{id:int}/access", async (int id, DeckAccessDto request, IDeckService decks, CancellationToken ct) =>
                (await decks.SetAccessAsync(id, request, ct)).OkOrProblem())
            .WithName("SetDeckAccess").WithSummary("Set who sees the deck: everyone, or the listed users")
            .WithDescription("Users who lose the deck keep their progress; it comes back with access.");
    }

    private static void MapYaml(RouteGroupBuilder g)
    {
        g.MapGet("/{id:int}/yaml", async Task<Results<ContentHttpResult, ProblemHttpResult>> (int id, IYamlDeckService yaml, CancellationToken ct) =>
            {
                var export = await yaml.ExportAsync(id, ct);
                return export.IsSuccess ? TypedResults.Text(export.Value, "text/yaml; charset=utf-8") : export.Error.ToProblem();
            })
            .WithName("ExportDeckYaml").WithSummary("Export the deck as YAML v1 (every card with its id)");

        g.MapPost("/{id:int}/yaml/preview", async (int id, YamlRequest request, IYamlDeckService yaml, CancellationToken ct) =>
                (await yaml.PreviewAsync(id, request, ct)).OkOrProblem())
            .WithName("PreviewDeckYaml").WithSummary("Dry run: new / changed / deleted / unchanged cards and errors with line numbers")
            .WithDescription("Always 200 for an existing deck; valid=false lists the errors. Nothing is written.");

        g.MapPut("/{id:int}/yaml", async (int id, YamlApplyRequest request, IYamlDeckService yaml, CancellationToken ct) =>
                (await yaml.ApplyAsync(id, request, ct)).OkOrProblem())
            .WithName("ApplyDeckYaml").WithSummary("Apply YAML previewed against baseHash")
            .WithDescription("422 yamlInvalid (with yamlErrors), 409 concurrencyConflict when the deck changed, 422 deleteNotConfirmed unless confirmDeleteIds lists exactly the cards to delete.");

        g.MapPost("/import/preview", async (YamlRequest request, IYamlDeckService yaml, CancellationToken ct) =>
                TypedResults.Ok(await yaml.PreviewNewDeckAsync(request, ct)))
            .WithName("PreviewDeckImport").WithSummary("Dry run of importing YAML as a new deck (cards without ids)");

        g.MapPost("/import", async (YamlRequest request, IYamlDeckService yaml, CancellationToken ct) =>
                (await yaml.ImportNewDeckAsync(request, ct)).CreatedOrProblem(d => $"/api/admin/decks/{d.Id}"))
            .WithName("ImportDeck").WithSummary("Create a new deck from YAML");

        g.MapGet("/{id:int}/delete-impact", async (int id, IDeckService decks, CancellationToken ct) =>
                (await decks.GetDeleteImpactAsync(id, ct)).OkOrProblem())
            .WithName("GetDeckDeleteImpact").WithSummary("How many cards and users' progress deleting the deck removes");
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

    private static void MapClaims(RouteGroupBuilder g)
    {
        g.MapGet("/", async Task<Results<Ok<IReadOnlyList<AdminClaimResponse>>, ProblemHttpResult>> (
                string? status, IClaimAdminService claims, CancellationToken ct) =>
            {
                ClaimStatus? parsed = null;
                if (status is not null)
                {
                    parsed = ParseSnake<ClaimStatus>(status);
                    if (parsed is null)
                    {
                        return Errors.Validation("status", "Stav musí být pending, confirmed nebo rejected.").ToProblem();
                    }
                }

                return TypedResults.Ok(await claims.ListAsync(parsed, ct));
            })
            .WithName("ListClaims").WithSummary("Purchase history, optionally filtered by status (pending, confirmed, rejected)");

        g.MapPost("/{id:int}/confirm", async (int id, IClaimAdminService claims, CancellationToken ct) =>
                (await claims.ConfirmAsync(id, ct)).OkOrProblem())
            .WithName("ConfirmClaim").WithSummary("Confirm a pending purchase (final)");

        g.MapPost("/{id:int}/reject", async (int id, IClaimAdminService claims, CancellationToken ct) =>
                (await claims.RejectAsync(id, ct)).OkOrProblem())
            .WithName("RejectClaim").WithSummary("Reject a pending purchase: refund the points and restock");
    }

    private static TEnum? ParseSnake<TEnum>(string value)
        where TEnum : struct, Enum =>
        Enum.GetValues<TEnum>()
            .Select(e => (TEnum?)e)
            .FirstOrDefault(e => JsonNamingPolicy.SnakeCaseLower.ConvertName(e!.Value.ToString()) == value);

    private static NotificationCategory? ParseCategory(string value) =>
        Enum.GetValues<NotificationCategory>()
            .Select(c => (NotificationCategory?)c)
            .FirstOrDefault(c => JsonNamingPolicy.SnakeCaseLower.ConvertName(c!.Value.ToString()) == value);
}
