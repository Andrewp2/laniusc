# Sorted word lookup

`sample_programs/library/look_words.lani` is a look(1)-style lookup over the
distinct words of UTF-8 stdin. It consumes the
[ordered navigation](stdlib-ordered-navigation.md) APIs: prefix families
through `range_bounds_by` with `core::text::TextPrefix`, nearest neighbors
through `last_below_by`/`upper_bound_by`, and an inclusive interval through
`range_bounds` with two `Included` Text bounds.

```sh
laniusc --stdlib-root stdlib --source-root extended \
  sample_programs/library/look_words.lani -o target/stdlib-work/look-words
printf 'apple apply app banana ap apt\n' | target/stdlib-work/look-words --near app pa
```

prints `ap<TAB>apt` and `banana<TAB>` (no word follows the `pa` family).

## Commands

| Command | Output, in operand order |
| --- | --- |
| `look_words [--] PREFIX...` | Every stored word starting with PREFIX, sorted, one per line |
| `look_words --count PREFIX...` | `COUNT<TAB>PREFIX` |
| `look_words --near PREFIX...` | `BEFORE<TAB>AFTER`: the last word ordered before the PREFIX family and the first after it; a field is empty when no such word exists |
| `look_words --between LOW HIGH` | Every stored word w with LOW <= w <= HIGH |

Only the first argument can be an option; `--` lets a first prefix start with
`-`. A first argument starting with `-` that is not one of the four forms is a
usage error. The empty prefix matches every word.

Words are maximal runs of bytes other than space, TAB, LF, VT, FF and CR, so
NUL and non-ASCII whitespace are word content. Each distinct word is stored
once as a borrowed Text key of the single input owner; nothing is copied per
word. Order and prefix matching are exact unsigned bytes, with no case
folding, normalization or locale collation.

## Limits and statuses

| Status | Cause |
| --- | --- |
| 0 | Success |
| 2 | Usage error, invalid UTF-8 in an operand or in stdin, `--between` with HIGH < LOW, more than 256 arguments or 65,536 argument bytes, more than 1 MiB or 16,384 reads of input, more than 65,536 distinct words, or more than 8 MiB of output |
| 3 | Unreadable stdin or a failed write (SIGPIPE is ignored, so a closed pipe is EPIPE) |
| 4 | Allocation failure |

Arguments are checked before stdin is read. All validation, indexing and a
complete dry-run sizing pass of the output precede the first write, so every
status other than 0 and 3 from a write produces no output. A write failure can
leave a published prefix. Output is staged through 1 KiB of scratch; at most
131,072 write calls are made. Owners are released in dependency order: the
word set and operand vector, then the input, then the argument snapshot.

## Evidence

`tests/stdlib_look_words_execution.rs` registers four groups driven by
`tests/fixtures/stdlib_execution/look_words/oracle.py`, whose reference is
Python's sorted bytes (no tree). No tracer runs; every process gets
RLIMIT_CORE 0. Results through the prebuilt `laniusc` on native Linux x86_64:

- **model** — 46 cases: fixed list/count/near/between cases, Unicode and
  combining sequences, NUL words, prefix chains, duplicates, `--`, 24 seeded
  mixtures and a 40,000-word reversed input. Exact stdout and status. 1.4 s.
- **admission** — 22 cases: missing operands, unknown options, wrong
  `--between` arity and order, invalid/truncated/overlong UTF-8 operands and
  inputs, and both argument caps at and one over the limit. 0.15 s.
- **limits** — 6 cases: input at 1 MiB and one byte over, 65,536 and 65,537
  distinct words, and output at exactly 8 MiB and over it (rejected before any
  write). 2.3 s.
- **faults** — 52 cases: closed stdout and /dev/full (status 3), a directory
  as stdin (3), usage errors before an unreadable stdin (2), and a 48-step
  address-space sweep from 1 MiB in 128 KiB steps. With RLIMIT_AS, 30 runs
  reach an allocation failure and exit 4 with no output; every larger limit
  succeeds with the exact reference output. 10.5 s.

The registered test type-checks; its test binary was not built here. Indexing
60,000 distinct seven-byte words takes 0.94 s natively. Most of that time is
AVL search over Text keys. A first version took 4.3 s; making
`Text.compare` a direct byte loop brought it to 1.18 s, and dropping a
redundant membership search per word to 0.94 s.
