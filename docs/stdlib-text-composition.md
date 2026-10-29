# Joining, repetition and word splitting

The composition APIs are implemented in Lanius. They combine borrowed UTF-8
views into packed owned Strings without consuming or destroying their inputs.
Executable evidence currently covers **x86_64 Linux** using the GPU compiler;
this does not establish GPU execution of user programs.

[Literal matching and bounded replacement](stdlib-text-replacement.md) form a
separate accepted native Linux x86_64 increment. The historical composition
receipts below retain their join/repeat/word-split scope.

## API contracts

| Operation | Result |
| --- | --- |
| `alloc::string::join(parts: View<Text>, separator: Text)` | Independent `Result<String, Error>` |
| `alloc::string::repeat(source: Text, count: i32)` | Independent `Result<String, Error>` |
| `String.try_append_joined(parts, separator)` | Append the complete joined sequence; return the new byte length |
| `String.try_append_repeated(source, count)` | Append all repetitions; return the new byte length |
| `Text.split_ascii_whitespace()` | Borrowed `SplitAsciiWhitespace` cursor with `next() -> Option<Text>` |

Join places the separator between parts, never before the first or after the
last. Empty parts are retained, so two empty parts joined by `:` yield `:`.
An empty collection produces empty text; one part is copied without using the
separator. Subviews and both packed and strided storage work through the same
`View<Text>` API. Initial physical backing remains a caller precondition.

Repetition appends the exact bytes `count` times. Negative counts return
`Bounds`, even for empty source text. Zero repetitions and empty source text
produce empty results without allocation. No Unicode normalization, padding,
grapheme processing or implicit terminator is performed. NUL remains a valid
text scalar. Inputs must obey Text's UTF-8 and lifetime contracts.

All concatenation sizes are checked before allocation or output mutation.
Lengths beyond `i32::MAX`, including separators or the existing destination,
return `CapacityOverflow`; allocation failure returns `AllocationFailed`.
Both errors preserve the original destination, its capacity and borrowed views.

Parts, separators and repeated source may borrow initialized bytes of the
destination itself. If growth is needed, the old allocation stays alive until
all copies finish. With sufficient capacity, append operations allocate nothing.
Successful mutation invalidates previously borrowed views; independently owned
constructor results remain valid after their sources are released.

Construction and append use at most one new allocation. Joining takes
O(number of parts + output bytes), plus copying the existing destination if it
grows. Repetition takes O(output bytes), plus any destination copy. No-op empty
results skip the output loop. The ordinary Text append uses the same atomic
storage preparation and commit functions.

## ASCII words

The whitespace cursor skips runs of HT, LF, VT, FF, CR and space and yields
maximal nonempty borrowed words. This is the existing six-character definition
used by `core::u8` and text trimming. NUL, nonbreaking space and other Unicode
whitespace are retained within words. Empty and whitespace-only text yield no
words. The cursor stays exhausted after returning `None`. Copies have independent
positions and share backing storage. Iteration takes O(input bytes) and allocates
nothing. The cursor now implements the canonical shared iterator protocol,
including the separately accepted [bidirectional traversal](stdlib-bidirectional-text.md).
The earlier receipts below predate that integration.

## Example: whitespace normalization

`sample_programs/normalize_words.lani` reads UTF-8 stdin, splits ASCII words,
joins them with single spaces and adds an optional indentation of 0–256 spaces.
Nonempty output ends with one newline. Empty/whitespace-only input emits nothing,
including when indentation was requested. Non-ASCII whitespace and NUL survive.
The program retains at most 1 MiB of input and 65,536 word views. It validates
the complete input and builds the result before writing output.

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  sample_programs/normalize_words.lani --stdlib-root stdlib \
  -o target/stdlib-work/normalize_words
printf '  hello\tworld\n' | timeout --kill-after=2s 10s \
  target/stdlib-work/normalize_words 4
```

The optional argument is 1–3 decimal digits; signs and whitespace are rejected.
Leading zeroes are accepted. Exit codes are `0` success, `2` invalid arguments,
UTF-8 or configured limits, `3` I/O failure, and `4` allocation failure.
Every owned buffer is released on handled failures. Output errors can leave a
prefix after validation; signals retain the normal native stream behavior.

## Execution evidence

On 2026-10-22, all four groups in `tests/stdlib_text_composition_execution.rs`
passed in 18.01 seconds, excluding the 1.33-second harness build:

- Contracts: empty/singleton collections, empty parts/separators, subviews,
  non-ASCII and NUL text, independent results, aliasing with growth and reserved
  capacity, negative repetition, cursor copies and repeated exhaustion.
- Overflow: valid 64-KiB text reused in 32,768 parts exceeds the byte limit
  without constructing a giant output. Empty parts with large separators check
  separator-product overflow separately. Repetition overflow uses a short input.
- Models: 800 generated join/repeat/append/word-split comparisons with independent
  Rust operations. Seed `0x5eed2026`, 32-bit LCG `1664525*x + 1013904223`, with
  ASCII controls, scalar widths 1–4, NUL and non-ASCII whitespace. The reference
  explicitly uses the six-character whitespace contract.
- Failures: fail each observed allocation and every later allocation, checking
  preserved destination bytes/capacity/views and complete cleanup from syscall
  traces. The normalizer also checks input/word limits, malformed UTF-8, argument
  limits, interrupted transfers, would-block, I/O errors and zero-progress writes.

Run the suite with the absolute target directory and environment described in
[stdlib-string.md](stdlib-string.md). Existing String and Text execution suites
also pass after the shared append refactor (three and four groups respectively).

Formatting, Unicode operations and buffered streams now have separate guides
and finite acceptance in the [roadmap](library-roadmap.md). Native `str` length
access, broader targets and enforced lifetimes remain separate
[dependencies](library-dependencies.md).

## Native construction cost

`tests/fixtures/stdlib_foundation/text_join_workload.lani` compares one join with
repeated Text appends, using the same current library and executable. It builds
65,536 borrowed parts containing `é`, NUL, an emoji and `z`, joins them with
spaces, and writes all 589,823 output bytes. Both paths include the same part
vector construction, output writes and cleanup.

On an AMD Ryzen 9 5950X, one warm-up pair followed by four alternating measured
pairs produced these medians on 2026-10-22:

| Construction | Native program time | Allocation calls | Peak live mmap request bytes |
| --- | ---: | ---: | ---: |
| Repeated append | 116.36 ms | 19 | 4,194,304 |
| Pre-sized join | 75.73 ms | 2 | 3,211,263 |

Both allocation counts include one allocation for the part vector. Thus joining
allocates its output once, while the append loop grows its output 18 times.
The syscall trace confirms every allocation was freed. Peak request bytes are
not RSS or allocator page-rounded physical memory. Every output was checked
against an independent byte-string join. Timing includes process startup and
capturing stdout, with a ten-second bound per run. This measures native library
runtime, not GPU compiler throughput or a regression against an older compiler.

Compile the fixture with the ordinary stdlib root. Run with no argument for
join, and with `append` for repeated append. Raw measurements and allocation
traces from this run are under the ignored `target/stdlib-work/text-join-*` paths.
