using Microsoft.AspNetCore.Antiforgery;
using Microsoft.AspNetCore.Authentication;
using Quizly.Web.Auth;

namespace Quizly.Web.Components;

/// <summary>Non-page endpoints of the /admin dashboard.</summary>
internal static class AdminDashboard
{
    public const string LoginPath = "/admin/login";

    public static void MapAdminDashboard(this IEndpointRouteBuilder app)
    {
        app.MapGet("/", () => TypedResults.Redirect("/admin")).ExcludeFromDescription();

        // A form post from the sidebar; the antiforgery token comes from <AntiforgeryToken />.
        // The middleware only records the validation result for handlers that bind no form, so check it here.
        // No result at all (e.g. not a form post) is rejected too.
        app.MapPost("/admin/logout", async Task<IResult> (HttpContext http) =>
            {
                if (http.Features.Get<IAntiforgeryValidationFeature>() is not { IsValid: true })
                {
                    return TypedResults.BadRequest();
                }

                await http.SignOutAsync(AuthSetup.AdminScheme);
                return TypedResults.Redirect(LoginPath);
            })
            .WithMetadata(new RequireAntiforgeryTokenAttribute())
            .ExcludeFromDescription();
    }

    /// <summary>Only local dashboard paths are allowed as a return URL (no open redirect).</summary>
    public static string SafeReturnUrl(string? returnUrl) =>
        returnUrl is { Length: > 0 } && returnUrl.StartsWith("/admin", StringComparison.Ordinal)
            && !returnUrl.StartsWith("//", StringComparison.Ordinal) && !returnUrl.Contains('\\', StringComparison.Ordinal)
            ? returnUrl
            : "/admin";
}
