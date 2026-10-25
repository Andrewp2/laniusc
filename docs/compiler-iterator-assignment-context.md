# Iterator result assignment contexts

Assigning an imported iterator result to an existing local could lose the
result's concrete type and native width. The repair decodes the parser's
statement flag before finding the receiving assignment, then requires result
inference to preserve type bindings already accepted for the call. Both changes
belong to the shared GPU type checker. They add no IR or ABI field, pass,
resource, extractor behavior, or proof change.

## Observed failure

The [selection model](../tests/fixtures/stdlib_foundation/iterator_selection/model.lani)
copies a generic cursor and chooses which copy to pull:

```lanius
let item: core::option::Option<i64> = core::option::None();
if (((schedule >> call) & 1) == 0) { item = first.next(); }
else { item = second.next(); }
```

For the empty Filter command `[0, 0, 1, 0, 0]`, the native process exited zero
but emitted the branch used for a non-None value, followed by zero. Source
position remained zero, the source received one call, and the predicate received
none. The serializer labels every `is_none == false` result as present, so this
observation did **not** establish that the assigned enum actually held
`Some(0)`. The original mismatch and exact command are in
`target/stdlib-work/iterator-selection-admission/models-diagnostic.log`.

The first reducer trapped with SIGILL before writing any output; that distinct
failure did not confirm the model's observation. Its preserved log is
[initial-sigill.log](../tests/fixtures/stdlib_compiler_state/iterator_selection_assignment/observed/initial-sigill.log).
The revised [frozen reducer](../tests/fixtures/stdlib_compiler_state/iterator_selection_assignment/reducer.lani)
uses simple `i32` source fields and publishes each Boolean observation with a
checkpoint. It passed the strict ELF checks and exited zero, then failed the
host comparison in 3.78 seconds:

```text
actual:   65 1 66 0 67 0 68 0   2 1 1   0 0 1
expected: 65 1 66 1 67 1 68 0   2 1 1   0 0 1
```

Direct binding correctly observes None. Both assignment branches report the
wrong `is_none` result. The Some control and all source/callback counts agree.
The [preserved diagnostic](../tests/fixtures/stdlib_compiler_state/iterator_selection_assignment/observed/reducer-revised.log)
and [capture description](../tests/fixtures/stdlib_compiler_state/iterator_selection_assignment/README.md)
record that failing version. They are historical evidence, not final acceptance
results. Additional direct, unconditional-assignment, and branch controls are in
[controls.lani](../tests/fixtures/stdlib_compiler_state/iterator_selection_assignment/controls.lani).
The unconditional control also failed, so a branch merge was not necessary.

## Captured type and layout facts

Two dispatch captures preserve the helper replay before later specialization
jobs overwrite the ordinary debug dump buffers:

- `target/stdlib-work/iterator-selection-admission/controls-call-artifact/manifest.json`:
  `type_check.semantic_artifact.calls`, dispatch index 3. Inputs include
  `call_result_instance`, `call_inference_result_tag/payload`, declaration types,
  and compact HIR; outputs include `semantic_calls_by_hir`.
- `target/stdlib-work/iterator-selection-admission/controls-scatter/manifest.json`:
  `lir.x86.scatter`, dispatch index 3. Inputs include the checked OptIR call and
  store metadata; outputs include the native calls and aggregate copy rows.

These captures are local work artifacts under `target/stdlib-work`. Their row
numbers identify this captured replay, not stable compiler identities.

| Observation | Call HIR | `call_result_instance` | Projected call reference | Native result words |
| --- | ---: | --- | --- | ---: |
| Direct binding | 176 | 483 | instance, tag 3 / payload 483 | 2 |
| First assignment branch | 130 | absent | external canonical, tag 5 / payload 679 | 0 |
| Second assignment branch | 136 | absent | external canonical, tag 5 / payload 679 | 0 |
| Unconditional assignment | 220 | absent | external canonical, tag 5 / payload 679 | 0 |

All four calls select the same dependency symbol. Their inference-result tags
are absent at the call artifact capture; the direct call's receiving context
has already supplied its result instance. Later normalization expresses the
bad nominal references as tag 1 / payload 679, without recovering a concrete
instance or width. The assignment destinations and None initializers still
have the correct two-word instance layout.

