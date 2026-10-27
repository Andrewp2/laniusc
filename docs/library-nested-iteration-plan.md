# Scan and nested iteration

Status: implementation after filesystem commit `48837130` and admission
checkpoint `b77567b5`. The four production adapters execute through actual
public stdlib imports. Two direct smoke programs, three semantic Rust tests
and all four real-application tests pass. All four strict adapter ownership/fault
groups also pass directly against the retained native executable. This accepts
the selected increment on the documented native target.
The earlier user-module controls retain their narrow accepted scope below.
The complete standard and extended library goal remains open.

## Existing boundary

Extend the canonical `core::iter::Iterator<T>` protocol and its documented
fused, shallow-value semantics. Keep one traversal engine for nested iteration.
Production remains Lanius; Rust/Python may only drive tests. Root serializes
compiler/native commands under `target/stdlib-work/library-gpu.lock`, with
every command below two minutes. No compiler IR, ABI, extractor, proof or
runtime implementation belongs to this increment. A missing compiler contract
requires an isolated reproduction and a dependency entry.

Ordinary owning collection cursors retain exhausted backing until explicit
finish or recovery. Replacing an exhausted inner cursor without retiring its
backing would leak it. Borrowed-only flattening would leave this general
ownership problem unsolved. This increment therefore includes explicit inner
retirement and recovery, rather than silently discarding owners.

## Scan contracts

Use the existing borrowed `Mapper<T,U>` callback pattern. The callback owns
its mutable state; the adapter borrows both callback and source.

| Adapter | Callback result | Canonical iterator item |
| --- | --- | --- |
| `Scan<I,M,T,U>` | `Option<U>` | `U` |
| `TryScan<I,M,T,U,E>` | `Result<Option<U>,E>` | `Result<U,E>` |

Construction performs no source/callback work or allocation. Each `next`
pulls at most one source item and invokes the callback at most once. Source
exhaustion skips the callback. Callback None consumes its current input and
permanently stops the adapter. TryScan emits one error item and then fuses;
failure never becomes ordinary successful exhaustion. All later calls after
termination avoid source/callback effects.

The caller keeps callback, state, source and backing alive. Consumed items,
replaced state, returned outputs and errors keep their documented cleanup
authority. The adapter introduces no deep clone or automatic destruction.

## General nested iteration

The implemented value-transfer policy is:

```text
RetireFailure<J,E> { inner:J, error:E }
InnerRetirement<J,E>::try_retire(&self, inner:J) -> Option<RetireFailure<J,E>>
```

`TryFlatten` borrows an outer `Iterator<J>` and the retirement policy, holding
at most one transferred inner `J: Iterator<T>`. It implements the same
`Iterator<Result<T,E>>` protocol. A nonempty inner yields Ok items. After an
inner returns None, the adapter transfers that inner to retirement. A None
result promises that all backing owned by the inner is released or disarmed
before the next outer item is acquired. An ordinary borrowed cursor can use a
policy which explicitly owns no backing. Retirement work remains caller-defined.

Retirement failure returns the actual updated inner with its error. The engine
reinstalls that returned inner, yields the error once and fuses. It never
reinstalls an older shallow copy. There is no rollback promise; any partially
retired state must remain valid and recoverable. Returned errors have separate
cleanup authority.

Before a local inner-next or retirement call, extract the active J and clear
the stored Option, transferring its sole position/cleanup authority to that
local or callback. After an item pull, reinstall the mutated local J. No cursor
or policy callback may reenter the adapter during this transition. This design
needs neither an implicit T-to-reference conversion nor a reference to an
unwrapped temporary. It also introduces no default-J, layout, per-type helper
or extra borrowing-trait requirement.

`take_active()` transfers the active inner and closes this adapter without
another source/policy call. `try_finish()` refuses while an active inner
remains and otherwise closes without consuming the outer. Early-stopping
callers recover/release the active inner first. The outer is already positioned
after that transferred inner; a fresh adapter can continue from its next item.
The adapter never drains, destroys or closes the remaining outer source.

`TryFlatMap` uses the same nested state transition, with a borrowed callback
returning `Result<J,E>`. Mapping and retirement use a common caller-chosen
error type, including a tagged enum when appropriate. A mapping failure emits
one error and stops; the callback must release its own partial result. Do not
return an adapter borrowing a temporary local Map wrapper.

