using System.Collections.Concurrent;
using System.Net;
using System.Text;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.Hosting;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ModelContextProtocol.Client;
using ModelContextProtocol.Protocol;
using Quizly.Tests.Infrastructure;

namespace Quizly.Tests.Api;

public class McpFactory(PostgresContainer postgres) : QuizlyFactory(postgres)
{
    public const string Secret = "test-mcp-secret_0123456789abcdefghijklmnopqrstuvwxyz";

    protected override IEnumerable<KeyValuePair<string, string>> ExtraSettings =>
    [
        new("Mcp:Enabled", "true"),
        new("Mcp:Secret", Secret),
        new("RateLimits:mcp:PermitLimit", "10000"),
    ];

    /// <summary>Every log line the app wrote, with the levels configured in appsettings.json.</summary>
    public ConcurrentQueue<string> Logs { get; } = new();

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        base.ConfigureWebHost(builder);
        builder.ConfigureLogging(logging => logging.AddProvider(new CapturingLoggerProvider(Logs)));
    }

    /// <summary>An MCP client over the in-memory server, as Claude connects to it.</summary>
    public async Task<McpClient> McpClientAsync(string path = "/mcp/" + Secret)
    {
        var http = CreateClient();
        var transport = new HttpClientTransport(
            new HttpClientTransportOptions { Endpoint = new Uri(http.BaseAddress!, path), TransportMode = HttpTransportMode.StreamableHttp },
            http,
            ownsHttpClient: true);
        return await McpClient.CreateAsync(transport, cancellationToken: TestContext.Current.CancellationToken);
    }
}

public sealed class CapturingLoggerProvider(ConcurrentQueue<string> logs) : ILoggerProvider
{
    public ILogger CreateLogger(string categoryName) => new Logger(categoryName, logs);

    public void Dispose()
    {
    }

    private sealed class Logger(string category, ConcurrentQueue<string> logs) : ILogger
    {
        public IDisposable? BeginScope<TState>(TState state)
            where TState : notnull => null;

        public bool IsEnabled(LogLevel logLevel) => true;

        public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception, Func<TState, Exception?, string> formatter) =>
            logs.Enqueue($"{category}: {formatter(state, exception)} {exception}");
    }
}

public sealed class McpTightLimitFactory(PostgresContainer postgres) : McpFactory(postgres)
{
    protected override IEnumerable<KeyValuePair<string, string>> ExtraSettings =>
        [.. base.ExtraSettings.Where(s => !s.Key.StartsWith("RateLimits:", StringComparison.Ordinal)), new("RateLimits:mcp:PermitLimit", "3")];
}

public sealed class McpShortSecretFactory(PostgresContainer postgres) : QuizlyFactory(postgres)
{
    protected override IEnumerable<KeyValuePair<string, string>> ExtraSettings =>
        [new("Mcp:Enabled", "true"), new("Mcp:Secret", "too-short")];
}

/// <summary>The MCP server for Claude (docs/mcp.md): the four deck tools, never deleting, behind the secret path.</summary>
public sealed class McpTests(McpFactory factory) : IClassFixture<McpFactory>
{
    private static CancellationToken Ct => TestContext.Current.CancellationToken;

    [Fact]
    public async Task Lists_exactly_the_four_deck_tools()
    {
        await using var client = await factory.McpClientAsync();

        var tools = await client.ListToolsAsync(cancellationToken: Ct);

        Assert.Equal(["apply_deck_yaml", "get_deck_yaml", "list_decks", "preview_deck_yaml"], tools.Select(t => t.Name).Order());
        Assert.Contains("Keep every existing card's `id`", tools.Single(t => t.Name == "get_deck_yaml").Description, StringComparison.Ordinal);
    }

    [Fact]
    public async Task List_decks_shows_ids_names_and_card_counts()
    {
        var name = "M" + Guid.NewGuid().ToString("N")[..6];
        var (deckId, _) = await factory.CreateDeckAsync(name, 3);
        await using var client = await factory.McpClientAsync();

        var decks = await CallAsync(client, "list_decks", []);

        var deck = decks.AsArray().Single(d => (int)d!["id"]! == deckId)!;
        Assert.Equal((name, "", 3), ((string?)deck["name"], (string?)deck["description"], (int)deck["cardCount"]!));
        Assert.False((bool)deck["archived"]!);
    }

    [Fact]
    public async Task List_decks_flags_archived_decks()
    {
        var (deckId, _) = await factory.CreateDeckAsync("A" + Guid.NewGuid().ToString("N")[..6], 1);
        await factory.WithDbAsync(async db =>
            await db.Decks.Where(d => d.Id == deckId).ExecuteUpdateAsync(s => s.SetProperty(d => d.ArchivedAt, DateTime.UtcNow), Ct));
        await using var client = await factory.McpClientAsync();

        var decks = await CallAsync(client, "list_decks", []);

        Assert.True((bool)decks.AsArray().Single(d => (int)d!["id"]! == deckId)!["archived"]!);
    }

