# Word concordance

`sample_programs/library/word_concordance.lani` reads bounded UTF-8 stdin and
prints each distinct word with every zero-based byte position where it starts.
Rows are sorted by the word's UTF-8 bytes. Each row is:

```text
word<TAB>position,position,...<LF>
```

A word is a nonempty run separated by ASCII space, TAB, CR, LF, vertical TAB
or form feed. Unicode whitespace such as NBSP remains word content. Case,
punctuation, NUL and other non-separator scalars are preserved. There is no
case folding, escaping or Unicode normalization. Positions count original
input bytes, including separators, rather than Unicode scalars or columns.
Empty input and whitespace-only input produce no output.

## Build and examples

From the repository root with the compiler binary built:

```sh
mkdir -p target/stdlib-work
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  target/stdlib-build/debug/laniusc --stdlib-root stdlib --source-root extended \
  --emit x86_64 sample_programs/library/word_concordance.lani \
  -o target/stdlib-work/word_concordance
printf 'pear apple pear\n' | \
  timeout --kill-after=2s 10s target/stdlib-work/word_concordance
```

The exact output is 18 bytes, including both final LF bytes:

```text
apple	5
pear	0,11
```

Multibyte text makes the byte-position convention visible:

```sh
printf 'é a é 🙂 a\n' | \
  timeout --kill-after=2s 10s target/stdlib-work/word_concordance
```

The exact output is 21 bytes:

```text
a	3,13
é	0,5
🙂	8
```

The standalone compiler command exited 0 with an empty
`target/stdlib-work/map-update-concordance-cli-build.log`. Both examples ran
from that artifact, returned 0, left stderr empty and matched the exact bytes;
their receipt is `target/stdlib-work/map-update-concordance-cli-examples.log`.

## Limits and failures

| Bound | Value |
| --- | ---: |
| Input bytes, including separators | 1,048,576 |
| Direct stdin read attempts | 16,384 |
| Distinct words | 65,536 |
| Defensive output preflight cap | 8,388,608 bytes |
| Global direct stdout write attempts | 131,072 |
| Output scratch | 1,024 bytes |
| Decimal scratch | 20 bytes |

Input at its byte cap receives a real one-byte EOF/excess probe. Read attempts
include EOF, the probe and Interrupted. The complete input must pass UTF-8
validation before grouping. Every word must fit the distinct-word bound, and
the complete output length is computed before stdout begins.

The output cap is defensive under this input profile. With `N` input bytes,
there are at most `ceil(N/2)` word occurrences. Distinct key bytes total at
most `N`; each position needs at most seven decimal digits, and allowing three
punctuation bytes per occurrence is conservative. Output is therefore bounded
by `N + 10*ceil(N/2)`, at most 6 MiB for admitted input. The 8 MiB rejection
cannot be reached through this CLI, and the tests do not claim to exercise it.

The program takes no arguments: even `--`, `-h` and `--help` reject before
input collection. The empty argument snapshot is allocation-free. SIGPIPE is
explicitly ignored before argument processing; setup failure returns silent
status 3. Standard descriptors are borrowed and never closed by the program.

| Status | Meaning |
| --- | --- |
| 0 | Complete sorted output, including empty output |
| 2 | Arguments, invalid UTF-8, limits or an exhausted read/write attempt budget |
| 3 | I/O failure, WouldBlock, zero/invalid write progress or failed SIGPIPE setup |
| 4 | Allocation failure |

All errors are quiet. Preflight errors leave stdout empty. After publication
begins, a write failure or exhausted budget may leave a confirmed output
prefix. Every direct write, including Interrupted, spends the same global
allowance across all buffered chunks. Only Interrupted is retried. There is no
diagnostic that can mask the original status, and empty output succeeds even
if stdout is a closed pipe. Call quotas do not bound provider blocking time.

## Map updates and ownership

The input collector adopts its byte Vec as a String after UTF-8 validation.
`TreeMap<Text,Vec<u64>>` stores borrowed input words and independent owned
position vectors. New keys receive a newly allocated vector. Existing keys
use `update_value` with a mapper that appends one position and returns both the
latest Vec descriptor and its `Result`, including after allocation failure.
The map retains the original representative key and stores the returned value
descriptor before the caller examines that result.

Keys borrow unchanged input until every map operation and output cursor ends.
One fixed output scratch batches words, separators and decimal positions;
there is no output String or per-row owner. Cleanup releases each position
vector once, then map storage, then the input owner. This ordering applies to
success, indexing failure, preflight rejection and output failure. These are
manual ownership rules; no automatic borrow checking is claimed.

## Verification scope

`tests/stdlib_word_concordance_execution.rs` runs the real program against an
independent model using byte-regex word boundaries, exact byte offsets and
byte-sorted keys. It checks complete outputs, real input-cap probes,
65,536/65,537 distinct words, large position-list expansion, reached allocation
failures, I/O faults and confirmed prefixes under exhausted budgets.

The resource ledger accounts for full allocation addresses/extents. It keeps
the final input mapping live through publication and requires it to be the
final mapping released. It rejects allocations after the first write and
publication-phase releases followed by another write. Indexing legitimately
allocates/releases storage before publication; the ledger does not separately
identify each nested owner in that phase. Its scope is the nine filtered
syscalls `read`, `write`, `mmap`, `munmap`, `mremap`, `brk`, `openat`, `close`
and `rt_sigaction`; it does not observe every possible host effect. Direct map
resource tests separately check callback and map-storage ownership.

Host-only corpus/ledger controls pass. All four focused native gates passed:
103 native process cases, including 38 reached allocation failures.

| Gate | Native cases | Test time | Separate build time |
| --- | ---: | ---: | ---: |
| Complete sorted output | 28 | 7.12 s | 1.68 s |
| Arguments/UTF-8 admission | 12 | 7.50 s | 0.19 s |
| Input/distinct-word limits | 6 | 42.56 s | 0.19 s |
| Allocation/I/O/attempt failures | 57 | 23.11 s | 0.19 s |

Their logs are `target/stdlib-work/map-update-concordance-{model,admission,limits,io}.log`.
Full receipts, retained evidence directories and frozen source hashes are
tracked in the fixture README. The two standalone examples are separate from
these 103 test cases. Accepted execution is Linux x86_64 CPU output from the
GPU compiler. It does not establish user-program GPU execution or other targets.
