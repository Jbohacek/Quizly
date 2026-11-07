namespace Quizly.Infrastructure.Seed;

/// <summary>A deck for the development data (#44). <see cref="Tags"/> are space-separated per card.</summary>
internal sealed record DemoDeck(
    string Name,
    string Description,
    string Color,
    bool ForEveryone,
    bool Archived,
    IReadOnlyList<DemoCard> Cards);

internal sealed record DemoCard(string Question, string Answer, string Tags = "");

/// <summary>The decks of the development data: small, in Czech, with tags and light formatting.</summary>
internal static class DemoDecks
{
    public const string RestrictedDeckName = "Anatomie";
    public const string ArchivedDeckName = "Starý balíček";

    public static IReadOnlyList<DemoDeck> All { get; } =
    [
        new("C# základy", "Základní pojmy jazyka C#", "#BAD69B", true, false,
        [
            new("Jaký je rozdíl mezi struct a class v C#?", "**struct** je hodnotový typ, **class** je referenční typ.", "csharp prednaska_01"),
            new("Co dělá klíčové slovo async?", "Označí metodu, ve které můžeš použít await.\nMetoda pak vrací Task.", "csharp prednaska_01"),
            new("Co je record v C#?", "Typ s hodnotovou rovností pro neměnná data.", "csharp ai_gen"),
            new("K čemu slouží using deklarace?", "Zavolá Dispose na konci bloku, i když nastane výjimka.", "csharp prednaska_01"),
            new("Co vrací LINQ metoda Where?", "Líně vyhodnocovanou sekvenci prvků, které splňují podmínku.", "csharp linq"),
            new("Co jsou nullable reference types?", "Anotace, která kompilátoru říká, jestli reference smí být null.\n<small>Zapíná se v projektu pomocí Nullable.</small>", "csharp ai_gen"),
            new("Jaký je rozdíl mezi == a Equals u referenčních typů?", "== porovnává odkazy, pokud typ operátor nepřetíží (string ho přetěžuje). Equals porovnává podle toho, jak ho typ přepíše.", "csharp prednaska_02"),
            new("Co dělá yield return?", "Vrátí další prvek sekvence a pozastaví metodu. Vzniká líný iterátor bez vlastní kolekce.", "csharp linq prednaska_02"),
            new("Co je dependency injection?", "Třída dostane své závislosti zvenčí (nejčastěji v konstruktoru), místo aby je vytvářela sama. Usnadňuje testování.", "csharp prednaska_02"),
            new("Čím se liší pole a List<T>?", "- pole má pevnou délku\n- List<T> umí růst i zmenšovat se\n- obojí zná přístup přes index", "csharp"),
            new("Co je Span<T>?", "Odlehčený pohled na souvislou část paměti bez kopírování.\n<small>Je to ref struct, takže žije jen na zásobníku.</small>", "csharp ai_gen"),
            new("Jaké jsou životnosti služeb v ASP.NET Core?", "1. **Transient**: nová instance při každém vyžádání\n2. **Scoped**: jedna instance na HTTP požadavek\n3. **Singleton**: jedna instance na celou aplikaci", "csharp prednaska_02"),
        ]),
        new("Angličtina: slovíčka", "Slovíčka, která se pletou", "#8FC7F0", true, false,
        [
            new("Jak se řekne anglicky „zásuvka“?", "**socket** (ve zdi) nebo **drawer** (v nábytku)", "slovicka"),
            new("Jak se řekne anglicky „ověřit“?", "to verify", "slovicka"),
            new("Jak se řekne anglicky „zlepšit se“?", "to improve", "slovicka"),
            new("Jak se řekne anglicky „ztratit“?", "to lose\n<small>Pozor: loose znamená volný.</small>", "slovicka"),
            new("Jak se řekne anglicky „půjčit si“?", "to borrow", "slovicka ai_gen"),
            new("Jak se řekne anglicky „půjčit někomu“?", "to lend", "slovicka ai_gen"),
            new("Jak se řekne anglicky „výzva“?", "a challenge", "slovicka"),
            new("Jak se řekne anglicky „rozhodnout se“?", "to decide", "slovicka"),
            new("Jak se řekne anglicky „úspěch“?", "success", "slovicka"),
            new("Jak se řekne anglicky „zvyk“?", "a habit", "slovicka"),
            new("Jak se řekne anglicky „zapomenout“?", "to forget", "slovicka"),
            new("Jak se řekne anglicky „pozdě“?", "late\n<small>Pozor: lately znamená v poslední době.</small>", "slovicka"),
        ]),
        MultiplicationTable(),
        new(RestrictedDeckName, "Jen pro vybrané uživatele", "#FF8A8A", false, false,
        [
            new("Kolik kostí má dospělý člověk?", "206", "anatomie prednaska_01"),
            new("Která kost je nejdelší?", "Stehenní kost (femur).", "anatomie prednaska_01"),
            new("Která kost je nejmenší?", "Třmínek (stapes) ve středním uchu.", "anatomie prednaska_01"),
            new("Z kolika oddílů se skládá lidské srdce?", "Ze čtyř: dvě síně a dvě komory.", "anatomie prednaska_02"),
            new("Který orgán vyrábí inzulin?", "Slinivka břišní (pankreas).", "anatomie prednaska_02"),
            new("Jak se jmenuje největší tepna v těle?", "Aorta (srdečnice).", "anatomie prednaska_02"),
            new("Z čeho se skládá bílá hmota mozku?", "Z myelinizovaných nervových vláken.", "anatomie ai_gen"),
            new("Kolik žeber má člověk?", "24 (12 párů).", "anatomie prednaska_01"),
        ]),
        new(ArchivedDeckName, "Archivovaný balíček pro zkoušku obnovení", "#C4BAFF", true, true,
        [
            new("Hlavní město Francie?", "Paříž", "zemepis"),
            new("Hlavní město Itálie?", "Řím", "zemepis"),
            new("Nejdelší řeka v Česku?", "Vltava", "zemepis"),
        ]),
    ];

    /// <summary>Násobilka 2 × 2 až 7 × 7: a lot of quick cards, so a goal of 20 is reachable for weeks.</summary>
    private static DemoDeck MultiplicationTable()
    {
        var cards = new List<DemoCard>();
        for (var a = 2; a <= 7; a++)
        {
            for (var b = 2; b <= 7; b++)
            {
                cards.Add(new DemoCard($"Kolik je {a} × {b}?", (a * b).ToString(System.Globalization.CultureInfo.InvariantCulture), "matika"));
            }
        }

        return new DemoDeck("Násobilka", "Rychlé počítání z hlavy", "#FFCB52", true, false, cards);
    }
}
