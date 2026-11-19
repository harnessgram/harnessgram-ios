# Harnessgram bundled fonts: provenance

Every font here is licensed under the SIL Open Font License 1.1. Each license text sits next to its font
(`OFL-<Family>.txt`, copied unmodified from the same upstream folder). The font files are unmodified; only the
file names were changed (no brackets).

Upstream: https://github.com/google/fonts at commit `cc39c4c2c304bc368c9b7c311ea2bcc6013299fe`
(the four variable families fetched 2026-11-15 for build 11, Secular One fetched 2026-11-16 for build 22).

| File | Upstream path | Weights | SHA-256 |
|---|---|---|---|
| Assistant-Variable.ttf | ofl/assistant/Assistant[wght].ttf | variable 200–800 (regular 400, bold 700) | 1c3b393884f8fb133a1b17f41d26178adae1050a4f86d7a429d1b5658c314fa3 |
| Heebo-Variable.ttf | ofl/heebo/Heebo[wght].ttf | variable 100–900 (regular 400, bold 700) | 18f930b583fa8fe6b40b2f8263b7ac6afbac07adc91a12467874e7467d3ace30 |
| Rubik-Variable.ttf | ofl/rubik/Rubik[wght].ttf | variable 300–900 (regular 400, bold 700) | 1b3a7437ba2af80e465e773ed60c5036d1ba6ace492d89046dbcf18fb31e4e88 |
| FrankRuhlLibre-Variable.ttf | ofl/frankruhllibre/FrankRuhlLibre[wght].ttf | variable 300–900 (regular 400, bold 700) | f9bf26966681037aae894b031bd0dcf2c1bfdfa128dd0640cf276fe62a338a43 |
| SecularOne-Regular.ttf | ofl/secularone/SecularOne-Regular.ttf | 400 only (the family has no other weight) | 2f45092a521db5042887941edfef73178ed7c5ba7fdfc5b6f581d44aab7b0234 |

Direct links (pinned): `https://raw.githubusercontent.com/google/fonts/cc39c4c2c304bc368c9b7c311ea2bcc6013299fe/<upstream path>`.

| License file | Upstream path | Copyright line |
|---|---|---|
| OFL-Assistant.txt | ofl/assistant/OFL.txt | The Assistant Project Authors, with portions from Source Sans Pro (Reserved Font Name "Source") |
| OFL-Heebo.txt | ofl/heebo/OFL.txt | The Heebo Project Authors |
| OFL-Rubik.txt | ofl/rubik/OFL.txt | The Rubik Project Authors |
| OFL-FrankRuhlLibre.txt | ofl/frankruhllibre/OFL.txt | The Frank Ruhl Libre Project Authors |
| OFL-SecularOne.txt | ofl/secularone/OFL.txt | The Secular One Project Authors (designer Michal Sahar; source googlefonts/secular at 6a1b3caa) |

Use: the "Message font" choice (bubbles and the input field, build 11) and the "App font" choice (the whole app,
build 22). A weight a family lacks takes its closest (Secular One always draws at 400, never a synthesized bold).
None of the fonts covers emoji or every script: HarnessgramFonts gives each font a cascade list ending in the
system font, so a missing glyph is drawn by the system font (never a missing-glyph box). Italic is a slanted
rendering of the upright font (none of these families ships an italic).

To add a font: take it from the same google/fonts commit (or record a new one here), keep its OFL text next to it,
add a row to both tables with its SHA-256, and a case in `HarnessgramFonts.BundledFamily`.