    [Fact]
    public async Task Get_deck_yaml_exports_with_ids_and_base_hash()
    {
        var (deckId, ids) = await factory.CreateDeckAsync("G" + Guid.NewGuid().ToString("N")[..6], 2);
        await using var client = await factory.McpClientAsync();

        var export = await CallAsync(client, "get_deck_yaml", new() { ["deckId"] = deckId });
        var missing = await CallRawAsync(client, "get_deck_yaml", new() { ["deckId"] = 999_999 });

        var yaml = (string)export["yaml"]!;
        Assert.StartsWith("# Quizly balíček · formát v1\n", yaml, StringComparison.Ordinal);
        Assert.Contains($"id: {ids[1]}", yaml, StringComparison.Ordinal);
        Assert.Equal(64, ((string)export["baseHash"]!).Length);
        Assert.True(missing.IsError);
        Assert.Contains("does not exist", Text(missing), StringComparison.Ordinal);
    }

    [Fact]
    public async Task Preview_keeps_missing_cards_and_saves_nothing()
    {
        var (deckId, ids) = await factory.CreateDeckAsync("P" + Guid.NewGuid().ToString("N")[..6], 3);
        await using var client = await factory.McpClientAsync();
        var yaml = $"deck:\n  name: Náhled\ncards:\n  - id: {ids[0]}\n    question: Změněná\n    answer: Odpověď 1\n  - question: Nová\n    answer: Ano\n";

        var preview = await CallAsync(client, "preview_deck_yaml", new() { ["yaml"] = yaml, ["deckId"] = deckId });

        Assert.True((bool)preview["valid"]!);
        Assert.Equal((1, 1, 0, 2), Counts(preview));
        Assert.Equal([ids[1], ids[2]], preview["missingKept"]!.AsArray().Select(c => (int)c!["id"]!));
        Assert.Null(preview["deleted"]);
        Assert.Contains("not deleted", (string)preview["note"]!, StringComparison.Ordinal);
        await factory.WithDbAsync(async db =>
            Assert.DoesNotContain(await db.Cards.Where(c => c.DeckId == deckId).Select(c => c.Question).ToListAsync(Ct), q => q is "Změněná" or "Nová"));
    }

    [Fact]
    public async Task Preview_reports_validation_errors_with_line_numbers()
    {
        var (deckId, _) = await factory.CreateDeckAsync("V" + Guid.NewGuid().ToString("N")[..6], 1);
        await using var client = await factory.McpClientAsync();

        var preview = await CallAsync(client, "preview_deck_yaml", new() { ["yaml"] = "deck:\n  name: A\ncards:\n  - question: Q\n    anwser: A\n", ["deckId"] = deckId });
        var newDeck = await CallAsync(client, "preview_deck_yaml", new() { ["yaml"] = "deck:\n  name: A\ncards:\n  - id: 7\n    question: Q\n    answer: A\n" });

        Assert.False((bool)preview["valid"]!);
        Assert.Contains(preview["errors"]!.AsArray(), e => (string?)e!["code"] == "unknownKey" && (int)e["line"]! == 5);
        Assert.False((bool)newDeck["valid"]!);
        Assert.Equal("idInNewDeck", (string?)newDeck["errors"]![0]!["code"]);
    }

    [Fact]
    public async Task Apply_never_deletes_and_keeps_everyones_progress()
    {
        var (deckId, ids) = await factory.CreateDeckAsync("A" + Guid.NewGuid().ToString("N")[..6], 3);
        var user = await factory.CreateUserAsync();
        using (var app = await factory.AppClientAsync(user))
        {
            await StudyTests.ReviewAsync(app, (ids[0], "know"), (ids[1], "know"));
        }

        await using var client = await factory.McpClientAsync();
        var baseHash = (string)(await CallAsync(client, "get_deck_yaml", new() { ["deckId"] = deckId }))["baseHash"]!;
        var yaml = $"deck:\n  name: Uložený\ncards:\n  - id: {ids[2]}\n    question: Třetí upravená\n    answer: Odpověď 3\n  - question: Přidaná\n    answer: Ano\n";

        var applied = await CallAsync(client, "apply_deck_yaml", new() { ["yaml"] = yaml, ["deckId"] = deckId, ["baseHash"] = baseHash });

        Assert.True((bool)applied["saved"]!);
        Assert.Equal((1, 1, 0, 2), Counts(applied));
        Assert.Equal([ids[0], ids[1]], applied["missingKept"]!.AsArray().Select(c => (int)c!["id"]!));
        Assert.Empty(applied["errors"]!.AsArray());
        await factory.WithDbAsync(async db =>
        {
            var cards = await db.Cards.Where(c => c.DeckId == deckId).OrderBy(c => c.SortOrder).ToListAsync(Ct);
            Assert.Equal(["Třetí upravená", "Přidaná"], cards.Take(2).Select(c => c.Question));
            Assert.Equal([ids[0], ids[1]], cards.Skip(2).Select(c => c.Id));   // kept cards follow, in their order
            Assert.Equal([0, 1, 2, 3], cards.Select(c => c.SortOrder));
            Assert.Equal(2, await db.CardStates.CountAsync(s => s.CardId == ids[0] || s.CardId == ids[1], Ct));
            Assert.Equal("Uložený", (await db.Decks.SingleAsync(d => d.Id == deckId, Ct)).Name);
        });

        // The returned hash is the new base: the fresh export applies with no changes.
        var export = await CallAsync(client, "get_deck_yaml", new() { ["deckId"] = deckId });
        Assert.Equal((string?)applied["baseHash"], (string?)export["baseHash"]);
        var again = await CallAsync(client, "apply_deck_yaml", new() { ["yaml"] = (string)export["yaml"]!, ["deckId"] = deckId, ["baseHash"] = (string)export["baseHash"]! });
        Assert.Equal((0, 0, 4, 0), Counts(again));
    }

