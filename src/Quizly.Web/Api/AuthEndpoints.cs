using System.Security.Claims;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Http.HttpResults;
using Quizly.Application.Auth;
using Quizly.Application.Common;
using Quizly.Web.Auth;

namespace Quizly.Web.Api;

internal static class AuthEndpoints
{
    /// <summary>App login, token rotation and logout (docs/api.md §2).</summary>
    public static void MapAppAuth(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/auth").WithTags("Auth").AllowAnonymous();

        group.MapPost("/login", async (LoginRequest request, IAuthService auth, CancellationToken ct) =>
                (await auth.LoginAsync(request, ct)).OkOrProblem())
            .RequireRateLimiting(AuthSetup.LoginLimit)
            .WithName("Login")
            .WithSummary("Log in with username and password")
            .WithDescription("Returns an access token (JWT, 60 min) and a rotating refresh token (90 days).");

        group.MapPost("/refresh", async (RefreshRequest request, IAuthService auth, CancellationToken ct) =>
                (await auth.RefreshAsync(request, ct)).OkOrProblem())
            .RequireRateLimiting(AuthSetup.RefreshLimit)
            .WithName("RefreshToken")
            .WithSummary("Rotate the refresh token")
            .WithDescription("Revokes the presented refresh token and returns a new pair.");

        group.MapPost("/logout", async (RefreshRequest request, IAuthService auth, CancellationToken ct) =>
            {
                await auth.LogoutAsync(request, ct);
                return TypedResults.NoContent();
            })
            .WithName("Logout")
            .WithSummary("Revoke the refresh token")
            .WithDescription("Always 204, also for an unknown token.");
    }

    /// <summary>Admin cookie login for the REST endpoints and Swagger UI.</summary>
    public static void MapAdminAuth(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/api/admin/auth").WithTags("Admin: auth");

        group.MapPost("/login", async Task<Results<NoContent, ProblemHttpResult>> (
                AdminLoginRequest request, IAdminAuthenticator admin, HttpContext http) =>
            {
                if (!admin.Verify(request.Username ?? "", request.Password ?? ""))
                {
                    return Errors.InvalidCredentials.ToProblem();
                }

                var identity = new ClaimsIdentity(
                    [new Claim(ClaimTypes.Name, admin.Username), new Claim(ClaimTypes.Role, AuthSetup.AdminRole)],
                    AuthSetup.AdminScheme);
                await http.SignInAsync(AuthSetup.AdminScheme, new ClaimsPrincipal(identity));
                return TypedResults.NoContent();
            })
            .AllowAnonymous()
            .RequireRateLimiting(AuthSetup.AdminLoginLimit)
            .WithName("AdminLogin")
            .WithSummary("Admin login")
            .WithDescription("Sets the admin cookie used by /api/admin/* and the dashboard.");

        group.MapPost("/logout", async (HttpContext http) =>
            {
                await http.SignOutAsync(AuthSetup.AdminScheme);
                return TypedResults.NoContent();
            })
            .AllowAnonymous()
            .WithName("AdminLogout")
            .WithSummary("Admin logout");

        group.MapGet("/me", (ClaimsPrincipal user) => TypedResults.Ok(new AdminMeResponse(user.Identity?.Name ?? "")))
            .RequireAuthorization(AuthSetup.AdminPolicy)
            .WithName("AdminMe")
            .WithSummary("The signed-in admin");
    }
}

/// <summary>Admin credentials.</summary>
public sealed record AdminLoginRequest(string Username, string Password);

/// <summary>The signed-in admin.</summary>
public sealed record AdminMeResponse(string Username);
