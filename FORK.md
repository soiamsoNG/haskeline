# This fork of haskeline

This is haskeline `master` at upstream commit `bbedbc9` (version 0.8.5.0),
with the following changes:

- Unicode 18.0.0 character-width data.
- A page-deduplicated width table in `cbits/h_wcwidth.c` (`38b4492`).
- Emoji and other extended grapheme clusters are kept together when editing
  (`ec611c5`).
- Fast paths for ASCII widths and for the common grapheme-joining checks
  (`8176f58`, `995fb6b`).
- A configurable terminal width policy (`c2bce96`, `005e4c6`).
- Internal terminal modules moved under `System.Console.Haskeline.Term`
  (`22da5d6`, `6b326f6`).

The public `System.Console.Haskeline` API and the C entry points are
unchanged.  Some internal modules are now exposed through
`System.Console.Haskeline.Internal`.

## Unicode 18 width tables

`cbits/h_wcwidth.c` was regenerated from the Unicode Character Database.
The old interval arrays have been replaced by a page-deduplicated table:
Unicode is split into 256-code-point pages, each page stores four 2-bit width
codes per byte, and a 4352-entry index maps a page to one of 116 unique
stored pages.  The table occupies 11,776 bytes.

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
  <https://www.unicode.org/Public/18.0.0/ucd/UnicodeData.txt>
  SHA-256 `0736451de439ae7baf1425136617da495e09ee5afbe6e394374db7009ea08950`
- `EastAsianWidth.txt`
  <https://www.unicode.org/Public/18.0.0/ucd/EastAsianWidth.txt>
  SHA-256 `a0cf29eacd00cfcaec4381c6b7c281685f18dbb4e7ff82b4076ccb342ca839aa`

The previous Unicode 17 table was cross-checked against
`@stackline/wcwidth@1.0.2`.  That package predates Unicode 18, so this
revision is derived only from the UCD 18.0.0 files above; the ambiguous table
is still generated independently with the rule shown above.

## How to generate the width table

The table is generated from the UCD files listed above.  The generator is
intentionally not part of the repository; the procedure is:

1. Parse field 3 of `UnicodeData.txt` for `Mn`, `Me` and `Cf`, expanding
   `First>`/`Last>` ranges.  Parse `EastAsianWidth.txt` for `A`, `W` and `F`.
2. Assign every code point in `U+0000..U+10FFFF` a 2-bit width class, in this
   order:
   - `0`: `Mn | Me | Cf`, except `U+00AD`, plus the Hangul Jamo ranges
     `U+1160-U+11FF`, `U+D7B0-U+D7C6` and `U+D7CB-U+D7FB`;
   - `2`: `W | F` from `EastAsianWidth.txt`;
   - `3`: `A` from `EastAsianWidth.txt`;
   - `1`: everything else.
3. Split the classes into 256-code-point pages.  Pack four 2-bit values into
   each byte, least significant pair first:
   `p[0] | p[1] << 2 | p[2] << 4 | p[3] << 6`.
4. Deduplicate identical packed pages and emit
   `haskeline_width_pages` plus the 4352-entry
   `haskeline_width_page_index`.
5. Update the UCD version, SHA-256 values, unique page count and table size
   in the file header and in this document.

Control characters are handled in `haskeline_width_for`, not in the page
table.  The CJK entry point maps class `3` to width `2`.

Verification:

```sh
gcc -std=c89 -pedantic -Wall -Wextra -c cbits/h_wcwidth.c -o /tmp/h89.o
cabal build all
cabal test
```

For the full check, compare every code point in `U+0000..U+10FFFF` against
the rules above for both the default and CJK entry points.  NUL maps to `0`,
C0/C1/DEL map to `-1`, and ambiguous code points map to `2` in the CJK
variant.

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

## Width policy

Terminals disagree about the cursor advance for one grapheme cluster.  VTE
lays out the codepoints separately and advances by the sum of their widths.
kitty, WezTerm, Ghostty and some newer terminals draw the whole cluster as
one glyph and advance by the rendered cluster width.  There is no portable
terminal query for this choice, so Haskeline carries an explicit
`WidthPolicy` in its internal `Layout`:

| Policy | Behaviour |
| --- | --- |
| `CodepointSum` | Sum the widths of all codepoints in the cluster.  This is the default and matches VTE. |
| `GraphemeCluster` | Use the width of the rendered cluster.  A regional-indicator pair, VS16 sequence or keycap sequence is 2 columns; otherwise the widest codepoint wins. |

For the sequences in the table below:

