using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Quizly.Web.Api;

internal static class JsonSetup
{
    /// <summary>camelCase, snake_case enums (<c>last_call</c>), UTC instants with <c>Z</c>, strict input.</summary>
    public static void Configure(JsonSerializerOptions options)
    {
        options.Converters.Add(new JsonStringEnumConverter(JsonNamingPolicy.SnakeCaseLower, allowIntegerValues: false));
        options.Converters.Add(new UtcDateTimeOffsetConverter());
        options.NumberHandling = JsonNumberHandling.Strict;
        options.PropertyNameCaseInsensitive = false;
        options.AllowDuplicateProperties = false;
        options.RespectNullableAnnotations = true;
        options.RespectRequiredConstructorParameters = true;
    }

    /// <summary>Writes instants as ISO 8601 UTC with <c>Z</c> (docs/api.md §1).</summary>
    private sealed class UtcDateTimeOffsetConverter : JsonConverter<DateTimeOffset>
    {
        public override DateTimeOffset Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options) =>
            reader.GetDateTimeOffset();

        public override void Write(Utf8JsonWriter writer, DateTimeOffset value, JsonSerializerOptions options) =>
            writer.WriteStringValue(value.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss.FFFFFFF'Z'", CultureInfo.InvariantCulture));
    }
}
