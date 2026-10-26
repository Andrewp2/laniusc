# range-dot

[`sample_programs/library/range_dot.lani`](../sample_programs/library/range_dot.lani)
computes a checked dot product from two inclusive ascending i32 ranges. It
uses the real borrowed `core::iter::Zip`, `Take`, `Map`, and `Enumerate`
adapters, an application `Mapper` implementation, `core::i64::checked_add`,
checked decimal parsing/formatting, owned raw argument snapshots, and checked
stdout writes. Application arithmetic and iteration are Lanius.

The current item-import/inference source is admitted as **x86_64 Linux ELF
through the GPU compiler**. Its unchanged focused gate passed all 67 native
cases in one Rust test, recorded in `target/stdlib-work/lang-range-dot.log`.
The current receipt and the separate earlier acceptance record below identify
their own checkpoints and scope.

## Item imports and inferred locals

The source uses focused item imports for its iterator constructors, Mapper and
Pair, numeric parsing/formatting, checked addition, argument snapshots, signal
policy and stdout. Initializers determine concrete local types, including the
borrowed adapter chain:

```lanius
let paired = zip(left.borrow(),right.borrow());
let selected = take(paired.borrow(),limit);
let product = Product {};
let products = map(selected.borrow(),product.borrow());
let indexed = enumerate(products.borrow());
```

