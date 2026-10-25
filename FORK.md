# This fork of haskeline

This is haskeline `master` at upstream commit `bbedbc9` (version 0.8.5.0),
with the following changes:

- Unicode 17.0.0 character-width data (`04dfa7c`).
- A page-deduplicated width table in `cbits/h_wcwidth.c` (`38b4492`).
- Emoji and other extended grapheme clusters are kept together when editing
  (`ec611c5`).
- Fast paths for ASCII widths and for the common grapheme-joining checks
  (`8176f58`, `995fb6b`).

The public `System.Console.Haskeline` API and the C entry points are
unchanged.  Some internal modules are exposed through
`System.Console.Haskeline.Internal`.

## Unicode 17 width tables

`cbits/h_wcwidth.c` was regenerated from the Unicode Character Database.
The old interval arrays have been replaced by a page-deduplicated table:
Unicode is split into 256-code-point pages, each page stores four 2-bit width
codes per byte, and a 4352-entry index maps a page to one of 115 unique
stored pages.  The table occupies 11,712 bytes.

The width classes are:

- zero width: `Mn | Me | Cf`, minus `U+00AD`, plus the Hangul Jamo ranges
  `U+1160-U+11FF`, `U+D7B0-U+D7C6` and `U+D7CB-U+D7FB`;
- wide: `W | F` from `EastAsianWidth.txt`;
- ambiguous: `A` from `EastAsianWidth.txt` minus `Mn`, `Me` and `Cf`.
  This class is used by the CJK variant.

Lookup order is control characters first, then the packed width table.
`U+302A-U+302D`, `U+3099-U+309A` and `U+16FE4` occur in both the zero-width
and wide classes and therefore return 0.  `U+00AD` is not zero width.

The tables were derived from these files:

- `UnicodeData.txt`
  <https://www.unicode.org/Public/17.0.0/ucd/UnicodeData.txt>
  SHA-256 `2e1efc1dcb59c575eedf5ccae60f95229f706ee6d031835247d843c11d96470c`
- `EastAsianWidth.txt`
  <https://www.unicode.org/Public/17.0.0/ucd/EastAsianWidth.txt>
  SHA-256 `ea7ce50f3444a050333448dffef1cadd9325af55cbb764b4a2280faf52170a33`

The result was cross-checked against `@stackline/wcwidth@1.0.2`.  Its
`ZERO_WIDTH` and `WIDE` tables match this implementation, and the ambiguous
table was derived independently from the same UCD files.

## Grapheme clusters

Haskeline's `Grapheme` type stores a base character and a list of following
characters.  `joinsGrapheme` now treats the following as part of the same
grapheme:

- non-spacing and enclosing marks;
- ZWNJ and ZWJ;
- variation selectors;
- emoji skin-tone modifiers and tag characters;
- a second regional indicator, forming a flag pair;
- Hangul Jamo in L/V/T order.

A character after ZWJ is joined when it is an extended pictographic character.
The check is deliberately broad: it only decides whether editing should keep
the sequence together.

`insertChar` uses the same joining rules, so a cluster also stays together
when its characters arrive one at a time from the terminal.  The keymap
accepts these characters even though they are not `isPrint`.

## Width behaviour

`gWidth` adds the widths of all codepoints in a grapheme.  This matches VTE,
which lays out the codepoints separately.  The family emoji is eight columns
wide because its four emoji components are each two columns wide and the
joiners are zero-width.

| Sequence | Codepoints | Width |
| --- | --- | ---: |
| `❤️` | `U+2764 U+FE0F` | 1 |
| `👍🏻` | `U+1F44D U+1F3FB` | 4 |
| `1️⃣` | `U+0031 U+FE0F U+20E3` | 1 |
| `🇨🇳` | `U+1F1E8 U+1F1F3` | 2 |
| `👨‍👩‍👧‍👦` | 7 codepoints | 8 |

