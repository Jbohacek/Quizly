using Quizly.Application.Yaml;
using Quizly.Domain;

namespace Quizly.Tests.Unit;

/// <summary>docs/yaml-format.md: schema, errors with line numbers, export and round trip.</summary>
public sealed class DeckYamlTests
{
    private const string Example = """
        # Quizly balíček · formát v1
        deck:
          name: C# základy
          description: Základní pojmy jazyka C#
          color: "#BAD69B"
        cards:
          - id: 101
            question: Jaký je rozdíl mezi struct a class v C#?
            answer: struct je hodnotový typ, class je referenční typ.
          - id: "102"
            question: Co dělá klíčové slovo async?
            answer: |
              Označí metodu, ve které můžeš použít await.
              Metoda pak vrací Task.
          - question: Co je record v C#?          # no id = new card
            answer: Typ s hodnotovou rovností pro neměnná data.
        """;

    [Fact]
    public void Parses_the_documented_example()
    {
        var (deck, errors) = DeckYaml.Parse(Example);

        Assert.Empty(errors);
        Assert.Equal(("C# základy", "Základní pojmy jazyka C#", "#BAD69B"), (deck!.Name, deck.Description, deck.Color));
        Assert.Equal([101, 102, null], deck.Cards.Select(c => c.Id));
        Assert.Equal("Označí metodu, ve které můžeš použít await.\nMetoda pak vrací Task.", deck.Cards[1].Answer);
        Assert.Equal([7, 10, 15], deck.Cards.Select(c => c.Line));
    }

    [Fact]
    public void Scalars_keep_their_source_text()
    {
        var (deck, errors) = DeckYaml.Parse("deck:\n  name: Typy\ncards:\n  - question: 42\n    answer: yes\n  - question: '007'\n    answer: ~\n");

        Assert.Empty(errors);
        Assert.Equal([("42", "yes"), ("007", "~")], deck!.Cards.Select(c => (c.Question, c.Answer)));
        Assert.Null(deck.Color);
    }

    [Fact]
    public void Empty_card_list_is_allowed()
    {
        Assert.Empty(DeckYaml.Parse("deck:\n  name: Prázdný\ncards: []\n").Deck!.Cards);
        Assert.Empty(DeckYaml.Parse("deck:\n  name: Prázdný\ncards:\n").Deck!.Cards);
    }

    [Theory]
    [InlineData("deck:\n  name: A\n   bad: indentation\ncards: []\n", "syntax", 3)]
    [InlineData("deck:\n  name: A\ncards: []\n---\ndeck:\n  name: B\ncards: []\n", "syntax", 4)]
    [InlineData("- just\n- a list\n", "notMapping", 1)]
    [InlineData("cards: []\n", "missingKey", 1)]
    [InlineData("deck:\n  name: A\n", "missingKey", 1)]
    [InlineData("deck:\n  name: A\ncards: []\nextra: 1\n", "unknownKey", 4)]
    [InlineData("deck:\n  name: A\n  colour: red\ncards: []\n", "unknownKey", 3)]
    [InlineData("deck: hello\ncards: []\n", "wrongType", 1)]
    [InlineData("deck:\n  name: A\ncards: nope\n", "wrongType", 3)]
    [InlineData("deck:\n  name: A\ncards:\n  - question: q\n    anwser: a\n", "unknownKey", 5)]
    [InlineData("deck:\n  name: A\ncards:\n  - question: q\n", "missingKey", 4)]
    [InlineData("deck:\n  name: A\ncards:\n  - question: \"   \"\n    answer: a\n", "emptyText", 4)]
    [InlineData("deck:\n  name: A\ncards:\n  - question:\n      nested: map\n    answer: a\n", "wrongType", 5)]
    [InlineData("deck:\n  name: A\n  color: blue\ncards: []\n", "invalidColor", 3)]
    [InlineData("deck:\n  name: A\ncards:\n  - id: -3\n    question: q\n    answer: a\n", "invalidId", 4)]
    [InlineData("deck:\n  name: A\ncards:\n  - id: abc\n    question: q\n    answer: a\n", "invalidId", 4)]
    [InlineData("deck:\n  name: A\ncards:\n  - id: 5\n    question: q\n    answer: a\n  - id: 5\n    question: r\n    answer: b\n", "duplicateId", 7)]
    [InlineData("deck:\n  name: &n A\ncards: []\n", "aliasNotAllowed", 2)]
    [InlineData("deck:\n  name: !!str A\ncards: []\n", "aliasNotAllowed", 2)]
    [InlineData("deck:\n  name: A\n  name: B\ncards: []\n", "syntax", 3)]
    public void Errors_have_codes_and_lines(string yaml, string code, int line)
    {
        var (deck, errors) = DeckYaml.Parse(yaml);

        Assert.Null(deck);
        var error = Assert.Single(errors, e => e.Code == code);
        Assert.Equal(line, error.Line);
        Assert.False(string.IsNullOrWhiteSpace(error.Message));
    }

