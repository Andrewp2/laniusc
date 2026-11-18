# Type-check stages outside the inference rounds

This file covers the type-check passes that run before the call inference
rounds, in the final pass and after the rounds. The rounds are covered in
`compiler-call-inference-rounds.md`.

## Method

- Workload: the settings recompile (`tools/benchmark_settings_recompile.py
  --profile`), settings hash `115a4d52a2ae77e0`, RTX 3090.
- Six builds per trace, after two warmups. Each pass occurrence is matched by
  name and occurrence index. The table value is the minimum over the six
  builds, summed over a pass's occurrences.
- Stages: "before" is every `type_check.` pass ahead of the first
  `calls.inference_blocks.list`. "Final" runs from the pass after the
  second-to-last `methods.resolve.inference` up to the last one. "After" is
  everything later, including the `interface.` passes of the semantic
  interface graph.
- Workgroups are the summed dispatch grids of one build. "Indirect" grids
  come from GPU-written arguments.

## Stage totals

| Stage | `main` 9df493a8a µs | Dispatches | This branch µs | Dispatches |
|---|---:|---:|---:|---:|
| Before the rounds | 6,666 | 452 | 6,501 | 452 |
| Final pass | 1,467 | 59 | 1,450 | 59 |
| After the rounds | 6,737 | 318 | 5,490 | 302 |
| Three stages | 14,871 | 829 | 13,441 | 813 |
| Rounds 1 to 10 (for reference) | 10,682 | 570 | 10,541 | 570 |

Both columns come from back-to-back traces of six builds each on 2026-11-17.

## Per-pass table (final head)

The 40 largest passes of the three stages.

| Stage | Pass | µs | Dispatches | Workgroups (one build) | Grid |
|---|---|---:|---:|---:|---|
| after | `interface.validate` | 375 | 8 | not recorded | indirect |
| after | `instance_closure.expand` | 268 | 16 | 64 lanes per frontier instance | indirect |
| after | `semantic_artifact.generic_native_words` | 265 | 1 | 2288 | direct |
| before | `type_instance_arg_rows.clear` | 181 | 1 | 2288 | direct |
| before | `modules.normalize_type_aliases` | 170 | 1 | 1773 | indirect |
| before | `methods.resolve_table` | 133 | 8 | 3546 | indirect |
| before | `calls.clear` | 132 | 1 | 9152 | direct |
| after | `interface.implementations.methods` | 132 | 1 | 828 | indirect |
| before | `canonical.rearm` | 127 | 1 | 21024 | direct |
| before | `methods.mark_call_keys.lookup` | 116 | 8 | 3546 | indirect |
| before | `substitution.expand.source_level.a_to_b` | 115 | 2 | 8 | indirect |
| after | `instance_closure.export` | 108 | 17 | 102 | indirect |
| after | `body_specialization.expand.level.a_to_b` | 102 | 2 | 8 | indirect |
| before | `methods.finalize_candidates` | 98 | 8 | 3546 | indirect |
| before | `methods.clear` | 98 | 1 | 1773 | indirect |
| final | `calls.contextual_results.final` | 94 | 1 | 828 | indirect |
| final | `calls.contextual_result_requests` | 94 | 1 | 828 | indirect |
| after | `predicates.count_obligation_pairs` | 92 | 1 | 828 | indirect |
| after | `semantic_artifact.member_layout` | 92 | 1 | 1824 | direct |
| after | `type_instances.validate_aggregate_access` | 88 | 1 | 828 | indirect |
| before | `constant_storage.clear` | 84 | 1 | 2288 | direct |
| after | `predicates.validate_obligation_pairs` | 81 | 1 | 23 | indirect |
| before | `modules.import_visibility.scatter_type` | 79 | 1 | 73 | indirect |
| before | `modules.import_visibility.scatter_value` | 79 | 1 | 73 | indirect |
| before | `methods.offer_bound_members` | 77 | 8 | 1656 | indirect |
| before | `dependencies.collect_methods.lookup` | 74 | 8 | 1656 | indirect |
| before | `canonical.round` | 72 | 7 | 10 | indirect |
| before | `substitution.clear` | 71 | 2 | 8192 | direct |
| after | `semantic_artifact.local_const_references` | 71 | 8 | 1656 | indirect |
| after | `instance_closure.advance` | 70 | 17 | 17 | direct |
| before | `dependencies.offer_bound_members.lookup` | 68 | 8 | 1656 | indirect |
| final | `calls.generic_claims.emit` | 68 | 1 | 828 | indirect |
| final | `calls.literal_contexts` | 68 | 1 | 828 | indirect |
| before | `methods.mark_call_return_keys` | 66 | 8 | 1656 | indirect |
| final | `calls.bind_method_receiver_environment` | 66 | 1 | 828 | indirect |
| after | `canonical.body.rearm` | 66 | 1 | 21024 | direct |
| after | `body_specialization.canonical_rearm` | 66 | 1 | 21024 | direct |
| final | `methods.resolve_table.inference` | 64 | 1 | 1773 | indirect |
| after | `predicates.collect_impls` | 64 | 1 | 828 | indirect |
| after | `canonical.late.rearm` | 64 | 1 | 21024 | direct |

