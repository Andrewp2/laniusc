# Nested iteration admission

These are small executable admission candidates for a proposed canonical
iterator extension. They do not implement a second iterator protocol or add
production APIs. Accepted execution is recorded separately from negative
compiler admissions below.

## First boundary: stored generic borrow

`slot_record.lani` isolates `Slot<T>::value_ref(&self) -> &T`, using the proposed
ordinary field return `return self.value`. It deliberately has no `Borrow`
trait, per-type borrowing helper, `Option` pattern binding or allocator.

Successful compilation alone is insufficient. Native assertions must show
that two generic projections mutate the same stored record, including its wide
scalar and array fields, while the original record's scalar fields stay unchanged.
The root's first CLI attempt **failed before native execution**, reporting
`LNC0006` at `return self.value`: the expression did not provide the required
`&T`. Receipt: `target/stdlib-work/nested-slot-record-first.log`. The negative
source remains unchanged (SHA-256
`cd154933c75b5c10de759e3e0ee953fe53267e0c23565d45b4515fa21600fed2`).
It is not an implemented library borrowing API.

The value-transfer candidates below exercise borrowed slice cursors, owning
Vec/Deque cursors, retirement failure and explicit active-owner recovery.
Those ownership contracts are not established by the rejected record control.

## Separate boundary: optional stored payload

`option_record.lani` matches `&Option<T>` and attempts to return `Option<&T>`.
Its current isolation uses a test-local inherent `Option<T>::candidate_borrow`
which returns `self`; it does not project an ordinary generic record field.
It separately tests whether a `Some` binding borrows the stored payload or a
temporary pattern copy. Two calls through a generic forwarding helper must
update the record inside the actual option. It then ends the borrows, changes
the slot to `None`, and checks both changed and initially empty slots.

The first version (SHA-256
`1985c2fb52fc74e0928ad84f68f919450095c6c92bb514f8f2d4adc48c6b731f`)
failed at its duplicated `Slot<T>::value_ref` prerequisite, before it could
establish anything about enum-payload matching. That failure is **not evidence
that borrowed enum-payload matching fails**. The current isolated candidate
has not been run and is optional for the chosen value-transfer design (SHA-256
`555ef3ea9e0a8e32adc9ea269a896f641233df6aab5a687edfe2de6055bf6037`).
A passing ordinary record-field projection would also not establish
borrowed enum-payload projection. Neither
candidate changes `core::option` or assumes enum layout, a default `T`, or
implicit ownership through an `unwrap()` copy. The first control checks that
the original record's scalar fields stay unchanged; it does not claim that
by-value array backing is independent.

## Value transfer and generic receiver: accepted slice control

`value_next.lani` follows the general value contract supported by the proposed
iterator design: extract `J`, clear the actual `Option<J>`, invoke `J.next()`
on that local receiver, and reinstall the updated `J` before returning.
The old shallow option/cursor copies stay inactive throughout. No reference
escapes, no default `J` is fabricated and no additional borrowing trait is used.

It uses the existing `core::iter::Iterator` and borrowed `slice::Iter<i32>`.
Native assertions establish persistent progress over three values,
fusion without another inner call, terminal recovery, and early recovery of
the two-item remainder. This narrow candidate alone does not establish
retirement or allocation ownership; the separate owning control below covers
its own finite value/retirement cases.

The initial version carried only `Active<J>` (SHA-256
`cd9cc2e2f636af8151eb8e0ce602a8116dca408a75bc497cbf9c029bec7db6e7`).
Its first CLI attempt failed before native execution at `active.next()` with
`TraitBoundUnsatisfied` (`LNC0008`, detail 4), recorded in
`target/stdlib-work/nested-value-next-first.log`. This call shape asked the
compiler to infer `T` in reverse from `J`'s iterator bound; it did not establish
a failure of a generic local `J.next()` receiver. The current candidate carries
`Active<J,T>`, matching the explicit item parameter of the planned adapter and
existing canonical adapters. The corrected source (SHA-256
`430f4660e30147b4a7476f94cd5445cb04a21e099cedc092eb7ed6e4d733d63c`)
passed CLI compilation and all native assertions, both with exit 0. Receipts:
`target/stdlib-work/nested-value-next-nominal-item-retry.log` and
`target/stdlib-work/nested-value-next-native-first.log`. This establishes only
the finite borrowed-slice value-transfer control, not general flatten behavior.
The CLI SHA-256 for these admissions is
`1c2718d4c17b7da613f999412bff037eef3770cb755a74e35e7eebd2cfc202f6`;
the accepted `value_next` native ELF SHA-256 is
`ff02a22b2112e1276684ecb07b1bec0de62354e53564a3744825e8e1ee375957`.
These receipts do not use the CLI hash from the earlier filesystem increment.