The native direct call therefore reserves and captures both returned words.
The bad calls retain aggregate classification but declare zero result words,
so [result capture](../shaders/codegen/lir/x86/instruction_plan.slang) publishes
an empty aggregate address without storing the returned tag or payload. Each
destination then copies two words from that carrier. The lost width is visible
before native emission; it does not require a storage-overlap or SSA hypothesis.

## Receiving assignment ownership

The [parser context producer](../shaders/parser/hir/context/relations/scatter.slang)
stores a dense statement ID together with `0x80000000` when the owner is a
statement. [Canonical call projection](../shaders/parser/hir/canonical/core.slang)
preserves that encoded value in a call's `payload.d`.

For captured call 130, `payload.d` is `0x8000007e`: statement 126 plus the flag.
Its parent is member expression 129, whose parent is assignment 126. The old
[assignment context reader](../shaders/type_checker/assignment_expression_context.slang)
treated the encoded value as an out-of-range HIR ID. Its fallback walk then
stopped at the member expression, which is not a forwarding wrapper, before
reaching the assignment. Calls 136 and 220 fail the same way. Direct binding's
plain context ID 171 reaches its declared destination.

The reader now preserves the absent sentinel and masks off the statement flag
before checking the candidate. The existing ownership checks still require the
assignment's complete RHS to be the queried expression, and project the
destination's complete checked type. Plain dense IDs are unchanged. No receiving
type is reconstructed from the call's own result, and no native width fallback
supplies the missing semantic fact.

## Accepted type bindings

The context decode repaired the positive reducer and selection model. A new
[incompatible assignment](../tests/fixtures/stdlib_compiler_state/iterator_selection_assignment/reject_incompatible_assignment.lani)
then exposed a separate gap: an `I: Iterator<i64>` call assigned to
`Option<bool>` compiled to ELF with only the context decode applied. That result
is recorded in
`target/stdlib-work/iterator-selection-admission/reject-fixed.log`.
This capture does not establish whether the invalid program also compiled
before the context decode change.

The [dependency result validator](../shaders/type_checker/dependencies/08a_validate_call_results.slang)
first matches the declared result against the receiving type, then validates
the result against argument claims. An iterator's `next()` has no explicit
value argument from which to obtain a claim for its item type. Its checked
`Iterator<i64>` bound supplies that type through the accepted call context.
The first publication could replace that context; the second checked claims
without checking the context binding.

Both publications now include `CT_PUBLISH_TYPE_PRIORS` in addition to their
existing admission flag. The second retains `CT_PUBLISH_CLAIMS`. The shared
[context publisher](../shaders/type_checker/match/ct_context_publish.slang)
therefore requires receiving constraints to agree with accepted explicit,
receiver, and bound type arguments. Slots with no accepted prior remain
available for inference. The publisher checks before writing, so rejection
does not partially replace an environment. Existing deferred mismatch handling
allows provisional expression facts to settle before final validation.
This extends the same authority rule described in the earlier
[trait result contract](compiler-trait-result-contract.md) to this dependency
result path.

## Execution evidence

The first two focused [assignment tests](../tests/stdlib_iterator_selection_assignment.rs)
passed together in 8.60 seconds:

- The unchanged frozen reducer passes strict x86 checks, exits zero, and emits
  the intended markers.
- The incompatible destination rejects with `LNC0006` at the exact source line
  `item = first.next();`.

The same unchanged diagnostic control input was then registered as a third
regression. It passed in 3.78 seconds after a 1.20-second driver relink:
all eight direct, unconditional and branch-assignment observations of None and
Some(0) have the correct `is_none`/`is_some` flags and source/callback counts.
That is one additional strict-checked ELF and native process, recorded in
`target/stdlib-work/iterator-selection-admission/assignment-controls-final.log`.
The earlier two tests and their fixtures were unchanged and were not rerun
solely for the appended registration.

