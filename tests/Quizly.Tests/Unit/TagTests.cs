using Quizly.Application.Yaml;
using Quizly.Domain;

namespace Quizly.Tests.Unit;

/// <summary>Tag names and tags in deck YAML (#29, docs/spec.md §2.5, docs/yaml-format.md §2).</summary>
public sealed class TagTests
{
    [Fact]
    public void Names_are_trimmed_lowercased_distinct_and_sorted()
    {
        var (names, invalid, tooMany) = TagNames.Normalize([" Prednaska_01", "ai_gen", "AI_GEN", "", "přednáška-2", null]);

        Assert.Equal(["ai_gen", "prednaska_01", "přednáška-2"], names);
        Assert.Empty(invalid);
        Assert.False(tooMany);
    }

    [Theory]
    [InlineData("dvě slova")]
    [InlineData("tag#1")]
    [InlineData("a.b")]
    [InlineData("1234567890123456789012345678901")]
    public void Invalid_names_are_reported(string name)
    {
        var (_, invalid, _) = TagNames.Normalize([name, "ok"]);

        Assert.Equal([name.ToLowerInvariant()], invalid);
    }

    [Fact]
    public void At_most_ten_tags_per_card()
    {
        Assert.False(TagNames.Normalize(Enumerable.Range(1, 10).Select(i => $"t{i}")).TooMany);
        Assert.True(TagNames.Normalize(Enumerable.Range(1, 11).Select(i => $"t{i}")).TooMany);
    }

    [Fact]
    public void Typed_text_splits_at_semicolons_commas_and_spaces()
    {
        Assert.Equal(["ai_gen", "prednaska_01", "x", "y"], TagNames.Split(" ai_gen ; prednaska_01,x  y;"));
        Assert.Empty(TagNames.Split(null));
    }

    [Fact]
    public void Yaml_tags_are_a_list_or_one_text()
    {
        var (deck, errors) = DeckYaml.Parse("""
            deck:
              name: T
            cards:
              - question: Q1
                answer: A1
                tags: [Prednaska_01, ai_gen]
              - question: Q2
                answer: A2
                tags: ai_gen ; prednaska_01
              - question: Q3
                answer: A3
                tags:
                  - x
              - question: Q4
                answer: A4
            """);

        Assert.Empty(errors);
        Assert.Equal(["ai_gen", "prednaska_01"], deck!.Cards[0].Tags);
        Assert.Equal(["ai_gen", "prednaska_01"], deck.Cards[1].Tags);
        Assert.Equal(["x"], deck.Cards[2].Tags);
        Assert.Empty(deck.Cards[3].Tags);
    }

    [Fact]
    public void Yaml_tag_errors_have_line_numbers()
    {
        var eleven = string.Join(", ", Enumerable.Range(1, 11).Select(i => $"t{i}"));
        var (deck, errors) = DeckYaml.Parse($"""
            deck:
              name: T
            cards:
              - question: Q1
                answer: A1
                tags: [ok, "dvě slova"]
              - question: Q2
                answer: A2
                tags: [{eleven}]
              - question: Q3
                answer: A3
                tags: {"{"}a: b{"}"}
            """);

        Assert.Null(deck);
        Assert.Equal([("invalidTag", 6), ("tooManyTags", 9), ("wrongType", 12)], errors.Select(e => (e.Code, e.Line ?? 0)));
        Assert.Contains("„dvě slova“", errors[0].Message, StringComparison.Ordinal);
    }

    [Fact]
    public void Export_writes_sorted_tags_and_round_trips()
    {
        var deck = new Deck { Name = "T", Color = "#BAD69B" };
        Card[] cards =
        [
            new() { Id = 1, Question = "Q1", Answer = "A1", Tags = [new() { Name = "prednaska_01" }, new() { Name = "ai_gen" }] },
            new() { Id = 2, Question = "Q2", Answer = "A2" },
            new() { Id = 3, Question = "Q3", Answer = "A3", Tags = [new() { Name = "-x" }, new() { Name = "123" }] },
        ];

        var yaml = DeckYaml.Write(deck, cards);
        var (parsed, errors) = DeckYaml.Parse(yaml);

        Assert.Contains("    answer: A1\n    tags: [ai_gen, prednaska_01]\n  - id: 2\n    question: Q2\n    answer: A2\n  - id: 3", yaml, StringComparison.Ordinal);
        Assert.Contains("tags: [\"-x\", \"123\"]", yaml, StringComparison.Ordinal);
        Assert.Empty(errors);
        Assert.Equal([["ai_gen", "prednaska_01"], [], ["-x", "123"]], parsed!.Cards.Select(c => c.Tags.ToArray()));
    }
}
