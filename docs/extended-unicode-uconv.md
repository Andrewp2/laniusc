# Unicode quick check, uconv and the Python oracle

This increment adds three things on top of the existing Unicode 17.0.0
library ([properties](stdlib-unicode.md), [normalization](extended-unicode-normalize.md)
and [casing](extended-unicode-case.md)):

- O(1) two-level lookup tables for `core::unicode` properties and for
  normalization's combining class and quick-check values.
- The UAX #15 quick-check fast path: `quick_check`, `normalize_quick_into` and
  `is_normalized_quick` in `ext::unicode_normalize`.
- A `uconv`-style stdin transformer and an exhaustive oracle that checks the
  library against Python's `unicodedata`.

## Tables

Both tables use the same layout. The code point space is split into 8,704
blocks of 128 code points. `stage1[cp >> 7]` selects a deduplicated block,
`stage2[block * 128 + (cp & 127)]` selects a slot, and `stage3[slot]` holds the
packed value. A lookup is three fixed-width hex reads from static string
storage. It does no search, allocates nothing and initializes nothing at
runtime.

| Table | Generator | Distinct blocks / values | Entry |
| --- | --- | --- | --- |
| `core::unicode_properties_data` | `tools/unicode17/generate_properties.py` | 264 / 136 | category, combining class, nine flags, decimal digit, three mapping-presence bits |
| `ext::unicode_quick_check_data` | `tools/unicode17/generate_quick_check.py` | 161 / 70 | combining class, `NFD_QC`, `NFKD_QC`, `NFC_QC`, `NFKC_QC` |

The core table keeps the 4,000-byte literal chunks that core data modules
already use. When a presence bit is clear, the simple-mapping, full-folding or
Turkic-folding point search is skipped.

The generators read the vendored, hash-checked Unicode 17.0.0 files under
`data/unicode/17.0.0`, so nothing is downloaded. They do not read the host
`unicodedata` module. This machine's Python 3.12 ships Unicode 15.0.0, and
building tables from it would downgrade the library by two versions. Python
is used only as the oracle below. Run either generator with `--check` to
confirm that the committed output is reproduced exactly.

## Quick check

