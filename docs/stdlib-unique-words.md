# unique-words

[`sample_programs/library/unique_words.lani`](../sample_programs/library/unique_words.lani)
reads UTF-8 stdin words, removes exact duplicates, and writes the unique words
in byte lexicographic order, followed by LF. It tokenizes incrementally and
owns independent Strings in a sorted set. All application behavior is Lanius.

Accepted on **2026-10-24** for x86_64 Linux native execution of an ELF built
through the GPU compiler. One strict ELF passed 126 native cases, including
all 79 observed representative allocation denials. The application executes
on the CPU. This is functional acceptance; no throughput result is claimed.
After switching publication to the owning TreeSet cursor, the same 126-case
gate passes in 8.15 seconds, including all 79 representative allocation
denials. The current receipt is
`target/stdlib-work/unique-words-owning-tree-execution.log`.

## Build and use

With the compiler binary built, from the repository root:

```sh
mkdir -p target/stdlib-work/unique-words
target/stdlib-build/debug/laniusc --stdlib-root stdlib --emit x86_64 \
  sample_programs/library/unique_words.lani \
  -o target/stdlib-work/unique-words/unique-words
printf 'pear apple pear banana\n' | target/stdlib-work/unique-words/unique-words
```

The output is exactly `apple\nbanana\npear\n`. There are no arguments or
options. Extra arguments return status 2 before allocation or stdin reads.
Empty input or input containing only delimiters produces empty output.

## Streaming input and validation

The total input limit is **1,048,576 bytes**, including delimiters. Reads use
packed 1,024-byte stack scratch and request at most the remaining byte budget.
At exactly the limit, the application makes an actual **one-byte EOF probe**.
Zero bytes confirms EOF; one byte returns status 7 without storing it or
publishing output. Detecting excess input therefore consumes at most one extra
byte. Interrupted reads retry; other input errors return status 3. Host I/O
has no elapsed-time bound.

Tokenization recognizes exactly six ASCII delimiter bytes: HT, LF, VT, FF,
CR, and space. A raw `alloc::io::Buffer` accumulates spans of the current word
across read boundaries, including a UTF-8 sequence split between chunks. At a
delimiter or EOF, `alloc::string::from_utf8` validates the complete nonempty
token and copies it to independent owned storage. The raw buffer is cleared
for reuse. Empty spans create no word.

ASCII delimiters are valid UTF-8 and cannot occur inside a multibyte UTF-8
sequence, so validating every complete token validates the entire successful
input. An invalid token returns status 6 with empty stdout. It can stop
reading immediately; errors do not promise to consume the remaining stream
or choose a later error over the first encountered failure. EOF completes and
validates the last word even when it has no trailing delimiter.

The application retains no complete input buffer. It keeps reusable token
storage, at most 64 pending owned words, and the unique owned words already in
the set. A single long word can use the full input bound. String records and
set nodes add storage overhead; the input byte limit is not a one-megabyte
heap limit. Token storage may grow and retain its capacity until collection
ends. Before publication, both token and batch storage are destroyed.

NUL and non-ASCII whitespace remain ordinary word bytes. There is no comment
syntax, quoting, case folding, Unicode normalization, or locale collation.
String order compares unsigned UTF-8 bytes lexicographically; a shorter equal
prefix sorts first. Exact byte duplicates collapse to one word. Composed and
decomposed spellings remain distinct when their bytes differ.

## Owning batches and transfer

The batch is a real `alloc::vec::Vec<alloc::string::String>`, reserved to 64
entries before stdin reads. Even an empty input can fail that reservation.
The application flushes a full batch, then flushes a partial batch after EOF:

```text
Vec<String>.take_iter()
  -> IntoIter<String>
  -> try_transfer_up_to(..., TreeSet<String>, 65)
```

`take_iter` empties and resets the actual Vec owner. The cursor owns its
backing and every unconsumed String. A successful unique set insertion takes
the yielded String's ownership. The transfer quota of 65 exceeds the batch
size, leaving room for an actual None probe and exhausted report in one pass.

The TreeSet unique sink preserves its stored representative on a duplicate
and returns the rejected independent String in `TransferError`. The app
explicitly destroys that String, then resumes transfer from the cursor's
remaining interval. Duplicates are successful deduplication, including those
within a batch, between batches, and at the end of input.

