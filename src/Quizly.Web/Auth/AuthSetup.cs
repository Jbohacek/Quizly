using System.Globalization;
using System.Security.Claims;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;
using Quizly.Application.Abstractions;
using Quizly.Application.Common;
using Quizly.Web.Api;

namespace Quizly.Web.Auth;

internal static class AuthSetup
{
    public const string AdminScheme = "Admin";
    public const string DefaultScheme = "Quizly";
    public const string AppPolicy = "App";
    public const string AdminPolicy = "Admin";
    public const string AdminRole = "admin";

    public const string LoginLimit = "login";
    public const string RefreshLimit = "refresh";
    public const string AdminLoginLimit = "admin-login";

    private const string AuthErrorKey = "quizly.authError";

    public static IServiceCollection AddQuizlyAuth(this IServiceCollection services, IConfiguration config, IHostEnvironment env)
    {
        var jwt = config.GetSection("Jwt").Get<JwtOptions>() ?? new JwtOptions();
        var signingKey = jwt.Key();

        services
            .AddAuthentication(DefaultScheme)
            // /api uses the JWT by default; everything else (the Blazor dashboard and its circuit) the admin cookie.
            // App and admin endpoints name their scheme in their policy, so a cookie never reaches app endpoints.
            .AddPolicyScheme(DefaultScheme, DefaultScheme, options => options.ForwardDefaultSelector = context =>
                context.Request.Path.StartsWithSegments("/api", StringComparison.OrdinalIgnoreCase)
                    ? JwtBearerDefaults.AuthenticationScheme
                    : AdminScheme)
            .AddJwtBearer(options =>
            {
                options.MapInboundClaims = false;
                options.TokenValidationParameters = new TokenValidationParameters
                {
                    ValidIssuer = jwt.Issuer,
                    ValidAudience = JwtOptions.Audience,
                    IssuerSigningKey = signingKey,
                    ValidAlgorithms = [SecurityAlgorithms.HmacSha256],
                    ClockSkew = TimeSpan.FromMinutes(1),
                    NameClaimType = JwtRegisteredClaimNames.Name,
                };
                options.Events = new JwtBearerEvents
                {
                    OnTokenValidated = CheckActiveUserAsync,
                    OnChallenge = async context =>
                    {
                        context.HandleResponse();
                        var error = context.HttpContext.Items[AuthErrorKey] as AppError
                            ?? new AppError("unauthorized", 401, "Přihlášení chybí nebo vypršelo. Přihlas se prosím.");
                        await error.ToProblem().ExecuteAsync(context.HttpContext);
                    },
                };
            })
            .AddCookie(AdminScheme, options =>
            {
                var production = env.IsProduction();
                options.Cookie.Name = production ? "__Host-quizly-admin" : "quizly-admin";
                options.Cookie.HttpOnly = true;
                options.Cookie.SameSite = SameSiteMode.Strict;
                options.Cookie.SecurePolicy = production ? CookieSecurePolicy.Always : CookieSecurePolicy.SameAsRequest;
                options.Cookie.Path = "/";
                options.ExpireTimeSpan = TimeSpan.FromHours(12);
                options.SlidingExpiration = true;
                options.LoginPath = "/admin/login";
                options.Events.OnRedirectToLogin = context => ApiAwareRedirect(context, StatusCodes.Status401Unauthorized);
                options.Events.OnRedirectToAccessDenied = context => ApiAwareRedirect(context, StatusCodes.Status403Forbidden);
            });

        services.AddAuthorizationBuilder()
            .AddPolicy(AppPolicy, p => p
                .AddAuthenticationSchemes(JwtBearerDefaults.AuthenticationScheme)
                .RequireAuthenticatedUser())
            .AddPolicy(AdminPolicy, p => p
                .AddAuthenticationSchemes(AdminScheme)
                .RequireAuthenticatedUser()
                .RequireRole(AdminRole));

        // Validate token lifetimes with the same clock that issues them (JwtTokenIssuer uses the injected TimeProvider).
        services.AddOptions<JwtBearerOptions>(JwtBearerDefaults.AuthenticationScheme)
            .Configure<TimeProvider>((options, time) =>
            {
                options.TimeProvider = time;
                options.TokenValidationParameters.LifetimeValidator = (notBefore, expires, _, parameters) =>
                {
                    var now = time.GetUtcNow().UtcDateTime;
                    return expires is not null
                        && expires.Value > now - parameters.ClockSkew
                        && (notBefore is null || notBefore.Value <= now + parameters.ClockSkew);
                };
            });
        services.AddOptions<CookieAuthenticationOptions>(AdminScheme)
            .Configure<TimeProvider>((options, time) => options.TimeProvider = time);

        services.AddRateLimiter(options =>
        {
            AddPerIpLimit(options, config, LoginLimit, defaultPermits: 10);
            AddPerIpLimit(options, config, RefreshLimit, defaultPermits: 30);
            AddPerIpLimit(options, config, AdminLoginLimit, defaultPermits: 5);
            options.OnRejected = async (context, ct) =>
            {
                if (context.Lease.TryGetMetadata(MetadataName.RetryAfter, out var retryAfter))
                {
                    context.HttpContext.Response.Headers.RetryAfter =
                        ((int)Math.Ceiling(retryAfter.TotalSeconds)).ToString(CultureInfo.InvariantCulture);
                }

                await Errors.RateLimited.ToProblem().ExecuteAsync(context.HttpContext);
            };
        });

        return services;
    }

