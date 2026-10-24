# index-words

[`sample_programs/library/index_words.lani`](../sample_programs/library/index_words.lani)
indexes unique UTF-8 stdin words by their original one-based positions. It
writes rows in byte lexicographic word order, with decimal position, TAB, word,
and LF. Any duplicate rejects the entire index with status 8 and empty stdout.
All application behavior is Lanius.

Accepted on **2026-10-24** for x86_64 Linux native execution of an ELF built
through the GPU compiler. One strict ELF passed 65 native cases, including
denial of all 12 observed allocation positions. This is functional acceptance;
the application executes on the CPU and no throughput result is claimed.

## Build and use

With the compiler binary built, from the repository root:

```sh
mkdir -p target/stdlib-work/index-words
target/stdlib-build/debug/laniusc --stdlib-root stdlib --emit x86_64 \
  sample_programs/library/index_words.lani \
  -o target/stdlib-work/index-words/index-words
printf 'pear apple banana\n' | target/stdlib-work/index-words/index-words
```

The output is exactly `2\tapple\n3\tbanana\n1\tpear\n`. There are no options or
arguments. Extra arguments return status 2 before input allocation or reads.
Empty input or input containing only delimiters produces empty output.

## Input, equality, and order

The input byte limit is **1,048,576**, including delimiters. One owned buffer
reserves that full bound before reading. The existing stream-copy adapter uses
1,024 packed stack bytes and checks actual EOF even when the input fills the
buffer exactly. Excess input returns status 7 with empty stdout; detecting it
may consume up to 1,024 extra bytes without appending them. Interrupted reads
are retried; other read errors return status 3. There is no elapsed-time bound
for host I/O.

The complete bounded input must be valid UTF-8 before any word is indexed.
Invalid UTF-8 returns status 6 with empty stdout, including when an earlier
word would be a duplicate. A read failure or excess input also precedes word
processing and publishes nothing.

Words split only at the six ASCII whitespace bytes: HT, LF, VT, FF, CR, and
space. Non-ASCII whitespace and NUL remain word bytes. There is no comment
syntax, quoting, case folding, Unicode normalization, or locale collation.
Positions count nonempty words starting at one, rather than bytes or lines.

`Text` compares unsigned UTF-8 bytes lexicographically, with a shorter equal
prefix first. Equality is exact byte equality. Distinct spellings such as a
composed character and its decomposed sequence remain distinct keys. A
duplicate at any position, including a nonadjacent duplicate, returns status
8 without printing an accepted prefix or a replacement entry.

## Real iterator transfer and ownership

The application uses the borrowed chain:

```text
Text.split_ascii_whitespace()
  -> enumerate_from(..., 1)
  -> map(IndexEntry: Pair<u64,Text> -> tree_map::Entry<Text,u64>)
  -> try_transfer_up_to(..., TreeMap<Text,u64>, 1048577)
```

The concrete source is `SplitAsciiWhitespace`; Enumerate and Map remain live
until transfer finishes. The sink is the real
`TrySink<Entry<Text,u64>,tree_map::SinkError>` implementation. It rejects an
existing key as `SinkError::Duplicate` before allocation or replacement, and
wraps storage failures as `SinkError::Storage(Error)`. The rejected source
entry has been consumed and is returned in `TransferError` alongside the
accepted count. The app then cleans up and exits; it does not resume transfer.

Every word occupies at least one input byte. The quota of 1,048,577 therefore
leaves room for the transfer's actual None probe, observing source exhaustion
in one pass. Every one-based position fits u64. Successful collection requires
both an exhausted report and agreement between the accepted count and map
length. See the [collection sink guide](stdlib-iterator-collection-sinks.md)
for unique rejection and `SinkError`, the
[transfer guide](stdlib-iterator-transfer.md) for cursor consumption, and the
[ordered map guide](stdlib-tree-map.md) for storage and ownership.

The input buffer owns every key's bytes. Map nodes contain shallow `Text`
aliases and numeric positions; they do not own nested allocations. Map growth
uses typed node relocation, releases each superseded allocation, and preserves
the live input owner. On duplicate, storage failure, defensive count failure,
success, and every output error, the application destroys the map before
destroying the input buffer. Output cursors finish before the map is destroyed.

Collection and validation finish before publication. An ordered map cursor
then emits each decimal position and TAB, the word, and LF through checked
`write_all` calls. Decimal formatting uses packed stack storage. Publication
does not allocate. Short writes advance to the remaining bytes and Interrupted
writes retry. A later output error can leave a prefix, including a position
without a word or a word without LF. Stderr is unused.