    [Fact]
    public async Task Apply_needs_a_current_base_hash()
    {
        var (deckId, ids) = await factory.CreateDeckAsync("H" + Guid.NewGuid().ToString("N")[..6], 1);
        await using var client = await factory.McpClientAsync();
        var yaml = $"deck:\n  name: H\ncards:\n  - id: {ids[0]}\n    question: Jiná\n    answer: Odpověď 1\n";

        var withoutHash = await CallRawAsync(client, "apply_deck_yaml", new() { ["yaml"] = yaml, ["deckId"] = deckId });
        var staleHash = await CallRawAsync(client, "apply_deck_yaml", new() { ["yaml"] = yaml, ["deckId"] = deckId, ["baseHash"] = new string('0', 64) });

        Assert.True(withoutHash.IsError);
        Assert.Contains("baseHash is required", Text(withoutHash), StringComparison.Ordinal);
        Assert.True(staleHash.IsError);
        Assert.Contains("changed since baseHash", Text(staleHash), StringComparison.Ordinal);
        await factory.WithDbAsync(async db => Assert.NotEqual("Jiná", (await db.Cards.SingleAsync(c => c.Id == ids[0], Ct)).Question));
    }

    [Fact]
    public async Task Apply_with_errors_saves_nothing()
    {
        var (deckId, ids) = await factory.CreateDeckAsync("X" + Guid.NewGuid().ToString("N")[..6], 1);
        await using var client = await factory.McpClientAsync();
        var baseHash = (string)(await CallAsync(client, "get_deck_yaml", new() { ["deckId"] = deckId }))["baseHash"]!;
        var yaml = $"deck:\n  name: X\ncards:\n  - id: {ids[0]}\n    question: Jiná\n    answer: Odpověď 1\n  - id: 999999\n    question: Q\n    answer: A\n";

        var applied = await CallAsync(client, "apply_deck_yaml", new() { ["yaml"] = yaml, ["deckId"] = deckId, ["baseHash"] = baseHash });

        Assert.False((bool)applied["saved"]!);
        Assert.Equal(("unknownId", 7), ((string?)applied["errors"]![0]!["code"], (int)applied["errors"]![0]!["line"]!));
        await factory.WithDbAsync(async db => Assert.NotEqual("Jiná", (await db.Cards.SingleAsync(c => c.Id == ids[0], Ct)).Question));
    }

    [Fact]
    public async Task Apply_without_deck_id_creates_a_new_deck()
    {
        await using var client = await factory.McpClientAsync();
        var name = "Nový " + Guid.NewGuid().ToString("N")[..6];
        var yaml = $"deck:\n  name: {name}\n  description: Od Clauda\ncards:\n  - question: Q1\n    answer: A1\n  - question: Q2\n    answer: |\n      **Tučně**\n      - bod\n";

        var created = await CallAsync(client, "apply_deck_yaml", new() { ["yaml"] = yaml });
        var withIds = await CallAsync(client, "apply_deck_yaml", new() { ["yaml"] = yaml.Replace("  - question: Q1", "  - id: 5\n    question: Q1", StringComparison.Ordinal) });

        Assert.True((bool)created["saved"]!);
        Assert.Equal((2, 0, 0, 0), Counts(created));
        var deckId = (int)created["deckId"]!;
        var export = await CallAsync(client, "get_deck_yaml", new() { ["deckId"] = deckId });
        Assert.Equal((string?)created["baseHash"], (string?)export["baseHash"]);
        await factory.WithDbAsync(async db =>
        {
            var deck = await db.Decks.Include(d => d.Cards).SingleAsync(d => d.Id == deckId, Ct);
            Assert.Equal((name, "Od Clauda", true), (deck.Name, deck.Description, deck.ForEveryone));
            Assert.Equal("**Tučně**\n- bod", deck.Cards.Single(c => c.Question == "Q2").Answer);
        });
        Assert.False((bool)withIds["saved"]!);
        Assert.Equal("idInNewDeck", (string?)withIds["errors"]![0]!["code"]);
    }