Workgroup counts come from a dispatch-grid dump of an earlier head. The three
changed grids are written out by hand.

## Rows that do work

The dump tool (`LANIUS_DUMP`) keys buffers by binding name, and the last
pass that binds a name wins. Counts read that way disagree with the grids
(for example `compact_hir_count` read 34,697 rows, while the active-HIR grid
is 828 workgroups, 211,968 lanes). The lane clock (`getRealtimeClock` per
lane) does not separate idle lanes from working lanes: an idle lane waits
several microseconds under load. The counts below come from the kernels'
own inputs where those are known.

| Pass | Lanes dispatched | Rows that do work |
|---|---:|---:|
| `predicates.validate_obligation_pairs` | 5,888 | 181 pairs |
| `instance_closure.expand` (level 1) | 64 per frontier instance | frontier instances |
| `methods.*` lookup sweeps 3 to 8 | 0 | 0 |
| `instance_closure.expand` levels 7 to 16 | 0 | 0 |
| `semantic_artifact.generic_native_words` | 585,728 | type instance rows |
| active token grid | 453,888 | 453,691 tokens |
| active HIR grid | 211,968 | active HIR rows |

## Changes

| Stage | Pass | `main` µs (dispatches) | Branch µs (dispatches) | Change |
|---|---|---:|---:|---:|
| after | `instance_table.rank` | 199 (1) | 22 (1) | -176 |
| after | `interface.validate` | 542 (8) | 375 (8) | -167 |
| after | `body_specialization.constant_claims` | 154 (1) | 6 (1) | -148 |
| after | `instance_closure.expand_bound` | 140 (16) | 0 (0) | -140 |
| after | `body_specialization.accepted_claims` | 143 (1) | 6 (1) | -137 |
| after | `body_specialization.argument_edges` | 150 (1) | 20 (1) | -130 |
| after | `predicates.validate_obligation_pairs` | 203 (1) | 81 (1) | -122 |
| before | `substitution.expand.source_level.a_to_b` | 192 (2) | 115 (2) | -78 |
| after | `body_specialization.expand.level.a_to_b` | 143 (2) | 102 (2) | -41 |
| after | `body_specialization.accepted_contexts` | 82 (1) | 43 (1) | -39 |
| after | `instance_closure.expand` | 306 (16) | 268 (16) | -38 |
| after | `body_specialization.accepted_imported_fields` | 27 (1) | 6 (1) | -20 |
| after | `body_specialization.explicit_bindings` | 28 (1) | 7 (1) | -20 |
| before | `methods.resolve_table` | 152 (8) | 133 (8) | -18 |
| after | `instance_closure.advance` | 86 (17) | 70 (17) | -16 |
| before | `type_instance_arg_rows.clear` | 195 (1) | 181 (1) | -13 |
| after | `canonical.body.rearm` | 75 (1) | 66 (1) | -9 |
| after | `canonical.late.rearm` | 74 (1) | 64 (1) | -9 |
| final | `methods.resolve_table.inference` | 74 (1) | 64 (1) | -9 |
| after | `body_specialization.canonical_rearm` | 74 (1) | 66 (1) | -8 |
| before | `methods.resolve_table.direct` | 68 (1) | 59 (1) | -8 |
| after | `semantic_artifact.generic_native_words` | 257 (1) | 265 (1) | +8 |

