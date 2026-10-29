# Bounded optional integer totals

`sample_programs/library/optional_sum.lani` reads optional signed integers
from stdin and writes their counts and checked total:

```sh
printf '7\n-\n-3\n' | optional_sum
```

Output is exactly:

```text
present,missing,sum
2,1,4
```

The program takes no operands. Only a sole `--help` or `-h` prints help
and bypasses stdin. Other arguments, repeated help and mixed options are
invalid. Argument capture admits at most one value and 64 total bytes,
excluding terminating NULs.

## Input grammar and arithmetic

Records are separated by ASCII LF. Each record contains either:

- Exactly `-`, meaning a missing value.
- A decimal i64 accepted by `core::decimal::parse_i64_range`: optional ASCII
  plus/minus, ASCII decimal digits and an exact representable signed value.
  Leading zeros and negative zero are allowed.

There is no whitespace trimming or CR removal. Spaces, CRLF, separators,
prefixes, non-ASCII bytes, sign-only numbers other than the missing marker,
and numbers outside the i64 range are invalid.

Empty input has zero records. A final nonempty record without LF is accepted.
One terminating LF adds no empty record; a leading LF, doubled LF or any
other empty record is invalid. Each record has at most 64 bytes excluding LF,
with at most 65536 records and 1048576 raw input bytes.

Present values are added in input order with `core::i64::checked_add`.
An intermediate overflow is an error even if a later value would cancel it.
Missing records increase only the missing count. Empty input therefore
produces the data row `0,0,0`.

## Public outcome composition

The application uses the public outcome operations for the three distinct
input states, rather than reproducing their variant conversion:

1. Missing is `None`; a parsed field is `Some(Result<i64, ParseError>)`.
2. `core::option::transpose_to_result` converts this to
   `Result<Option<i64>, ParseError>`.
3. The widened `core::result::or` keeps a successful optional payload and
   selects application error 2 after a decimal-parser error.
4. `core::option::transpose_to_option` restores the optional outer shape,
   preserving missing, valid and invalid states in the application error type.
5. For a present field, the widened `core::result::and` selects a proposed
   Summary only when parsing succeeded, while retaining a parse error
   otherwise. Its success payload changes from i64 to Summary.

The proposed Summary uses checked addition. An eager candidate may use the
safe zero fallback when a parser result is erroneous, but public `and`
retains that earlier error; the fallback can never turn invalid input into
an accepted zero. No candidate mutates the committed summary before selection.
All composed payloads are plain values, with no resource owners or callbacks.

## Validation, output and ownership

The program reads through actual EOF into one `alloc::io::Buffer` limited to
1048576 logical bytes. Only after EOF does it scan records, validate their
length/count/number grammar and compute the checked sum. A complete successful
summary is required before formatting or stdout. Thus malformed input, input
errors, allocation failures and overflow publish no stdout.

A fixed caller-backed 128-byte array stages the whole CSV using
`core::io::SliceWriter` and `core::decimal::format_i64`. No CSV field needs
quoting: the fixed header and decimal numbers have no commas, quotes or
line separators within a field. Encoding is unquoted CSV with ASCII commas,
LF record endings, no leading zeros in numbers, and no extra rows. Output is
at most 53 bytes.

The input owner starts without backing, grows through the existing bounded
byte-sink API and is explicitly destroyed before formatting/output, including
every failed validation path. No allocation occurs after EOF. The argument
snapshot has its own cleanup authority and is destroyed before main returns.
The ordinary no-argument snapshot needs no backing; help capture may allocate.
Output storage and its writer are borrowed stack values. Descriptor wrappers
borrow stdin/stdout, which the application does not close.

## Budgets and errors

| Resource | Bound |
| --- | ---: |
| Captured arguments / bytes | 1 / 64 |
| Input bytes | 1048576 |
| Record bytes excluding LF | 64 |
| Records | 65536 |
| Input stream attempts, including EOF and Interrupted | 8192 |
| Output stream attempts, including Interrupted | 8192 |
| Stack input staging | 4096 logical bytes |
| Stack output staging | 128 logical bytes |
| Bytes per native descriptor transfer | 1024 |
| Help stdout attempts | 64 |
| Diagnostic stderr attempts | 8 |

Every stream call consumes one attempt. Interrupted retries; other errors,
invalid positive counts and input/output budget exhaustion terminate. At the
input byte cap, a one-byte probe distinguishes EOF from oversized input
without extending the buffer. Record scanning examines at most the admitted
input bytes, with at most 65536 successful record updates.

The entire staged CSV is published by one loop, advancing only by confirmed
positive write counts. Output failure may leave the already published prefix;
it is not replayed or rolled back. The call budgets impose no wall-clock
deadline on blocking host I/O. An input host/allocation error can be reported
before a later input syntax issue is examined.

