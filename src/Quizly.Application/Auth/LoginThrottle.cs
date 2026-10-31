using System.Collections.Concurrent;
using Microsoft.Extensions.Options;

namespace Quizly.Application.Auth;

public interface ILoginThrottle
{
    bool IsBlocked(string key);

    void RecordFailure(string key);

    void Reset(string key);
}

/// <summary>In-memory sliding window of failed logins per key (username). One server instance, so memory is enough.</summary>
internal sealed class LoginThrottle(TimeProvider time, IOptions<LoginThrottleOptions> options) : ILoginThrottle
{
    private readonly ConcurrentDictionary<string, Queue<DateTimeOffset>> _failures = new(StringComparer.Ordinal);

    public bool IsBlocked(string key)
    {
        if (!_failures.TryGetValue(key, out var queue))
        {
            return false;
        }

        lock (queue)
        {
            Prune(queue);
            return queue.Count >= options.Value.MaxFailures;
        }
    }

    public void RecordFailure(string key)
    {
        var queue = _failures.GetOrAdd(key, _ => new Queue<DateTimeOffset>());
        lock (queue)
        {
            Prune(queue);
            queue.Enqueue(time.GetUtcNow());
        }
    }

    public void Reset(string key) => _failures.TryRemove(key, out _);

    private void Prune(Queue<DateTimeOffset> queue)
    {
        var cutoff = time.GetUtcNow() - options.Value.Window;
        while (queue.Count > 0 && queue.Peek() <= cutoff)
        {
            queue.Dequeue();
        }
    }
}