This is a cursor-width model, not a model of every terminal's rendering.
Terminals such as kitty and WezTerm draw a cluster as one glyph and may
advance only two columns for the last two sequences.  This branch has no
terminal width policy; see the `width-policy-1` branch for that work.

## Benchmarks

The cumulative changes were compared with upstream `bbedb` (`bbedbc9`) using
GHC 9.14.1 and `-O2` on x86-64 Linux.  The two binaries were run alternately
for seven rounds; the table reports the median.

The segmentation and width benchmarks use 500,000 characters, the insertion
benchmarks use 200,000 characters, and the typing benchmarks use 150,000
characters.

| Benchmark | `bbedb` | this branch | Change |
| --- | ---: | ---: | ---: |
| width/ascii | 21.34 ms | 18.50 ms | -13.3% |
| width/random | 20.65 ms | 16.28 ms | -21.1% |
| width/chinese | 15.07 ms | 12.37 ms | -17.9% |
| width/mixed | 9.88 ms | 6.53 ms | -33.9% |
| insert/ascii | 19.38 ms | 17.78 ms | -8.2% |
| insert/random | 30.99 ms | 21.26 ms | -31.4% |
| insert/chinese | 28.85 ms | 25.32 ms | -12.2% |
| insert/mixed | 24.77 ms | 24.58 ms | -0.8% |
| type/ascii | 16.73 ms | 14.87 ms | -11.2% |
| type/random | 20.62 ms | 18.66 ms | -9.5% |
| type/mixed | 27.50 ms | 26.06 ms | -5.2% |
| splitall/mixed | 29.44 ms | 25.55 ms | -13.2% |

Emoji benchmarks are not directly comparable: `bbedb` treats a family
sequence as seven graphemes, while this branch treats it as one.  The
remaining comparisons are microbenchmarks for segmentation, width
calculation and line-state updates; they do not measure terminal rendering
or interactive latency.  The `insert/random` median also has noticeable
run-to-run variance.

## Verification

- Every code point in `U+0000..U+10FFFF` was compared against the rules
  above, for both the default and CJK variants.  No differences were found.
- `cbits/h_wcwidth.c` compiles as C89 with
  `gcc -std=c89 -pedantic -Wall -Wextra` without warnings.
- `cabal build all` succeeds and `cabal test` passes all 68 tests.
- The regression tests cover ASCII, Hangul, combining marks and ZWJ family
  sequences.
- There is still no direct unit test for the C width function; the existing
  tests cover it indirectly through pseudoterminal interactions.

## Known limitations

The width function is terminal-independent and uses the VTE-style
codepoint-sum model.  A terminal that composes grapheme clusters into one
glyph can therefore advance by fewer columns than Haskeline expects.

VTE does not compose ZWJ emoji into one glyph.  A family sequence is drawn as
four separate emoji, and this implementation advances eight columns for that
rendering, but the visual result differs from terminals that compose the
sequence.

The grapheme joining rules cover common emoji and Hangul cases, but are not a
complete implementation of UAX #29.  `isExtendedPictographic` is a
deliberately broad approximation.

## Possible follow-ups

These are not implemented in this branch.

1. Add a terminal width policy, so terminals that compose grapheme clusters
   can use cluster width instead of codepoint-sum width.  This is implemented
   on the `width-policy-1` branch.
2. Add a direct FFI test suite for `haskeline_mk_wcwidth` and
   `haskeline_mk_wcwidth_cjk`, including control characters, combining
   characters, `U+00AD`, the overlapping ranges, page boundaries, the
   ambiguous table and the CJK variant.
3. Implement full UAX #29 grapheme segmentation and cluster widths.
4. Test the Windows backend on a real Windows terminal.

## Building and testing

```sh
gcc -std=c89 -pedantic -Wall -Wextra -c cbits/h_wcwidth.c -o /tmp/h89.o
cabal build all
cabal test
```