Stdin and stdout remain borrowed descriptors. Main installs process-wide
SIGPIPE Ignore before allocation, allowing an actual closed stdout pipe to
report EPIPE and reach owner cleanup. The byte cap bounds word count and
positions; AVL map insertion takes O(log n) key comparisons and comparisons
can inspect long common prefixes. The bound does not promise a throughput or
latency target.

| Status | Meaning |
| --- | --- |
| 0 | Every indexed position, word, and LF was written |
| 2 | Unexpected command arguments |
| 3 | Signal setup, host input/output, or argument-count host error |
| 4 | Input reservation or map storage allocation failure |
| 6 | Invalid UTF-8 anywhere in the bounded input |
| 7 | Input limit, map storage capacity, or defensive transfer-count failure |
| 8 | Duplicate word |

## Focused test and accepted evidence

[`tests/stdlib_index_words_execution.rs`](../tests/stdlib_index_words_execution.rs)
defines `index_words_unique_positions_transfer_and_exact_failure_cleanup`. It
compiled the real application once through the production stdlib root, passed
the unchanged shared strict ELF/jump checker, and reused that executable.
Every native process has a five-second timeout and one-second
forced-termination grace.

The independent host oracle validates the entire UTF-8 input, splits byte
slices at exactly the six ASCII delimiters, and records original positions in
a Rust `BTreeMap`. It rejects repeated keys and compares the complete ordered,
TAB/LF-framed output. The 53 fixed native cases cover:

- Twenty byte-order and UTF-8 cases: empty/blank input, positions, case and
  prefix order, six delimiters, NUL, non-ASCII whitespace, Unicode without
  normalization, malformed encodings, and invalid UTF-8 after a duplicate.
- Six adjacent/nonadjacent duplicates, four chunk/input-boundary cases, and a
  unique four-word prefix compared with two duplicate extensions. The duplicate
  extensions must not add an allocation attempt.
- A 2,048-key reverse workload, a 4,096-key permutation, and a late duplicate
  after that full permutation. Original positions must survive ordered output;
  the late duplicate must publish nothing and add no allocation attempt.
- A small successful baseline, five read faults, eight write faults, real
  EPIPE, signal setup failure before allocation, and extra arguments without
  stdin reads.

The large permutation records every observed mmap attempt; the driver then
denies each ordinal independently with reached ENOMEM. These additional native
processes must return status 4 with empty stdout, including failures after a
partially accepted map prefix. The ledger matches allocation address, identity,
and requested length, rejecting unknown, double, or wrong-length releases and
mremap. Every successful mapping must be released exactly once, and the first
input mapping must be released last, including when an address is reused. It
assumes neither a physical Text/Node width nor a growth factor. Publication
must not allocate.

Read faults cover EIO before and after transfer, EAGAIN, an invalid count of
1,025 for a 1,024-byte request, and Interrupted retry. Write faults cover an
empty prefix, a position-only prefix, a word without LF, a complete first row,
EAGAIN, zero progress, retry, and a synthetic short write. The synthetic short
write suppresses the first host write while reporting one byte; the test
expects the actual remaining suffix once. The closed-pipe case uses real
EPIPE rather than an injected result.

The serialized acceptance run used source checkpoint
`61284e3a58debbb74615631cf8fdd29e04b4e0d0` plus five collection sink source
additions. This milestone changed no compiler, shader, or core protocol
sources. The application body and integration driver stayed frozen after the
gate; only this guide and the application's admission comment were updated.

| Evidence | Accepted result |
| --- | --- |
| Fresh Rust test build | 1.73 s for the sink faults, sink bounds, and application targets together; not an isolated application build |
| Application execution | One strict ELF, 65 native cases, one Rust test passed in 9.15 s |
| Allocation faults | All 12 observed allocation positions independently denied and exactly cleaned up |
| Build log | `target/stdlib-work/iterator-collection-sinks-admission/build-faults-bounds-application.log` |
| Runtime log | `target/stdlib-work/iterator-collection-sinks-admission/application.log` |

The 65 processes comprise the 53 fixed cases described above plus 12 reached
allocation denials. The log paths are ignored local artifacts.

The accepted runtime command, from the repository root, was:

```sh
timeout --kill-after=2s 100s \
  flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s \
  env RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  target/stdlib-build/debug/deps/stdlib_index_words_execution-cfcdf43f6a84744e \
  --nocapture
```

This evidence covers the tested x86_64 Linux target and fault model. Injected
allocation failures verify reached attempts and owner cleanup; synthetic write
results describe the bytes the host actually received, as explained above.
