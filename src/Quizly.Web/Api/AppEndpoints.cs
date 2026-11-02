using System.Globalization;
using System.Security.Claims;
using Microsoft.AspNetCore.Http.HttpResults;
using Microsoft.IdentityModel.JsonWebTokens;
using Quizly.Application.Auth;
using Quizly.Application.Decks;
using Quizly.Application.Learning;
using Quizly.Application.NotificationTexts;
using Quizly.Application.Profile;
using Quizly.Application.Shop;
using Quizly.Application.Stats;
using Quizly.Web.Auth;

namespace Quizly.Web.Api;

/// <summary>App endpoints (docs/api.md §3–9). All need the app access token.</summary>
internal static class AppEndpoints
{
    public static void MapApp(this IEndpointRouteBuilder app)
    {
        var api = app.MapGroup("/api").RequireAuthorization(AuthSetup.AppPolicy);

        var me = api.MapGroup("/me").WithTags("Me");
        me.MapGet("/", async (ClaimsPrincipal user, IMeService service, CancellationToken ct) =>
                TypedResults.Ok(await service.GetAsync(user.UserId(), ct)))
            .WithName("GetMe").WithSummary("Profile, balance, streak, multiplier, today's progress and due counts");
        me.MapGet("/settings", async (ClaimsPrincipal user, IMeService service, CancellationToken ct) =>
                TypedResults.Ok(await service.GetSettingsAsync(user.UserId(), ct)))
            .WithName("GetSettings").WithSummary("User settings");
        me.MapPut("/settings", async (SettingsDto request, ClaimsPrincipal user, IMeService service, CancellationToken ct) =>
                (await service.UpdateSettingsAsync(user.UserId(), request, ct)).OkOrProblem())
            .WithName("UpdateSettings").WithSummary("Save all settings")
            .WithDescription("Lowering the daily goal can complete today, so the response carries the summary and events.");
        me.MapPost("/password", async (ChangePasswordRequest request, ClaimsPrincipal user, IAuthService auth, CancellationToken ct) =>
                (await auth.ChangePasswordAsync(user.UserId(), request, ct)).OkOrProblem())
            .WithName("ChangePassword").WithSummary("Change my password")
            .WithDescription("Needs the current password. Signs out every other device and returns a new token pair for this one.");

        api.MapGet("/decks", async (ClaimsPrincipal user, IStudyService study, CancellationToken ct) =>
                TypedResults.Ok(await study.GetDecksAsync(user.UserId(), ct)))
            .WithTags("Study").WithName("GetDecks").WithSummary("Decks with total, due, new available and % mastered");

        api.MapGet("/decks/{deckId:int}/cards", async (int deckId, ClaimsPrincipal user, IStudyService study, CancellationToken ct) =>
                (await study.GetDeckCardsAsync(user.UserId(), deckId, ct)).OkOrProblem())
            .WithTags("Study").WithName("GetDeckCards")
            .WithSummary("A deck with all its cards and my status per card (new, learning, mastered)");

        var cards = api.MapGroup("/decks/{deckId:int}/cards").WithTags("Cards");
        cards.MapPost("/", async (int deckId, AppCardRequest request, ClaimsPrincipal user, IAppCardService service, CancellationToken ct) =>
                (await service.CreateAsync(user.UserId(), deckId, request, ct)).CreatedOrProblem(c => $"/api/decks/{deckId}/cards"))
            .WithName("AppCreateCard").WithSummary("Add a card to a deck I see (at the end)");
        cards.MapPut("/{cardId:int}", async (int deckId, int cardId, AppCardRequest request, ClaimsPrincipal user, IAppCardService service, CancellationToken ct) =>
                (await service.UpdateAsync(user.UserId(), deckId, cardId, request, ct)).OkOrProblem())
            .WithName("AppUpdateCard").WithSummary("Edit a card; every user's progress on it is kept");
        cards.MapDelete("/{cardId:int}", async (int deckId, int cardId, ClaimsPrincipal user, IAppCardService service, CancellationToken ct) =>
                (await service.DeleteAsync(user.UserId(), deckId, cardId, ct)).NoContentOrProblem())
            .WithName("AppDeleteCard").WithSummary("Delete a card with every user's progress on it");

        api.MapGet("/session", async (int? deckId, int? extraNew, ClaimsPrincipal user, IStudyService study, CancellationToken ct) =>
                (await study.GetSessionAsync(user.UserId(), deckId, extraNew ?? 0, ct)).OkOrProblem())
            .WithTags("Study").WithName("GetSession")
            .WithSummary("Session queue: due cards (most overdue first), then new cards up to today's allowance")
            .WithDescription("Omit deckId for \"Učit se vše\". extraNew (0–50) adds new cards over today's allowance.");

        api.MapPost("/reviews", async (ReviewBatchRequest request, ClaimsPrincipal user, IReviewService reviews, CancellationToken ct) =>
                (await reviews.SubmitAsync(user.UserId(), request, ct)).OkOrProblem())
            .WithTags("Study").WithName("SubmitReviews")
            .WithSummary("Submit 1–50 answers in order")
            .WithDescription("Idempotent per review id: a repeated id returns status duplicate with the original points.");

        api.MapGet("/stats", async (int? deckId, ClaimsPrincipal user, IStatsService stats, CancellationToken ct) =>
                (await stats.GetAsync(user.UserId(), deckId, ct)).OkOrProblem())
            .WithTags("Stats").WithName("GetStats").WithSummary("Tiles, heatmap, daily bars, weekdays, best time and deck progress");

        var shop = api.MapGroup("").WithTags("Shop");
        shop.MapGet("/shop", async (ClaimsPrincipal user, IShopService service, CancellationToken ct) =>
                TypedResults.Ok(await service.GetShopAsync(user.UserId(), ct)))
            .WithName("GetShop").WithSummary("Active rewards with stock and wishlist flags, plus the balance");

        shop.MapPost("/shop/{itemId:int}/claim", async Task<Results<Created<ClaimCreatedResponse>, Ok<ClaimCreatedResponse>, ProblemHttpResult>> (
                int itemId, ClaimRequest request, ClaimsPrincipal user, IShopService service, CancellationToken ct) =>
            {
                var result = await service.ClaimAsync(user.UserId(), itemId, request, ct);
                if (!result.IsSuccess)
                {
                    return result.Error.ToProblem();
                }

                var (response, created) = result.Value;
                return created
                    ? TypedResults.Created("/api/claims", response)
                    : TypedResults.Ok(response);
            })
            .WithName("ClaimReward").WithSummary("Buy a reward: points are deducted now, the admin confirms later")
            .WithDescription("Repeating the same requestId returns 200 with the original claim.");

        shop.MapGet("/claims", async (ClaimsPrincipal user, IShopService service, CancellationToken ct) =>
                TypedResults.Ok(await service.GetClaimsAsync(user.UserId(), ct)))
            .WithName("GetClaims").WithSummary("My purchases, newest first");

        shop.MapPut("/wishlist/{itemId:int}", async (int itemId, ClaimsPrincipal user, IShopService service, CancellationToken ct) =>
                (await service.AddToWishlistAsync(user.UserId(), itemId, ct)).NoContentOrProblem())
            .WithName("AddToWishlist").WithSummary("Heart a reward (idempotent)");

        shop.MapDelete("/wishlist/{itemId:int}", async (int itemId, ClaimsPrincipal user, IShopService service, CancellationToken ct) =>
            {
                await service.RemoveFromWishlistAsync(user.UserId(), itemId, ct);
                return TypedResults.NoContent();
            })
            .WithName("RemoveFromWishlist").WithSummary("Remove a heart (idempotent)");

        api.MapGet("/notification-texts", async Task<Results<Ok<AppNotificationTextsResponse>, StatusCodeHttpResult>> (
                HttpContext http, INotificationTextService texts, CancellationToken ct) =>
            {
                var result = await texts.GetActiveAsync(ct);
                var etag = $"\"{result.Version}\"";
                http.Response.Headers.ETag = etag;
                if (http.Request.Headers.IfNoneMatch.Contains(etag))
                {
                    return TypedResults.StatusCode(StatusCodes.Status304NotModified);
                }

                return TypedResults.Ok(result);
            })
            .WithTags("Notification texts")
            .WithName("GetNotificationTexts")
            .WithSummary("Active notification texts grouped by category")
            .WithDescription("Send If-None-Match with the last ETag to get 304 when nothing changed.");
    }

    /// <summary>The app user's id from the access token's <c>sub</c> claim.</summary>
    public static int UserId(this ClaimsPrincipal user) =>
        int.Parse(user.FindFirstValue(JwtRegisteredClaimNames.Sub)!, CultureInfo.InvariantCulture);
}
