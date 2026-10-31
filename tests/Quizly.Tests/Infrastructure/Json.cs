using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;

namespace Quizly.Tests.Infrastructure;

public static class Json
{
    public static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.SnakeCaseLower) },
    };

    public static async Task<T> ReadAsync<T>(this HttpResponseMessage response) =>
        (await response.Content.ReadFromJsonAsync<T>(Options))!;

    public static async Task<JsonNode> ReadNodeAsync(this HttpResponseMessage response) =>
        JsonNode.Parse(await response.Content.ReadAsStringAsync())!;

    /// <summary>Asserts a ProblemDetails response with the given status and code (docs/api.md §1.1).</summary>
    public static async Task<JsonNode> AssertProblemAsync(this HttpResponseMessage response, HttpStatusCode status, string code)
    {
        var body = await response.Content.ReadAsStringAsync();
        Assert.True(response.StatusCode == status, $"Expected {(int)status}, got {(int)response.StatusCode}: {body}");
        Assert.Equal("application/problem+json", response.Content.Headers.ContentType?.MediaType);
        var problem = JsonNode.Parse(body)!;
        Assert.Equal(code, (string?)problem["code"]);
        Assert.StartsWith("https://quizly.jbohacek.cz/problems/", (string?)problem["type"], StringComparison.Ordinal);
        Assert.False(string.IsNullOrEmpty((string?)problem["title"]));
        Assert.False(string.IsNullOrEmpty((string?)problem["traceId"]));
        return problem;
    }
}
