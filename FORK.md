# This fork of haskeline

This is haskeline `master` at upstream commit `bbedbc9` (version 0.8.5.0), with
one change:

- Unicode 17.0.0 character-width tables (`04dfa7c`).

The Haskell API and the C entry points are unchanged.

## The change

`cbits/h_wcwidth.c` was regenerated from the Unicode Character Database:

- `combining[]`: 378 intervals, `Mn | Me | Cf`, minus `U+00AD`, plus the
  Hangul Jamo ranges `U+1160-U+11FF`, `U+D7B0-U+D7C6` and `U+D7CB-U+D7FB`.
- `wide[]`: 123 intervals, `W | F` from `EastAsianWidth.txt`.
- `ambiguous[]`: 176 intervals, `A` from `EastAsianWidth.txt` minus
  `Mn`, `Me` and `Cf`. This table drives the CJK variant.
- Lookup order is control characters, then zero-width characters, then wide
  characters. `U+302A-U+302D`, `U+3099-U+309A` and `U+16FE4` occur in both
  the zero-width and wide tables and therefore return 0. `U+00AD` is not
  zero width.
- The file header records the source URLs and SHA-256 hashes, the generation
  rules, the lookup order, and the verification steps.

The tables were derived from these files:

- `UnicodeData.txt`
  <https://www.unicode.org/Public/17.0.0/ucd/UnicodeData.txt>
  SHA-256 `2e1efc1dcb59c575eedf5ccae60f95229f706ee6d031835247d843c11d96470c`
- `EastAsianWidth.txt`
  <https://www.unicode.org/Public/17.0.0/ucd/EastAsianWidth.txt>
  SHA-256 `ea7ce50f3444a050333448dffef1cadd9325af55cbb764b4a2280faf52170a33`

The result was cross-checked against `@stackline/wcwidth@1.0.2`: its
`ZERO_WIDTH` and `WIDE` tables match `combining[]` and `wide[]`, and the
ambiguous table was derived independently from the same UCD files.

## Verification

- Every code point in `U+0000..U+10FFFF` was compared against the rules
  above, for both the default and CJK variants. No differences were found.
- `cbits/h_wcwidth.c` compiles as C89 with
  `gcc -std=c89 -pedantic -Wall -Wextra` without warnings.
- `cabal build all` succeeds and `cabal test` passes all 65 tests.
- There is currently no direct unit test for the C width function; the
  existing tests cover it indirectly through pseudoterminal interactions.

## Known limitations

The width function works on one code point at a time. Haskeline's
`Grapheme` type currently merges only `Mn` characters, and `gWidth` uses only
the base character's width. As a result, these sequences have the following
widths:

| Sequence | Code points | Haskeline width |
| --- | --- | --- |
| `❤️` | `U+2764 + U+FE0F` | 1 |
| `👍🏻` | `U+1F44D + U+1F3FB` | 4 |
| `👩‍👩` | `U+1F469 + U+200D + U+1F469` | 4 |
| `1️⃣` | `U+0031 + U+FE0F + U+20E3` | 1 |
| `🇨🇳` | `U+1F1E8 + U+1F1F3` | 2 |

These are cursor widths, not necessarily the widths at which terminals render
the sequences. VS16, keycap sequences, skin-tone modifiers, regional
indicators and ZWJ sequences are not handled as grapheme clusters.

## Possible follow-ups

These are not implemented in this fork.

1. Add a direct FFI test suite for `haskeline_mk_wcwidth` and
   `haskeline_mk_wcwidth_cjk`, including control characters, combining
   characters, `U+00AD`, the overlapping ranges, interval boundaries, the
   ambiguous table and the CJK variant.
2. Improve emoji handling. Possible scopes, from smallest to largest:
   - Documentation only: roughly half an hour.
   - Keycap sequences only: roughly 0.5-1 person-day.
   - Common emoji heuristics (keycap, VS15/VS16, skin tones, regional
     indicators, ZWJ): roughly 2-4 person-days.
   - Full UAX #29 grapheme segmentation and cluster widths: roughly 7-11
     person-days. This would need a generation script, which this change
     deliberately does not add.

The estimates are rough and are not commitments.

## Building and testing

```sh
gcc -std=c89 -pedantic -Wall -Wextra -c cbits/h_wcwidth.c -o /tmp/h89.o
cabal build all
cabal test
```
