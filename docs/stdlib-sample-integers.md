# Seeded bounded integer samples

`sample_programs/library/sample_integers.lani` prints a reproducible sequence
of non-cryptographic integer samples:

```sh
sample_integers 7 100 10 100 > samples.txt
```

The CLI is exactly `sample_integers SEED BOUND COUNT DRAW_LIMIT`, or sole
`--help` / `-h`. The program never reads stdin.

## Arguments and values

Every numeric argument is 1..20 ASCII decimal bytes, parsed by the existing
`core::decimal::parse_u64_range`. Leading zeros are allowed. Signs,
whitespace, prefixes, empty values, overflow and extra operands are errors.
Capture admits four arguments and at most 80 bytes, excluding terminating NULs.

| Argument | Admitted range |
| --- | --- |
| SEED | Every u64, including zero and u64::MAX |
| BOUND | 1..u64::MAX |
| COUNT | 0..4096 |
| DRAW_LIMIT | Every u64, including zero and u64::MAX |

All COUNT samples lie in the half-open interval [0, BOUND). Output has one
canonical unsigned decimal value plus LF per sample, without a header or extra
rows. COUNT zero produces empty output. BOUND one produces zeros and requires
no source draws, even with a zero draw limit.

This is deterministic test/data generation, not secret material or host entropy.
The application calls the existing public seeded generator and sampler; it
implements no random or cryptographic primitive.

## One shared draw counter

The application creates one `core::random::from_seed` generator, one
`draw_budget(DRAW_LIMIT)` counter and one borrowed `budgeted` adapter.
The same adapter is passed to public `core::random::below` for every sample.
Neither the source nor the budget is copied or reset between samples.

A delegated draw spends one unit before calling the source. Rejected sampler
words spend budget too. Exhaustion returns DrawLimit without another source
call or a biased fallback. Any exhaustion, including after earlier samples
succeeded, discards the complete private result and returns 2 with empty stdout.
Other unexpected source/sampler errors return 6 before output.

The existing below sampler keeps its rejection policy: for BOUND greater
than one, discard words below `2^64 mod BOUND`, then return an accepted
word modulo BOUND. No extra app-level source calls, modulo shortcut or per-value
budget is introduced.

The source and counter are plain local values that remain live through all
adapter calls. This counter bounds delegated draws, not elapsed time, source
internals or memory use. A very large DRAW_LIMIT is allowed; it is not a
wall-clock deadline. No statistical test or uniformity/security claim is made
for a fixed deterministic seed.

## Storage, output and cleanup

Argument parsing returns plain numeric Options. The snapshot owner is destroyed
before help output or result allocation. Data mode creates one `Vec<u64>`
with capacity COUNT, at most 32768 bytes on the current native u64 target.
COUNT zero requires no value backing. The result loop performs exactly COUNT
successful appends only when sampling succeeds, remaining within that one
reservation.

All sampling completes before stdout. Only then does the program format the
retained values through `core::decimal::format_u64` into a 21-byte line
array and pack them into a 1024-byte caller-backed output batch. Decimal lines
may cross batch boundaries without changing their bytes. No output/String
allocation or per-value write is needed.

One shared counter spans all data writes, including retries and every batch.
The 128-attempt limit applies to the entire result, not to each line or batch.
COUNT 4096 can require at most 86016 output bytes, fitting at most 84 ordinary
1024-byte Descriptor transfers. Thus the admitted maximum fits failure-free
execution without bypassing the public Descriptor staging contract. Interrupted
or partial writes still consume attempts and can exhaust that margin.

The vector remains the single live owner through formatting/publication and is
explicitly destroyed after success or failure. Sampling/allocation failures
also release every acquired owner before the diagnostic. No owner copy gains
another cleanup authority. Standard descriptors are borrowed and never closed.

Output advances only by confirmed positive counts. Interrupted retries; zero,
invalid counts, other errors or attempt exhaustion stop. An output failure can
leave a confirmed prefix without replay or rollback. Defensive formatting
contract failure could likewise follow earlier batches; no rollback is promised.
The valid u64 formatter contract supplies at most twenty digits per value.

## Bounds and statuses

| Resource | Bound |
| --- | ---: |
| Captured arguments / total bytes | 4 / 80 |
| Numeric token bytes | 1..20 |
| Samples / reserved vector capacity | 4096 |
| Value backing | At most 32768 bytes on the native target |
| Source draws | Shared DRAW_LIMIT |
| Caller line / output batch storage | 21 / 1024 logical bytes |
| Output bytes | At most 86016 |
| Data stdout attempts, including Interrupted | 128 total |
| Help stdout attempts, including Interrupted | 128 total |
| Diagnostic stderr attempts | 8 |

