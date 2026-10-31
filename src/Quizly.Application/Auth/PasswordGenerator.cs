using System.Security.Cryptography;
using Quizly.Domain;

namespace Quizly.Application.Auth;

public interface IPasswordGenerator
{
    string Generate();
}

/// <summary>12 characters from an alphabet without look-alikes (no 0/O, 1/l/I), crypto RNG.</summary>
internal sealed class PasswordGenerator : IPasswordGenerator
{
    internal const string Alphabet = "abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789";

    public string Generate() => RandomNumberGenerator.GetString(Alphabet, Limits.GeneratedPasswordLength);
}