The [normalization guide](extended-unicode-normalize.md#quick-check) gives
the API contract and work accounting. The full engine uses the
quick-check table to skip decomposition and composition searches; its
results and work units do not change.

Native timings on this laptop for one process making one call per scalar over
all 1,111,998 scalars. The times include the loop and process start.

| Operation | Time |
| --- | --- |
| `core::unicode::general_category`, all 1,114,112 code points, run-length binary search (before) | 1.54 s |
| the same with the two-level table (after) | 0.42 s |
| `ext::unicode_quick_check_data::entry`, all code points | 0.39 s |
| `normalize_into(.., Nfc, ..)`, table-filtered full engine | 2.17 s |
| `normalize_quick_into(.., Nfc, ..)` | 0.95 s |
| `ext::unicode_case::transform_into(.., Lower, ..)` | 6.7 s |

Casing is the slowest per scalar at about 6 µs, and is the next optimization
target. These numbers are not a comparison with host Unicode libraries.

## `uconv`

[`sample_programs/library/uconv.lani`](../sample_programs/library/uconv.lani)
reads UTF-8 stdin and writes one Unicode transform to stdout:

```sh
target/release/laniusc --stdlib-root stdlib --source-root extended \
  sample_programs/library/uconv.lani -o target/claude-work/s8/uconv
printf 'A\314\212\n' | target/claude-work/s8/uconv -x any-nfc     # Å
printf 'ﬃ\n' | target/claude-work/s8/uconv -x any-upper           # FFI
target/claude-work/s8/uconv --check -x any-nfd < file.txt         # exit 0 or 1
```

| Option | Meaning |
| --- | --- |
| `-x`, `--transform NAME` | `any-nfc` (default), `any-nfd`, `any-nfkc`, `any-nfkd`, `any-lower`, `any-upper`, `any-title`, `any-casefold` (root locale). |
| `--check` | Normalization only. Write nothing; exit 1 and report the first line not in the form. |
| `--max-input-bytes N` | Input limit; default 16,777,216, at most 67,108,864. |
| `-h`, `--help` | Usage. |

Exit status: 0 success, 1 check failed, 2 invalid arguments, malformed UTF-8
(the byte offset is reported) or a limit, 3 I/O failure, 4 allocation failure.

The whole input is validated first, then each LF-terminated line is
transformed on its own. This gives the same result as transforming the whole
text. LF is a starter with combining class 0 that never composes. It is
neither cased nor case-ignorable, so it ends every `Final_Sigma` context, and
UAX #29 always breaks words around it. Scratch and output buffers therefore
grow only to the longest line. For normalization, a line whose quick check is
`Yes` is written straight from the input buffer without being normalized.

Measured on this laptop with an NFC text of mixed scripts:

| Input | Transform | Time |
| --- | --- | --- |
| 2,000,000 bytes, already NFC | `any-nfc` (every line takes the fast path) | 0.43 s |
| 2,000,000 bytes | `any-lower` | 15.7 s |
| 22 MB NFC / 26 MB NFD | `any-nfc` on NFC, `any-nfd` on NFD (fast path) | 11.9 s / 6.4 s |
| 22 MB NFC / 26 MB NFD | `any-nfd` on NFC, `any-nfc` on NFD (full engine) | 59.2 s / 62.3 s |

All four large outputs have the same MD5 as Python's `unicodedata.normalize`.
On the fast path, time grows faster than input size: 0.43 s, 1.32 s and 3.02 s
for 2, 4 and 8 MB with `--check`. That points at whole-input buffering rather
than per-line work, but the cause has not been isolated.

## Python oracle

[`tools/unicode17/python_oracle.py`](../tools/unicode17/python_oracle.py)
drives
[`sample_programs/library/unicode_oracle.lani`](../sample_programs/library/unicode_oracle.lani).
With empty stdin, that program dumps raw records for every code point. Given
strings terminated by 0xFF, it emits the same record for each string. Each
record holds:

- category, combining class, decimal digit and the nine flags;
- full lower, upper, title and fold;
- NFC, NFD, NFKC and NFKD, produced by `normalize_quick_into`;
- `is_normalized_quick` for all four forms.

Inside the program, every normalization is also produced by `normalize_into`
and every `is_normalized_quick` answer is recomputed by `is_normalized`. A
field is marked when the fast path and the full engine disagree.

```sh
python3 -I tools/unicode17/python_oracle.py target/claude-work/s8/unicode-oracle \
  --strings 20000 --uconv target/claude-work/s8/uconv
```

Python's `str.lower`, `upper`, `title` and `casefold` and
`unicodedata.normalize`/`is_normalized` are the references. Every
disagreement is classified:

- **Version.** The code point, or a scalar in the Lanius result, is
  unassigned in the host's Unicode 15.0.0 but assigned in 17.0.0. For
  category, class and digit, Lanius must also match the vendored 17.0.0
  `UnicodeData.txt`.
- **Defect.** Anything else. Any defect makes the harness exit with status 1.

The flags have no `unicodedata` equivalent, so they are compared with the
vendored 17.0.0 `DerivedCoreProperties.txt` and `PropList.txt`.

Recorded run (host Python 3.12.3, `unicodedata` 15.0.0, seed 17):

| Field | Compared | Agree | Version | Defect |
| --- | --- | --- | --- | --- |
| category | 1,114,112 | 1,103,495 | 10,617 | 0 |
| combining class | 1,114,112 | 1,114,066 | 46 | 0 |
| decimal digit | 1,114,112 | 1,114,022 | 90 | 0 |
| flags (vs UCD 17) | 1,114,112 | 1,114,112 | 0 | 0 |
| lower / upper / title / fold | 1,112,064 each | 1,112,009 each | 55 each | 0 |
| NFC / is-NFC | 1,112,064 | 1,112,064 | 0 | 0 |
| NFD / is-NFD | 1,112,064 | 1,112,044 | 20 | 0 |
| NFKC / is-NFKC | 1,112,064 | 1,112,027 | 37 | 0 |
| NFKD / is-NFKD | 1,112,064 | 1,112,007 | 57 | 0 |

Surrogates (2,048) get property rows only. The generated-string run uses
20,000 strings with 689,609 input bytes. The strings mix host-assigned
scalars, combining marks, decomposable scalars, Hangul jamo, ASCII and casing
specials such as Σ, ß, İ, U+0345, ﬃ and U+0344. Results:

- lower, fold, all four normalizations and all four `is_normalized` answers
  agree for all 20,000 strings.
- upper agrees for 19,998; the other 2 are version cases (U+019B and similar
  scalars gained uppercase partners in Unicode 16).
- title agrees for 13,310 and is a version case for 1. The other 6,689 differ
  by design: `str.title()` starts a word after any uncased character, while
  the library uses UAX #29 word boundaries
  ([casing guide](extended-unicode-case.md)).

Running `uconv` over the same strings joined into a 20,000-line text gives
output byte-identical to Python on the whole text for NFC, NFD, NFKC, NFKD,
lower and casefold. Upper differs only on the 2 version lines. `--check`
agrees with `unicodedata.is_normalized` for all four forms, on both the raw
text and Python's normalized output. Each run takes 0.9–1.7 s.

The registered test `tests/extended_unicode_uconv_execution.rs` compiles both
programs, checks uconv's transforms and exit codes, and runs the oracle with
5,000 strings. It also checks that the three generators reproduce their
tables. It was written in this increment; its own Rust test receipt is
pending. The results above come from the direct runs described here.

Target: native x86_64 Linux, code emitted by the GPU compiler. User-program
GPU execution, streaming normalization across reads and locale tailoring
beyond the casing guide remain separate work.
