using Microsoft.AspNetCore.Http.HttpResults;
using Quizly.Application.NotificationTexts;
using Quizly.Web.Auth;

namespace Quizly.Web.Api;

/// <summary>App endpoints available in Etapa 2.</summary>
internal static class AppEndpoints
{
    public static void MapApp(this IEndpointRouteBuilder app)
    {
        app.MapGet("/api/notification-texts", async Task<Results<Ok<AppNotificationTextsResponse>, StatusCodeHttpResult>> (
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
            .RequireAuthorization(AuthSetup.AppPolicy)
            .WithTags("Notification texts")
            .WithName("GetNotificationTexts")
            .WithSummary("Active notification texts grouped by category")
            .WithDescription("Send If-None-Match with the last ETag to get 304 when nothing changed.");
    }
}
