# Directed graph resource and scale acceptance

All four registered resource gates passed compiler/native acceptance through
separate commands. The parent agent ran all compiler, Cargo and
native commands. These focused gates check the
[directed graph contract](../../../docs/library-directed-graph-plan.md),
complementing the small direct contracts and independent graph models.
The author ran only bounded CPU reference controls and static source audits.

The first owner gate stopped in genuine mode 0 with SIGILL, markers CF and no
mmap: the fixture used an end index where `view_range(values,start,count)`
expects a count, including a trailing invalid sentinel. All three owner ranges
were corrected to 6 edges, 7 offsets and 5 targets at start 1, preserving both
outside guards; the remaining fixture ranges were audited against their actual
APIs. No production change or expectation weakening was needed. That
fixture failure is recorded in
`target/stdlib-work/directed-graph-owner-faults-first.log`.

The corrected owner fixture then passed its registered gate in 7.77 seconds,
recorded in `target/stdlib-work/directed-graph-owner-faults-retry.log`. All five
genuine/Cycle modes and seven selected mmap ENOMEM schedules passed, including
input preservation and exact once-only address/length cleanup for every
successful allocation. The amended owner identity is recorded below.

The guarded adjacency gate passed one test in 6.80 seconds, recorded in
`target/stdlib-work/directed-graph-boundaries-first.log`: all three pure phases
passed with one 8192-byte mapping, protection of its second page and exact
release. The analytic scale gate passed one test in 7.12 seconds, recorded in
`target/stdlib-work/directed-graph-scale-first.log`. Chain, star and layered
graphs each matched all 65,536 emitted triples, required exactly three BFS
and three topology allocations, and matched all nine total mappings to nine
exact releases. The physical-precondition gate separately passed one test in
7.51 seconds, recorded in
`target/stdlib-work/directed-graph-physical-first.log`. Both deliberately
overclaimed backing programs exited exactly 101 with empty stdout/stderr.
Those trap observations remain distinct from positive guarded-access evidence.

## Selected allocation failures and input preservation

`owners.lani` uses actual nonzero-start native input views with outside guards.
The unsorted six-edge list contains one duplicate; its canonical graph has six
nodes, five distinct edges and an isolated node. A separate canonical view has
the same adjacency. Every input edge field, every offset/target and all guards
are checked after the selected operation, on both success and failure.
Construction copies before sorting, so the original edge order must survive.

| Mode | Operation | Reserved allocation lengths in the native profile |
| --- | --- | --- |
| 0 | from_edges | 96-byte staged Edge records, 28-byte offsets, 20-byte targets |
| 1 | from_view | 28-byte offsets, 20-byte targets |
| 2 | BFS | Three 24-byte distance, parent and queue owners |
| 3 | topological order | Three 24-byte output, incoming-count and heap owners |
| 4 | Cycle after a private output prefix | Three 24-byte output/workspace owners |

Five genuine lifecycles cover all modes. Seven finite fault lifecycles inject
one actually reached mmap ENOMEM: mode 0 ordinals 1/3, mode 1 ordinal 2, mode 2
ordinals 1/3 and mode 3 ordinals 1/3. No successful allocation return is forged.
Every fault must produce AllocationFailed with node=edge=-1, preserve the
input, and leave zero live private owners at the public return boundary.
The selected later failures exercise cleanup after earlier owners were acquired;
this is not an exhaustive allocation-fault campaign.

Successful construction checks all canonical offsets and targets. BFS checks
all six public distance/predecessor results, including unreachable and source
absence, then retires its two returned owners. The topological result must be
the complete lexicographically smallest order. Native assertions check that
Graph/BfsPaths destruction empties the owner and returns false on repetition;
the trace rejects any second backing release.

Mode 4 contains the cycle 0->1->2->0, the independent edge 3->4 and isolated
node 5. Kahn's ready bag first emits the private prefix [3,4,5], then exhausts.
Cycle must return no partial Vec and release all three private owners before
returning. A CPU min-heap reference independently confirmed that prefix.

`C`/`F` delimit the public operation; the full syscall trace records each
reservation and the number of still-live mappings at F. Success leaves exactly
two Graph owners, two BFS owners or one topological Vec; Cycle/OOM leaves none.
`P`/`p` phases check results and unchanged input without any host operation.
A small binary report tells the host the selected operation and actual outcome;
its expected success/OOM/Cycle code is independently fixed by the schedule.

## Reserved 65,536-node shapes

`scale.lani` builds canonical adjacency using reserved Vecs. An independently
reserved output Vec stages every public result as an i32 triple
`(distance-or--1, predecessor-or--1, topological-node)`.

| Shape | Stored edges | Reachable from node 0 | Maximum hop count |
| --- | --- | --- | --- |
| Chain i->i+1 | 65535 | 65536 | 65535 |
| Outward star 0->i | 65535 | 65536 | 1 |
| 256 layers of 256 nodes | 130560 | 32896 | 255 |