On a storage failure, the app destroys the rejected String, calls
`alloc::clone::destroy_vec_iter` to destroy all remaining cursor-owned Strings
front to back and free the cursor backing, then returns an allocation or
capacity error. After draining, the helper recovers the empty Vec through
`take_remaining`, checks that it is empty, and destroys that canonical owner.
The original batch Vec remains empty with capacity zero. The caller also
destroys the token buffer and drains all accepted set-owned Strings. The same
cursor cleanup protects a defensive non-exhausted report.

On successful exhaustion, `cursor.take_remaining()` returns an empty Vec with
the **same allocation and capacity**, disarming the cursor. Assigning it back
to the reset batch restores the backing for the next 64 words. There is no
per-batch backing allocation or implicit String destruction. Previously
consumed slots own nothing and are not destroyed again.

See the [collection sink guide](stdlib-iterator-collection-sinks.md),
[transfer guide](stdlib-iterator-transfer.md),
[owned sets guide](stdlib-owned-sets.md), and
[nested cleanup guide](stdlib-nested-clone.md) for the underlying contracts.

## Publication and cleanup

No output occurs before actual EOF, successful validation of every word, and
the final successful flush. Input, validation, limit, and collection allocation
failures therefore leave stdout empty. Stderr is unused.

Publication calls the sorted set's `take_iter()`, resetting the actual set to
empty with zero capacity. The [owning tree cursor](stdlib-owning-tree.md)
transfers each String in ascending order through the shared Iterator protocol.
The application checks `write_all` for the word bytes and LF, then destroys
that String. On either write error it destroys the current word and calls
`destroy_tree_set_iter` to release only the unconsumed keys and node storage.
The same helper releases empty backing after successful exhaustion. Collection
errors use the canonical deep set helper before ownership has transferred.
No allocation occurs during publication.

`write_all` advances after short writes and retries Interrupted. A later
output failure can leave a prefix, including a word without LF. Stdin and
stdout remain borrowed descriptors. Main installs process-wide SIGPIPE Ignore
before any allocation, allowing a closed stdout pipe to report EPIPE and reach
all explicit cleanup. There is no flush, close, or durability promise.

| Status | Meaning |
| --- | --- |
| 0 | Every sorted unique word and LF was written |
| 2 | Unexpected command arguments |
| 3 | Signal setup, host input/output, or argument-count host error |
| 4 | Batch, token, String, or set allocation failure |
| 6 | Invalid UTF-8 in a completed token |
| 7 | Input limit, storage capacity, or defensive transfer invariant failure |

## Focused test and accepted evidence

[`tests/stdlib_unique_words_execution.rs`](../tests/stdlib_unique_words_execution.rs)
defines `unique_words_streaming_owners_reuse_and_exact_failure_cleanup`. It
compiled the real application once through the production stdlib root, passed
the unchanged shared strict ELF/jump checker, and reused that ELF for every
native process. Each process has a five-second timeout and one-second
forced-termination grace.

The independent host oracle checks UTF-8, splits byte slices at the same six
specified ASCII bytes, and uses Rust's byte-key `BTreeSet` to deduplicate and
order them. It compares complete newline-framed output. The fixed 47 cases
are:

| Cases | Count |
| --- | ---: |
| Empty/blank input, exact duplicates, byte order, NUL, Unicode and malformed UTF-8 | 18 |
| Split UTF-8 and long words across chunks, invalid trailing sequence, exact/exceeded input bounds | 7 |
| One 64-word batch and three batches of the same word | 2 |
| Representative baseline, invalid token after accepted batches, and read failure before EOF | 3 |
| Separate 4,096-word correctness workload with duplicates across many batches | 1 |
| Small successful output-fault baseline | 1 |
| Read faults and retry | 5 |
| Write faults, zero progress, retry, and synthetic short write | 7 |
| Real EPIPE, signal setup failure, and unexpected arguments | 3 |
| Total fixed native processes | 47 |

