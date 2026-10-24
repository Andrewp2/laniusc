# Generic implementation forwarding regression

Both focused tests passed native-v3 admission. The accepted active sources and
the separately preserved nested-expression failure are described below.
The retained failure and eleven source hashes remain unchanged in
`tests/fixtures/stdlib_compiler_state/foundation_admission/stream_forward_current/`.

## Contract under test

An imported generic consumer must route its required method through the exact
selected generic implementation application, preserving the implementation's
owner identity, composed arguments, prerequisites, and checked receiver plan.
In particular, imported `core::io::write_all` must execute an imported
`Forward<W>` implementation, and `read_exact` must execute its Read analogue.
Two nested forwarding layers must reach the original borrowed endpoint.

The production stream contracts in `stdlib/core/io.lani` are the behavioral
source of truth. `Interrupted` transfers no bytes and is retried; successful
short operations advance the offset and remaining count; later errors retain
completed progress. `write_all` does not flush. Explicit `flush` forwards one
leaf call and its complete result.

## Source layout

Two focused tests in one integration target:

`tests/compiler_generic_impl_forwarding_execution.rs`

Its test-only source root is this directory, containing:

| File | Purpose |
| --- | --- |
| `imported_write.lani` | Minimal retained imported Forward through imported `write_all` topology, using `SliceWriter` and three bytes. |
| `contracts.lani` | Four bounded native stream scenarios and owner/trace/payload assertions. |
| `constant_application.lani` | One native job checks composed type and full-width typed constant application values. |
| `controls.lani` | Direct imported adapter calls, local generic adapter/helper, and nongeneric adapter through imported consumer controls. |
| `missing_write_impl.lani` | Read-only leaf wrapped successfully, then rejected by `write_all`. |
| `missing_read_impl.lani` | Write-only leaf wrapped successfully, then rejected by `read_exact`. |
| `unrelated_owner_bound.lani` | A proof on generic B cannot authorize a consumer call on unbound generic A. |
| `probe/forward.lani` | One `Forward<W> { inner: &W }`; generic Write and Read implementations use ordinary dotted calls. |
| `probe/consumers.lani` | Imported generic flush helper and Forward-consuming wrappers; no alternate write-all/read-exact implementation. |
| `probe/script.lani` | Fixed-size state, event recording, reset and nongeneric assertion helpers. |
| `probe/alpha.lani` | First nominal `Endpoint`, with leaf Read/Write implementations. |
| `probe/beta.lani` | Second same-layout nominal `Endpoint`, with distinct leaf implementation markers and error payloads. |
| `probe/constant_application.lani` | One imported `Inspect<T>` impl for `Carrier<T,const N:u64>`, generic mixed-width payload records, and borrowed state. |
| `probe/constant_consumer.lani` | Imported generic trait-bound consumer returning the method's full-u64 stamp and complete payload. |

The Forward Write constructor retains the existing `W: Write` contract and
body shape. A separate generic Read constructor requires `R: Read`; both
construct the same wrapper. Missing-trait negatives can therefore create a
legitimate wrapper through its other supported trait, then fail specifically at
the imported consumer. There are no per-concrete-type forwarding overloads.

## Minimal native oracle

The two `Endpoint` types have the same basename and native layout but belong to
different source modules. Their implementations record different constant
owner markers on every leaf call and return different `Host(i32)` payloads.
The state belongs to the entry program; endpoints and forwarding layers borrow
it. Assertions inspect that original state after calls and ensure an inactive
endpoint's state remains untouched. Choosing the wrong same-layout
implementation must therefore fail even if the copied bytes happen to match.

Use five bytes including zero and values above 127, a nonzero requested offset,
and untouched sentinel bytes surrounding the requested destination. The finite
leaf script is:

1. `Err(Interrupted)`, with no buffer or cursor change.
2. `Ok(1)`.
3. `Ok(2)`.
4. Either `Ok(2)` or `Err(Host(owner-specific code))`, with no transfer on Err.

For an initial `(offset=1, count=5)`, the independently asserted leaf request
trace is `(1,5), (1,5), (2,4), (4,2)`. Success returns five and failure reports
exactly three completed bytes. Compare actual byte prefixes, untouched suffixes
and sentinels, original cursor, call count, owner markers, and error payloads.
No test oracle duplicates the production retry loop.

The alpha single-write case calls the imported generic
`write_through_forward<W>` consumer. Its `W: Write` assumption authorizes
constructing `Forward<W>` and passing it to imported `write_all` inside that
generic body. The beta single-read case uses the corresponding `R: Read`
consumer. These cases require the implementation application's retained
assumption provenance, as well as the concrete leaf implementation at replay.

Four scenarios cover the important combinations without a Cartesian matrix:

| Endpoint | Consumer | Adapter depth | Outcome |
| --- | --- | --- | --- |
| alpha | `write_all` | one | Interrupted, short writes, complete success |
| beta | `write_all` | two | Interrupted, short writes, Host error after three bytes |
| beta | `read_exact` | one | Interrupted, short reads, complete success |
| alpha | `read_exact` | two | Interrupted, short reads, Host error after three bytes |

Before explicit flush, assert both write scenarios recorded zero flushes. An
imported generic flush helper then verifies alpha's `Ok(0)` and beta's distinct
Host error, including one leaf flush through two layers and no extra read/write
calls. The small control entry uses a simple one-call success script so the
control shapes do not accidentally implement retries themselves.

All sources are allocation-free and need no host IO. Native assertions and an
exact zero exit status are the acceptance oracle, with empty stdout/stderr.
Every executable uses `common::TempArtifact` and the strict x86 checker.

## Typed constant application oracle

One additional entry passes two applications through an imported generic
`observe<W,T>` consumer constrained by `W: Inspect<T>`. Both select the same
imported implementation and method targets. Its own parameters are `T` and
`const N:u64`; methods have no own generics and the trait has no inherited
bounds. The constant values `4294967297` and `8589934593` have the same low
32-bit word and different high words. They are returned as `u64` and recorded
through the original borrowed state, so a truncated or reused substitution is
observable without allocating a large array.

The first T is `Payload<i32>`, the second `Payload<Extra>`, with different record
layouts. Both payloads include high `u64`, negative `i32`, and `bool` fields;
the nested Extra adds another high `u64` and negative `i32`. Assertions check
every field, both complete constant values, two method calls on the correct
original state, and an untouched inactive state. Mutating returned records
then checks that by-value payloads did not alias either source. This is one
bounded native job, with no additional Cartesian cases or host services.

The trait also requires static `echo(value:T)->T`. The imported consumer calls
`source.payload()` into an explicit generic local T, then `W::echo(payload)`
into a second local T, and the generic implementation returns the complete
value. This exercises a typed-first-parameter declaration (receiver mode 3)
through its checked static-call adjustment (mode 0), as well as the borrowed
receiver methods. Existing payload and source-copy assertions cover its return
value; it adds no state calls or additional native jobs.

The original nested `W::echo(source.payload())` record-field expression failed
with `LNC0006` in root's first native-v2 run, after the control and minimal
imported-write entries had executed successfully. Its exact source closure is
preserved under
`../stdlib_compiler_state/implementation_application_static_result/`. The
explicit generic locals passed the independent constant-application native-v3
test. The original nested expression has not been rerun and remains an open
captured failure; this evidence does not establish that expression as fixed.

## Serial job order and negative diagnostics

Core serial test order:

1. Compile and execute controls.
2. Compile and execute the minimal imported write entry.
3. Compile and execute behavioral contracts.
4. Compile each of the three negative entries and reject emitted artifacts.
5. Recompile and execute behavioral contracts in the same process.

This core test has seven small compilation jobs and four native executions.
The independent
`typed_constant_implementation_applications_preserve_values_and_layouts` test
has one compilation job and one native execution. Running the complete target
therefore has eight jobs and five native executions. Each negative retains a
primary source label at the bad consumer call and was observed to reject with
`LNC0008`: missing Write, missing Read, and an unrelated generic owner's bound.
Timeouts, a GPU-lock miss, linker failure, and an unrelated call-resolution
failure are not accepted as those semantic rejections.

The repeated behavioral entry checks that failed proof jobs do not authorize a
later wrong implementation. Source code cannot manufacture a stale internal
proof handle or arena serial. Stale/mismatched protocol-handle negatives belong
in the owning compiler packet/projection unit tests; this source target must
not claim to cover them.

## Accepted native-v3 evidence

Root ran the two focused tests separately against the coherent native-v3
compiler generation:

| Test | Compile jobs | Native executions | Result | Test duration |
| --- | --- | --- | --- | --- |
| `imported_generic_implementation_applications_preserve_stream_and_owner_contracts` | 7 | 4 | Passed, including all three source-local `LNC0008` rejections | 7.97 s |
| `typed_constant_implementation_applications_preserve_values_and_layouts` | 1 | 1 | Passed all full-width constant, record, static-call and source-alias assertions | 2.50 s |

Every native executable passed the strict x86 checker, exited zero and produced
empty stdout/stderr. The core test ran with
`LANIUS_CHECK_LIBRARY_INSTANCE_CACHE=1`. Its repeated behavioral entry recorded
one actual two-body cache hit checked equal to fresh replay:
`[library-instance-cache] check ok unit=0:0 bodies=2`.

The logs are
`target/stdlib-work/implementation-applications/stream-contracts-v3.log` and
`target/stdlib-work/implementation-applications/constant-application-v3.log`.
This evidence covers GPU-compiled x86-64 Linux programs, not execution as GPU
kernels or arbitrary generic implementation forms. No broad stream, stdlib or
compiler suite was needed for this focused acceptance. The original nested
static-result expression remains separately captured and open.