    [Fact]
    public void Duplicate_id_names_the_other_line()
    {
        var (_, errors) = DeckYaml.Parse("deck:\n  name: A\ncards:\n  - id: 5\n    question: q\n    answer: a\n  - id: 5\n    question: r\n    answer: b\n");

        Assert.Contains("také na řádku 4", errors.Single().Message, StringComparison.Ordinal);
    }

    [Fact]
    public void All_errors_are_reported_at_once()
    {
        var (_, errors) = DeckYaml.Parse("deck:\n  name: A\n  color: x\ncards:\n  - id: 0\n    question: q\n  - question: q\n    answer: a\n    hint: h\n");

        Assert.Equal(["invalidColor", "invalidId", "missingKey", "unknownKey"], errors.Select(e => e.Code).Order());
    }

    [Fact]
    public void Text_over_the_limit_is_too_long()
    {
        var yaml = $"deck:\n  name: A\ncards:\n  - question: {new string('x', 501)}\n    answer: a\n";

        var (_, errors) = DeckYaml.Parse(yaml);

        Assert.Equal("tooLong", Assert.Single(errors).Code);
    }

    [Fact]
    public void Files_over_one_megabyte_are_rejected()
    {
        var (_, errors) = DeckYaml.Parse(new string('#', DeckYaml.MaxBytes + 1));

        Assert.Equal("fileTooLarge", Assert.Single(errors).Code);
    }

    [Fact]
    public void Export_matches_the_documented_layout()
    {
        var deck = new Deck { Name = "C# základy", Description = "Základní pojmy jazyka C#", Color = "#BAD69B" };
        Card[] cards =
        [
            new() { Id = 101, Question = "Jaký je rozdíl mezi struct a class v C#?", Answer = "struct je hodnotový typ, class je referenční typ." },
            new() { Id = 102, Question = "Co dělá klíčové slovo async?", Answer = "Označí metodu, ve které můžeš použít await.\nMetoda pak vrací Task." },
        ];

        var yaml = DeckYaml.Write(deck, cards);

        Assert.Equal(
            """
            # Quizly balíček · formát v1
            deck:
              name: C# základy
              description: Základní pojmy jazyka C#
              color: "#BAD69B"
            cards:
              - id: 101
                question: Jaký je rozdíl mezi struct a class v C#?
                answer: struct je hodnotový typ, class je referenční typ.
              - id: 102
                question: Co dělá klíčové slovo async?
                answer: |-
                  Označí metodu, ve které můžeš použít await.
                  Metoda pak vrací Task.

            """.Replace("\r\n", "\n", StringComparison.Ordinal),
            yaml);
    }

    [Theory]
    [InlineData("Otázka: s dvojtečkou")]
    [InlineData("- začíná pomlčkou")]
    [InlineData("končí dvojtečkou:")]
    [InlineData("text # s mřížkou")]
    [InlineData("\"v uvozovkách\" a 'apostrofy'")]
    [InlineData("yes")]
    [InlineData("42")]
    [InlineData("3.14")]
    [InlineData("null")]
    [InlineData("~")]
    [InlineData("@zavináč a `backtick`")]
    [InlineData("[hranaté] {složené}")]
    [InlineData("emoji 🎉 a ŽLUŤOUČKÝ kůň")]
    [InlineData("tab\tuvnitř")]
    [InlineData("zpětné \\ lomítko")]
    [InlineData("řádek 1\n  odsazený řádek 2\n\nřádek 4 po prázdném")]
    [InlineData("řádek: s dvojtečkou\n- a pomlčkou")]
    [InlineData("*kurzíva* na začátku")]
    [InlineData("**tučně** a <small>malé</small>")]
    [InlineData("Typy:\n- **struct**\n- *class*\n1. první\n2. druhý")]
    [InlineData("&kotva *hvězdička")]
    public void Export_round_trips_tricky_text(string text)
    {
        var deck = new Deck { Name = text.Split('\n')[0], Description = "", Color = "#8FC7F0" };
        var cards = new[] { new Card { Id = 7, Question = text, Answer = text } };

        var (parsed, errors) = DeckYaml.Parse(DeckYaml.Write(deck, cards));

        Assert.Empty(errors);
        Assert.Equal((deck.Name, "", "#8FC7F0"), (parsed!.Name, parsed.Description, parsed.Color));
        Assert.Equal((7, text, text), (parsed.Cards[0].Id!.Value, parsed.Cards[0].Question, parsed.Cards[0].Answer));
    }

    [Fact]
    public void Export_of_an_empty_deck_parses()
    {
        var yaml = DeckYaml.Write(new Deck { Name = "Prázdný", Color = "#BAD69B" }, []);

        Assert.Contains("cards: []", yaml, StringComparison.Ordinal);
        Assert.Empty(DeckYaml.Parse(yaml).Errors);
    }

    [Fact]
    public void Hash_changes_with_content()
    {
        var a = DeckYaml.Hash(DeckYaml.Write(new Deck { Name = "A", Color = "#BAD69B" }, []));
        var b = DeckYaml.Hash(DeckYaml.Write(new Deck { Name = "B", Color = "#BAD69B" }, []));

        Assert.NotEqual(a, b);
        Assert.Equal(64, a.Length);
    }
}
