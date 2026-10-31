using System.Text.Json.Serialization;

namespace Quizly.Application.Yaml;

/// <summary>YAML to preview or import.</summary>
public sealed record YamlRequest(string Yaml);

/// <summary>YAML to apply, the base it was previewed against, and the cards whose deletion was confirmed.</summary>
public sealed record YamlApplyRequest(string Yaml, string BaseHash, IReadOnlyList<int>? ConfirmDeleteIds = null);

/// <summary>Which deck fields the file changes.</summary>
public sealed record YamlDeckChanges(bool NameChanged, bool DescriptionChanged, bool ColorChanged);

/// <summary>How many cards are new, changed, deleted or unchanged.</summary>
public sealed record YamlCounts(int New, int Changed, int Deleted, int Unchanged);

/// <summary>A card without an id: it will be created.</summary>
public sealed record YamlNewCard(int Line, string Question);

/// <summary>Question/answer text on one side of a change; unchanged fields are left out.</summary>
public sealed record YamlCardText(
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? Question = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? Answer = null);

/// <summary>An existing card whose text changes; users' progress is kept.</summary>
public sealed record YamlChangedCard(int Id, int Line, string Question, IReadOnlyList<string> Fields, YamlCardText Before, YamlCardText After);

/// <summary>An existing card missing from the file: it will be deleted with all users' progress.</summary>
public sealed record YamlDeletedCard(int Id, string Question, int UsersWithProgress);

/// <summary>The dry run of an import (docs/yaml-format.md §5). Nothing is written.</summary>
public sealed record YamlPreviewResponse(
    bool Valid,
    string? BaseHash,
    YamlDeckChanges? Deck,
    YamlCounts Counts,
    bool OrderChanged,
    IReadOnlyList<YamlNewCard> New,
    IReadOnlyList<YamlChangedCard> Changed,
    IReadOnlyList<YamlDeletedCard> Deleted,
    IReadOnlyList<YamlIssue> Errors);

/// <summary>What was applied, and the deck's new export.</summary>
public sealed record YamlApplyResponse(YamlCounts Counts, string Yaml);
