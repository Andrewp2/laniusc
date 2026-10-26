# Imported resumable transport admission probe

Status: the explicitly annotated full probe compiled and executed successfully.
The initial rejected source and the accepted first-probe sources are retained
unchanged. Smaller context reductions and a separate production-shape extension
have their own admission status below.

## Accepted annotated first probe

Root's serialized retry returned compile exit 0 in
`target/stdlib-work/resumable-transport-admission-compile-typed-retry.log`.
The generated file was confirmed as ELF64 EXEC with machine 62 (x86_64) using
readelf. Native execution returned 0 with empty stdout/stderr in
`target/stdlib-work/resumable-transport-admission-native-first.log`. Both logs
are empty successful receipts. No compiler patch was made.
`accepted-first.sha256` records the accepted main and four imported source
modules; the production-shape extension does not modify those files.

This verifies the two concrete first-probe executions and their value/state
assertions with explicit Pending and Result contexts. The precise minimal
inference boundary remains unverified until the three reductions run.

## Observed consumer admission failure

`original/main.lani` preserves the exact first entry source, with its SHA-256 in
`original/main.sha256`. The corresponding diagnostic is retained verbatim in
`original/compile-first.log`; the root receipt is
`target/stdlib-work/resumable-transport-admission-compile-first.log`:

```text
error[LNC0006]: type mismatch
 --> tests/fixtures/stdlib_compiler_state/resumable_transport_admission/main.lani:24:142
```

The expression was:

```text
let item: admission::scheduler::Outcome<admission::plain::Error> = report.outcomes.set(index,admission::scheduler::Outcome::Pending).unwrap();
```

This locates the observed failure at a generic record-field member call whose
argument is a nullary generic variant and whose Result is immediately unwrapped
under a receiving annotation. It does not yet isolate which of those contexts
loses the type, establish that imported Driver/Factory dispatch is unsupported,
or prove a shared cause with an earlier compiler dependency.

The current full `main.lani` changes only that reset in both concrete consumers:
an explicitly typed `Outcome<E>` Pending local, an explicitly typed
`Result<Outcome<E>,alloc::vec::Error>` member result, and then a typed unwrap.
The generic scheduler/traits and both concrete error types are unchanged.
That annotated full form is the accepted control above. It establishes a
source annotation distinction, without claiming a compiler repair.

## Small candidate reductions

All three entries use the same imported two-variant `Outcome<E>`, generic
`Report<E>` field and stored scalar error value 37. None imports the scheduler
or drivers. Native success must inspect that returned value and return 0.

| Entry | Context at reset | Execution status |
| --- | --- | --- |
| `reduction_nested.lani` | Original nested set/Pending/unwrap shape. | Pending. |
| `reduction_pending_only.lani` | Typed Pending local; nested set/unwrap retained. | Pending. |
| `reduction_typed.lani` | Typed Pending and typed member Result before unwrap. | Pending. |

These are candidate reductions until the original diagnostic is reproduced.
If a small form passes, that narrows its scope; it does not invalidate the
preserved full-probe failure. The typed forms use ordinary source annotations,
not a production error specialization or compiler change.

## Initial trait boundary

`admission/protocol.lani` imports the requested boundary:

- `Driver<E>` returns concrete Stats and `Result<Option<Response>,E>`, plus
  fallible abort. The owned Response layout is independent of E.
- `Factory<J,P,D,E>` prepares a borrowed J, consumes P on both begin outcomes,
  and classifies a borrowed error descriptor without releasing its payload.
- `admission/scheduler.lani` provides one imported
  `run<F,J,P,D,E>` with `Vec<Option<D>>` active slots and
  `Vec<Outcome<E>>` results containing typed `Fault<E>` records.

Jobs enter as `View<&J>` so this probe tests the requested borrowed-job factory
contract without adding a separate generic borrowing trait. The caller keeps
the concrete jobs alive. Driver slots are disarmed before step/abort, restored
only for a pending result, and absent before the generic Vec is destroyed.

The candidate main specializes that exact function twice. The first error is a
small Local/Clock/Timeout enum. The second is a record with a distinct nested
kind and `Option<Context>`; Context contains `Result<Option<i32>,bool>` and an
independently owned byte Vec. Both Factory implementations classify typed
Timeout/Clock variants as shared and Local as local, with no integer error
casts or type erasure. The prepared and driver shapes also differ: the second
contains an optional compound payload, fixed array and u64 call counter.

Each specialization covers success, prepare error, consuming begin error,
step error, abort error and successful abort. The successful driver first
returns None, is reinstalled in its generic slot, then transfers a concrete
Response. Compound `Cell { i64, bool }` elements exercise the Vec's canonical
strided raw-storage owner; no separate raw allocator abstraction is invented.
The assertions inspect exact high/negative values, nested error payloads,
stats fields, dispatch classification and logical acquisition/release counts.
Completed cells and error bytes remain readable after driver cleanup and are
released by the concrete consumer after disarming the result slots.