    /// <summary>Every authenticated request checks that the user still exists and is active (docs/spec.md §9.1).</summary>
    private static async Task CheckActiveUserAsync(TokenValidatedContext context)
    {
        var sub = context.Principal?.FindFirstValue(JwtRegisteredClaimNames.Sub);
        if (!int.TryParse(sub, CultureInfo.InvariantCulture, out var userId))
        {
            context.Fail("Missing subject.");
            return;
        }

        var services = context.HttpContext.RequestServices;
        var db = services.GetRequiredService<IAppDbContext>();
        var ct = context.HttpContext.RequestAborted;
        var isActive = await db.Users.Where(u => u.Id == userId).Select(u => (bool?)u.IsActive).FirstOrDefaultAsync(ct);
        if (isActive != true)
        {
            context.HttpContext.Items[AuthErrorKey] = Errors.AccountDisabled;
            context.Fail("Account disabled.");
            return;
        }

        // last_active_at at most once per minute.
        var now = services.GetRequiredService<TimeProvider>().GetUtcNow().UtcDateTime;
        var threshold = now.AddMinutes(-1);
        await db.Users
            .Where(u => u.Id == userId && (u.LastActiveAt == null || u.LastActiveAt < threshold))
            .ExecuteUpdateAsync(s => s.SetProperty(u => u.LastActiveAt, now), ct);
    }

    private static Task ApiAwareRedirect(Microsoft.AspNetCore.Authentication.RedirectContext<CookieAuthenticationOptions> context, int status)
    {
        if (!context.Request.Path.StartsWithSegments("/api", StringComparison.OrdinalIgnoreCase))
        {
            context.Response.Redirect(context.RedirectUri);
            return Task.CompletedTask;
        }

        var error = status == StatusCodes.Status401Unauthorized
            ? new AppError("unauthorized", 401, "Přihlas se prosím jako správce.")
            : new AppError("forbidden", 403, "Na tohle nemáš oprávnění.");
        return error.ToProblem().ExecuteAsync(context.HttpContext);
    }

    private static void AddPerIpLimit(RateLimiterOptions options, IConfiguration config, string name, int defaultPermits)
    {
        var permits = config.GetValue($"RateLimits:{name}:PermitLimit", defaultPermits);
        var window = config.GetValue($"RateLimits:{name}:Window", TimeSpan.FromMinutes(5));
        options.AddPolicy(name, context => RateLimitPartition.GetFixedWindowLimiter(
            context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            _ => new FixedWindowRateLimiterOptions { PermitLimit = permits, Window = window, QueueLimit = 0 }));
    }
}