    [Theory]
    [InlineData("/mcp")]
    [InlineData("/mcp/")]
    [InlineData("/mcp/wrong-secret")]
    [InlineData("/mcp/" + McpFactory.Secret + "x")]
    [InlineData("/mcp/" + McpFactory.Secret + "/mcp/" + McpFactory.Secret)]
    [InlineData("/MCP/WRONG")]
    public async Task Without_the_right_secret_the_endpoint_is_404(string path)
    {
        using var http = factory.CreateClient();

        var response = await http.PostAsync(path, Initialize(), Ct);

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task Path_case_does_not_matter_for_the_secret_check()
    {
        await using var client = await factory.McpClientAsync("/MCP/" + McpFactory.Secret);

        Assert.NotEmpty(await client.ListToolsAsync(cancellationToken: Ct));
    }

    [Fact]
    public async Task The_secret_never_reaches_the_log()
    {
        var (deckId, _) = await factory.CreateDeckAsync("L" + Guid.NewGuid().ToString("N")[..6], 1);
        await using (var client = await factory.McpClientAsync())
        {
            await CallAsync(client, "get_deck_yaml", new() { ["deckId"] = deckId });
        }

        using var http = factory.CreateClient();
        await http.PostAsync("/mcp/" + McpFactory.Secret[..^1], Initialize(), Ct);

        Assert.Contains(factory.Logs, l => l.Contains("MCP get_deck_yaml", StringComparison.Ordinal));
        Assert.DoesNotContain(factory.Logs, l => l.Contains(McpFactory.Secret[..20], StringComparison.Ordinal));
    }

    internal static StringContent Initialize() => new(
        """{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}""",
        Encoding.UTF8,
        "application/json");

    private static async Task<JsonNode> CallAsync(McpClient client, string tool, Dictionary<string, object?> args)
    {
        var result = await CallRawAsync(client, tool, args);
        Assert.True(result.IsError is not true, Text(result));
        return JsonNode.Parse(Text(result))!;
    }

    private static Task<CallToolResult> CallRawAsync(McpClient client, string tool, Dictionary<string, object?> args) =>
        client.CallToolAsync(tool, args, cancellationToken: Ct).AsTask();

    private static string Text(CallToolResult result) => string.Concat(result.Content.OfType<TextContentBlock>().Select(c => c.Text));

    private static (int New, int Changed, int Unchanged, int MissingKept) Counts(JsonNode body)
    {
        var c = body["counts"]!;
        return ((int)c["new"]!, (int)c["changed"]!, (int)c["unchanged"]!, (int)c["missingKept"]!);
    }
}

/// <summary>With <c>Mcp__Enabled</c> off (the default) nothing answers under /mcp.</summary>
public sealed class McpDisabledTests(QuizlyFactory factory) : IClassFixture<QuizlyFactory>
{
    [Fact]
    public async Task The_endpoint_is_404()
    {
        using var http = factory.CreateClient();

        var response = await http.PostAsync("/mcp/" + McpFactory.Secret, McpTests.Initialize(), TestContext.Current.CancellationToken);

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }
}

public sealed class McpRateLimitTests(McpTightLimitFactory factory) : IClassFixture<McpTightLimitFactory>
{
    [Fact]
    public async Task The_endpoint_is_rate_limited()
    {
        using var http = factory.CreateClient();
        var statuses = new List<HttpStatusCode>();
        for (var i = 0; i < 4; i++)
        {
            using var request = new HttpRequestMessage(HttpMethod.Post, "/mcp/" + McpFactory.Secret) { Content = McpTests.Initialize() };
            request.Headers.Accept.ParseAdd("application/json");
            request.Headers.Accept.ParseAdd("text/event-stream");
            statuses.Add((await http.SendAsync(request, TestContext.Current.CancellationToken)).StatusCode);
        }

        Assert.Equal([HttpStatusCode.OK, HttpStatusCode.OK, HttpStatusCode.OK, HttpStatusCode.TooManyRequests], statuses);
    }
}

public sealed class McpStartupTests(McpShortSecretFactory factory) : IClassFixture<McpShortSecretFactory>
{
    [Fact]
    public void Refuses_to_start_with_a_short_secret()
    {
        var error = Assert.ThrowsAny<Exception>(() => factory.CreateClient());

        Assert.Contains("Mcp__Secret must be at least 48", error.ToString(), StringComparison.Ordinal);
    }
}
