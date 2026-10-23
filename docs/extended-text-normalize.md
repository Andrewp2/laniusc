# Text normalization program

[`sample_programs/library/text_normalize.lani`](../sample_programs/library/text_normalize.lani)
reads bounded UTF-8 stdin, normalizes the whole text with Unicode 17.0.0, and
writes the normalized bytes to stdout. NFC is the default. NUL, line endings,
noncharacters, private-use characters and supplementary scalars are ordinary
input; no terminator or extra newline is added. Combining sequences can span
host read boundaries.

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --stdlib-root stdlib --source-root extended \
  sample_programs/library/text_normalize.lani -o target/stdlib-work/text-normalize
printf 'A\314\212\n' | timeout 10s target/stdlib-work/text-normalize --stats
# stdout: Å followed by newline
# stderr: bytes=3 scalars=2 graphemes=2
```

## Options and limits

| Option | Default | Meaning |
| --- | --- | --- |
| `--form nfc\|nfd\|nfkc\|nfkd` | `nfc` | Exact normalization form; lowercase spellings only. |
| `--stats` | off | Report output byte, scalar and default extended grapheme counts on stderr. |
| `--max-input-bytes N` | 4,194,304 | Maximum input bytes. |
| `--max-output-bytes N` | 16,777,216 | Maximum normalized output bytes, checked before output allocation. |
| `--max-scratch-scalars N` | 4,194,304 | Maximum `u32` elements for full decomposition scratch. |
| `--max-work N` | 100,000,000 | Work budget for **each** normalization phase. |
| `--help`, `-h` | off | Print usage without consuming stdin. |

Numeric options accept unsigned decimal digits, including zero. Byte and scratch
limits are capped at 67,108,864; work is capped at 1,000,000,000. There are no
operands. Argument capture allows at most 32 options/value tokens and 8,192 raw
argument bytes; these are host arguments after shell splitting. The help option
does not suppress invalid arguments elsewhere in the invocation.

The work limit applies independently to `scratch_len`, `measure` and
`normalize_into`. It is not a cumulative process budget. Input reading, UTF-8
validation, initialization, host writes and the optional linear grapheme scan
are bounded by byte/scalar limits rather than charged against that counter.
Canonical ordering can be quadratic on hostile combining runs; normalization
charges each ordering comparison and fails explicitly when its budget is spent.

Scratch is counted in elements, **not bytes**. The current native layout stores
each `u32` array element in an eight-byte slot, so the default scratch cap allows
up to 32 MiB of scratch storage. The input buffer may reserve geometric capacity;
output and scratch reserve their measured capacities before initialization.
Owners are distinct and are released on every returned outcome.

## Failure and output behavior

| Exit | Meaning |
| --- | --- |
| 0 | Success or help. |
| 2 | Invalid arguments, malformed UTF-8, or input/output/scratch/work limit. |
| 3 | Host input/output failure, including failure to write a diagnostic/statistics. |
| 4 | Allocation failure. |

Errors attempt a stderr diagnostic with a reason and stage. Invalid UTF-8
identifies the malformed sequence's initial byte relative to stdin. Encoding
and resource errors happen before stdout is written. A later host write error
may leave a prefix on stdout. Statistics follow successful output; a failed
statistics write returns status 3 even when normalized output is already complete.
`EINTR` is retried, short writes advance correctly, and zero writes fail explicitly.
No replacement characters or silent truncation are used.

## Implementation and evidence

The program composes `ext::cli`, owned argument snapshots, bounded `alloc::io`,
stream copying, checked `core::text`, owned vectors, the
[normalization engine](extended-unicode-normalize.md),
[grapheme segmentation](extended-unicode-graphemes.md) and `core::fmt`.
All production behavior is Lanius. Python is used only as a test oracle over
characters assigned before Unicode 14; the engine's independent complete Unicode
17 conformance evidence is recorded in its own guide.

The three executable test groups in `tests/extended_text_normalize_execution.rs`
cover all four forms and idempotence, mixed Unicode/NUL/CRLF, exact limits,
malformed UTF-8 and read-boundary cases, arguments, allocation denial at every
observed allocation, host read/write errors, interruption, short/zero writes,
failed diagnostics and `/dev/full`. The fault runs reconcile every successful
mapping with its unmapping.

A seeded 3,000-sequence workload contains 293,745 input bytes. Native process
measurements on this machine were NFC 1,302 ms / 295,213 output bytes; NFD 814 ms /
342,174 bytes; NFKC 1,403 ms / 279,542 bytes; NFKD 886 ms / 327,348 bytes. The timer
includes process/file setup and I/O and excludes compilation. These observations
are not a comparison with optimized host Unicode libraries.

Verified target: **native x86_64 Linux**, emitted by the GPU compiler. User-program
GPU execution, other native targets, streaming normalization with retained state,
full contextual casing and locale-sensitive collation remain separate work.
