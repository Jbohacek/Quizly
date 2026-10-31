using System.Security.Cryptography;
using System.Text;
using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.Options;

namespace Quizly.Application.Auth;

public interface IAdminAuthenticator
{
    string Username { get; }

    bool Verify(string username, string password);
}

/// <summary>The single admin account. The password is hashed once at startup and compared with <see cref="PasswordHasher{TUser}"/>.</summary>
internal sealed class AdminAuthenticator : IAdminAuthenticator
{
    private static readonly AdminAccount Account = new();
    private readonly PasswordHasher<AdminAccount> _hasher = new();
    private readonly string _passwordHash;

    public AdminAuthenticator(IOptions<AdminCredentialsOptions> options)
    {
        var value = options.Value;
        if (string.IsNullOrWhiteSpace(value.Username) || string.IsNullOrEmpty(value.Password))
        {
            throw new InvalidOperationException("ADMIN_USERNAME and ADMIN_PASSWORD must be set.");
        }

        Username = value.Username.Trim();
        _passwordHash = _hasher.HashPassword(Account, value.Password);
    }

    public string Username { get; }

    public bool Verify(string username, string password)
    {
        var usernameOk = CryptographicOperations.FixedTimeEquals(
            Encoding.UTF8.GetBytes(username.Trim()), Encoding.UTF8.GetBytes(Username));
        var passwordOk = _hasher.VerifyHashedPassword(Account, _passwordHash, password) != PasswordVerificationResult.Failed;
        return usernameOk && passwordOk;
    }

    private sealed class AdminAccount;
}