| Exit | Meaning |
| ---: | --- |
| 0 | Complete summary written, or help written |
| 2 | Invalid CLI, syntax/range/count/byte/line/input-attempt bound, or sum overflow |
| 3 | Input or argument-capture host error |
| 4 | Input-buffer or argument-snapshot allocation failure |
| 5 | Summary/help output or SIGPIPE-policy failure |
| 6 | Unexpected internal formatting/buffer contract failure |

Errors attempt the exact diagnostic `optional_sum: operation failed\n`
with eight stderr calls. Diagnostic failure preserves the primary status.
SIGPIPE is ignored before I/O; setup failure returns 5 without a diagnostic.
A successful run has no stderr output. Success acknowledges completed
descriptor writes, not downstream consumption or crash durability.

## Target and acceptance

All four registered application groups passed on 2026-10-28, totaling 98
native cases across two focused runs:

| Accepted group | Cases | Receipt under `target/stdlib-work/` |
| --- | ---: | --- |
| Model | 33 | One test, 7.26s; `outcome-composition-app-model-first.log`, three other tests filtered |
| CLI, rejection and I/O | 17 + 30 + 18 | Three tests, 8.02s; `outcome-composition-app-boundaries-first.log`, model filtered |

The model run's driver build took 1.70s. Both registered runs compiled the
application through the GPU compiler and passed the shared strict ELF checker
before native Linux x86_64 CPU execution, using existing descriptor and
allocator services. GPU-device execution and other backends remain unverified.

Executed application source SHA-256:
`12e4acaedabeb4815d63eab9aabb58d616892f99af6048b14a7b417ef718ae1b`.
Oracle SHA-256:
`006907de078b05e3185d831ae4d3adb4ea3974e719087d6ed0818e9ff753ef9c`.
Evidence directories:

- Model: `/tmp/optional-sum-model-8lt2heja`.
- CLI: `/tmp/optional-sum-cli-xa7ywdhk`.
- Rejection: `/tmp/optional-sum-rejection-ft6y0iw0`.
- I/O: `/tmp/optional-sum-io-a2lfj7mz`.

The independent test-only oracle separates missing from present zero, checks
the i64 domain and every intermediate sum, and constructs the exact CSV
without importing the production parser or composition implementation.
Executed models cover empty/all-missing/mixed records, signs and leading
zeros, full-width extrema and cancellation, safe intermediates, final LF or
unterminated records, 64-byte lines, read boundaries, 65536 records, exact
1 MiB input and seeded cases. Rejections cover empty/control/non-ASCII and
malformed fields, range errors, intermediate overflow despite later
cancellation, later invalid records and line/count/byte limits, with empty
stdout. CLI cases include sole-help input bypass and argument bounds.

I/O cases execute directory stdin, closed summary/help stdout, read/write
EINTR, input and required-EOF errors, output errors and SIGPIPE setup failure.
Persistent interruption summaries observe 8192 input calls/errors, or 8192
output errors followed by one successful stderr diagnostic. Those compact
summaries do not observe allocation releases.

The genuine prefix case uses a regular stdout file with `RLIMIT_FSIZE=10`
and inherited ignored SIGXFSZ. The application returns 5 and leaves exactly
the first ten independently expected CSV bytes after a real positive kernel
write; no success count is fabricated and production writes are not split for
the test. This case is untraced, so its file-size limit cannot truncate syscall
evidence. Cleanup is observed separately in traced output-error controls.

The baseline observes output only after actual EOF and no allocation after
EOF. Five selected allocation denials reach three input-growth sites and
both help-argument owners; each returns 4 with empty stdout. Detailed traces
require successful same-address/same-size releases for all observed successful
mappings. These finite observations are not a resource checker or proof of
general lifetime, aliasing, leak freedom or arbitrary-failure safety. The
defensive status-6 formatting/buffer path is not claimed reachable from valid
bounded input.

See `tests/fixtures/stdlib_execution/optional_sum/README.md` for retained
commands and detailed scope, and `tests/stdlib_optional_sum_execution.rs` for
the registered driver. Whitespace-only driver formatting after these receipts
does not represent a native rerun. With a warm build and configured GPU,
reproduce using:

```sh
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  env CARGO_TARGET_DIR=target/stdlib-build LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=70000 \
  cargo test --test stdlib_optional_sum_execution -- --nocapture --test-threads=1
```

Production is entirely Lanius. This application adds no compiler, runtime ABI,
proof, host service, Rust/Python library implementation, JSON transport or
Wasm dependency. See the
[outcome-composition plan](library-outcome-composition-plan.md) for the
separate public API contracts and library acceptance requirements.