| Sequence | `CodepointSum` | `GraphemeCluster` |
| --- | ---: | ---: |
| `❤️` (`U+2764 U+FE0F`) | 1 | 2 |
| `1️⃣` (`U+0031 U+FE0F U+20E3`) | 1 | 2 |
| `🇨🇳` (`U+1F1E8 U+1F1F3`) | 2 | 2 |
| `👨‍👩‍👧‍👦` | 8 | 2 |

The policy is detected once when a terminal backend starts:

- `VTE_VERSION` selects `CodepointSum`;
- `KITTY_WINDOW_ID`, `WEZTERM_PANE`, `TERM=xterm-kitty`,
  `TERM=xterm-ghostty`, `TERM_PROGRAM=wezterm` or `TERM_PROGRAM=ghostty`
  select `GraphemeCluster`;
- unknown terminals keep the historical `CodepointSum` behaviour.

`HASKELINE_WIDTH_POLICY=codepoint` or
`HASKELINE_WIDTH_POLICY=grapheme` overrides detection.  This is also used by
the regression tests.

## Benchmarks

The width-policy implementation was compared with `995fb6b`, before the
policy abstraction, using GHC 9.14.1 and `-O2` on x86-64 Linux.  The
workloads were 500,000 ASCII characters, 200,000 Hangul characters, 50,000
emoji family clusters and 100,000 mixed characters.

Each binary ran seven iterations after a warm-up.  The two binaries were run
alternately for 24 rounds; the table reports the median of those rounds.
Lower is better.

| Benchmark | `995fb6b` | width policy | Change |
| --- | ---: | ---: | ---: |
| width/ascii | 19.19 ms | 18.89 ms | -1.6% |
| width/hangul | 10.88 ms | 10.85 ms | -0.2% |
| width/family | 6.32 ms | 6.32 ms | 0.0% |
| width/mixed | 19.02 ms | 19.40 ms | +2.0% |
| segment/mixed | 74.60 ms | 76.81 ms | +3.0% |
| insert/ascii | 54.99 ms | 52.31 ms | -4.9% |
| insert/mixed | 101.69 ms | 100.92 ms | -0.8% |
| type/ascii | 17.92 ms | 17.26 ms | -3.7% |
| type/family | 10.72 ms | 10.84 ms | +1.1% |

The policy dispatch does not introduce a consistent regression: most results
are within ±3%, and the ASCII insertion path is slightly faster.  These are
microbenchmarks for segmentation, width calculation and line-state updates;
they do not measure terminal rendering or interactive latency.

## Verification

- Every code point in `U+0000..U+10FFFF` was compared against the rules
  above, for both the default and CJK variants.  No differences were found.
- `cbits/h_wcwidth.c` compiles as C89 with
  `gcc -std=c89 -pedantic -Wall -Wextra` without warnings.
- `cabal build all` succeeds and `cabal test` passes all 72 tests.
- The regression tests cover ASCII, Hangul, combining marks, ZWJ family
  sequences, VS16, keycaps and flags, under both width policies.
- There is still no direct unit test for the C width function; the existing
  tests cover it indirectly through pseudoterminal interactions.

## Known limitations

The width policy is selected from environment variables, not by querying the
terminal.  An unknown terminal that renders grapheme clusters as single
glyphs will use `CodepointSum` and may advance too far.

VTE does not compose ZWJ emoji into one glyph.  A family sequence is drawn as
four separate emoji, and `CodepointSum` correctly advances eight columns for
that rendering, but the visual result differs from terminals that compose the
sequence.

`GraphemeCluster` width is a heuristic.  It handles the common emoji cases
listed above, but it is not a complete implementation of UAX #29 or of a
terminal's cell layout.  Hangul joining is limited to the L/V/T rules above.

The Windows backend has been updated to use the policy, but has not been
compiled or tested on Windows in this environment.

## Possible follow-ups

These are not implemented in this fork.

1. Add a direct FFI test suite for `haskeline_mk_wcwidth` and
   `haskeline_mk_wcwidth_cjk`, including control characters, combining
   characters, `U+00AD`, the overlapping ranges, page boundaries, the
   ambiguous table and the CJK variant.
2. Implement full UAX #29 grapheme segmentation and cluster widths, including
   terminal-specific cell layout where it can be detected.
3. Document `HASKELINE_WIDTH_POLICY` in the user-facing manual rather than
   only in the changelog and this file.
4. Test the Windows backend on a real Windows terminal.

## Building and testing

```sh
gcc -std=c89 -pedantic -Wall -Wextra -c cbits/h_wcwidth.c -o /tmp/h89.o
cabal build all
cabal test
```
