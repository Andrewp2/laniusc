# Owned row flattening and running totals

Status: ordinary `FlatMap` migration passes compiler admission and all four
direct executable groups: 219 process group cases with overlapping baselines.
The earlier fallible-adapter receipts are recorded separately below. The program
uses public adapters in [`core::iter`](stdlib-iterators.md). The complete
library goal remains open. Source: [flatten_sum.lani](../sample_programs/library/flatten_sum.lani).

```text
printf '1 2\n\n-3 +4\n' | flatten_sum
1
3
0
4
```

## Byte format

LF terminates a physical row. Space, tab, carriage return, vertical tab and
form feed separate tokens within a row. A final row need not end in LF;
a trailing LF terminates the preceding row without inventing another row.
Empty input has zero rows; `\n\n` has two empty rows. Whitespace-only rows are
valid. Each token is `[+-]?[0-9]+`, within the complete i64 range. Leading zeros
and negative zero are accepted. NUL, non-ASCII bytes, underscores, commas and
other syntax fail explicitly.

Flatten values in row order, starting at total zero, and write every checked
running i64 total as decimal plus LF. Integer-token overflow and running-total
overflow fail. An input containing no integer values produces no output. The complete result is staged
before stdout delivery, so malformed input, arithmetic overflow and output-byte
limits publish no totals. A later host-write failure or exhausted write-call
allowance can leave an actual accepted prefix.

## Command and limits

`flatten_sum --help` prints one usage line without consuming stdin. Otherwise
the following unsigned-decimal option/value pairs are optional and unique:

| Option | Default | Allowed range |
| --- | --- | --- |
| `--input-bytes` | 65,536 | 0..1,048,576 |
| `--rows` | 1,024 | 0..4,096 |
| `--values` | 8,192 | 0..65,536 |
| `--output-bytes` | 172,032 | 0..1,376,256 |
| `--read-calls` | 1,024 | 0..65,536 |
| `--write-calls` | 1,024 | 0..65,536 |

Argument snapshots admit at most 12 selected arguments and 512 argument bytes,
excluding argv[0] and NUL terminators. Unknown, duplicate, unpaired, signed or
over-limit option values fail before stdin access. `--help` must appear alone.
The command installs SIGPIPE ignore before allocation/output; failed setup
returns 3 without attempting output. Help and closed-output errors therefore
follow the ordinary cleanup path rather than terminating by SIGPIPE.

Reads/writes transfer at most 1,024 bytes per host attempt. Interrupted calls
consume their allowance; EINTR alone retries. Read allowance includes the EOF
read. At an exact byte cap, a one-byte probe distinguishes EOF from over-limit
input; at cap zero, empty input still needs one read attempt. Empty staged
output needs no write allowance. Zero/invalid write counts and other host
errors fail. One bounded best-effort diagnostic write follows cleanup on
ordinary failure; it is separate from the stdout-write allowance and does not
replace the primary status.

| Exit | Meaning |
| --- | --- |
| 0 | All staged totals delivered, or help delivered. |
| 2 | Argument/input grammar, integer/running overflow, or an explicit resource/call limit. |
| 3 | Signal/host I/O error, invalid progress or unexpected ownership failure. |
| 4 | Source allocation failure. |

## Ownership pipeline

The input buffer is fully validated first. The program constructs an owned
`Vec<Vec<i64>>` with exact row/value capacities; even an empty physical row has
a real one-element backing reservation. It then releases the input buffer.

1. `Vec.take_iter()` transfers the outer backing and remaining row owners.
2. Ordinary `FlatMap` borrows the outer cursor and mapper. Mapping transfers
   each row directly to its owning `Vec::IntoIter<i64>`, without allocation or
   a fallible result wrapper.
3. The scalar-specific `InnerRetirement<IntoIter<i64>,Infallible>` policy
   consumes the inner with `take_remaining()` and destroys its backing before
   another outer row is acquired. No i64 item owns a nested resource, so this
   policy is total even for a nonempty supplied cursor. The shared nested
   engine calls it only after exhaustion. No fallible finish result is ignored.
4. `TryScan` receives plain i64 values and uses canonical checked addition.
   Overflow remains an explicit AppError. Successful totals are formatted into
   the bounded staging owner.
5. On normal termination or error, `take_active()` transfers any active inner.
   Its remainder is recovered and destroyed; every unconsumed outer row and
   the outer backing are explicitly released. No error masquerades as None.
6. Only successful processing delivers staged bytes. Output and argument owners
   are released even after delivery failure. AppError contains scalar metadata
   and owns no heap payload.

There is no implicit Drop. Adapter/callback/source copies cannot independently
own traversal or cleanup. The explicit owners require at most one input, one
outer, one per physical row, one staging allocation and two argument allocations;
zero capacities can avoid some requests. For configured caps B/R/V/O, their
requested storage is bounded by argument storage plus
`R*sizeof(Vec<i64>) + 8*(V+R) + max(B,O)`; input is freed before output staging.
The adapters allocate no traversal scratch. Runtime/stack/kernel allocations,
RSS and host-call wall time are separate from these explicit library-owner
bounds. Empty-row traversal work is bounded by the outer row count.

## Current ordinary-adapter receipts