The 70-word representative workload includes a 1,300-byte word, duplicate
positions inside and across batches, enough unique keys for set growth, and a
final partial batch. Its successful run records every observed allocation
attempt. The driver then denies **each representative ordinal** independently
with reached ENOMEM, requiring status 4, empty output, and exact cleanup. These
additional processes exercise token growth, String copies, set growth, and
fatal transfer while an owning cursor still has remaining items. The
4,096-word case is a separate correctness/scale case; it does not receive an
exhaustive allocation sweep.

The native case total is **47 plus the observed representative allocation
count**. The accepted run observed 79 representative positions, giving 126
native cases. The driver printed both counts after every case passed.

The allocation ledger matches each live allocation generation, address, and
requested length with exactly one release, tolerating address reuse after
release. It rejects unknown, duplicate, or wrong-length releases, mremap, and
allocation during publication. The first batch backing must survive all input
reads and be released before the first output attempt. No physical String or
node width is hardcoded.

The existing one-word case calibrates the allocation cost of independent
String creation against 64 identical words. The additional 128 words in the
three-batch case must have the same proportional cost, with no extra batch
backing allocation. Both runs require the same observed batch allocation
length. This checks reuse without assuming how many allocations construct a
String.

Success and every publication attempt require an observed final zero-byte
read. Exact-bound cases also check a one-byte final request, including the
actual one-byte over-limit result. Read faults include EIO before and after
partial ownership, EAGAIN, an invalid 1,025-byte result for a 1,024-byte request,
and Interrupted retry. Write faults check empty and nonempty prefixes, failure
on LF, EAGAIN, zero progress, Interrupted retry, and a synthetic short write.
The short-write injection suppresses the first host write while reporting one
byte, so the test expects the real remaining suffix once. The closed-pipe case
uses real EPIPE under Ignore. Signal setup failure must precede allocations
and reads; extra arguments must not allocate or read stdin.

### Admission history and source scope

The initial source used the payload pattern `InvalidUtf8(_)`, which the
compiler rejected as an unresolved `_` identifier. Naming that payload
`offset` removed that failure, matching the previously recorded
[payload-wildcard dependency](library-dependencies.md). The next attempt reached a replay
native-layout boundary in the original cleanup helper's chained
`try_finish().is_none()` path. The preserved reduction and controls are in the
[owning String application reproduction](../tests/fixtures/stdlib_compiler_state/owning_string_application/README.md).

The accepted helper drains the cursor, recovers its empty canonical Vec or
Deque owner with `take_remaining`, checks emptiness, and destroys that owner.
This keeps the public API and ownership contract. It required no compiler or
shader edits and no further application-body changes. The accepted source
base was `f867a59606127508110208986318bb5eaaa82192` plus the canonical cleanup
helper release, named payload correction, and driver EOF/reuse checks. The
application body and driver stayed frozen for that acceptance. The later
publication migration uses the owning TreeSet cursor and canonical deep cleanup;
the unchanged driver passes again with the current receipt above. That
migration introduces no compiler or runtime changes.

| Evidence | Accepted result |
| --- | --- |
| Fresh Rust driver build | 2.06 s for the owning iterator, nested clone, and application targets together; not an isolated application build |
| Application gate | One strict ELF, 126 native cases, one Rust test passed in 8.78 s |
| Representative allocation faults | All 79 observed positions independently denied and exactly cleaned up |
| Larger workload | 4,096 words, correctness/scale only |
| Build log | `target/stdlib-work/owning-iterators-admission/build-final.log` |
| Runtime log | `target/stdlib-work/owning-iterators-admission/unique-words.log` |

The log paths are ignored local artifacts. From the repository root, the exact
accepted serialized runtime command was:

```sh
RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  timeout --kill-after=2s 100s \
  flock -E75 -w35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s \
  target/stdlib-build/debug/deps/stdlib_unique_words_execution-e990b59b71be94b8 \
  unique_words_streaming_owners_reuse_and_exact_failure_cleanup \
  --exact --nocapture --test-threads=1 \
  > target/stdlib-work/owning-iterators-admission/unique-words.log 2>&1
```

This evidence covers the tested x86_64 Linux target and stated fault model.
Allocation denials verify reached attempts and explicit owner cleanup;
synthetic write results are checked against the bytes the host actually
received, as described above.
