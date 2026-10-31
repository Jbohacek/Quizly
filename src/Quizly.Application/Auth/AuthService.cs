using System.Buffers.Text;
using System.Security.Cryptography;
using System.Text;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Quizly.Application.Abstractions;
using Quizly.Application.Common;
using Quizly.Domain;

namespace Quizly.Application.Auth;

public interface IAuthService
{
    Task<Result<TokenResponse>> LoginAsync(LoginRequest request, CancellationToken ct);

    Task<Result<TokenResponse>> RefreshAsync(RefreshRequest request, CancellationToken ct);

    Task LogoutAsync(RefreshRequest request, CancellationToken ct);

    Task RevokeAllAsync(int userId, CancellationToken ct);
}

/// <summary>App login, rotating refresh tokens and logout (docs/spec.md §9.1).</summary>
internal sealed class AuthService(
    IAppDbContext db,
    IAccessTokenIssuer accessTokens,
    IPasswordHasher<User> hasher,
    ILoginThrottle throttle,
    TimeProvider time,
    IOptions<RefreshTokenOptions> refreshOptions) : IAuthService
{
    // Verified against when the username doesn't exist, so both paths cost the same.
    private static readonly string DummyHash = new PasswordHasher<User>().HashPassword(new User(), "quizly-dummy-password");

    public async Task<Result<TokenResponse>> LoginAsync(LoginRequest request, CancellationToken ct)
    {
        var username = (request.Username ?? "").Trim().ToLowerInvariant();
        var password = request.Password ?? "";
        if (username.Length == 0 || password.Length == 0)
        {
            return Errors.InvalidCredentials;
        }

        if (throttle.IsBlocked(username))
        {
            return Errors.RateLimited;
        }

        var user = await db.Users.FirstOrDefaultAsync(u => u.Username == username, ct);
        var verification = hasher.VerifyHashedPassword(user ?? new User(), user?.PasswordHash ?? DummyHash, password);
        if (user is null || verification == PasswordVerificationResult.Failed)
        {
            throttle.RecordFailure(username);
            return Errors.InvalidCredentials;
        }

        throttle.Reset(username);
        if (!user.IsActive)
        {
            return Errors.AccountDisabled;
        }

        if (verification == PasswordVerificationResult.SuccessRehashNeeded)
        {
            user.PasswordHash = hasher.HashPassword(user, password);
        }

        var now = time.GetUtcNow().UtcDateTime;
        user.LastActiveAt = now;
        var (raw, token) = NewRefreshToken(user.Id, now);
        db.RefreshTokens.Add(token);
        await db.SaveChangesAsync(ct);

        return Tokens(user, raw, token);
    }

    public async Task<Result<TokenResponse>> RefreshAsync(RefreshRequest request, CancellationToken ct)
    {
        if (string.IsNullOrEmpty(request.RefreshToken))
        {
            return Errors.RefreshTokenInvalid;
        }

        var hash = Hash(request.RefreshToken);
        var now = time.GetUtcNow().UtcDateTime;

        await using var transaction = await db.Database.BeginTransactionAsync(ct);

        // Row lock: two refreshes of the same token run one after the other.
        var presented = await db.RefreshTokens
            .FromSql($"SELECT * FROM refresh_tokens WHERE token_hash = {hash} FOR UPDATE")
            .FirstOrDefaultAsync(ct);
        if (presented is null || presented.ExpiresAt <= now)
        {
            return Errors.RefreshTokenInvalid;
        }

        var user = await db.Users.FirstAsync(u => u.Id == presented.UserId, ct);
        if (!user.IsActive)
        {
            return Errors.AccountDisabled;
        }

        RefreshToken? toRevoke = presented;
        if (presented.RevokedAt is not null)
        {
            var replacement = presented.ReplacedById is int replacedById
                ? await db.RefreshTokens
                    .FromSql($"SELECT * FROM refresh_tokens WHERE id = {replacedById} FOR UPDATE")
                    .FirstOrDefaultAsync(ct)
                : null;

            var withinGrace = now - presented.RevokedAt.Value < refreshOptions.Value.RetryGrace;
            if (!withinGrace || replacement is null || replacement.RevokedAt is not null)
            {
                // Reuse of a rotated token: treat as theft and sign the user out everywhere.
                await RevokeActiveAsync(user.Id, now, ct);
                await db.SaveChangesAsync(ct);
                await transaction.CommitAsync(ct);
                return Errors.RefreshTokenInvalid;
            }

            // The phone lost the previous response: rotate again from the unused replacement.
            toRevoke = replacement;
        }

        var (raw, token) = NewRefreshToken(user.Id, now);
        db.RefreshTokens.Add(token);
        await db.SaveChangesAsync(ct);

        toRevoke.RevokedAt = now;
        toRevoke.ReplacedById = token.Id;
        user.LastActiveAt = now;
        await db.SaveChangesAsync(ct);
        await transaction.CommitAsync(ct);

        return Tokens(user, raw, token);
    }

    public async Task LogoutAsync(RefreshRequest request, CancellationToken ct)
    {
        if (string.IsNullOrEmpty(request.RefreshToken))
        {
            return;
        }

        var hash = Hash(request.RefreshToken);
        var token = await db.RefreshTokens.FirstOrDefaultAsync(t => t.TokenHash == hash && t.RevokedAt == null, ct);
        if (token is not null)
        {
            token.RevokedAt = time.GetUtcNow().UtcDateTime;
            await db.SaveChangesAsync(ct);
        }
    }

    public async Task RevokeAllAsync(int userId, CancellationToken ct)
    {
        await RevokeActiveAsync(userId, time.GetUtcNow().UtcDateTime, ct);
        await db.SaveChangesAsync(ct);
    }

    internal static byte[] Hash(string rawToken) => SHA256.HashData(Encoding.UTF8.GetBytes(rawToken));

    private async Task RevokeActiveAsync(int userId, DateTime now, CancellationToken ct)
    {
        var active = await db.RefreshTokens.Where(t => t.UserId == userId && t.RevokedAt == null).ToListAsync(ct);
        foreach (var token in active)
        {
            token.RevokedAt = now;
        }
    }

    private (string Raw, RefreshToken Token) NewRefreshToken(int userId, DateTime now)
    {
        var raw = Base64Url.EncodeToString(RandomNumberGenerator.GetBytes(32));
        var token = new RefreshToken
        {
            UserId = userId,
            TokenHash = Hash(raw),
            CreatedAt = now,
            ExpiresAt = now + refreshOptions.Value.Lifetime,
        };
        return (raw, token);
    }

    private TokenResponse Tokens(User user, string rawRefresh, RefreshToken refresh)
    {
        var access = accessTokens.Issue(user);
        return new TokenResponse(
            access.Token,
            access.ExpiresAt.ToUtcOffset(),
            rawRefresh,
            refresh.ExpiresAt.ToUtcOffset(),
            new AuthUserResponse(user.Id, user.Username, user.DisplayName));
    }
}