One next call can cross many empty inner cursors. Downstream Take quotas do
not bound that work. Bounded applications must bound outer acquisition and
potentially infinite inner cursors separately. Returned borrowed items cannot
outlive inner backing released at retirement. Adapter copies alias one manual
owner, and abandoning an active adapter performs no cleanup.

An ordinary flatten specialization requires actual admission with a real
uninhabited error type. Do not fabricate an error variant, introduce per-type
overloads or require unrelated borrowing traits merely to admit the engine.

## Admission before implementation

The [small source candidates](../tests/fixtures/stdlib_foundation/nested_iteration_admission/README.md)
separate source-language admission from the desired runtime contracts:

1. The initial borrowed-policy proposal tried returning a stored T as &T.
   The first Slot candidate is rejected with LNC0006 before native emission;
   an Option candidate initially had the same failed prerequisite. This does
   not establish arbitrary generic or enum-payload failure. Its corrected
   enum-only matching candidate has a separate admission question.
2. The value-transfer design must prove that generic local J.next mutates the
   actual cursor which is reinstalled in its Option. Empty construction,
   early take_active recovery and fused call counts must execute. The first
   tiny candidate omitted T from its nominal Active<J> and failed bound
   inference at an unannotated call; the representative Active<J,T> retry
   retains that item parameter as the planned public adapters do.
3. Borrowed slice cursors and owning Vec/Deque cursors preserve position and
   owner state through that boundary, with nested Option/Result and wide items.
4. Retirement success disarms stored backing; failure preserves a recoverable
   active inner. An owned error is transferred exactly once.

Only actual native assertions establish positive admission. These initial
source-shape rejections are not confirmed compiler bugs or a reason to narrow
the supported inner-cursor types. A passing slice control does not establish
owning-cursor retirement or error-owner cleanup.

The representative `value_next.lani` candidate (SHA-256
`430f4660e30147b4a7476f94cd5445cb04a21e099cedc092eb7ed6e4d733d63c`)
now compiles and its native ELF exits zero. Its assertions check three advancing
slice values, the reinstalled remaining count, one terminal inner call with
fused later calls, and early take/recovery/resumption. Receipts under
`target/stdlib-work/` are `nested-value-next-nominal-item-retry.log` for
compilation and `nested-value-next-native-first.log` for execution. The ELF
SHA-256 is `ff02a22b2112e1276684ecb07b1bec0de62354e53564a3744825e8e1ee375957`.
The CLI observed for these new admission commands is
`1c2718d4c17b7da613f999412bff037eef3770cb755a74e35e7eebd2cfc202f6`;
its recorded modification time precedes all of these commands. The older
filesystem isolation's fresh CLI hash belongs to that earlier receipt.
The rejected initial sources have separate logs; no native result is inferred
from either. This slice receipt alone establishes no owning-cursor retirement
or production-adapter behavior.

The user-module `value_retirement.lani` prototype now also compiles and exits
zero with six authored profiles: Vec and physically wrapped Deque each exercise
success, partial retirement/error recovery and retry, and early active-owner
recovery/resumption. A scratch allocation is destroyed before the simulated
retirement failure while the cursor backing remains owned. Recovered step and
capacity assertions distinguish the actual returned updated J from an older
shallow copy. The nested wide payload and all five bytes of the owned error
String are checked. The error survives backing retirement and is explicitly
released once through its idempotent owner method.

The accepted source hash is
`6244ebe9d31fb3468fb3883c5dbc4c2b1b310884c2156f38e0029bac47ec9894`;
its ELF is `e3d9578d85bfe46158bcce149beaca83cf99e8bee4c4495174ebba33423b421d`.
Receipts are `nested-value-retirement-policy-identity-retry.log` and
`nested-value-retirement-native-first.log`. The first source failed LNC0027
because two policy implementations used equivalent nongeneric receiver
patterns. Giving the caller policy its inner-type marker admitted the same
single generic active-owner engine; no compiler or production source changed.
Independent review confirmed the stale-state discriminator and genuine cleanup
calls; three missing payload checks were added before the accepted run.