The imported free functions infer their item types from the concrete Iterator
and Mapper implementations under the
[bound-directed inference rule](language-ergonomics.md#local-type-inference).
The mapper still widens each operand with `as i64`; the zero-initialized count
and sum remain explicitly `u64` and `i64`. The packed output storage retains its
`[i32;16]` backing and `[u8]` view annotations.

Status conversion remains explicit in functions returning i32. Main retains
the argument owner through processing and destroys it after every processing
result. Parsing order, mapper effects, checked prefix accumulation and output
publication follow the earlier program's order. The existing native test and
oracle are unchanged; its exact filter remains
`range_dot_csv_prefix_arithmetic_and_exact_failure_cleanup`.

## Build and use

From the repository root, with the compiler binary built:

```sh
mkdir -p target/stdlib-work/range-dot
target/stdlib-build/debug/laniusc --stdlib-root stdlib --emit x86_64 \
  sample_programs/library/range_dot.lani \
  -o target/stdlib-work/range-dot/range-dot
target/stdlib-work/range-dot/range-dot 1 5 2 6 10
```

The command takes exactly five positional arguments:

```text
range-dot LEFT_START LEFT_END RIGHT_START RIGHT_END LIMIT
```

The example prints:

```csv
count,dot
5,70
```

Each range includes both endpoints and advances by one. Reversed bounds make
that range empty. Zip stops when either range ends; Take selects at most LIMIT
pairs. The dot is the sum of the selected corresponding products. Unequal
range lengths use their common prefix. An empty range or zero quota prints
`count,dot\n0,0\n`.

## Arguments and work bounds

Endpoints are complete ASCII i32 decimals. One optional leading `+` or `-`
and leading zeroes are accepted. LIMIT is a complete unsigned u64 decimal with
leading zeroes permitted and neither sign accepted; its value must be
`0..=1_000_000`. Whitespace, separators, suffixes, missing digits, non-ASCII
digits, and overflow are argument errors.

Main snapshots at most five raw arguments and 160 total bytes, excluding
argv[0] and terminating NULs, then requires exactly five arguments. The byte
budget comfortably covers four full-width i32 spellings and a full-width u64
spelling, with room for leading zeroes. No per-argument spelling cap is added.
There are no options, defaults, or stdin input.

The iterator chain is:

```text
left RangeI32 + right RangeI32
  -> Zip -> Take(LIMIT) -> Map(Product) -> Enumerate(0)
  -> checked prefix accumulation -> staged CSV
```

Zip polls left first. When a right range ends after a left value was obtained,
that unpaired left value is consumed. Take with quota zero does not poll Zip;
at a reached quota it makes no extra upstream probe. Enumerate supplies the
zero-based index; the program sets count to index plus one after a successful
addition. Count is at most 1,000,000, so index/count arithmetic fits u64.

The program makes at most LIMIT successful selected steps plus the final None
check. Parsing is bounded by the snapshot budget. There is no elapsed-time
bound for host output, and the existing `write_all` helper retries Interrupted.

## Checked arithmetic

The mapper casts both i32 operands to i64 before multiplying. Every possible
i32 product fits i64: the maximum is `i32::MIN * i32::MIN = 2^62`. The sum of
products can overflow, so every addition uses `core::i64::checked_add`.

The first prefix outside the i64 range returns status 5 before any stdout
write. This rule applies even if later products would bring the final
mathematical sum back into range. The program stops immediately and publishes
no partial arithmetic summary. A lower quota can select a valid prefix of a
range whose longer dot product would overflow.

## CSV publication and errors

After all selected additions succeed, the program stages the header, decimal
count, comma, decimal dot, and newline in 64 packed logical stack bytes. Every
formatter result is checked before publication. The complete u64 and i64
decimal domains need at most 52 bytes with this framing. Fixed-array backing
may occupy more native stack storage than the logical byte count.

Publication uses `core::io::write_all`. Short writes continue from the completed
offset; a later output error can leave a CSV prefix. Output is not atomic.
Stderr is unused, and error rows are not mixed into stdout.

| Status | Meaning |
| --- | --- |
| 0 | Complete CSV header and summary written |
| 2 | Argument count, byte budget, decimal grammar/range, or quota error |
| 3 | SIGPIPE-policy setup, checked output, defensive formatting, or argument host-read error |
| 4 | Argument-snapshot allocation failure |
| 5 | A selected dot-product prefix overflowed or underflowed i64 |

Main installs process-wide SIGPIPE Ignore before allocating. An actual closed
stdout pipe can then report EPIPE and return status 3 while releasing argument
storage. Iterator adapters do not change the process signal policy.

## Ownership

Main keeps one active argument-snapshot owner and destroys it after every
processing result, including parsing, arithmetic, and output failures.
Snapshot errors clean up their own partial construction. The private processing
function uses a shallow read-only handle; copying that handle creates no new
owner. Argument views finish before snapshot destruction.

The argument entry vector and packed argument bytes are the only heap owners.
Both range cursors, Zip, Take, the stateless Product mapper, Map, Enumerate,
counters, and output storage are typed stack locals. Every source cursor,
adapter, and mapper remains alive while a downstream adapter borrows it.
Stdout is borrowed and remains open.

## Current language-migration acceptance

The unmodified
[`stdlib_range_dot_execution`](../tests/stdlib_range_dot_execution.rs) driver
passed `range_dot_csv_prefix_arithmetic_and_exact_failure_cleanup` in **7.22 s**,
including production-root GPU compilation and all 67 native cases. It reused one
strict-checked ELF for the case set detailed in the historical table below:
numeric prefixes and extremes, grammar/budget errors, reached allocation and
output faults, actual EPIPE and signal setup. The existing independent numeric
oracle, output/status checks and exact argument-owner cleanup checks were
unchanged. The migrated iterator chain therefore has executable evidence, not
only successful type checking.

| Evidence | Scope | Receipt under `target/stdlib-work/` |
| --- | --- | --- |
| Shared driver build | Ten test drivers built in 45.55 s; not a range-dot-only build time | `lang-adoption-drivers-build.log` |
| Current application gate | One Rust test, 67 native cases, 7.22 s, exit 0 | `lang-range-dot.log` |

The rebased HEAD was `21764809dcab66be3e2e2afe0b5c17c93b3b7dc0`, with
`origin/lang` at `0d2e4a07aa5b0f0dda6a2bcbd0d1c9d3de4a0eca`. The working tree
also contained other stdlib language migrations and package-lock fixes, so HEAD
alone does not identify a clean source snapshot. The checked application, test
driver source and retained ELF have these SHA-256 values:

| Artifact | SHA-256 |
| --- | --- |
| `sample_programs/library/range_dot.lani` | `b02397bef70f720415f94701b4483b1aea7339d88b1cead36786423cf9f876d5` |
| `tests/stdlib_range_dot_execution.rs` | `d75abce779cdb9df867b6397f69242b7ce7f60ebb27984af718f047405ac5d2f` |
| `/tmp/laniusc_range_dot_executable_310831_0` | `328acfcaaa141282759f8153abec605db285a730e5d466a928d3500deb16e8cd` |

The retained ELF and logs are local artifacts. This receipt establishes the
documented native Linux application behavior for this finite case set. It is
not an application GPU-kernel target, a throughput benchmark, or acceptance of
unrelated language features or stdlib migrations.

## Focused test and historical accepted evidence

[`tests/stdlib_range_dot_execution.rs`](../tests/stdlib_range_dot_execution.rs)
defines `range_dot_csv_prefix_arithmetic_and_exact_failure_cleanup`. It compiled
the real application once through the production stdlib root, passed the
unchanged strict shared ELF/jump checker through `common::TempArtifact`, and
reused one executable for all 67 native cases. Each native run has an explicit
five-second timeout with a one-second forced-termination grace.

The accepted group passed in **6.43 s**, including GPU compilation, reference
calculations, and native tracing. The Rust driver build completed in **1.15 s**.
The compiler checkpoint was `3415fb76a46672a11d8049306bd911f450ead355`, with
uncommitted stdlib iterator-adapter sources supplied by the production stdlib
root. Compiler sources were unchanged for this gate, and the application body,
driver, and stdlib inputs remained frozen. Both commands below returned zero.

| Native cases | Count | Checked behavior |
| --- | --- | --- |
| Numeric and range cases | 24 | i32 extremes, singletons, reversed/unequal ranges, zero and truncated quotas, successful million-item selections, valid near-boundary prefixes, positive/negative prefix overflow, and cancellation witnesses |
| Accepted spellings and budget boundary | 2 | Signed and zero-padded endpoints, zero-padded unsigned quota, and exactly 160 total argument bytes |
| Invalid arguments | 32 | Missing/extra arguments, empty values, all four endpoint range boundaries, malformed/non-ASCII decimals, signed/overflowing/out-of-range quotas, invalid raw bytes, and an exceeded snapshot budget |
| Allocation faults | 2 | Reached ENOMEM at each of the two argument-snapshot mmap attempts, status 4, no output, and exact cleanup of prior owners |
| Output faults | 5 | Reached EIO, EAGAIN, zero progress, Interrupted retry, and a synthetic one-byte short write with resumed suffix |
| Real closed stdout | 1 | Actual EPIPE under SIGPIPE Ignore, status 3, and complete argument cleanup |
| Signal setup fault | 1 | Reached rt_sigaction EINTR, status 3 before any allocation or output |

The independent oracle computes bounded cardinality and each prefix in i128
using the closed-form sum of `(a+k)(b+k)`, rather than running the application's
adapter chain. It checks every prefix against i64 bounds, including positive
and negative overflow followed by mathematical cancellation back into range.
Four numeric cases return status 5 without a write. Two cross the bound on
their third selected product; the other two have out-of-range prefixes even
though their final exact mathematical sums fit i64. The remaining 20 numeric
cases compare complete CSV bytes with the independent oracle.

Output fault tests require each injection to be reached once and check exact
write-attempt counts. A synthetic one-byte short write reports progress while
strace suppresses the first host write; the test expects the remaining stdout
suffix exactly once and checks the resumed request length. The Interrupted
case retries and emits the complete CSV. The real closed-pipe case reaches
EPIPE without injection. Signal setup is checked to precede allocations and
writes in every case.

The memory ledger matches actual mmap addresses and requested lengths to exact
munmap releases. It rejects unknown/double/mismatched releases, extra
allocations, growth, and live owners at exit, without assuming a physical
`View<u8>` width. The normal nonempty snapshot owns one entry allocation and
one packed-byte allocation. Both allocation fault ordinals are reached, with
every successful prior mapping released exactly once. Arithmetic, parsing,
and output failures also leave no live allocation owners. Each case checks
complete stdout, stderr suppression, status, and preallocation SIGPIPE policy.

Create `target/stdlib-work/iterator-adapter-admission/` before redirecting logs
when reproducing these commands. The actual bounded driver-build command was:

```sh
mkdir -p target/stdlib-work/iterator-adapter-admission
timeout --kill-after=2s 100s \
  flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s env \
  CARGO_TARGET_DIR=/home/andrew-peterson/code/laniusc/target/stdlib-build \
  CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  cargo test --test stdlib_range_dot_execution --no-run \
  > target/stdlib-work/iterator-adapter-admission/application-build.log 2>&1
```

The actual bounded acceptance command used the resulting driver binary:

```sh
timeout --kill-after=2s 100s \
  flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s env \
  RUST_MIN_STACK=16777216 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000 \
  target/stdlib-build/debug/deps/stdlib_range_dot_execution-c6cb6079cacc0f63 \
  --exact range_dot_csv_prefix_arithmetic_and_exact_failure_cleanup --nocapture \
  > target/stdlib-work/iterator-adapter-admission/application.log 2>&1
```

The outer timeout is 100 seconds, lock acquisition is bounded to 35 seconds,
and the inner command is bounded to 60 seconds. Acceptance used a 16 MiB Rust
thread stack and a 45-second GPU codegen guard. The recorded binary filename is
specific to this build; a later build can have a different hash.

| Evidence | Terminal log |
| --- | --- |
| Rust driver build | `target/stdlib-work/iterator-adapter-admission/application-build.log` |
| Accepted application group | `target/stdlib-work/iterator-adapter-admission/application.log` |

These logs are local ignored build artifacts. The committed driver and commands
reproduce the gate; the logs are not included in a fresh checkout.

The GPU compiler produced the ELF; application execution was native on x86_64
Linux. These gate timings establish this functional profile and include
compilation and instrumentation. Throughput, other targets, and user GPU
kernels have no acceptance evidence from this group.
