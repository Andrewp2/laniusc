# Ordinary flatten and flat-map

Status: the selected increment is accepted on the finite native profile below.
Public admission, semantic/payload checks, negative bounds, live native owners
and the migrated real application pass. The fallible adapters retain their own
[contracts and receipts](stdlib-nested-iteration.md).

## Public API

| Function | Bounds | Iterator item |
| --- | --- | --- |
| `flatten<I,J,R,T>(source:&I, retirement:&R) -> Flatten<I,J,R,T>` | `I:Iterator<J>`, `J:Iterator<T>`, `R:InnerRetirement<J,core::clone_values::Infallible>` | `T` |
| `flat_map<I,M,R,S,J,T>(source:&I, mapper:&M, retirement:&R) -> FlatMap<I,M,R,S,J,T>` | `I:Iterator<S>`, `M:Mapper<S,J>`, `J:Iterator<T>`, same retirement bound | `T` |

All names except the explicitly qualified error type belong to `core::iter`.
`Infallible` is an empty enum: safe callers cannot construct an error value.
Retirement still returns `Option<RetireFailure<J,Infallible>>`, using the
existing protocol; a successful policy returns `None`. A policy with a real
failure case must use `try_flatten` or `try_flat_map`.

Ordinary nested adapters support `borrow()`, `has_active()`, `take_active()` and
`try_finish()` with the same recovery contracts as their fallible counterparts.
Taking closes the adapter and transfers the actual updated inner, including
after its final item has been yielded but before its terminal `None` is read.
Finishing with an active inner reports `NestedFinishError::Active` and changes
nothing. Finishing without an inner closes without consuming the outer.

## Effects and ownership

Construction calls no iterator, mapper or retirement policy. One shared engine
advances the active inner, restores its mutated value after an item, retires it
after terminal `None`, and only then acquires another outer item. Flat-map calls
its ordinary mapper once for each acquired outer item. EOF fuses the adapter;
later calls perform no further work.

Retirement consumes the exhausted cursor's cleanup authority. It can release
owned backing or explicitly disarm a resource-free borrowed cursor. It must
not retain another active shallow copy. A no-op policy is appropriate only for
a cursor with no owned resource or remaining cleanup obligation.

The adapter itself performs no allocation, cloning or destruction. Keep the
outer cursor, mapper, policy and borrowed backing valid. Yielded borrowed
items must stop being used before retirement releases their backing. Yielded
owners transfer their own cleanup obligations to the consumer. Shallow copies
do not create independent ownership. Sources and callbacks must not reenter the
adapter or mutate its active inner through another alias.

On an early stop, take and resolve the active inner, then recover or release
the unread outer items separately. Abandoning an adapter does not clean either
up. A downstream output quota does not bound the work of crossing empty inners;
bound the outer and callback operations when finite work is required.

## Verification

The implementation is frozen at SHA-256
`5034fbac8a84b1499af18fbaf2963d54da4452e633413d33804b154e1a108a64`.
It adds 92 lines to `core::iter`; all earlier bodies, including `nested_next`,
are unchanged. Independent source review found no material issue in the
bridges, empty error, recovery or application cleanup.

| Gate | Current evidence |
| --- | --- |
| [Actual public smoke](../tests/fixtures/stdlib_foundation/infallible_nested_iteration/README.md) | Direct CLI compile and native exit zero for both adapters, lazy/empty traversal, retirement order, finish refusal, take/resume and fused effects. |
| Independent semantics and payloads | Two Rust tests pass together in 9.38s after a separate 1.76s build. The model compares 24 curated action schedules in one native process with the existing independent row/deque oracle; the shape test checks optional/Result/array items, wide words, actual descending and packed positive byte strides, zero-sized items and Scan/Take composition. |
| [Negative bounds](../tests/fixtures/stdlib_foundation/infallible_nested_bounds/README.md) | Three Rust tests pass in 4.77s after a separate 1.80s build. Fallible mapping/retirement and wrong inner items produce source-local LNC0008. These tests execute no emitted program. |
| [Real flatten_sum program](stdlib-flatten-sum.md) | All four direct Python oracle groups pass on one retained current ELF: models138, bounds54, allocations11 (baseline plus10 reached OOMs) and faults16. These 219 group cases overlap setup/baselines; they are not four current Rust-libtest receipts. |
| [Live native owners](../tests/fixtures/stdlib_execution/infallible_nested_iteration_owners/README.md) | Eight direct native cases pass: Vec/physically wrapped Deque × Flatten/FlatMap × full/early-take-resume. Four acknowledged live checkpoints verify actual owner partitions, held output after deep cleanup and zero source mappings before exit. There are no reached OOM cases in this infallible-adapter campaign. |

The smoke logs are `infallible-nested-public-smoke-first.log` and
`infallible-nested-public-smoke-native-first.log`; its retained ELF is
`262636b9c15f4c702eed2c724e3295a58849ecd2a403be496073b8c5a1f3a1b7`.
Semantic and bound receipts are `infallible-nested-model-shapes-first.log`
and `infallible-nested-bounds-first.log`. App receipts use
`infallible-flatten-sum-{models,bounds,allocations,faults}-first.log`.
All logs are under `target/stdlib-work/`; linked fixture guides record source
and executable identities. The nine semantic CPU controls are separate from
native behavior. Existing unchanged application oracle controls were not rerun.

Owner source `0a8aa0d4...`, retained ELF `530cbe74...` and oracle `7f7c77c8...`
pass in `infallible-nested-owners-lifecycle-first.log`, with evidence under
`/tmp/infallible-nested-owners-zvsp_l7g`. The oracle reuses the accepted raw
allocation and live-process verifier, checks exact callback/retirement order,
and forbids every new source allocation attempt after setup, even inside the
mapper, retirement and recovery callbacks. Twenty-five CPU oracle controls are
separate. The direct native gate is not a passing Rust-libtest receipt.
Its registered Rust driver builds with `--no-run` in 1.75s, recorded in
`infallible-nested-owner-driver-build-first.log`; that build repeats no native
owner cases.
The final probe `5bed1e45...` removes only one trailing ASCII space from the
executed `0a8aa0d4...` form; the fixture guide records that byte-only cleanup.

The executed profile is native Linux x86_64 CPU output from the GPU compiler.
No other host or user GPU-kernel execution follows from these receipts. The
separate [compiler dependencies](library-dependencies.md) remain open; this
increment changes no compiler, IR, ABI, extractor, proof or runtime source.
The complete standard and extended library goal remains open.