- The canonical re-arm and body reference sweeps are bounded by GPU-written
  live counts. This change accounts for the `body_specialization.` rows.
- `interface.validate` checks interface scopes with one workgroup per owner
  row (`04_scopes`) in place of one lane per pair of rows.
- The instance table rank uses eight lanes per instance (`05b_table_rank`).
- Each closure frontier entry has 32 lanes, and one lane in each wave works
  (`ct_expand.slang`, `03_expand`, `03b_expand_dependency`). One instance's
  edge walk is a long chain of dependent reads. With one working lane per
  wave, the entries do not wait for each other.
- One closure level dispatch expands both edge kinds: lane 0 of an
  instance's 64 lanes walks the call edges and lane 32 walks the bound-member
  edges. `03c_expand_bound` is removed (16 dispatches).
- Each obligation pair has 32 lanes in `02b_validate_obligations`.
- `01c_generic_native_words` reads the cached word count of an untyped
  instance row and skips its layout walk. The final traces show no
  measurable change for this pass (257 µs before, 265 µs after).
- `07_resolve_table` exits a token without a method name before it reads the
  function activity tables.

## Dispatches with no work

A dispatch traces at 4 to 6 µs with any grid, including zero workgroups. The
closure expand levels 7 to 16 dispatch zero workgroups and trace 6.1 µs each.
The export retries after the first dispatch a full grid of lanes that exit at
once and trace 5.1 to 6.1 µs each. A GPU-written gate that sets their grids to
zero would save about 1 µs per retry, so it was not built.

In one build, 349 dispatches of the three stages trace 7.2 µs or less, 1.87 ms
in all. Only fewer recorded dispatches remove that time. Without a readback the
host records the worst-case count of every loop:

| Loop | Dispatches per build | Idle dispatches |
|---|---:|---:|
| Method lookup sweeps (gate and 8 lookup kernels) | 9 × 8 | 9 × 6 |
| Canonical rounds (dependency, early, body, late) | 4 × 15 | about 40 |
| Instance closure levels (advance, expand) | 2 × 16 + 1 | 21 |
| Instance closure export | 18 | 16 |
| Module path prefix intern | 20 | 18 |
| Local constant folding | 3 × 8 | about 18 |

One change removes dispatches without a readback: a round kernel's last
workgroup writes the next round's arguments, in place of a one-lane
arguments pass. The kernel cannot write the buffer it is dispatched from, so
two argument buffers alternate. A round after the last one then reads stale
arguments from two rounds earlier. Its lanes exit because the GPU-side count
is zero. For the canonical rounds this removes 32 `round_args` dispatches
(about 140 µs). For the closure levels it removes 15 `advance` dispatches
(about 60 µs). Neither is built.

## Host gaps

Inside the type check the GPU waits for the host only at five submit
boundaries, 16 to 28 µs each (about 106 µs in all):

| After pass | Gap |
|---|---:|
| `canonical.dependency.round_args` | 16 to 28 µs |
| `canonical.round_args` | 16 to 28 µs |
| `methods.resolve.inference` (before `calls.contextual_results.final`) | 16 to 28 µs |
| `canonical.body.round_args` | 16 to 28 µs |
| `canonical.late.round_args` | 16 to 28 µs |

Between the type check and the semantic interface graph there are two longer
gaps: about 0.65 ms after `calls.explicit_applications.validate.admit_constants`
and 1.9 ms (up to 3.6 ms) after `program_retention.snapshot_rows`, ahead of
`interface.type_topology.init`.

## Tried, not kept

- Lists of the active tokens for `07_resolve_table` and the method sweep
  kernels. The full grid's idle lanes cost about 10 µs per dispatch. The
  working rows' dependent reads set the pass time.
- Gating the export retries to zero workgroups (see above).