## Value retirement and owning cursors: accepted user-module control

`value_retirement.lani` adds one candidate generic active-owner boundary over
the existing `Iterator<Result<T,E>>` protocol. The callback consumes `J` by
value and returns `Option<RetireFailure<J,E>>`. `None` consumes all remaining
inner backing authority; `Some` returns the actual updated inner and a separate
error. The engine clears its optional owner before calling either the generic
receiver or retirement policy. It reinstalls only the returned failure inner,
emits the error once and fuses. `take_active()` disarms before transfer.
The first source (SHA-256
`1b9e33a7f28c4632d72c583d38d7e8c14634d85e8cfed6b7dcfbf0cc38b2942d`)
failed CLI admission before native execution: its two retirement implementations
had the same nongeneric `Policy` receiver pattern despite different trait
arguments (`LNC0027`, `target/stdlib-work/nested-value-retirement-first.log`).
The corrected candidate uses disjoint `Policy<Vec::IntoIter<T>>` and
`Policy<Deque::IntoIter<T>>` receiver patterns. This changes caller policy
identity only; one generic engine and the same retirement/value contracts
serve both. The initial rejection does not establish an engine or generic
owner-state failure. The typed-policy source SHA-256
`3b2b1a91e64e7ec9db18205616e373e88ccb9a5f1ca840859f0ed1873e1aff72`
received read-only review. Before the accepted gate, the root added three
missing payload checks: error message bytes 2 and 4, and the last item's first
array cell. No engine or ownership contract changed.

All six authored native profiles passed: success, partial retirement failure/recovery,
and early recovery for each of real Vec and wrapped Deque owning cursors. Items
contain wide signed/unsigned scalars, fixed arrays and nested Option/Result
arrays/errors. A partial failure really frees a scratch allocation while
retaining cursor backing. Its mutated step counter and disarmed scratch
survive recovery; the caller retries retirement, then checks an independently
owned binary/UTF-8 String error before releasing it exactly once. These checks
would fail if the engine reinstalls its obsolete pre-policy shallow copy.

The accepted source SHA-256 is
`6244ebe9d31fb3468fb3883c5dbc4c2b1b310884c2156f38e0029bac47ec9894`.
CLI compilation and the emitted native executable both exited 0:
`target/stdlib-work/nested-value-retirement-policy-identity-retry.log` and
`target/stdlib-work/nested-value-retirement-native-first.log`. The accepted
ELF SHA-256 is
`e3d9578d85bfe46158bcce149beaca83cf99e8bee4c4495174ebba33423b421d`;
the CLI is the same `1c2718d4...202f6` recorded for the slice control above.
Execution scope is native Linux x86_64 CPU programs emitted by the GPU
compiler. This is not user-program GPU execution or a passing Rust/libtest gate.

This admission has no outer iterator, flatten loop, resource-fault campaign or
strict native allocation ledger. It establishes this finite user-module
value-flow boundary only. Source counters and post-release capacity assertions are not
substitutes for the later production adapter resource gates.

Both value-transfer controls define their candidate state/policy machinery in
the **user entry module**. They import the real `core::iter::Iterator`, but do
not establish that an adapter defined inside a stdlib-classified module can
compose with caller-defined retirement and mapper implementations. The actual
production adapters must pass that public-import boundary separately. Initially
empty active construction, outer acquisition/ordering, and strict pre-exit
native allocation balance also remain future gates.

## Reproduce a positive control

From the repository root, using the existing CLI build, hold the compiler lock
through compilation and native execution. A failed compilation must not run an
older ELF. The outer deadline bounds the complete command:

```sh
timeout --kill-after=2s 100s flock target/stdlib-work/library-gpu.lock bash -c '
  set -e
  ulimit -c 0
  target/stdlib-build/debug/laniusc --stdlib-root stdlib --emit x86_64 \
    tests/fixtures/stdlib_foundation/nested_iteration_admission/value_retirement.lani \
    -o target/stdlib-work/nested-value-retirement.elf
  timeout --kill-after=1s 10s target/stdlib-work/nested-value-retirement.elf
'
```

The corresponding `value_next.lani`/`nested-value-next.elf` paths select the
slice control. `slot_record.lani` is a negative admission and must not be
treated as an executable success case. The isolated `option_record.lani`
candidate has no current execution receipt.

The parent ran every accepted compiler/native gate above. Fixture authors
performed source work and read-only review; they ran neither compiler nor
native Lanius.
