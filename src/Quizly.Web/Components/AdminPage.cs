using Microsoft.AspNetCore.Components;
using Quizly.Application.Common;

namespace Quizly.Web.Components;

/// <summary>
/// Base for dashboard pages. A Blazor Server page lives as long as the circuit, so every service call
/// gets its own DI scope (fresh DbContext, no stale tracked entities).
/// </summary>
public abstract class AdminPage : ComponentBase
{
    [Inject]
    private IServiceScopeFactory ScopeFactory { get; set; } = default!;

    /// <summary>Short confirmation shown at the top of the page ("Uloženo").</summary>
    protected string? Notice { get; set; }

    /// <summary>The last failure: its Czech title and field errors.</summary>
    protected AppError? Error { get; set; }

    protected async Task<T> UseAsync<TService, T>(Func<TService, Task<T>> action)
        where TService : notnull
    {
        await using var scope = ScopeFactory.CreateAsyncScope();
        return await action(scope.ServiceProvider.GetRequiredService<TService>());
    }

    protected async Task UseAsync<TService>(Func<TService, Task> action)
        where TService : notnull
    {
        await using var scope = ScopeFactory.CreateAsyncScope();
        await action(scope.ServiceProvider.GetRequiredService<TService>());
    }

    /// <summary>Clears messages, runs a service result and records the error or notice.</summary>
    protected bool Handle(Result result, string? notice = null)
    {
        Error = result.IsSuccess ? null : result.Error;
        Notice = result.IsSuccess ? notice : null;
        return result.IsSuccess;
    }

    protected bool Handle<T>(Result<T> result, string? notice = null)
    {
        Error = result.IsSuccess ? null : result.Error;
        Notice = result.IsSuccess ? notice : null;
        return result.IsSuccess;
    }

    /// <summary>The first error for a field (camelCase name), for showing under an input.</summary>
    protected string? FieldError(string field) =>
        Error?.Errors is { } errors && errors.TryGetValue(field, out var messages) ? messages.FirstOrDefault() : null;

    protected void ClearMessages()
    {
        Error = null;
        Notice = null;
    }
}