This is a small executable admission candidate, not the production batch
scheduler or a network/TLS test. It does not establish fault cleanup on OOM,
all possible driver states, type-level linear ownership or native ABI breadth.
The logical counters supplement actual buffer reads and explicit destruction;
they are not an independent native mapping ledger.

From the repository root, using the already-built CLI:

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  target/stdlib-build/debug/laniusc --stdlib-root stdlib \
  --source-root tests/fixtures/stdlib_compiler_state/resumable_transport_admission \
  tests/fixtures/stdlib_compiler_state/resumable_transport_admission/main.lani \
  -o /tmp/resumable-transport-admission
timeout --kill-after=1s 2s readelf -h /tmp/resumable-transport-admission
timeout --kill-after=1s 2s /tmp/resumable-transport-admission
```

Acceptance requires successful ELF generation, an x86_64 executable header,
and native exit 0 with empty stdout/stderr. A check-only result is insufficient.
Save the compile/header/native exit receipts separately. If admission fails,
retain this source and exact diagnostic before attempting a smaller reduction;
do not infer a common cause from earlier generic/compiler dependencies.

To compile a reduction, use the same bounded command with exactly one selected
entry (`reduction_nested.lani`, `reduction_pending_only.lani` or
`reduction_typed.lani`) and a distinct output path. Run each compile as a
separate invocation; for example:

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  target/stdlib-build/debug/laniusc --stdlib-root stdlib \
  --source-root tests/fixtures/stdlib_compiler_state/resumable_transport_admission \
  tests/fixtures/stdlib_compiler_state/resumable_transport_admission/reduction_typed.lani \
  -o /tmp/resumable-transport-typed
timeout --kill-after=1s 2s readelf -h /tmp/resumable-transport-typed
timeout --kill-after=1s 2s /tmp/resumable-transport-typed
```

## Separate production-shape candidate

`production_shape.lani` with `shape/adapters.lani` and `shape/runner.lani` is a
separately accepted executable control. It imports the **actual** public
`ext::http_batch::Driver<E>`, `Factory<J,D,E>`, `Report<E>` and `Outcome<E>`
definitions. No mirrored replacement interface or production module edit is
used. It requires the additional `extended` source root.

The generic runner accepts `View<J>` and a borrowed Factory. Job arguments to
request/begin are by-value shallow borrowed descriptors. It creates real
canonical HTTP Prepared owners with `prepare_until`; each fixture Factory
consumes/disarms that owner on both begin results, without opening a socket.
The two concrete drivers wrap the accepted first-probe owners. Their distinct
state layouts remain intact, while all six production Driver methods are
called through the generic bound: stats, interest, raw_handle, before_wait,
step(Readiness), and abort. Both pending reinstallation and terminal removal
are checked. All five production Factory methods are also dispatched.

Successful responses are converted to independently owned concrete HTTP
Responses with canonically parsed wire views and three binary body bytes.
The compound-cell values are checked before their source owner is released.
This isolates interface/owner admission; it does not run the real scheduler,
network or TLS, or claim that its fixture counters are engine performance
measurements.

The current simple and nested Error types implement `core::clone::Destroy` in
the new adapter module. Constructors and the generic run have no Destroy bound.
Only generic consumers require `E: core::clone::Destroy<E>`:

- One typed error is taken from the actual Report and released through
  `E::destroy_value`; repeated take is None.
- Three retained owned nested errors, including an abort cleanup error, are
  released by the actual generic `Report<E>.destroy` implementation.
- A taken completed Response remains readable after report destruction and is
  released by the generic outcome consumer. Repeated report destruction is
  checked separately.
- Extra Timeout and Clock(707) conversions preserve typed shared causes; the
  resulting nested owned payloads also use the generic destruction path.

For the nested specialization, the ledger must progress from 9 acquisitions
and 5 releases after the run, to 6 releases after taking/destroying one error,
to 9 after report destruction, and finally 11/11 after two conversion errors
are created and released. The error payload bytes and nested Result/Option
values are inspected while live. These executed assertions check destruction
dispatch; they do not replace an independent mapping ledger.

The root's serialized compile returned 0 in
`target/stdlib-work/resumable-transport-production-shape-first.log`. The result
was confirmed as ELF64 little-endian EXEC for x86_64. Native execution returned
0 with empty stdout/stderr in
`target/stdlib-work/resumable-transport-production-shape-native.log`. This
control covers its two concrete driver/error shapes and generic destruction;
actual scheduler, network and TLS behavior have separate runtime gates.

Reproduce it separately from the accepted first probe:

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  target/stdlib-build/debug/laniusc --stdlib-root stdlib --source-root extended \
  --source-root tests/fixtures/stdlib_compiler_state/resumable_transport_admission \
  tests/fixtures/stdlib_compiler_state/resumable_transport_admission/production_shape.lani \
  -o /tmp/resumable-transport-production-shape
timeout --kill-after=1s 2s readelf -h /tmp/resumable-transport-production-shape
timeout --kill-after=1s 2s /tmp/resumable-transport-production-shape
```
