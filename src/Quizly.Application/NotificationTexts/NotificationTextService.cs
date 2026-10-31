using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.EntityFrameworkCore;
using Quizly.Application.Abstractions;
using Quizly.Application.Common;
using Quizly.Domain;

namespace Quizly.Application.NotificationTexts;

public interface INotificationTextService
{
    Task<IReadOnlyList<NotificationTextResponse>> ListAsync(NotificationCategory? category, CancellationToken ct);

    Task<Result<NotificationTextResponse>> GetAsync(int id, CancellationToken ct);

    Task<Result<NotificationTextResponse>> CreateAsync(NotificationTextRequest request, CancellationToken ct);

    Task<Result<NotificationTextResponse>> UpdateAsync(int id, NotificationTextRequest request, CancellationToken ct);

    Task<Result> DeleteAsync(int id, CancellationToken ct);

    Result<NotificationPreviewResponse> Preview(NotificationPreviewRequest request);

    Task<AppNotificationTextsResponse> GetActiveAsync(CancellationToken ct);
}

internal sealed partial class NotificationTextService(IAppDbContext db, TimeProvider time) : INotificationTextService
{
    /// <summary>Sample values for the admin preview (docs/api.md §13).</summary>
    internal static readonly IReadOnlyDictionary<string, string> SampleValues = new Dictionary<string, string>
    {
        ["due"] = "23",
        ["left"] = "7",
        ["done"] = "13",
        ["goal"] = "20",
        ["streak"] = "14",
        ["multiplier"] = "1,2×",
        ["item"] = "Jít na pizzu",
        ["points"] = "1 457",
    };

    public async Task<IReadOnlyList<NotificationTextResponse>> ListAsync(NotificationCategory? category, CancellationToken ct)
    {
        var query = db.NotificationTexts.AsQueryable();
        if (category is not null)
        {
            query = query.Where(t => t.Category == category);
        }

        var texts = await query.OrderBy(t => t.Category).ThenBy(t => t.Id).ToListAsync(ct);
        return texts.Select(ToResponse).ToList();
    }

    public async Task<Result<NotificationTextResponse>> GetAsync(int id, CancellationToken ct)
    {
        var text = await db.NotificationTexts.FirstOrDefaultAsync(t => t.Id == id, ct);
        return text is null ? TextNotFound : ToResponse(text);
    }

    public async Task<Result<NotificationTextResponse>> CreateAsync(NotificationTextRequest request, CancellationToken ct)
    {
        var text = Validator.Clean(request.Text);
        var v = Validate(request.Category, text);
        if (!v.IsValid)
        {
            return v.ToError();
        }

        var now = time.GetUtcNow().UtcDateTime;
        var entity = new NotificationText
        {
            Category = request.Category,
            Text = text,
            IsActive = request.IsActive,
            CreatedAt = now,
            UpdatedAt = now,
        };
        db.NotificationTexts.Add(entity);
        await db.SaveChangesAsync(ct);
        return ToResponse(entity);
    }

    public async Task<Result<NotificationTextResponse>> UpdateAsync(int id, NotificationTextRequest request, CancellationToken ct)
    {
        var entity = await db.NotificationTexts.FirstOrDefaultAsync(t => t.Id == id, ct);
        if (entity is null)
        {
            return TextNotFound;
        }

        var text = Validator.Clean(request.Text);
        var v = Validate(request.Category, text);
        if (!v.IsValid)
        {
            return v.ToError();
        }

        entity.Category = request.Category;
        entity.Text = text;
        entity.IsActive = request.IsActive;
        entity.UpdatedAt = time.GetUtcNow().UtcDateTime;
        await db.SaveChangesAsync(ct);
        return ToResponse(entity);
    }

    public async Task<Result> DeleteAsync(int id, CancellationToken ct)
    {
        var deleted = await db.NotificationTexts.Where(t => t.Id == id).ExecuteDeleteAsync(ct);
        return deleted == 0 ? TextNotFound : Result.Ok();
    }

    public Result<NotificationPreviewResponse> Preview(NotificationPreviewRequest request)
    {
        var text = Validator.Clean(request.Text);
        var v = new Validator();
        ValidateText(v, text);
        if (!v.IsValid)
        {
            return v.ToError();
        }

        var rendered = PlaceholderRegex().Replace(text, m => SampleValues[m.Groups[1].Value]);
        return new NotificationPreviewResponse(rendered);
    }

    public async Task<AppNotificationTextsResponse> GetActiveAsync(CancellationToken ct)
    {
        var texts = await db.NotificationTexts
            .Where(t => t.IsActive)
            .OrderBy(t => t.Category).ThenBy(t => t.Id)
            .ToListAsync(ct);

        var categories = Enum.GetValues<NotificationCategory>().ToDictionary(
            CategoryName,
            c => (IReadOnlyList<AppNotificationText>)texts
                .Where(t => t.Category == c)
                .Select(t => new AppNotificationText(t.Id, t.Text))
                .ToList());

        return new AppNotificationTextsResponse(VersionOf(texts), categories);
    }

    /// <summary>Category as it appears in JSON (<c>last_call</c>).</summary>
    internal static string CategoryName(NotificationCategory category) =>
        JsonNamingPolicy.SnakeCaseLower.ConvertName(category.ToString());

    /// <summary>Placeholder rules from docs/spec.md §8.</summary>
    internal static void ValidateText(Validator v, string text)
    {
        v.Text("text", text, "Text", Limits.NotificationTextMax);

        foreach (Match match in PlaceholderRegex().Matches(text))
        {
            var name = match.Groups[1].Value;
            if (!Limits.Placeholders.Contains(name))
            {
                v.Add("text", $"Neznámý zástupný symbol {{{name}}}.");
            }
        }

        // Every brace must belong to a {name} placeholder.
        var withoutPlaceholders = PlaceholderRegex().Replace(text, "");
        if (withoutPlaceholders.Contains('{') || withoutPlaceholders.Contains('}'))
        {
            v.Add("text", "Složené závorky nejsou spárované.");
        }
    }

    private static Validator Validate(NotificationCategory category, string text)
    {
        var v = new Validator();
        if (!Enum.IsDefined(category))
        {
            v.Add("category", "Neznámá kategorie.");
        }

        ValidateText(v, text);
        return v;
    }

    private static string VersionOf(IEnumerable<NotificationText> texts)
    {
        var builder = new StringBuilder();
        foreach (var t in texts)
        {
            builder.Append(t.Id).Append('|').Append((int)t.Category).Append('|').Append(t.Text).Append('\n');
        }

        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(builder.ToString()));
        return Convert.ToHexStringLower(hash)[..16];
    }

    private static AppError TextNotFound => Errors.NotFound("Text upozornění neexistuje.");

    private static NotificationTextResponse ToResponse(NotificationText t) =>
        new(t.Id, t.Category, t.Text, t.IsActive, t.CreatedAt.ToUtcOffset(), t.UpdatedAt.ToUtcOffset());

    [GeneratedRegex(@"\{(\w+)\}")]
    private static partial Regex PlaceholderRegex();
}
