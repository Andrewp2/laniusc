# Fast byte and substring search

`core::search` searches `[u8]` slices over explicit `[from, to)` ranges. It
needs no allocation and no native library. `core::text::Text::find` now uses
it, and the [parallel grep](stdlib-concurrency.md#samples) uses it for both
line scanning and matching.

| Function | Result |
| --- | --- |
| `find_byte(bytes, from, to, byte)` | First index of `byte`, or -1 |
| `rfind_byte(bytes, from, to, byte)` | Last index of `byte`, or -1 |
| `find(bytes, from, to, needle, needle_start, needle_length)` | Leftmost match start, or -1. An empty needle matches at `from` |
| `rfind(...)` | Rightmost match start, or -1. An empty needle matches at `to` |
| `count(...)` | Nonoverlapping leftmost matches. An empty needle counts `to - from + 1` |
| `find_two_way(...)` / `rfind_two_way(...)` | Two-Way search alone, with the same results as `find`/`rfind` |
| `rank(byte)` | The frequency rank used to choose prefilter bytes |

Results equal a naive search and Python's
`bytes.find`/`rfind`/`count(sub, from, to)`. The caller guarantees two
preconditions, because the word loads are not bounds-checked:

- `to` does not exceed the slice length.
- The needle range lies inside the needle slice.

Negative or inverted ranges return -1, or 0 for `count`.

## Algorithm

**Byte scans.** `find_byte` builds one `u64` storage view over the range and
tests two words per step with the SWAR zero-byte expression
`(x - 0x01..01) & !x & 0x80..80`, where `x` is the word XORed with the
repeated byte. Only the lowest flagged byte of a word is used; higher flags
can be borrow artifacts. `rfind_byte` confirms the highest zero byte
exactly.

**Substring search.** `find` ranks the needle's bytes by a fixed
text/source frequency table and picks the two rarest offsets. It runs
`find_byte` on the rarest byte, checks the second rarest at its offset, and
only then compares the whole needle. The table affects speed only, never
results.

**Two-Way fallback.** `find` and `rfind` count their full-needle compares.
Once `compares × m` exceeds `4 × scanned bytes + 256`, they continue from
the current position with Two-Way (Crochemore–Perrin). That happens on
periodic needles, or when every haystack byte is the needle's rarest byte.

- Before the switch, positions are rejected only by a failed compare, so the
  results do not change.
- Two-Way uses the critical factorization from the two maximal suffixes. A
  short-period needle remembers its matched prefix; a long-period needle
  shifts by `max(critical, m - critical) + 1`.
- `rfind` runs the same search with the haystack range and the needle read
  backwards.

Prefilter work stays linear before the switch, so `find`, `rfind`, `count`
and `Text::find` are O(n + m) with O(1) space. `find_two_way` and
`rfind_two_way` expose the fallback directly.

**Platform assumptions.** The word loads may be unaligned, which x86_64
permits. `core::mem::i32_slice_data_ptr` supplies the byte slice's data
pointer; on this compiler it accepts `[u8]` views.

## Evidence

[`cases.lani`](../tests/fixtures/stdlib_execution/search/cases.lani) runs
`find`, `rfind`, `count`, `find_byte` and `Text::find` on cases read from
stdin. [`oracle.py`](../tests/fixtures/stdlib_execution/search/oracle.py)
generates those cases and compares the results with Python's
`bytes.find`/`rfind`/`count` and `str.find` (converted to byte offsets).

- **Coverage:** each oracle run adds 57 adversarial cases to 20,000 random
  ones. Eight seeds gave 160,456 cases with 0 mismatches. About 69% of the
  cases are valid UTF-8 and also check `Text::find`. Every case also calls
  `find_two_way` and `rfind_two_way` directly.
- **Adversarial cases:** needles `b`×{2, 3, 17, 500, 4000} followed by `a`,
  `ab` or `ba`, in all-`b` haystacks of 100,000–200,000 bytes, with the
  match at the start, in the middle or absent. Also periodic units `ab`,
  `aab`, `abaab` and `bbbbbbba` repeated about 60,000 bytes, with periodic
  needles and subranges.
- **Speed on the adversarial set:** the 57 cases took 82.1 s before the
  fallback and 1.55 s after, with identical find, rfind and count results.
- **Generated inputs:** haystacks of 0 to 3,000 bytes, including every
  boundary near multiples of 8 and 64; alphabets of 1, 2, 3 and 256 bytes,
  English and UTF-8; needles cut from the haystack, empty needles and
  periodic needles; random subranges.

A single-process micro-benchmark scanned 40,000,000 bytes for an absent
byte in 41–64 ms, about 1–1.6 ns per byte. The first one-word-per-step
version took 133 ms. The range comes from load on the shared laptop.

## parallel_grep timings

Best of five runs, writing to a file, on a 49 MB corpus of repeated
`docs/*.md` and `stdlib/*/*.lani` and on the 43 MB synthetic file. Output
matched GNU `grep -F` in every row.

| Pattern | Input | Lines | Old naive (ms) | core::search (ms) | GNU grep -F (ms) |
| --- | --- | --- | --- | --- | --- |
| `zzzz` | corpus | 0 | 669 | 101 | 19 |
| `core::result::Result` | corpus | 8,682 | 743 | 286 | 40 |
| `fn main` | corpus | 18 | 731 | 131 | 47 |
| `the` | corpus | 150,582 | 827 | 741 | 264 |
| `zzzz` | synthetic | 0 | 630 | 170 | 58 |
| `fn main` | synthetic | 0 | 607 | 94 | 14 |
| `the` | synthetic | 0 | 736 | 195 | 104 |

GNU grep is still 2–7x faster. Two costs remain:

- Reading stdin takes about 45 ms on 43 MB.
- When many lines match, output takes one `write` per run of adjacent
  matching lines.

Each worker also builds per-chunk match summaries, so the parent skips the
flag scan for chunks with no match.

On an adversarial file, `parallel_grep` went from 8.13 s to 0.109 s with
the fallback; GNU grep took 0.004 s. The file held 4,000 lines of 5,000 `b`
bytes, and the pattern was `b`×400 followed by `a`. Output still matched
GNU `grep -F` in 42 of 42 cases, across seven patterns (including both
adversarial ones) and six inputs.

Do not benchmark GNU grep with output to `/dev/null`. It detects that and
stops at the first match, which made it look about ten times faster.
