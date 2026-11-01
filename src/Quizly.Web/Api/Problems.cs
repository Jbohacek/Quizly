using System.Text.Json;
using Microsoft.AspNetCore.Http.HttpResults;
using Microsoft.AspNetCore.Mvc;
using Quizly.Application.Common;

namespace Quizly.Web.Api;

/// <summary>Builds RFC 7807 responses in the shape of docs/api.md §1.1.</summary>
internal static class Problems
{
    public const string TypeBase = "https://quizly.jbohacek.cz/problems/";

    public static ProblemHttpResult ToProblem(this AppError error)
    {
        var problem = new ProblemDetails
        {
            Type = TypeBase + Kebab(error.Code),
            Title = error.Title,
            Status = error.Status,
        };
        problem.Extensions["code"] = error.Code;
        if (error.Errors is not null)
        {
            problem.Extensions["errors"] = error.Errors;
        }

        foreach (var (key, value) in error.Extensions ?? new Dictionary<string, object?>())
        {
            problem.Extensions[key] = value;
        }

        return TypedResults.Problem(problem);
    }

    /// <summary>Fills code, type, Czech title and traceId on every ProblemDetails, including framework ones (404 route, 401 challenge).</summary>
    public static void Customize(ProblemDetailsContext context)
    {
        var problem = context.ProblemDetails;
        var status = problem.Status ?? context.HttpContext.Response.StatusCode;
        if (!problem.Extensions.ContainsKey("code"))
        {
            var (code, title) = Defaults(status);
            problem.Extensions["code"] = code;
            problem.Type = TypeBase + Kebab(code);
            problem.Title = title;
        }

        problem.Detail = null;
        problem.Extensions.Remove("exception");
        problem.Extensions["traceId"] = context.HttpContext.TraceIdentifier;
    }

    private static (string Code, string Title) Defaults(int status) => status switch
    {
        400 => ("validation", "Některé údaje nejsou v pořádku."),
        401 => ("unauthorized", "Přihlášení chybí nebo vypršelo. Přihlas se prosím."),
        403 => ("forbidden", "Na tohle nemáš oprávnění."),
        404 => ("notFound", "Tohle jsme nenašli."),
        405 => ("methodNotAllowed", "Tahle metoda tu není povolená."),
        415 => ("unsupportedMediaType", "Pošli data jako application/json."),
        429 => ("rateLimited", "Příliš mnoho pokusů. Zkus to prosím za chvíli."),
        _ => ("serverError", "Něco se pokazilo. Zkus to prosím znovu."),
    };

    private static string Kebab(string code) => JsonNamingPolicy.KebabCaseLower.ConvertName(code);
}
