# Strong components and condensation contracts

`tests/extended_graph_components_execution.rs` registers exactly three native
execution tests for `ext::graph_algorithms::strong_components` and
`condensation`. The fixtures are Lanius programs with runtime assertions. They
compile through the GPU compiler and run as Linux x86_64 CPU executables; this
is not a user GPU execution or formal proof claim.

## Admission

`strong_components_and_condensation_execute_canonical_native_admission` runs
`admission.lani`. Four nodes contain a two-node cycle, a separate predecessor,
and a self-loop. Both APIs must return the literal canonical mapping
`[0,1,0,2]`. Condensation must have offsets `[0,1,2,2]` and targets `[2,0]`.
Existing topological ordering must return `[1,0,2]`, demonstrating that component
IDs follow original minima rather than topological order. Original input values
must survive unchanged; both owners are destroyed exactly once.

## Owners and complete outputs

`strong_component_owners_exact_edges_closed_queries_and_work_boundaries_execute`
runs `contracts.lani`. It checks:

- A guarded seven-node subview with three cycles, an isolated node, and multiple
  original edges that collapse to one condensation edge. Every component ID,
  every pair query, every DAG offset and target, and every input/guard word is
  compared with literal expectations.
- Output independence after mutating borrowed input, destroying an owned input
  graph, and destroying unrelated result owners. Topological ordering consumes
  a remaining condensation DAG after the source graph has been destroyed.
- Bounds payloads for extreme and one-past-end indices, left-before-right
  precedence when both query operands are invalid, and right errors after a
  valid left operand. Closed precedes bounds; closed counts are zero, closed
  views are `None`, and repeated destruction returns false.
- Exact successful work limits: `(SCC, condensation)` are `(68,132)` for a
  three-node, three-edge graph; `(2,3)` for empty; `(53,57)` for three isolated
  nodes; and `(41,56)` for one self-loop plus an isolated node. Empty
  condensation retains the canonical `[0]` offset owner.

## Preflight and no host effects

`strong_component_preflight_preserves_validation_precedence_without_host_effects`
runs `preflight.lani`. It checks both constructors against invalid limits,
metadata, graph hard/configured node/edge ceilings, exact offset length and
validation-work rejection. Null backing is used only where rejection precedes
reads; it is not presented as a valid graph.

Malformed first, interior and final offsets reject before any target access,
including null target backing. Full validation errors precede operation-work
rejection. Target-range and canonical-order errors retain exact node/edge
payloads. Valid three-node, three-edge input rejects at SCC work 67 and
condensation work 131. Empty SCC rejects at work 1 and succeeds at 2 without
allocating; empty condensation rejects at 2. All input and guard words are
checked unchanged. Operation-specific Edge staging capacity beyond the shared
graph profile is not claimed by these bounded fixtures.

## Host evidence

All three tests require a strict x86_64 ELF and the shared in-function jump
checks before execution. A ten-second child timeout bounds each fixture.
Full `strace` output permits one successful `execve`, one successful exit, and
only `mmap`/`munmap` between them for allocating fixtures. Successful mappings
must have positive extents at most 4096 bytes; at most 256 acquisitions and 32
simultaneously live mappings are permitted. Each release must match its live
address and exact extent, and the final ledger must be empty. The preflight
fixture permits no intervening host effects at all.

The broad storage bounds catch accidental unbounded host activity; they do not
claim a fixed allocation count, denial coverage, or large-graph complexity.
Dedicated resource/model tests own those claims separately.

A host-only independent mutual-reachability check confirmed six literal
mapping/DAG/topology expectations and four exact work-boundary pairs. Those
controls are separate from native evidence.

## Runtime receipt

All three native gates passed on the accepted source through the GPU compiler
and Linux x86_64 CPU execution:

- Admission: one test passed in 6.86 seconds (separate Rust build: 3.10 seconds),
  recorded in `target/stdlib-work/graph-components-admission-first.log`.
- Owner/contracts and preflight: two tests passed in 9.56 seconds (separate Rust
  build: 1.63 seconds), recorded in
  `target/stdlib-work/graph-components-contracts-first.log`.

The first run filtered out the other two gates; the second filtered out the
admission gate. These are three distinct native tests, including their host
effect ledgers. The timings are test-run receipts, not algorithm throughput
measurements. No user GPU execution, other target, allocation-denial, scale,
CLI, or formal verification claim follows from these direct fixtures.
