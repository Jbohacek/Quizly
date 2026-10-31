# Notification texts (seed)

These texts are seeded into `notification_texts` when the table is empty (spec §2.13). After that the admin edits them on **Texty upozornění**. When/how they fire: [`notifications.md`](./notifications.md).

Format for the seeder: every list item under a `## <category>` heading is one active text.

## Writing rules

1. **Tone:** warm, friendly, supportive, emoji welcome. **Never guilt-tripping** (no "zklamal/a jsi", "škoda", "zase nic").
2. **Gender-neutral:** no past tense or adjectives that agree with the user or the app. Use present/future 2nd person ("zvládneš", "máš", "dáš"), nouns, or impersonal forms ("máš splněno"). First person of the app only in neutral forms ("věřím ti", "gratuluju", "máš můj obdiv").
3. **Czech plural safety:** a number placeholder must not need a noun or verb that changes with the number (1 karta · 2 karty · 5 karet). Put it after a colon ("Karty na dnešek: {due}"), in "{done} z {goal}", or where the value is always ≥ 5 (milestone `{streak} dní`, milestone `+{points} bodů`).
4. **Placeholders** (formatted by the app in Czech style, e.g. `1 457`, `1,2×`):

| Placeholder | Value | Unknown when |
| --- | --- | --- |
| `{due}` | cards waiting (morning: forecast; else due now) | no fresh data from the server |
| `{left}` | cards left to today's goal | goal already met |
| `{done}` | graded answers today | no data |
| `{goal}` | today's goal | no data |
| `{streak}` | current streak (milestone: the milestone reached) | streak is 0 |
| `{multiplier}` | current multiplier, e.g. `1,2×` | no data |
| `{item}` | wishlist item name | outside `wishlist` |
| `{points}` | `milestone`: bonus points · `wishlist`: balance | outside those categories |

If any placeholder in a text is unknown, that text is skipped and another one from the same category is picked. Every category has at least two texts without placeholders.

## morning

- Dobré ráno! ☀️ Karty na dnešek: {due}. Uvař si kafe a pojďme na to spolu ☕
- Krásné ráno! 🌤️ Dnešní dávka karet je připravená: {due}. Zvládneš to levou zadní 💪
- Dobré ráno! Nový den, nová šance naučit se něco nového 🌱
- Ahoj! 👋 Dnes máš v plánu karet: {due}. Stačí pár minut a máš hotovo.
- Ráno je ideální na pár karet 🧠 Pustíme se do toho?
- Dobré ráno! 🔥 Série: {streak}, násobič {multiplier}. Dnes ji můžeš prodloužit!
- Hezký den! ☀️ Dnešní cíl: {goal}. Půjdeme na to spolu? 🙂
- Dobré ráno! 📚 Na dnešek čeká karet: {due}. Jedna po druhé a bude to hned.
- Vstávej, mozek se těší! 🧠✨ Dáme si dnes pár karet?
- Dobré ráno! Kafe ☕, karty 📚 a dobrá nálada. Věřím ti ❤️
- Ahoj! Tvůj násobič je dnes {multiplier} 🚀 Každá správná odpověď se počítá víc.
- Dobré ráno! 🌻 Pár minut učení dnes udělá radost tvému budoucímu já.

## evening

- Jde ti to skvěle! 💪 Už máš {done} z {goal}. Dáme ještě kousek spolu?
- Do dnešního cíle zbývá: {left}. To dáš! ✨
- Večer je na karty jako stvořený 🌙 Pár minut a cíl je splněný.
- Ahoj! 👋 Dnešní cíl ještě čeká. Dáme ho spolu? 🙂
- Ještě kousek! 🧩 Máš {done} z {goal} a cíl je na dosah.
- Zvládneš to! Věřím ti ❤️
- Malá pauza na karty? ☕ Do cíle chybí: {left}.
- Série: {streak} 🔥 Dnešní karty ji udrží při životě. Jdeme na to?
- Krátké opakování před večeří? 🍝 Mozek ti poděkuje.
- Jsi blíž, než si myslíš 🌟 Do cíle zbývá: {left}.

## last_call

- Ještě je čas! ⏰ Do cíle zbývá: {left}. Série: {streak} 🔥 Udržíme ji spolu?
- Poslední výzva na dnešek 🌙 Pár karet a série zůstane v bezpečí 💚
- Psst… 🤫 Dnešní cíl ještě čeká. Stačí chvilka a série žije dál 🔥
- Ještě jedno kolo před spaním? 😴📚 Do cíle chybí: {left}.
- Tvoje série se drží 🔥 Dáme dnešní karty, ať to tak zůstane?
- Ještě to stihneš! 💪 Máš {done} z {goal}, už jen poslední kousek.
- Den ještě nekončí ✨ Pár karet a máš splněno.
- Pojďme to dnes dotáhnout 🙌 Věřím ti ❤️

## milestone

- {streak} dní v řadě! 🎉 Tohle je paráda, máš můj obdiv!
- Série {streak} dní! 🔥 Bonus +{points} bodů je tvůj. Zasloužíš si ho!
- Wow, {streak} dní bez přestávky! 🏆 Násobič je teď {multiplier}.
- Milník splněn! 🎯 {streak} dní v řadě a k tomu bonus +{points} bodů 🎁
- Neuvěřitelné! 🌟 Učíš se už {streak} dní v kuse. Jen tak dál!
- Gratuluju! 🎉 Nový milník série je tady.
- Tohle je výkon! 🏅 Další milník série je za tebou 💚
- {streak} dní! 🚀 Tvoje vytrvalost je obdivuhodná.

## wishlist

- Máš na to! 🎁 Body ti teď stačí na „{item}“. Zasloužíš si tu odměnu!
- Hurá! 🥳 Na „{item}“ už máš dost bodů. Mrkni do obchodu 🛍️
- Tvoje přání je na dosah 💛 „{item}“ si teď můžeš koupit.
- Body na kontě: {points} 🪙 To stačí na „{item}“!
- Splněné přání čeká! ✨ Odměna ze Seznamu přání je teď v dosahu.
- Dřina se vyplácí 💪 Na jednu z tvých vysněných odměn už máš dost bodů 🎁
- Šetření se vyplatilo! 🎉 „{item}“ může být tvoje.

## comeback

- Vítej zpátky 💚 Série se přerušila, to se stává každému. Začneme znovu, spolu to dáme!
- Nový den, nový start 🌱 Každá série začíná jedničkou.
- Žádný stres 🤗 Jeden vynechaný den nic nemění. Dáme dnes pár karet?
- Ahoj! 👋 Karty se na tebe těší. Začneme novou sérii?
- I ty nejlepší série se někdy přeruší 💚 Hlavní je pokračovat. Jdeme na to?
- Čistý štít ✨ Dnes můžeš začít novou sérii. Věřím ti ❤️
- Dobré ráno! ☀️ Na dnešek čeká karet: {due}. Pomalu a v klidu, krok za krokem 🐢

## Review checklist

| Check | Result |
| --- | --- |
| Total texts ≥ 50 | 52 (morning 12 · evening 10 · last_call 8 · milestone 8 · wishlist 7 · comeback 7) |
| ≥ 2 texts without placeholders per category | morning 5 · evening 4 · last_call 5 · milestone 2 · wishlist 2 · comeback 6 |
| No gendered past tense / adjectives about the user or app | checked: only nouns agree (dávka připravená, cíl splněný, série se přerušila) |
| Plural-safe numbers | colons, "{done} z {goal}", milestone values always ≥ 5 |
| No guilt-tripping | checked |
| Each text ≤ 300 chars | longest is 85 chars |
