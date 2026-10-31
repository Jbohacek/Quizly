using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using Quizly.Application.Common;
using Quizly.Domain;
using YamlDotNet.Core;
using YamlDotNet.Core.Events;
using YamlDotNet.RepresentationModel;

namespace Quizly.Application.Yaml;

/// <summary>A validation error with a 1-based line (docs/yaml-format.md §6).</summary>
public sealed record YamlIssue(string Code, string Message, int? Line = null, int? Column = null);

/// <summary>A card as written in the file; <see cref="Line"/> is where its item starts.</summary>
public sealed record ParsedCard(int? Id, string Question, string Answer, int Line);

/// <summary>A syntactically valid deck file. <see cref="Color"/> is null when the key is missing.</summary>
public sealed record ParsedDeck(string Name, string Description, string? Color, IReadOnlyList<ParsedCard> Cards);

/// <summary>Deck YAML v1: pure parsing, validation and export (docs/yaml-format.md). Database checks live in <see cref="YamlDeckService"/>.</summary>
public static partial class DeckYaml
{
    public const int MaxBytes = 1_000_000;
    public const int MaxCards = 2_000;
    public const string Header = "# Quizly balíček · formát v1";

    private static readonly string[] RootKeys = ["deck", "cards"];
    private static readonly string[] DeckKeys = ["name", "description", "color"];
    private static readonly string[] CardKeys = ["id", "question", "answer"];

    public static (ParsedDeck? Deck, IReadOnlyList<YamlIssue> Errors) Parse(string? yaml)
    {
        yaml ??= "";
        var errors = new List<YamlIssue>();
        if (Encoding.UTF8.GetByteCount(yaml) > MaxBytes)
        {
            errors.Add(new YamlIssue("fileTooLarge", "Soubor je větší než 1 MB."));
            return (null, errors);
        }

        if (!CheckEvents(yaml, errors))
        {
            return (null, errors);
        }

        var stream = new YamlStream();
        try
        {
            stream.Load(new StringReader(yaml));
        }
        catch (YamlException e)
        {
            // e.g. a duplicate key, which the event scan doesn't see
            var detail = Detail(e.InnerException?.Message ?? e.Message);
            errors.Add(new YamlIssue("syntax", $"Neplatný YAML: {detail} (řádek {Line(e.Start)})", Line(e.Start), Column(e.Start)));
            return (null, errors);
        }
        if (stream.Documents.Count == 0 || stream.Documents[0].RootNode is not YamlMappingNode root)
        {
            errors.Add(new YamlIssue("notMapping", "Kořen souboru musí obsahovat klíče „deck“ a „cards“.", 1));
            return (null, errors);
        }

        var rootEntries = Entries(root, RootKeys, errors);
        var deck = ParseDeck(root, rootEntries, errors);
        var cards = ParseCards(root, rootEntries, errors);
        return errors.Count > 0 || deck is null || cards is null
            ? (null, errors)
            : (deck with { Cards = cards }, errors);
    }

    /// <summary>The export: header, deck, then every card with its id in sort order (docs/yaml-format.md §3).</summary>
    public static string Write(Deck deck, IEnumerable<Card> cards)
    {
        var b = new StringBuilder();
        b.Append(Header).Append('\n');
        b.Append("deck:\n");
        b.Append("  name: ").Append(Scalar(deck.Name)).Append('\n');
        b.Append("  description: ").Append(Scalar(deck.Description)).Append('\n');
        b.Append("  color: ").Append(Quoted(deck.Color)).Append('\n');

        var list = cards.ToList();
        if (list.Count == 0)
        {
            b.Append("cards: []\n");
            return b.ToString();
        }

        b.Append("cards:\n");
        foreach (var card in list)
        {
            b.Append("  - id: ").Append(card.Id.ToString(CultureInfo.InvariantCulture)).Append('\n');
            AppendText(b, "question", card.Question);
            AppendText(b, "answer", card.Answer);
        }

        return b.ToString();
    }

    /// <summary>SHA-256 of the export, used to detect changes between preview and apply.</summary>
    public static string Hash(string export) =>
        Convert.ToHexStringLower(System.Security.Cryptography.SHA256.HashData(Encoding.UTF8.GetBytes(export)));

    private static void AppendText(StringBuilder b, string key, string value)
    {
        b.Append("    ").Append(key).Append(':');
        if (!value.Contains('\n', StringComparison.Ordinal))
        {
            b.Append(' ').Append(Scalar(value)).Append('\n');
            return;
        }

        // Literal block; "-" drops the final newline (the importer trims anyway).
        b.Append(" |-\n");
        foreach (var line in value.Split('\n'))
        {
            b.Append(line.Length == 0 ? "" : "      " + line).Append('\n');
        }
    }

    /// <summary>A plain scalar when that is unambiguous, else double-quoted.</summary>
    private static string Scalar(string value) => IsSafePlain(value) ? value : Quoted(value);