This establishes the narrow user-module value/retirement mechanism. Those
initial controls alone did not establish production outer traversal, initially
empty construction, stdlib-classified public adapters with caller-defined
policies, or a strict pre-exit mapping ledger. The production receipts below
now cover those separate acceptance gates.

## Acceptance and real use

Use an independent nested-list/state-machine oracle for empty inners, source
and callback order, early stopping, resumption, retirement error, active-owner
recovery and fused calls. Effect traces must show retirement before subsequent
outer acquisition. Exercise arbitrary supported generic payload shapes and
real nested String owners; verify pre-exit allocation balance, no adapter
allocation during traversal, no double retirement, and no lost active or outer
remainder. Scan tests cover terminating None, errors, state changes and exact
source/callback counts.

The `flatten_sum` program reads bounded integer rows, builds owned per-row
vectors, flat-maps rows into owning cursors, explicitly retires exhausted backing,
and uses TryScan for checked running totals. It stages bounded output before
delivery. Its accepted gates include empty rows, malformed/binary input,
integer overflow, source allocation failure and output failure, using real
library modules.

## Production checkpoint and current receipts

`stdlib/core/iter.lani` implements Scan/TryScan and TryFlatten/TryFlatMap with
one private `nested_next` traversal engine. TryFlatten supplies a call-local
identity Mapper; it stores no reference to that temporary. Both constructors
store only the borrowed source/callbacks and an initially empty active slot.
All previous API bodies are byte-preserved. The current production SHA-256 is
`7256a39462db691ece403a6d9a409947f7fafa7919783be474d510f1bf63ce3c`.

The first public scan import rejected the private identity's trait block
because the public Mapper contract requires a `pub impl`. Adding that keyword
admitted the module without changing any body, type or compiler source. That
initial source-authoring error is not a compiler dependency.

Receipts below are under `target/stdlib-work/`. Two smokes import the actual
public stdlib adapters and define callbacks/retirement in the caller. They do
not duplicate a local adapter implementation.

| Accepted scope | Execution | Receipt |
| --- | --- | --- |
| Scan/TryScan: lazy construction, empty source, callback None/error, state and fusion | CLI compilation and native exit 0 | `nested-public-scan-smoke-visibility-retry.log`, `nested-public-scan-smoke-native-first.log` |
| Nested adapters: empty-inner retirement order, updated-J failure, finish refusal, take/retry and outer resumption | CLI compilation and native exit 0 | `nested-public-nested-smoke-first.log`, `nested-public-nested-smoke-native-first.log` |
| Independent state models and generic shapes | Three Rust tests pass in one 9.31s command: 360 nested commands, 672 scan commands, nested Option/Result/arrays, wide records, actual strided views and zero-sized items | `nested-public-models-shapes-first.log` |
| `flatten_sum` composition admission | Three physical rows/four integer values produce the exact four running totals, native exit 0 | `nested-flatten-sum-admission-first.log`, `nested-flatten-sum-admission-native-first.log` |
| `flatten_sum` normal and admission groups | Two Rust tests pass: 138 model and 54 bounds process cases, 8.51s | `nested-flatten-sum-models-bounds-first.log` |
| `flatten_sum` allocation and I/O fault groups | Two Rust tests pass: 11 allocation cases (baseline plus all ten reached OOMs) and 16 I/O cases, 8.23s | `nested-flatten-sum-allocations-faults-first.log` |
| Larger `flatten_sum` workload | Accepted ELF processes 3,072 physical rows, including 2,048 empty rows, and 65,536 values; exact 382,110-byte output passes outside the timer | `nested-flatten-sum-scale-first.log` |
| Direct owner lifecycle | 14 healthy profiles pass through four live checkpoints, with real Vec/wrapped Deque and owned String items/errors | `nested-owners-lifecycle-lazy-count-retry.log` |
| Flatten allocation recovery | 30 process group cases pass, including two baselines and all 28 reached OOMs | `nested-owners-flatten-oom-first.log` |
| Flat-map Vec allocation recovery | 56 process group cases pass, including four baselines and all 52 reached OOMs, including resumed mapping | `nested-owners-flatmap-vec-oom-first.log` |
| Flat-map wrapped Deque allocation recovery | 56 process group cases pass, including four baselines and all 52 reached OOMs, including resumed mapping | `nested-owners-flatmap-deque-oom-first.log` |