The draw and I/O-attempt bounds do not impose timeouts on host writes or
hypothetical source implementations. COUNT and BOUND are admitted even when
the requested draw limit will be insufficient; the public adapter determines
exhaustion after accounting for actual rejected words.

| Exit | Meaning |
| ---: | --- |
| 0 | Complete sampled lines written, or help written |
| 2 | Invalid CLI/count/bound or shared draw-limit exhaustion |
| 3 | Argument-capture host failure |
| 4 | Argument or result-vector allocation failure |
| 5 | Data/help stdout or SIGPIPE-policy failure |
| 6 | Unexpected source/formatting/storage/internal contract failure |

Errors attempt the exact line `sample_integers: operation failed\n` using
at most eight stderr write attempts. Diagnostic failure preserves its primary
status. SIGPIPE is ignored before I/O; setup failure returns 5 without a
diagnostic. Successful runs have no stderr output.

## Target and acceptance

All four registered application groups passed in one 7.59s run after a 1.99s
driver build, totaling 98 distinct native cases:

| Accepted group | Cases | Evidence directory |
| --- | ---: | --- |
| Model | 32 | `/tmp/sample-integers-model-dvyvqmn3` |
| Budget | 19 | `/tmp/sample-integers-budget-q91gu3sp` |
| CLI | 36 | `/tmp/sample-integers-cli-rnjhpls7` |
| I/O | 11 | `/tmp/sample-integers-io-5_kel5dc` |

The receipt is `target/stdlib-work/random-budget-sample-app-first.log`:
four tests passed with no filtered tests. The registered driver compiled
through the GPU compiler, required an actual ELF64 x86-64 executable and
passed the shared strict jump gate before native Linux x86_64 CPU execution,
using existing allocator and Descriptor services. GPU-device execution and
other backends remain unverified.

Executed application source SHA-256:
`f63a73509e8ed44cd3df749dd4234ba4b0baf71ba1f843835fb65da506eb2e63`.
Oracle SHA-256:
`74ae03a7ca17c1b37351e90ac49f85fafa0378f70416e3381fe9321b98dc4dde`.
Random module SHA-256:
`7f1bf3857137cd610a23d69a3d6d3e0bdfb4df62d5d4e0fc160f811460cdf09b`.

The independent test-only oracle uses integer generator transitions anchored
to six checked-in author-vector seeds/states and their initial raw words,
then applies independently expressed rejection/budget arithmetic. It imports
no production implementation. Executed models include those seeds,
BOUND one/two/u64::MAX, rejection-heavy and power-of-two/odd bounds, u64::MAX
draw limits, zero/no-draw paths, and maximum COUNT with both small and
full-width output. Budget cases check success on the exact last allowed draw,
failure one earlier and a single counter shared across samples. CLI cases
cover arity/help, all numeric field bounds, malformed/non-ASCII inputs and
exact 80-byte leading-zero arguments.

Three selected ENOMEM sites reach both argv owners and the one sample
reservation. Each returns 4 with empty stdout. Complete traces observe argv
release before the vector reserve, no later allocations, no stdin reads or
borrowed-descriptor closes, sample-owner lifetime through data output, and
explicit release before any error diagnostic. Successful mapping releases
match both address and requested size, including actual address reuse. COUNT
zero obtains no sample backing or stdout write; help releases argv before
publication. Draw exhaustion after earlier samples also releases the owner
without publishing data.

Actual closed data/help stdout produces EPIPE, injected EIO returns 5, and a
write EINTR retries to the exact expected result. No successful transfer count
is fabricated. The shared 128-attempt policy covers all batches; a compact
summary observes 128 output errors followed by one successful diagnostic.
That summary establishes attempt bounds, not the full mapping-release ledger;
separate complete traces observe selected cleanup paths.

The argument-capture Host failure branch and status 3 were not fault-reached.
Positive short writes and partial-output behavior are not claimed tested.
Unexpected source/internal error injection, exhaustive fault schedules,
automatic lifetime enforcement, general aliasing safety, leak freedom,
statistical uniformity, formal verification and cryptographic security remain
outside these finite receipts.

See `tests/fixtures/stdlib_execution/sample_integers/README.md` for detailed
scope and retained commands, and `tests/stdlib_sample_integers_execution.rs`
for the registered driver. Root applied whitespace-only driver formatting
after runtime acceptance; that is not represented as a native rerun. With a
warm build and configured GPU, reproduce using:

```sh
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  env CARGO_TARGET_DIR=target/stdlib-build LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=70000 \
  cargo test --test stdlib_sample_integers_execution -- --nocapture --test-threads=1
```

Production is entirely Lanius and adds no compiler, runtime ABI, proof or host
service. No Rust/Python library implementation, JSON transport or Wasm
dependency is introduced. See the [random-budget plan](library-random-budget-plan.md)
for separate adapter contracts and library acceptance requirements.
