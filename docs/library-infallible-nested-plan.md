# Ordinary nested iteration

Status: the selected increment is implemented and accepted on the finite native
profile in the [module guide](stdlib-infallible-nested.md). Public admission,
semantic/payload checks, negative bounds, live native-owner checks and the
migrated real application pass. This increment does not complete the standard
and extended library goal.

## Library gap

The canonical iterator protocol already provides recoverable `TryFlatten` and
`TryFlatMap`. A caller whose mapping and inner retirement cannot fail must
still construct and consume `Result` items. Ordinary `flatten` and `flat_map`
should yield `T` directly while retaining the same ownership and effect order.

## Chosen contract

- Add `Flatten<I,J,R,T>` and `FlatMap<I,M,R,S,J,T>` in `core::iter`, with
  `flatten(source, retirement)` and `flat_map(source, mapper, retirement)`.
- Flat-map uses the existing ordinary `Mapper<S,J>` trait.
- Retirement uses the existing `InnerRetirement<J,E>` protocol with the real
  empty `core::clone_values::Infallible` error. A fallible retirement policy
  remains on the `try_` API. There is no fabricated error case or erased error.
- Both adapters call the existing `nested_next` engine. A per-call mapping
  bridge lifts an ordinary inner to `Ok(inner)`; no borrowed bridge escapes.
  The returned infallible Result is projected to a plain item.
- Keep lazy construction, one active inner, retirement before the next outer
  acquisition, fused exhaustion and explicit `take_active`/`try_finish`.
  Early stopping preserves the actual mutated inner and unread outer owners.
- The adapters allocate and destroy nothing themselves. Callers provide a
  retirement policy for borrowed or owning inners and keep all backing alive.
  An ordinary policy must actually complete cleanup without reportable failure.

Reusing the existing retirement protocol avoids a second cleanup abstraction.
Reusing the existing empty error avoids distinct nominal substitutes. Existing
fallible APIs and traversal state transitions keep their established behavior.

## Implementation and acceptance

1. Admit both public adapters with an executable smoke using the real empty
   error, ordinary callbacks and active recovery.
2. Compare plain-item traversal, lazy effects, early finish/take and shared
   source resumption against an independent sequence model. Exercise nested
   optional/result/array values, wide words, strided views and zero-sized items.
3. Reject fallible mapping/retirement and incompatible inner item types at the
   public helper call. Negative compiler tests establish no runtime behavior.
4. Check actual Vec/Deque String owners across complete traversal and early
   take/resume, including live cleanup, held outputs and callback order. Do not
   repeat fallible-adapter fault campaigns for an adapter with no error path.
5. Migrate the existing `flatten_sum` application, whose cursor acquisition
   cannot fail, to ordinary flat-map. Use a total scalar retirement policy;
   retain checked arithmetic, bounded input/output and all error cleanup.
   Run its existing independent behavior, bounds, allocation and I/O gates.
6. Document accepted sources, runtime receipts and target limits; refresh the
   declaration inventory only after implementation is stable.

The selected runtime target is Linux x86_64 CPU programs emitted by the GPU
compiler. Compilation through that compiler does not establish execution as a
user GPU kernel. Compiler failures require isolated evidence and a recorded
dependency; no compiler change is part of this library increment.

The module guide is [ordinary nested iteration](stdlib-infallible-nested.md).

## Accepted checkpoint

- Public smoke: direct compile and native exit zero for both adapters.
- Semantics: two Rust tests pass together in 9.38s, covering 24 modeled
  schedules in one native process and the separate payload/composition program.
- Bounds: three source-local negative Rust tests pass in 4.77s.
- Native owners: all eight direct cases pass with four live checkpoints and no
  allocation attempt after setup. No fallible-adapter fault cases are repeated.
- Real application: all four direct oracle groups pass 219 overlapping cases,
  including all ten reached source allocation failures and the existing I/O
  fault profiles. The registered app driver and independent oracle are unchanged.

The core source is `5034fbac...`; the migrated application is `65cfcdfc...`.
No existing traversal body or compiler/runtime source changed. The guides and
fixture receipts distinguish Rust test runs, direct retained-ELF executions,
CPU-only oracle checks and historical fallible-application evidence.