In the layered graph, each node points to the same column and the next column
modulo 256 in the next layer, with each pair stored ascending. From node 0,
layer L reaches columns 0..L. Its distance is L; column 0's parent is the
previous layer's column 0, and other reached columns first come from their
previous column. Every shape's min-ready topological order is 0..65535.
These parent formulas describe these graphs; they do not change the general
API's FIFO first-discovery policy into a smallest-parent guarantee.

The fixture checks every result and all original adjacency storage. The host
independently checks all 65,536 emitted triples against closed-form values,
including every unreachable node. This checks more than aggregate checksums
or repeated source lookups. CPU controls additionally built all three actual
graph families, ran independent deque BFS/min-heap Kahn algorithms, and compared
every distance, parent and order entry to the formulas.

Three setup mappings reserve offsets, targets and the complete report. Each
BFS/topology operation must make exactly three n*4-byte reservations. The
trace rejects any growth/reallocation, so queues/heaps with broad frontiers
cannot silently allocate per item. Production source reserves these owners
before its traversal loops; the finite runtime witness requires only those
six algorithm mappings, plus the three setup mappings. The final returned
owners are explicitly destroyed and every one of the nine successful mappings
must be released at its exact address and requested length. No wall-clock
performance guarantee is claimed.

## Honest guard-page extents and logical admission

`boundaries.lani` has three effect-free P/p phases and one 8192-byte backing
allocation. Its second 4096-byte page is PROT_NONE. Each positive packed i32
raw slice honestly covers one leading canary plus its selected payload, ending
exactly at that guard. Guarded offsets and guarded targets are tested separately
against native descending-byte i32 counterparts, both with nonzero View starts.
Validation and both neighbor rows must work without speculative access, while
preserving all initialized backing and canaries. A zero-edge row has an empty
selected target view ending exactly at the guard and must not read it.

The metadata phase provides null-backed descriptors only when a prior logical
failure requires no payload access. Negative start/length, overflowing sums,
wrong offset count, NodeLimit and WorkLimit are checked across validation,
view construction, neighbors, copying and algorithms. from_edges separately
checks malformed metadata and size/work rejection over null edge backing.
A physically backed bad first offset with null nonempty targets checks the
rule that every offset is validated before any target is read. No rejected
operation may allocate or reach any other host service.

The driver requires exactly one successful 8192-byte mapping, one protection of
its second page and one matching complete release after all phases. It traces
every syscall, rather than only allocation services. The only admitted effects
outside phases are process entry/exit, optional one-byte mode configuration,
explicit markers, declared mapping/protection/release and observation writes.

Two separate fixtures intentionally violate physical caller preconditions.
`offset_overclaim.lani` has one actual offset but claims two; the first offset
is valid, so the second native access must trap. `target_overclaim.lani` has
one actual target but claims two; its valid first self-edge precedes the
unbacked second access. Both expect native exit 101. These are not recoverable
Bounds errors and establish no arbitrary-pointer safety or trap rollback.
Logical metadata checks cannot prove physical backing or lifetime.

## Scope and identities

All executables require the existing strict x86_64 ELF/jump admission. Owner
and positive boundary processes are bounded to ten seconds, each physical
trap to five seconds, and each scale shape to thirty seconds. Run the four
registered selectors separately so each command remains below two minutes.
Accepted target evidence is finite Linux x86_64 CPU execution produced by the
GPU compiler with the current native/packed i32 layouts and 4096-byte base-page
profile. User-program GPU execution, other targets, automatic ownership/lifetime
enforcement and formal verification remain unclaimed.

| Executed source | SHA-256 |
| --- | --- |
| `owners.lani` | `62c852de57a88de3340732d70988ff887e9ea4b7380905e88ac6f9f6ecf1703f` |
| `scale.lani` | `741f64e59df61ea71376fdd89dbec56ad780495e7342737d71a33128783f583a` |
| `boundaries.lani` | `4cfdf9c9d73a7acf6770340b97c5b2a14f8ddd8c53dc336b89ae0246215a389c` |
| `offset_overclaim.lani` | `0bcfbfa3a39622ccf9cee12bdde7776fccf433f7072bde36cc2baa9278838311` |
| `target_overclaim.lani` | `2d06c5ec88a0d7a34c165c37de331a429a86d8ff27475d747f50364440270a54` |
| Rust driver/oracle, tested before formatting | `05ac20e8d151cb5a102cbae9bb6547d6da665edee626a23a721222f65db1467a` |

```text
cargo test --test extended_graph_resource_execution graph_selected_allocation_failures_preserve_inputs_and_retire_partial_owners -- --exact --nocapture
cargo test --test extended_graph_resource_execution graph_reserved_65536_node_shapes_match_analytic_paths_and_order -- --exact --nocapture
cargo test --test extended_graph_resource_execution graph_guarded_adjacency_and_metadata_rejection_respect_honest_extents -- --exact --nocapture
cargo test --test extended_graph_resource_execution graph_logical_views_retain_the_actual_backing_precondition -- --exact --nocapture
```
