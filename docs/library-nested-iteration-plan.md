# Scan and nested iteration

Status: proposed next library increment after filesystem commit `48837130`.
Production adapters below are not implemented or accepted. Small executable
admission candidates are being checked first. The complete standard and
extended library goal remains open.

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

The explicit value-transfer policy under admission is:

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

This establishes the narrow user-module value/retirement mechanism. It does
not establish a production outer traversal, initially empty construction,
stdlib-classified public adapters with caller-defined policies, or a strict
pre-exit mapping ledger. Those remain explicit implementation/acceptance gates.

## Acceptance and real use

Use an independent nested-list/state-machine oracle for empty inners, source
and callback order, early stopping, resumption, retirement error, active-owner
recovery and fused calls. Effect traces must show retirement before subsequent
outer acquisition. Exercise arbitrary supported generic payload shapes and
real nested String owners; verify pre-exit allocation balance, no adapter
allocation during traversal, no double retirement, and no lost active or outer
remainder. Scan tests cover terminating None, errors, state changes and exact
source/callback counts.

A `flatten_sum` program will read bounded integer rows, build owned per-row
vectors, flat-map rows into owning cursors, explicitly retire exhausted backing,
and TryScan checked running totals. It stages bounded output before delivery.
Its gates include empty rows, malformed/binary input, integer overflow, source
allocation failure and output failure, using real library modules.

Initial acceptance is native Linux x86_64 CPU execution of programs emitted by
the GPU compiler. No user-program GPU or other-host support is inferred.
Relevant operation/allocation counts and representative compilation evidence
must retain their measured workload scope.

## Subsequent ownership-aware sinks

Replacement sinks remain part of the full roadmap. They follow this increment
under a separate contract: rejection before insertion returns the incoming
owner, while a failure delivering an already displaced owner must report the
committed replacement and return that displaced owner. Existing TrySink
rejection semantics remain unchanged. A secondary-output failure must never
silently discard displaced keys or values.
