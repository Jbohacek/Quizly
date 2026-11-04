using System.Security.Cryptography;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using ModelContextProtocol;
using Quizly.Web.Auth;

namespace Quizly.Web.Mcp;

/// <summary>MCP settings from <c>Mcp__*</c> (docs/mcp.md).</summary>
public sealed class McpOptions
{
    public const int MinSecretLength = 48;

    public bool Enabled { get; set; }

    public string Secret { get; set; } = "";

    /// <summary>The secret is a whole path segment: long enough not to be guessed, and URL-safe so it needs no escaping.</summary>
    public void Validate()
    {
        if (Secret.Length < MinSecretLength || !Secret.All(c => char.IsAsciiLetterOrDigit(c) || c is '-' or '_'))
        {
            throw new InvalidOperationException(
                $"Mcp__Secret must be at least {MinSecretLength} URL-safe characters (A–Z, a–z, 0–9, '-', '_') when Mcp__Enabled is true.");
        }
    }
}

/// <summary>
/// The MCP server for Claude (docs/mcp.md): Streamable HTTP at <c>/mcp/&lt;secret&gt;</c>, only when <c>Mcp__Enabled</c>.
/// </summary>
internal static class McpSetup
{
    /// <summary>The path the endpoint is mapped at; requests reach it only through <see cref="UseQuizlyMcpSecret"/>.</summary>
    public const string Path = "/mcp";

    private const string VerifiedKey = "quizly.mcpSecretVerified";

    public static IServiceCollection AddQuizlyMcp(this IServiceCollection services, IConfiguration config)
    {
        var options = Options(config);
        if (!options.Enabled)
        {
            return services;
        }

        options.Validate();
        services.AddMcpServer(o => o.ServerInfo = new() { Name = "quizly", Title = "Quizly", Version = "1.0.0" })
            .WithHttpTransport(o => o.Stateless = true)
            // Czech text and YAML as written (no \u00E1 escapes): easier for Claude to read back, fewer tokens.
            .WithTools<DeckTools>(new JsonSerializerOptions(McpJsonUtilities.DefaultOptions) { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping });
        return services;
    }

    /// <summary>
    /// Checks the secret in <c>/mcp/&lt;secret&gt;</c> and strips it from the path before routing, so routing, the MCP
    /// handler and their logs only ever see <c>/mcp</c>. Anything else under <c>/mcp</c> (or all of it with MCP off)
    /// gets 404, as if nothing was there. Must run before <c>UseRouting</c>.
    /// </summary>
    public static IApplicationBuilder UseQuizlyMcpSecret(this IApplicationBuilder app, IConfiguration config)
    {
        var options = Options(config);
        var secret = Encoding.UTF8.GetBytes(options.Secret);
        return app.Use((context, next) =>
        {
            // Routing ignores case, so this must too.
            if (!context.Request.Path.StartsWithSegments(Path, StringComparison.OrdinalIgnoreCase, out var rest))
            {
                return next(context);
            }

            // Only "/<secret>" (or "/<secret>/") may follow.
            var segment = (rest.Value ?? "").TrimEnd('/');
            if (!options.Enabled || segment.Length < 2 || segment.IndexOf('/', 1) >= 0
                || !CryptographicOperations.FixedTimeEquals(Encoding.UTF8.GetBytes(segment[1..]), secret))
            {
                context.Response.StatusCode = StatusCodes.Status404NotFound;
                return Task.CompletedTask;
            }

            context.Request.Path = Path;
            context.Items[VerifiedKey] = true;
            return next(context);
        });
    }

    public static void MapQuizlyMcp(this IEndpointRouteBuilder app, IConfiguration config)
    {
        if (Options(config).Enabled)
        {
            var endpoints = app.MapMcp(Path).AllowAnonymous().RequireRateLimiting(AuthSetup.McpLimit);

            // Defense in depth: a request that reached the endpoint without passing the secret check
            // (some path spelling routing matches but the check doesn't) is still a 404.
            endpoints.Add(endpoint =>
            {
                var inner = endpoint.RequestDelegate!;
                endpoint.RequestDelegate = context =>
                {
                    if (context.Items.ContainsKey(VerifiedKey))
                    {
                        return inner(context);
                    }

                    context.Response.StatusCode = StatusCodes.Status404NotFound;
                    return Task.CompletedTask;
                };
            });
        }
    }

    private static McpOptions Options(IConfiguration config) => config.GetSection("Mcp").Get<McpOptions>() ?? new McpOptions();
}
