# Weighted graph execution fixtures

These fixtures exercise the frozen `ext::weighted_graph` public contract.
All four registered gates passed on native Linux x86_64 code emitted by the
GPU compiler. They do not establish GPU-device execution, other-target support
or formal correctness. Full module contracts and evidence limits are in the
[module guide](../../../../docs/extended-weighted-graph.md).

| Native gate | Receipt | Run time |
| --- | --- | --- |
| Direct contracts and preflight | 2 passed, 0 failed | 8.84 s |
| Independent path/cycle model | 1 passed; 2,819 graphs, 5,638 outcomes, 12 controls | 6.95 s |
| Ownership and reached allocation failure | 1 passed; five profiles, nine injected failures, 16 controls; balanced and recovered | 9.09 s |

Local logs: `target/stdlib-work/weighted-graph-direct.log`,
`target/stdlib-work/weighted-graph-model.log` and
`target/stdlib-work/weighted-graph-resources.log`. The separate route-cost
application is not part of this receipt and has not yet been accepted.

- `contracts.lani`: canonical multigraph storage and unchanged selected input;
  independent graph, result and materialized-path owners; deterministic ties,
  zero cycles and stale queue entries; exact signed 64-bit endpoints;
  overflow even for a non-improving candidate; disconnected and reachable
  negative cycles; both orders of final-scan overflow/cycle precedence.
- `preflight.lani`: invalid metadata and configured/hard limits before backing
  reads, including deliberately unreadable backing behind rejected metadata;
  offset-first validation; canonical order allowing duplicates; relative
  endpoint diagnostics; exact work boundaries; full-width work arithmetic;
  source and closed-result precedence; path population, work and actual-edge
  limits. Borrowed physical backing is only omitted where the public contract
  guarantees that a rejection occurs before any backing read.
- `model.lani` and `oracle.py`: a bounded binary test adapter and independent
  arbitrary-integer simple-path/cycle enumeration. The oracle does not replay
  Dijkstra's heap or Bellman–Ford's relaxation schedule. It checks canonical
  storage, all distances, path-edge membership/continuity/cost, predecessor
  consistency, unreachable/source behavior, owner cleanup, input preservation,
  and deterministic results under raw-edge permutations.
- `resources.lani` and `resource_oracle.py`: five operation profiles
  (`from_edges`, `from_view`, Dijkstra, Bellman–Ford, `path_to`). The current
  native source-site verifier separates loader/CRT mappings from Lanius
  owners. Every reached operation allocation is failed once by its global
  syscall ordinal; its phase must balance before a successful same-process
  retry, with setup owners still valid. Natural `Overflow` and `NegativeCycle`
  failures also balance. The traversal graph has repeated tentative
  improvements and requires no queue growth. Final cleanup is checked before
  the output receipt; terminal CRT unmapping remains permitted.

The exact model corpus is 2,819 graphs and 5,638 algorithm outcomes: 4,910
finite, 445 global-negative-edge rejections and 283 reachable-negative-cycle
rejections. It exhausts two-node graphs with absent/-1/0/2 arcs and all sources,
then non-self three-node graphs with absent/0/2 arcs and all sources, and adds
seeded four-to-six-node multigraphs, signed DAGs and input permutations.
Seed: `0x6a90261107`. Small costs isolate this model from the direct overflow
fixtures. Negative-cycle diagnostics in generated cases must identify a
reachable canonical arc; exact scan-order diagnostics are checked by the
hand-written fixtures. The model does not promise lexicographically minimal
paths or identical tie choices between the two algorithms.

Host-only observer controls are available without compiling or running Lanius:

```sh
timeout --kill-after=2s 100s python3 -I -B tests/fixtures/extended/weighted_graph/oracle.py controls
timeout --kill-after=2s 100s python3 -I -B tests/fixtures/extended/weighted_graph/resource_oracle.py controls
```

The registered Rust test selectors are:

```text
weighted_graphs_preserve_parallel_edges_exact_costs_paths_and_error_policy
weighted_graphs_validate_descriptors_and_admit_limits_before_backing_reads
weighted_shortest_paths_match_independent_integer_path_and_cycle_enumeration
weighted_graph_owners_release_partial_results_and_recover_each_reached_allocation_failure
```

Each native oracle is bounded: model child 50 seconds, allocation trace child
6 seconds, outer oracle 70 seconds. These are focused test oracles, not Python
implementations shipped as part of the library. Resource fault coverage is
limited to allocations actually reached by the five declared profiles; it is
not an exhaustive allocation history or machine-failure model.
