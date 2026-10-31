using Quizly.Domain;

namespace Quizly.Application.Auth;

/// <summary>Login with a username and password.</summary>
public sealed record LoginRequest(string Username, string Password, string? DeviceName = null);

/// <summary>A refresh token to rotate or revoke.</summary>
public sealed record RefreshRequest(string RefreshToken);

/// <summary>The signed-in app user.</summary>
public sealed record AuthUserResponse(int Id, string Username, string DisplayName);

/// <summary>Access and refresh tokens returned by login and refresh.</summary>
public sealed record TokenResponse(
    string AccessToken,
    DateTimeOffset AccessTokenExpiresAt,
    string RefreshToken,
    DateTimeOffset RefreshTokenExpiresAt,
    AuthUserResponse User);

/// <summary>A signed access token (JWT) and its expiry.</summary>
public sealed record AccessToken(string Token, DateTime ExpiresAt);

/// <summary>Creates access tokens. Implemented by the web host (JWT).</summary>
public interface IAccessTokenIssuer
{
    AccessToken Issue(User user);
}

/// <summary>Refresh-token lifetimes (docs/spec.md §9.1).</summary>
public sealed class RefreshTokenOptions
{
    public TimeSpan Lifetime { get; set; } = TimeSpan.FromDays(90);

    /// <summary>A token rotated less than this long ago may be presented again once (lost response).</summary>
    public TimeSpan RetryGrace { get; set; } = TimeSpan.FromSeconds(60);
}

/// <summary>Failed-login limit per username (docs/spec.md §9.1).</summary>
public sealed class LoginThrottleOptions
{
    public int MaxFailures { get; set; } = 5;

    public TimeSpan Window { get; set; } = TimeSpan.FromMinutes(5);
}

/// <summary>Admin credentials from <c>ADMIN_USERNAME</c> and <c>ADMIN_PASSWORD</c>.</summary>
public sealed class AdminCredentialsOptions
{
    public string Username { get; set; } = "";

    public string Password { get; set; } = "";
}
