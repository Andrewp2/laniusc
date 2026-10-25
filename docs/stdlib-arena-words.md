# Arena-backed word counting

`sample_programs/library/arena_words.lani` is an executable integration program
for `alloc::arena`, `alloc::tree_map`, reusable vectors, CLI arguments and native
streams. It runs on x86_64 Linux through the GPU compiler's native output.
GPU kernel execution has not been verified.

## Program contract

Read stdin in 1024-byte chunks. Words are nonempty runs separated by exactly
ASCII HT, LF, VT, FF, CR and space (bytes 9–13 and 32). NUL, invalid UTF-8 and all
other bytes belong to words. Comparisons use unsigned byte order, with a shorter
prefix before a longer word. Case is significant.

The program reuses one vector for the current word. On a first occurrence it
copies the bytes into the arena and stores that stable view in an ordered map.
On a duplicate it increments the `u64` count using the stored key; the map never
retains a view into the reusable buffer. Counts check overflow before addition.

After EOF, all input and resource limits must pass. A first sorted pass measures
the complete output before any stdout write. A second emits decimal count,
TAB, the raw word and LF. Because delimiters cannot occur inside words, each row
has one TAB separator and one LF terminator even for binary input. Output uses
4096 bytes of stack buffering and creates no new heap owners.

For input `pear apple pear`, output is:

```text
1	apple
2	pear
```

## Limits and failures

| Option | Default | Accepted range |
| --- | --- | --- |
| `--max-input-bytes N` | 16777216 | 0–1073741824 |
| `--max-word-bytes N` | 65536 | 0–1048576 |
| `--max-unique N` | 100000 | 0–1000000 |
| `--arena-bytes N` | 67108864 | 0–1073741824 |
| `--max-output-bytes N` | 33554432 | 0–1073741824 |

Values are unsigned decimal. Repeated options use the last value; operands are
rejected. `--help`/`-h` prints usage after argument validation. Argument snapshots
allow at most 32 arguments and 8192 total bytes. Arena retained bytes include
chunk headers and alignment padding; map and reusable-vector storage are
separate. Arena chunks normally have a 4096-byte payload, and a larger word
can request a larger chunk. Input may be read up to one chunk beyond its limit
to detect excess data; it is never emitted or retained as a complete input.

Exit 2 reports invalid arguments, resource limits or count overflow; exit 3
reports I/O failure; exit 4 reports allocation failure. Each failure attempts a
short stderr diagnostic. Invalid input, resource limits, allocation failure and
read failure leave stdout empty. An output I/O failure may leave a prefix.
Interrupted reads/writes retry. Other errors, including would-block and a write
that makes zero progress, exit 3.

All paths destroy the reusable vector and map before destroying arena storage.
Map keys borrow arena data throughout sorting and output; resetting or freeing
the arena earlier would invalidate them. No automatic destructor or enforced
lifetime is assumed.

## Storage boundary

The program uses `alloc::arena::copy_slice<u8>(arena, word.as_view())` for each
new key and borrows its returned stable byte view. The local
`Key { bytes: View<u8> }` implements the standard comparison traits. This
exercises a typed arena allocation inside a real generic map consumer. Arena
implementation limits and remaining compiler dependencies are documented with
the arena module.

## Executable evidence

`tests/stdlib_arena_words_execution.rs` contains focused native execution tests
for binary words, every whitespace delimiter, chunk-spanning words, empty input,
20,000 distinct keys, duplicate updates, exact limits and a Python byte-counter
reference. Failure tests deny every observed allocation, read and write in
turn, check that every successful allocation is released, and retry interrupted
I/O. A repeated-input check denies all allocations after the first vocabulary
has been processed. The 33-byte arena check accepts 20,000 occurrences of the
same one-byte key and rejects a second distinct key, exercising the promise to
retain each distinct key once.

Run the focused tests with:

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR=/home/andrew-peterson/code/laniusc/target/stdlib-build \
  CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test stdlib_arena_words_execution
```
