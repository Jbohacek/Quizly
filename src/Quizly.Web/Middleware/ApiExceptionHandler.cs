using System.Text.Json;
using Microsoft.AspNetCore.Diagnostics;
using Quizly.Application.Common;
using Quizly.Web.Api;

namespace Quizly.Web.Middleware;

/// <summary>
/// Turns unreadable request bodies into 400 validation problems. Everything else falls through
/// to the default handler, which logs it and returns a 500 serverError ProblemDetails.
/// </summary>
internal sealed class ApiExceptionHandler(ILogger<ApiExceptionHandler> logger) : IExceptionHandler
{
    public async ValueTask<bool> TryHandleAsync(HttpContext httpContext, Exception exception, CancellationToken cancellationToken)
    {
        if (exception is not BadHttpRequestException badRequest)
        {
            return false;
        }

        logger.LogInformation(exception, "Rejected an unreadable request to {Path}", httpContext.Request.Path);

        var field = badRequest.InnerException is JsonException { Path: { } path } ? path : "body";
        var error = Errors.Validation(field, "Požadavek nejde přečíst. Zkontroluj formát a povinné údaje.");
        if (badRequest.StatusCode == StatusCodes.Status415UnsupportedMediaType)
        {
            error = new AppError("unsupportedMediaType", 415, "Pošli data jako application/json.");
        }

        await error.ToProblem().ExecuteAsync(httpContext);
        return true;
    }
}
