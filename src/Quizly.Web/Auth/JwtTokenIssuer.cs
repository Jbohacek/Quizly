using System.Security.Claims;
using System.Text;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;
using Quizly.Application.Auth;
using Quizly.Domain;
using SecurityClaim = System.Security.Claims.Claim;

namespace Quizly.Web.Auth;

/// <summary>JWT settings from <c>Jwt__*</c> (docs/spec.md §9.1).</summary>
public sealed class JwtOptions
{
    public const string Audience = "quizly-app";

    public string SigningKey { get; set; } = "";

    public string Issuer { get; set; } = "";

    public TimeSpan AccessTokenLifetime { get; set; } = TimeSpan.FromMinutes(60);

    public SymmetricSecurityKey Key()
    {
        var bytes = Encoding.UTF8.GetBytes(SigningKey);
        if (bytes.Length < 32)
        {
            throw new InvalidOperationException("Jwt__SigningKey must be at least 32 bytes.");
        }

        if (string.IsNullOrWhiteSpace(Issuer))
        {
            throw new InvalidOperationException("Jwt__Issuer must be set.");
        }

        return new SymmetricSecurityKey(bytes);
    }
}

internal sealed class JwtTokenIssuer(IOptions<JwtOptions> options, TimeProvider time) : IAccessTokenIssuer
{
    private readonly JsonWebTokenHandler _handler = new();

    public AccessToken Issue(User user)
    {
        var jwt = options.Value;
        var now = time.GetUtcNow().UtcDateTime;
        var expires = now + jwt.AccessTokenLifetime;
        var token = _handler.CreateToken(new SecurityTokenDescriptor
        {
            Issuer = jwt.Issuer,
            Audience = JwtOptions.Audience,
            IssuedAt = now,
            NotBefore = now,
            Expires = expires,
            Subject = new ClaimsIdentity(
            [
                new SecurityClaim(JwtRegisteredClaimNames.Sub, user.Id.ToString(System.Globalization.CultureInfo.InvariantCulture)),
                new SecurityClaim(JwtRegisteredClaimNames.Name, user.Username),
            ]),
            SigningCredentials = new SigningCredentials(jwt.Key(), SecurityAlgorithms.HmacSha256),
        });
        return new AccessToken(token, expires);
    }
}