    private static bool IsSafePlain(string value) =>
        value.Length > 0
        && !char.IsWhiteSpace(value[0]) && !char.IsWhiteSpace(value[^1])
        && "-?:,[]{}#&*!|>'\"%@`".IndexOf(value[0], StringComparison.Ordinal) < 0
        && !value.Contains(": ", StringComparison.Ordinal) && !value.Contains(" #", StringComparison.Ordinal)
        && !value.EndsWith(':')
        && !value.Any(char.IsControl)
        && !LooksTyped().IsMatch(value);

    private static string Quoted(string value)
    {
        var b = new StringBuilder("\"");
        foreach (var c in value)
        {
            b.Append(c switch
            {
                '"' => "\\\"",
                '\\' => "\\\\",
                '\n' => "\\n",
                '\t' => "\\t",
                _ when char.IsControl(c) => $"\\u{(int)c:X4}",
                _ => c.ToString(),
            });
        }

        return b.Append('"').ToString();
    }

    /// <summary>Syntax, single document, no anchors/aliases/tags. Returns false when parsing can't continue.</summary>
    private static bool CheckEvents(string yaml, List<YamlIssue> errors)
    {
        var parser = new Parser(new StringReader(yaml));
        var documents = 0;
        try
        {
            while (parser.MoveNext())
            {
                switch (parser.Current)
                {
                    case DocumentStart:
                        documents++;
                        if (documents > 1)
                        {
                            errors.Add(new YamlIssue("syntax", "Neplatný YAML: soubor smí obsahovat jen jeden dokument.", Line(parser.Current.Start)));
                            return false;
                        }

                        break;
                    case AnchorAlias alias:
                        errors.Add(new YamlIssue("aliasNotAllowed", "Kotvy, aliasy a tagy nejsou povolené.", Line(alias.Start), Column(alias.Start)));
                        break;
                    case NodeEvent node when !node.Anchor.IsEmpty || !node.Tag.IsEmpty:
                        errors.Add(new YamlIssue("aliasNotAllowed", "Kotvy, aliasy a tagy nejsou povolené.", Line(node.Start), Column(node.Start)));
                        break;
                }
            }
        }
        catch (YamlException e)
        {
            var detail = e.InnerException?.Message ?? e.Message;
            errors.Add(new YamlIssue("syntax", $"Neplatný YAML: {Detail(detail)} (řádek {Line(e.Start)})", Line(e.Start), Column(e.Start)));
            return false;
        }

        return errors.Count == 0;
    }

    private static Dictionary<string, (YamlScalarNode Key, YamlNode Value)> Entries(
        YamlMappingNode mapping, string[] allowed, List<YamlIssue> errors)
    {
        var entries = new Dictionary<string, (YamlScalarNode, YamlNode)>(StringComparer.Ordinal);
        foreach (var (keyNode, value) in mapping.Children)
        {
            if (keyNode is not YamlScalarNode key || key.Value is null || !allowed.Contains(key.Value))
            {
                var name = (keyNode as YamlScalarNode)?.Value ?? "?";
                errors.Add(new YamlIssue("unknownKey", $"Neznámý klíč „{name}“.", Line(keyNode.Start), Column(keyNode.Start)));
                continue;
            }

            entries[key.Value] = (key, value);
        }

        return entries;
    }

    private static ParsedDeck? ParseDeck(YamlMappingNode root, Dictionary<string, (YamlScalarNode Key, YamlNode Value)> entries, List<YamlIssue> errors)
    {
        if (!entries.TryGetValue("deck", out var deckEntry))
        {
            errors.Add(new YamlIssue("missingKey", "Chybí povinný klíč „deck“.", Line(root.Start)));
            return null;
        }

        if (deckEntry.Value is not YamlMappingNode deck)
        {
            errors.Add(WrongType("deck", "mapování (klíč: hodnota)", deckEntry.Value));
            return null;
        }

        var fields = Entries(deck, DeckKeys, errors);
        var name = Text(fields, "name", deck, Limits.DeckNameMax, required: true, errors);
        var description = Text(fields, "description", deck, Limits.DeckDescriptionMax, required: false, errors) ?? "";
        string? color = null;
        if (fields.TryGetValue("color", out var colorEntry))
        {
            color = (colorEntry.Value as YamlScalarNode)?.Value?.Trim().ToUpperInvariant();
            if (color is null || !ColorRegex().IsMatch(color))
            {
                errors.Add(new YamlIssue("invalidColor", "Barva musí být ve tvaru #RRGGBB.", Line(colorEntry.Value.Start), Column(colorEntry.Value.Start)));
            }
        }

        return name is null ? null : new ParsedDeck(name, description, color, []);
    }

