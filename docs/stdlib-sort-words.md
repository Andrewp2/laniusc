# sort-words

[`sample_programs/library/sort_words.lani`](../sample_programs/library/sort_words.lani)
sorts UTF-8 stdin words in byte lexicographic order and writes each word followed
by LF. It collects the real `Text.split_ascii_whitespace()` cursor through
`core::iter::try_transfer_up_to` into `alloc::vec::Vec<Text>`, then uses the
existing `Text` Ord implementation and Vec's in-place sort. Duplicates remain.
Application behavior is Lanius.

Accepted on **2026-10-24** for x86_64 Linux native execution of an ELF built
through the GPU compiler. One strict ELF passed 51 native cases, including
denial of all 12 observed allocation positions. This is functional acceptance;
the application executes on the CPU and no throughput result is claimed.

## Build and use

With the compiler binary built, from the repository root:

```sh
mkdir -p target/stdlib-work/sort-words
target/stdlib-build/debug/laniusc --stdlib-root stdlib --emit x86_64 \
  sample_programs/library/sort_words.lani \
  -o target/stdlib-work/sort-words/sort-words
printf 'pear apple pear\n' | target/stdlib-work/sort-words/sort-words
```

The output is exactly `apple\npear\npear\n`. There are no arguments or options;
extra arguments return status 2 before input allocation or reads. Empty input
or input containing only delimiters produces empty output.

## Input, words, and order

The byte limit is **1,048,576**, including all delimiters. One owned input
buffer reserves the full bound before reading. The existing stream-copy
adapter uses 1,024 packed stack bytes and reads until actual EOF. At the bound,
it still checks EOF. Excess input returns status 7 without output; detecting
it may consume up to 1,024 extra bytes, which are not appended to the buffer.
Interrupted reads are retried; other read errors return status 3.

The complete bounded input must be valid UTF-8 before splitting, collection,
sorting, or output. Invalid UTF-8 anywhere returns status 6 with empty stdout.
Words split only at HT, LF, VT, FF, CR, and ASCII space. Non-ASCII whitespace
and NUL remain ordinary word bytes. No case folding, Unicode normalization,
locale collation, comment syntax, or quoting is applied.

Text compares its unsigned UTF-8 bytes lexicographically. A shorter equal
prefix sorts first. The in-place heapsort is not stable, but equal byte words
are indistinguishable in output and all duplicates are preserved. It uses
O(n log n) comparisons and no sorting allocation; a comparison can inspect
the shared prefix of its two words.

## Transfer and ownership

The actual `SplitAsciiWhitespace` source and Vec sink are passed by borrow to
`try_transfer_up_to`, with error type `alloc::vec::Error`. Its quota is
1,048,577. Every word occupies an input byte, so this strict larger quota
always leaves room to observe the source's None. The program requires an
exhausted transfer and agreement between its accepted count and Vec length.
A sink refusal preserves the accepted prefix and returns the rejected shallow
Text item; the application returns an allocation/limit error after cleanup.
See the [bounded iterator transfer guide](stdlib-iterator-transfer.md) for the
library contract.

The word Vec grows on demand. Each growth uses typed element relocation, and
the old allocation is released after its Text records have been copied. The
input buffer owns the bytes; every collected Text borrows them. The application
destroys the word Vec before destroying the input buffer on transfer failure,
defensive count failure, and every output outcome. Text entries have no nested
allocation to release. Stack cursors and transfer/error records finish before
the input owner is destroyed.

Collection and sorting finish before the first output call. Allocation or
input errors therefore publish no words. Output streams checked word bytes
and a checked LF using `write_all`; it handles short writes and retries
Interrupted. A later output error can leave a prefix, including a word without
its final LF. No allocation happens during publication. Stderr is unused.

Input/output descriptors remain borrowed and are not closed. Main installs
process-wide SIGPIPE Ignore before allocation so an actual closed stdout pipe
can report EPIPE and reach both owner cleanups. There is no elapsed-time bound
for host I/O. The byte cap bounds collection, word count, and output bytes
(at most input bytes plus one), while long common word prefixes can increase
comparison work.

| Status | Meaning |
| --- | --- |
| 0 | Every collected word and LF was written |
| 2 | Unexpected command arguments |
| 3 | Signal setup, host input/output, or argument-count host error |
| 4 | Input reservation or Vec transfer allocation failure |
| 6 | Invalid UTF-8 anywhere in the bounded input |
| 7 | Input limit, collection capacity, or defensive transfer-count failure |

## Focused test and accepted evidence

[`tests/stdlib_sort_words_execution.rs`](../tests/stdlib_sort_words_execution.rs)
defines `sort_words_byte_order_transfer_and_exact_failure_cleanup`. It compiled
the real application once through the production stdlib root, passed the
unchanged shared strict ELF/jump checker, and reused that executable. Each
native process has a five-second timeout and one-second forced-termination
grace.

The independent host oracle validates UTF-8, splits byte slices using the six
ASCII delimiters, sorts those slices with Rust byte lexicographic ordering,
and compares complete newline-framed output. Cases cover empty/blank input,
duplicates, case and prefix order, all delimiters, NUL, non-ASCII whitespace,
Unicode without normalization, malformed UTF-8, cross-chunk sequences, exact
and exceeded input bounds, and a 4,096-word workload with repeated words.

The large workload's baseline records every observed mmap attempt. Each
ordinal is then independently denied with reached ENOMEM, checking status 4,
empty output, and complete cleanup. The ledger matches live allocation
addresses and requested lengths, rejects unknown/double/wrong releases and
mremap, and requires the first input mapping to be released last. It assumes
neither a physical Text width nor a Vec growth factor. Publication must not
allocate.

Read faults cover EIO before/after input transfer, EAGAIN, an invalid count,
and Interrupted retry. Output faults cover empty and nonempty prefixes,
failure on a word's LF, EAGAIN, zero progress, retry, and a synthetic short
write. The short-write injection suppresses the first host write while
reporting one byte, so the test expects the real remaining suffix once.
An actual closed pipe reaches EPIPE under Ignore; signal setup failure must
precede all allocations and reads. Extra arguments must not read stdin.

The serialized acceptance run used source checkpoint
`52872260ba2f159e6a299fea7d021023c51f46dd` plus the four current library source
edits. This milestone changed no compiler or shader sources. The application
body and integration driver were unchanged after the gate; only this guide and
the application's admission comment were updated.

| Evidence | Accepted result |
| --- | --- |
| Fresh Rust test build | 1.32 s for the transfer, slice iterator regression, and application targets together; not an isolated application build |
| Application execution | One strict ELF, 51 native cases, one Rust test passed in 7.24 s |
| Allocation faults | All 12 observed allocation positions independently denied and exactly cleaned up |
| Build log | `target/stdlib-work/iterator-transfer-admission/build-model-application.log` |
| Runtime log | `target/stdlib-work/iterator-transfer-admission/application.log` |

The 51 processes comprise 18 byte-order/UTF-8 cases, four chunk/input-boundary
cases, the large and small baselines, 12 allocation denials, five read faults,
seven write faults, real EPIPE, signal setup failure, and unexpected arguments.
The log paths above are ignored local artifacts.

The accepted runtime command, from the repository root, was:

```sh
timeout --kill-after=2s 100s \
  flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s \
  env RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  target/stdlib-build/debug/deps/stdlib_sort_words_execution-731b2d8878d3ebfa \
  --nocapture
```

This evidence covers the tested x86_64 Linux target and fault model. Injected
allocation failures verify reached attempts and owner cleanup; synthetic write
results describe the bytes the host actually received, as explained above.
