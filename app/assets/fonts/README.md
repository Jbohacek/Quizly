# Fonts

Static instances of the Google Fonts variable fonts (SIL Open Font License 1.1, licenses next to the files):

- **Manrope** `Manrope[wght].ttf` → weights 400, 600, 700, 800 (body text).
- **Bricolage Grotesque** `BricolageGrotesque[opsz,wdth,wght].ttf` → weights 600, 700, 800 at `opsz=32`, `wdth=100` (headings, big numbers).

Subset to Latin + Latin Extended-A/B, general punctuation, `€ ← → − × …` (all Czech diacritics included).
Made with fontTools (`varLib.instancer` + `subset`). Flutter doesn't map `FontWeight` to the `wght` axis of a variable font, hence static files.