The two registered smoke Rust functions were not rerun solely to change the
receipt format; their source programs have the direct accepted receipts above.
The 1,032 model commands are logical scenarios, not native process counts.
An initial Rust-driver build failed because its smoke helper passed Command
instead of a mutable reference; the one-character source correction rebuilt
both semantic/application drivers in 1.39s. This launcher correction changed
no Lanius source. The application groups total 219 process group cases,
including overlapping baselines and setup, rather than independent properties.
Their allocation traces require explicit release before process exit; they
do not supply the direct adapters' live ownership checkpoints.

The larger workload reuses the accepted application ELF rather than recompiling.
Its one untraced process takes 0.157614975 seconds, including launch, stdin
transfer, parsing, the owning pipeline, formatting and stdout capture. Input
and exact expected output are prepared before the timer; validation follows
it. This is one native application observation, not a compiler benchmark or
general throughput ratio. Evidence is under `/tmp/flatten-sum-scale-c24v1gy5`.

The strict ownership fixture's first lifecycle attempt
(`nested-owners-lifecycle-first.log`) rejects before native emission with GPU
parser code 4 and final stack-effect depth -4. The fallback LNC0021 points at
a nested Mapper argument, but that concrete header compiles in isolation.
The minimal rejected/accepted pair instead isolates the applied bound subject
`where Make<J>: Mapper<...>` versus a bare generic `M` subject. The canonical
grammar (`grammar/lanius.bnf`, `where_predicate`) admits only an identifier in
that position. This was unsupported fixture syntax, not a demonstrated generic
type failure or compiler regression. The test helper now accepts the borrowed
mapper explicitly, keeping the actual owning cursor types and effect contracts.
The [retained source controls](../tests/fixtures/stdlib_compiler_state/nested_iteration_owners/README.md)
record the reductions and separate declaration admission from runtime evidence.

The next attempt passes parsing but cannot infer a generic cursor-field call's
local result (`nested-owners-lifecycle-generic-mapper.log`). Explicit local J
and Option types, including reinstallation of the actual mutated cursor, admit
the same owning values. This source form needs no compiler change; the retained
original and diagnostic describe the observed inference gap without claiming
an isolated general inference defect.

The admitted probe SHA-256 is
`e92ee3b894a6ce93eafed81a217ef9f04dd5dcf610239ea1c8cb503a608fdfc4`.
Its first native attempt reaches the live resource checkpoints but exposes an
oracle expectation which counted an unconstructed flat-map inner as allocated.
The corrected oracle (`eb37f142...`) distinguishes three preconstructed flatten
inners from two constructed flat-map inners at retirement failure. The strict
source ledger, live mappings/descriptors, callback order and fault-prefix
assertions are unchanged. Four added CPU controls cover this eager/lazy
distinction; all 41 owner-oracle controls pass independently.

All four owner groups above then execute directly against the same retained
ELF, SHA-256
`3d99ec693eee833df297e5201e992210761845707a21ce00f7d176bc58b7d32c`,
without recompiling unchanged source. They total 156 process group cases,
including overlapping baseline/setup profiles, and 132 individually reached
OOMs. This is direct Python-oracle acceptance, not four passing Rust libtests.
The Rust driver has build/source admission and its first native oracle attempt;
the corrected direct receipts supply the runtime acceptance. Each profile
checks actual live `/proc` mappings and descriptors at four acknowledged frames,
including held output/error owners after inner/outer cleanup and zero remaining
source owners before exit. No hidden constructor or adapter allocation is
accepted. Callback allocations remain explicit caller effects.

Initial acceptance is native Linux x86_64 CPU execution of programs emitted by
the GPU compiler. No user-program GPU or other-host support is inferred.
Relevant operation/allocation counts and representative compilation evidence
must retain their measured workload scope.

## Subsequent ownership-aware sinks

The [replacement-sink plan](library-replacement-sinks-plan.md) remains part of
the full roadmap. It follows this increment under a separate contract:
rejection before insertion returns the incoming
owner, while a failure delivering an already displaced owner must report the
committed replacement and return that displaced owner. Existing TrySink
rejection semantics remain unchanged. A secondary-output failure must never
silently discard displaced keys or values.
