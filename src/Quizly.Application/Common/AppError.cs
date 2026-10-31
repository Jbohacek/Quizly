namespace Quizly.Application.Common;

/// <summary>
/// A failure the API turns into RFC 7807 ProblemDetails (docs/api.md §1.1).
/// <see cref="Title"/> is a Czech message the app may show as is.
/// </summary>
public sealed record AppError(
    string Code,
    int Status,
    string Title,
    IReadOnlyDictionary<string, string[]>? Errors = null);

public static class Errors
{
    public static AppError Validation(IReadOnlyDictionary<string, string[]> errors) =>
        new("validation", 400, "Některé údaje nejsou v pořádku.", errors);

    public static AppError Validation(string field, string message) =>
        Validation(new Dictionary<string, string[]> { [field] = [message] });

    public static AppError NotFound(string title = "Tohle jsme nenašli.") =>
        new("notFound", 404, title);

    public static readonly AppError InvalidCredentials =
        new("invalidCredentials", 401, "Nesprávné uživatelské jméno nebo heslo.");

    public static readonly AppError AccountDisabled =
        new("accountDisabled", 401, "Účet je deaktivovaný. Ozvi se správci aplikace.");

    public static readonly AppError RefreshTokenInvalid =
        new("refreshTokenInvalid", 401, "Přihlášení vypršelo. Přihlas se prosím znovu.");

    public static readonly AppError RateLimited =
        new("rateLimited", 429, "Příliš mnoho pokusů. Zkus to prosím za chvíli.");

    public static readonly AppError ConcurrencyConflict =
        new("concurrencyConflict", 409, "Záznam se mezitím změnil. Načti ho znovu.");

    public static readonly AppError HasClaims =
        new("hasClaims", 409, "Odměnu už někdo koupil, nejde smazat. Můžeš ji deaktivovat.");

    public static AppError Conflict(string code, string title) => new(code, 409, title);
}