The ordinary `FlatMap` application is source-frozen at SHA-256 `65cfcdfc...`.
It preserves the command grammar, bounds, status codes, staging and explicit
active-inner/unread-row cleanup. The independent oracle and Rust driver are
unchanged. With `core::iter` `5034fbac...`, compiler admission passes in
`target/stdlib-work/infallible-flatten-sum-admission-first.log`. The emitted
ELF is SHA-256 `2707585b...`; full identities are in the fixture guide.

Four separate direct Python oracle groups reuse that executable:

| Log under `target/stdlib-work/` | Current accepted scope |
| --- | --- |
| `infallible-flatten-sum-models-first.log` | 138 model process cases, including physical empty-row ownership. |
| `infallible-flatten-sum-bounds-first.log` | 54 argument/input/overflow/output-limit process cases. |
| `infallible-flatten-sum-allocations-first.log` | 11 process cases: one baseline and all ten reached source OOMs. |
| `infallible-flatten-sum-faults-first.log` | 16 I/O fault process cases. |

These total 219 group cases with overlapping setup/baselines, not independent
properties. This acceptance is direct Python execution against the retained
ELF; the registered Rust tests were not rerun for this migration. The current
source has no new scale observation. Historical native receipts and the older
scale timing below retain their source-specific scope.

## Historical fallible-adapter receipts

The earlier `TryFlatMap` application is SHA-256 `946043fe...`, unchanged
throughout these gates, with `core::iter` `7256a394...`. Full identities are recorded in the
[fixture guide](../tests/fixtures/stdlib_execution/flatten_sum/README.md).
Logs under `target/stdlib-work/` record:

| Log | Accepted scope |
| --- | --- |
| `nested-flatten-sum-models-bounds-first.log` | Two passing tests in 8.51s: models 138 and bounds 54 process cases. |
| `nested-flatten-sum-allocations-faults-first.log` | Two passing tests in 8.23s: allocations 11 (one baseline plus all ten reached source OOMs) and faults 16 process cases. |

The allocation evidence at `/tmp/lanius-flatten-sum-allocations-_d2m0iun`
contains a baseline exiting 0 and ten individually reached mmap/ENOMEM cases
exiting 4. Each fault binds the successful baseline's exact instruction,
requested mapping and prefix, and all owned mappings are explicitly released.
The earlier direct CLI smoke (three physical rows, four values) overlaps this
workflow and is not added to the 219 cases. Its admission/execution logs are
`nested-flatten-sum-admission-first.log` and
`nested-flatten-sum-admission-native-first.log`.

The target is native Linux x86_64 CPU execution emitted by the GPU compiler,
kernel `7.0.0-38-generic`; test evidence resides under local ext4 `/tmp`.
There is no user GPU-kernel, broader-host or universal performance claim.
Eighteen CPU oracle controls passed separately from that native execution;
no new execution is inferred from the unchanged oracle.
The shared semantic/application driver build passed in 1.39s
(`nested-semantic-app-drivers-borrow-retry.log`); that is not an isolated
app-build time. Its initial E0308 (`nested-semantic-app-drivers-first-build.log`)
was in the other semantic driver's test harness, with no application-source
change or runtime failure inferred.

The [focused driver](../tests/stdlib_flatten_sum_execution.rs) compiles the
actual command. Its [independent oracle](../tests/fixtures/stdlib_execution/flatten_sum/oracle.py)
uses an explicit byte grammar and Python's unbounded integers for expected
prefix sums and overflow rejection. It includes authored/seeded nested rows,
physical empty-row allocations, exact/over limits, binary/malformed input,
overflow with active and unconsumed rows, all dynamically reached source OOMs,
actual closed-reader output/help pipes, interruptions and genuine output
prefixes before a later failure.

Raw-ELF allocation sites and full-width requested mappings use the existing
strict verifier without a MAP32-only or named fallback. Every scheduled fault
must be reached at the intended instruction/descriptor/request; OOMs bind the
baseline allocation prefix. All source mappings must be explicitly released
before the traced process-exit syscall. The application has no ACK handshake:
this is exit-boundary trace evidence, distinct from direct adapter fixtures'
live `/proc` ownership checkpoints.

These historical results cover that source's listed workflow and fault schedules. The direct
adapters' semantic, owned-error and live-checkpoint campaigns retain their
separate scope in the [nested-iteration plan](library-nested-iteration-plan.md);
these application results do not complete the full library goal.

### Separate scale observation

One historical untraced run reused accepted ELF `906488cc...` with app
`946043fe...` and core `7256a394...`. It processed 3,072 physical rows:
1,024 nonempty rows of 64 ones and 2,048 empty rows, totaling 65,536 values and
133,120 input bytes. Output was 382,110 bytes; exact totals 1..65,536 were
verified outside the timer. Options were `--input-bytes 1048576 --rows 4096
--values 65536 --output-bytes 1376256`.

Observed wall time was **0.157614975 seconds**, including launch, stdin,
parsing, ownership traversal, formatting and stdout capture. This is one local
process observation, with no scale allocation count, compiler/GPU benchmark
or general speed-ratio claim. It adds no fault-group case to the four tests/
219 process group cases. Receipt: `target/stdlib-work/nested-flatten-sum-scale-first.log`;
evidence: `/tmp/flatten-sum-scale-c24v1gy5`.
