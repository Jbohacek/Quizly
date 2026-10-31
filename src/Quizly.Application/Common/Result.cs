using System.Diagnostics.CodeAnalysis;

namespace Quizly.Application.Common;

/// <summary>Either a value or an <see cref="AppError"/>.</summary>
public readonly struct Result<T>
{
    private Result(T? value, AppError? error)
    {
        Value = value;
        Error = error;
    }

    public T? Value { get; }

    public AppError? Error { get; }

    [MemberNotNullWhen(true, nameof(Value))]
    [MemberNotNullWhen(false, nameof(Error))]
    public bool IsSuccess => Error is null;

    public static Result<T> Ok(T value) => new(value, null);

    public static Result<T> Fail(AppError error) => new(default, error);

    public static implicit operator Result<T>(T value) => Ok(value);

    public static implicit operator Result<T>(AppError error) => Fail(error);
}

/// <summary>A result without a value.</summary>
public readonly struct Result
{
    private Result(AppError? error) => Error = error;

    public AppError? Error { get; }

    [MemberNotNullWhen(false, nameof(Error))]
    public bool IsSuccess => Error is null;

    public static Result Ok() => new(null);

    public static implicit operator Result(AppError error) => new(error);
}
