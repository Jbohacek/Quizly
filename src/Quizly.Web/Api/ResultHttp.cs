using Microsoft.AspNetCore.Http.HttpResults;
using Quizly.Application.Common;

namespace Quizly.Web.Api;

/// <summary>Maps service results to typed HTTP results.</summary>
internal static class ResultHttp
{
    public static Results<Ok<T>, ProblemHttpResult> OkOrProblem<T>(this Result<T> result) =>
        result.IsSuccess ? TypedResults.Ok(result.Value) : result.Error.ToProblem();

    public static Results<Created<T>, ProblemHttpResult> CreatedOrProblem<T>(this Result<T> result, Func<T, string> location) =>
        result.IsSuccess ? TypedResults.Created(location(result.Value), result.Value) : result.Error.ToProblem();

    public static Results<NoContent, ProblemHttpResult> NoContentOrProblem(this Result result) =>
        result.IsSuccess ? TypedResults.NoContent() : result.Error.ToProblem();
}