The final result is recorded in
`target/stdlib-work/iterator-selection-admission/assignment-final.log`.
The interim context-decode-only results are also retained: the positive reducer
passed in 17.04 seconds in
`target/stdlib-work/iterator-selection-admission/reducer-fixed.log`,
and the two selection tests, including 960 commands in one native process,
passed in 7.05 seconds in
`target/stdlib-work/iterator-selection-admission/selection-fixed.log`.
The three adjacent generic assignment tests passed at that interim stage in
5.76 seconds; their log is
`target/stdlib-work/iterator-selection-admission/assignment-regressions.log`.
Those interim results do not replace checks of the final two-change state.

The final two-change state also passed these focused gates:

| Gate | Result | Wall time | Local log |
| --- | --- | --- | --- |
| Selection contracts and independent models | Two strict ELFs/native processes; all 960 commands; exact String-owner cleanup | 7.69 s | `selection-final.log` |
| Nearby assignment contexts | Three tests: six native programs and three intended conflicts | 5.29 s | `assignment-regressions-final.log` |
| Interleaved trait result contexts | Seven compile jobs: three native runs, four intended rejections, including ordinary inference between trait jobs | 4.72 s | `trait-context-final.log` |
| Compound return inference | Three tests covering complete environments, imported copies/aliases and long inference chains | 8.99 s | `compound-context-final.log` |
| New consumers | Two strict ELFs/native processes; all 714 commands and exact String cleanup | 9.30 s | `consumers-final.log` |
| Exact callback bounds | Four intended `LNC0008` rejections at their factory calls | 4.23 s | `bounds-final.log` |
| Existing typed adapters | One strict ELF/native process with compound callbacks and shallow owner cleanup | 6.96 s | `adapter-regression-final.log` |
| Column-sum application | One strict ELF reused for 58 normal and failure cases | 6.63 s | `application-final.log` |

Logs are local ignored artifacts in
`target/stdlib-work/iterator-selection-admission/`. The first shader/test rebuild
took 5.75 seconds; adding the accepted-prior guard and relinking its focused
drivers took 6.96 seconds. The final six-target regression build took 1.11
seconds. Drivers were rebuilt before direct execution; cached executable names
alone do not establish compiler or shader freshness.

Every runtime gate used an outer 100-second timeout, the shared GPU lock with a
35-second wait, a 60-second inner timeout, `RUST_MIN_STACK=16777216` and
`LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000`. Tests within each multi-test target
ran with `--test-threads=1`. This evidence concerns native x86_64 Linux programs
produced by GPU compilation; it does not establish user-program GPU execution,
other platforms or unrestricted generic compiler completeness.

## Compiler cost

The existing `examples/stdlib_gpu_perf.rs` harness measured the same selection
contract entry and unchanged library sources before and after both compiler
repairs. Each process used one warmup and five measured private entry rebuilds
with `LANIUS_PERF_REBUILD_ENTRY=1`; imports and the device remained warm within
each process. Every emitted ELF executed successfully outside the measured
compiler span, including warmups. Both versions emitted 347,640 bytes.

| Compiler | Median | Sample range | Local log |
| --- | --- | --- | --- |
| Before either repair | 1,717.652 ms | 1,496.877–1,817.768 ms | `perf-before.log` |
| After both repairs | 1,735.571 ms | 1,707.533–1,799.893 ms | `perf-after.log` |

The median increased 1.04%; ranges overlap. Other desktop activity was not
controlled. This focused observation does not establish a broad regression,
speedup, cold-build cost, large-corpus result or cross-compiler speed ratio.
The debug compiler reads shader artifacts from its configured build directory:
the baseline ran before rebuilding them, and the after run used the final
artifacts. Copying a debug executable alone does not preserve a shader set.

Nine of 918 shader artifacts changed. The largest remains 374,584 bytes,
below the 524,288-byte guard. Current and earlier shader manifests and the delta
list are local artifacts in the admission directory. No source or artifact
change was made to native emission, runtime, IR, extractor or proofs.

The measured command, with each invocation bounded separately, was:

```sh
timeout --kill-after=2s 100s flock -E 75 -w 35 \
  target/stdlib-work/library-gpu.lock timeout --kill-after=2s 60s \
  env RUST_MIN_STACK=16777216 LANIUS_PERF_REBUILD_ENTRY=1 \
  target/stdlib-build/debug/examples/stdlib_gpu_perf \
  tests/fixtures/stdlib_foundation/iterator_selection/contracts.lani stdlib - 1 5
```