    private static List<ParsedCard>? ParseCards(YamlMappingNode root, Dictionary<string, (YamlScalarNode Key, YamlNode Value)> entries, List<YamlIssue> errors)
    {
        if (!entries.TryGetValue("cards", out var cardsEntry))
        {
            errors.Add(new YamlIssue("missingKey", "Chybí povinný klíč „cards“.", Line(root.Start)));
            return null;
        }

        if (cardsEntry.Value is YamlScalarNode { Value: null or "" })
        {
            return []; // "cards:" with nothing after it
        }

        if (cardsEntry.Value is not YamlSequenceNode sequence)
        {
            errors.Add(WrongType("cards", "seznam", cardsEntry.Value));
            return null;
        }

        if (sequence.Children.Count > MaxCards)
        {
            errors.Add(new YamlIssue("tooManyCards", "Balíček může mít nejvýš 2 000 karet.", Line(sequence.Start)));
            return null;
        }

        var cards = new List<ParsedCard>();
        var idLines = new Dictionary<int, int>();
        foreach (var item in sequence.Children)
        {
            if (item is not YamlMappingNode card)
            {
                errors.Add(WrongType("cards[]", "mapování (id, question, answer)", item));
                continue;
            }

            var fields = Entries(card, CardKeys, errors);
            int? id = null;
            if (fields.TryGetValue("id", out var idEntry))
            {
                var raw = (idEntry.Value as YamlScalarNode)?.Value;
                if (int.TryParse(raw, NumberStyles.None, CultureInfo.InvariantCulture, out var parsed) && parsed > 0)
                {
                    id = parsed;
                    if (idLines.TryGetValue(parsed, out var otherLine))
                    {
                        errors.Add(new YamlIssue("duplicateId", $"Karta s id {parsed} je v souboru víckrát (také na řádku {otherLine}).", Line(idEntry.Value.Start), Column(idEntry.Value.Start)));
                    }
                    else
                    {
                        idLines[parsed] = Line(idEntry.Value.Start);
                    }
                }
                else
                {
                    errors.Add(new YamlIssue("invalidId", "„id“ musí být kladné celé číslo.", Line(idEntry.Value.Start), Column(idEntry.Value.Start)));
                }
            }

            var question = Text(fields, "question", card, Limits.QuestionMax, required: true, errors);
            var answer = Text(fields, "answer", card, Limits.AnswerMax, required: true, errors);
            if (question is not null && answer is not null)
            {
                cards.Add(new ParsedCard(id, question, answer, Line(card.Start)));
            }
        }

        return cards;
    }

    /// <summary>A text field: trimmed, \n line endings, within the length limit.</summary>
    private static string? Text(
        Dictionary<string, (YamlScalarNode Key, YamlNode Value)> fields, string key, YamlNode parent, int max, bool required, List<YamlIssue> errors)
    {
        if (!fields.TryGetValue(key, out var entry))
        {
            if (required)
            {
                errors.Add(new YamlIssue("missingKey", $"Chybí povinný klíč „{key}“.", Line(parent.Start), Column(parent.Start)));
            }

            return null;
        }

        if (entry.Value is not YamlScalarNode scalar)
        {
            errors.Add(WrongType(key, "text", entry.Value));
            return null;
        }

        var text = Validator.Clean(scalar.Value);
        if (text.Length == 0 && required)
        {
            errors.Add(new YamlIssue("emptyText", $"„{key}“ nesmí být prázdné.", Line(entry.Key.Start), Column(entry.Key.Start)));
            return null;
        }

        if (text.Length > max)
        {
            errors.Add(new YamlIssue("tooLong", $"„{key}“ má {text.Length} znaků, maximum je {max}.", Line(entry.Key.Start), Column(entry.Key.Start)));
            return null;
        }

        return text;
    }

    private static YamlIssue WrongType(string key, string type, YamlNode node) =>
        new("wrongType", $"„{key}“ musí být {type}.", Line(node.Start), Column(node.Start));

    private static int Line(Mark mark) => (int)mark.Line;

    private static int Column(Mark mark) => (int)mark.Column;

    /// <summary>YamlDotNet messages start with "(Line: 3, Col: 5, …): "; the line is reported separately.</summary>
    private static string Detail(string message) => LocationPrefix().Replace(message, "").Trim();

    [GeneratedRegex(@"^\(Line: \d+, Col: \d+, Idx: \d+\) - \(Line: \d+, Col: \d+, Idx: \d+\):\s*")]
    private static partial Regex LocationPrefix();

    [GeneratedRegex("^#[0-9A-F]{6}$")]
    private static partial Regex ColorRegex();

    /// <summary>Values other YAML tools would read as numbers, booleans or null get quoted on export.</summary>
    [GeneratedRegex(@"^([-+]?(\d[\d_]*(\.\d*)?|\.\d+)([eE][-+]?\d+)?|0x[0-9a-fA-F]+|0o[0-7]+|\.inf|\.nan|true|false|yes|no|on|off|y|n|null|~)$", RegexOptions.IgnoreCase)]
    private static partial Regex LooksTyped();
}
