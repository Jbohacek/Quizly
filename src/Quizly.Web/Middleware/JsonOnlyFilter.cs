using Quizly.Application.Common;
using Quizly.Web.Api;

namespace Quizly.Web.Middleware;

/// <summary>
/// Admin writes must be JSON (docs/spec.md §9.2). Cross-site forms can only send form or text bodies,
/// so together with the SameSite=Strict cookie this blocks CSRF.
/// </summary>
internal sealed class JsonOnlyFilter : IEndpointFilter
{
    public async ValueTask<object?> InvokeAsync(EndpointFilterInvocationContext context, EndpointFilterDelegate next)
    {
        var request = context.HttpContext.Request;
        var isWrite = HttpMethods.IsPost(request.Method) || HttpMethods.IsPut(request.Method)
            || HttpMethods.IsPatch(request.Method) || HttpMethods.IsDelete(request.Method);
        var hasBody = request.ContentLength > 0 || request.ContentType is not null;
        if (isWrite && hasBody && !request.HasJsonContentType())
        {
            return new AppError("unsupportedMediaType", StatusCodes.Status415UnsupportedMediaType, "Pošli data jako application/json.")
                .ToProblem();
        }

        return await next(context);
    }
}
