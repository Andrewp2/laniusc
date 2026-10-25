# Current generic stream forwarding boundary

Fresh admission at source `66e966d3111aa72e34184eca3700addfd7d34e7c` confirms
the earlier `buffered_io_dependency` result. This investigation changes no
compiler, production adapter, IR, formal proof, native ABI or runtime code.
`SOURCES.sha256` records all eleven entry/import source files. `RESULTS.txt` and
the three normalized diagnostics retain the actual outcomes, not expected
failure tests.

| Source shape | Compile | Native |
| --- | --- | --- |
| Imported `Forward<W>` through imported `core::io::write_all` | LNC0027: unrouted bound member in `core::io` | Not run |
| Direct call to imported `Forward<W>` | 0 | 0; empty stdout/stderr |
| Local `Forward<W>` through a local generic helper | 0 | 0; empty stdout/stderr |
| Local `Forward<W>` through imported `core::io::write_all` | LNC0027: unrouted bound member in `core::io` | Not run |
| Imported associated witness `W::write(inner, ...)` | LNC0027: invalid checked receiver adjustment | Not run |

The committed nominal/variant spelling correction is present in the shader
set. Its digest is `a1a3dc017ab72950`; the compiler binary SHA-256 is
`51704757e738dfbf37d7ed3bc33fc976f7bf8348ab340d1f4068efbed58abfcf`.
The run froze the compiler, shaders and stdlib before testing. Its whole-stdlib
manifest includes unrelated working-tree files; `SOURCES.sha256` identifies the
actual clean imported closure at the recorded source commit. Raw local artifacts
are under `target/stdlib-work/stream-forward-current-66e966d3/`.

## Existing contracts and exact missing boundary

1. The GPU implementation solver retains the selected implementation's exact
   substitution. `proof_frontier_selection.slang` stores `PPS_BINDINGS` and a
   `PPS_SUBSTITUTIONS` row containing implementation identity and the binding
   span. `proof_substitution_walk.slang` validates that same accepted substitution
   for the implementation's prerequisites. The environment exists in the owned
   proof closure; it must not be reconstructed from a nominal type's arguments.
2. Native export deliberately drops generic implementations.
   `FrozenCatalog::implementation_method_targets` in
   `compiler/gpu_compiler/program_evidence/catalog.rs` returns `None` whenever
   `composed_parameters(owner)` is nonempty. Its contract says those methods need
   an environment of their own. `native_session.rs::impl_bindings` skips them.
3. `BodyImplBinding` in `type_checker/generic_body.rs` and its shader reader
   `type/instances/body_impl_bindings.slang` retain only instance/slot/member key
   and a native target triple. They carry no implementation substitution, method
   generic environment or bound-prerequisite closure.
4. `methods/09_route_bound_members.slang::external_target` therefore cannot obtain
   an external target for `Forward<W>`. It can bind local generic implementation
   patterns while their definitions are resident, explaining the local control.
   `type_checker/generic_calls.rs::resolve_generic_requirements` explicitly treats
   exported implementation targets as nongeneric and assigns zero requirements.
   Removing the catalog guard would violate that downstream contract.
5. The existing GPU `materialize_proof_terms` service can copy an accepted term
   and compute its native layout. `dispatch/native_layout.rs` explicitly states
   that `MaterializedProofType` grants no call/implementation authority; routing
   still needs the exact proof, binding, target and original call occurrence.
   Its current callers are tests, not native implementation routing. This is a
   reusable data projection component, not an existing routed-call capability.

Receiver adjustment is another owned contract. Method selection accepts the
callee and its source receiver, dereference count, matched checked type, passing
mode and parameter reference together. `methods/08_finalize_candidates.slang`
constructs that plan; `semantic/artifact/00_calls.slang` refuses a callable with
a missing/stale plan. Imported trait bound offering in
`dependencies/15b_offer_bound_members.slang` currently rejects a path call of a
self member; thus the explicit `W::write` probe fails before reaching the missing
generic external-target export. Weakening receiver checks would not supply the
implementation environment needed by ordinary dotted `writer.write` calls.

## Coherent prerequisite proposal

The missing feature is an **owned admitted implementation application**, not a
new type-name rule or a nongeneric-target assertion exception:

- Project the GPU-selected implementation's accepted substitution in exact
  composed-owner order, including independent type/constant domains and its
  prerequisite proof closure. Retain the proof arena/serial and source occurrence
  provenance. Reuse the existing type/layout materializer for data only.
- Bind that admitted application to the implementation method identity selected
  for the required trait member. Supply its checked call environment to ordinary
  body replay and requirement accounting; do not force generic requirements to
  zero or infer them from the receiver's positional arguments on the host.
- Publish the routed callable and its checked receiver plan as one fact. The
  imported/helper and implementation-own scopes must retain their separate
  binders. Reject stale, mismatched, ambiguous or incomplete environments before
  publishing a native call.
- Verify the original imported `write_all` path, corresponding Read/`read_exact`
  path, two nested forwarding adapters and a real buffered reader/writer. Check
  short progress, interruption, propagated errors, underlying borrowed-owner
  identity and pending-buffer state. Include unrelated-type/trait and stale-proof
  negatives, plus existing nongeneric/local routing controls.

This requires an export/transport contract across the owned proof closure,
native replay binding packet and routed generic call. The existing protocol does
not carry that contract end to end. A small receiver predicate change cannot
implement it, so this investigation stops at the concrete dependency. No
production buffering API is claimed from passing direct/local controls.

## Bounded reproduction

From the repository root, use a fresh output directory. The runner freezes the
provided compiler/shader/stdlib roots and stages only the two probe modules.
It records every compile/native status and never executes a failed artifact.
Its exit status describes orchestration, not candidate acceptance; inspect the
ledger. Timeout 124/137 and GPU-lock exit 75 are not language rejections.

```sh
timeout --kill-after=2s 100s flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s bash \
  tests/fixtures/stdlib_compiler_state/foundation_admission/stream_forward_current/run.sh
```

Each tiny compile has eight seconds plus one second kill grace; native programs
have one second plus one second grace. To reproduce the recorded source closure
later, archive `stdlib` from the recorded commit into a fresh staging directory
and pass its path as `ADMISSION_STDLIB_ROOT`, with the commit recorded as
`ADMISSION_SOURCE_HEAD`. `LANIUSC` selects the compiler;
`LANIUS_SHADER_ARTIFACT_ROOT` selects its matching preserved shader set.
