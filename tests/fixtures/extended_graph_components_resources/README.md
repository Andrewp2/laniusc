# Strong-component resources and analytic scale

These producers exercise `ext::graph_algorithms::strong_components` and
`condensation` through the native Linux x86_64 output of the GPU compiler.
The Rust driver is `tests/extended_graph_components_resource_execution.rs`.
It requires a real x86_64 ELF and the shared jump checks before execution.
Root runs the compiler and native programs serially under the library lock.

## Ownership and allocation failures

`owners.lani` creates independently owned offset/target vectors for an
eight-node graph with thirteen canonical edges. The expected partition is
`[0,1,1,0,1,2,3,3]`. Its six cross-component arcs become five canonical DAG
edges. The fixture also exercises the empty graph with a real owned offset
`[0]`.

For each API the driver first records a successful full syscall trace. It
checks the current source reservations: six `n`-entry i32 allocations for a
nonempty SCC, followed for condensation by an original-edge pair buffer,
the actual cross-edge staging buffer, canonical offsets and unique targets.
The pair size comes from the compiled producer's `size_of<graph::Edge>()`.
Each selected fault ordinal comes from this observed baseline, rather than
assuming a particular global mmap number. All six nonempty SCC sites, all
ten nonempty condensation sites and the empty condensation offset allocation
are selected. Empty SCC performs no allocation.

Every fault must be a reached, explicitly injected ENOMEM. The preceding
allocation/release sequence must equal the baseline after addresses have
been normalized to allocation identities. At the failed return, only the
original input owners may remain live. The producer verifies every input
offset/target plus storage pointers, lengths and capacities, retries in the
same process, destroys both input owners, and then queries the complete
independent result. It checks all node-pair equality queries on the small
graph, every condensation offset/target, closed queries and double destroy.

The full syscall ledger rejects unknown or repeated releases, mismatched
extents, overlapping live allocations, host effects during pure observation
phases and any owner still live at the final marker. It matches every
successful mmap to one exact address/extent munmap; process exit is never
used as cleanup evidence.

Test selector:

```text
graph_components_all_reached_allocation_failures_preserve_sources_and_retire_owners
```

## Analytic scale

`scale.lani` reserves normal allocator-backed input and report vectors. It
uses no large stack arrays. Each shape contains 65,536 nodes:

| Shape | Original edges | Components | Cross arcs before deduplication | Canonical DAG edges |
| --- | ---: | ---: | ---: | ---: |
| Directed chain | 65,535 | 65,536 | 65,535 | 65,535 |
| One directed cycle | 65,536 | 1 | 0 | 0 |
| Chain of 256-node cycles | 66,046 | 256 | 510 | 255 |

The deep chain and giant cycle require traversal depth 65,536. The component
chain supplies two original arcs per neighboring component pair, so the
result must deduplicate them. Both APIs execute on each shape. Every source
word is checked before input destruction; all 131,072 result labels and
every condensation offset/target are checked afterward and emitted for the
host's independent closed-form comparison. The syscall ledger requires six
reserved allocations for SCC, the actual condensation reservations, no
growth during traversal, only result owners at return, and exact final
release of all input, output and private allocations.

Test selector:

```text
graph_components_65536_node_shapes_match_complete_analytic_mapping_and_canonical_dags
```

## Evidence

Both focused native gates passed on Linux x86_64 output from the GPU compiler:

| Gate | Accepted scope | Test time | Separate Rust build |
| --- | --- | ---: | ---: |
| Ownership and allocation failures | Four baselines; 17 reached allocation denials and 17 same-process recoveries | 6.54 s | 1.75 s |
| Analytic scale | Three 65,536-node shapes; 131,072 mapping observations per shape and complete canonical DAG storage | 7.45 s | 0.20 s |

The ownership baselines had respectively 8, 12, 1 and 2 successful mappings,
with the same number of exact releases, for nonempty SCC, nonempty
condensation, empty SCC and empty condensation. These totals include the
input vectors; empty SCC itself allocated nothing. The three scale runs
had respectively 19, 17 and 19 mappings and exact releases. Every injected
allocation failure was reached, released its partial owners before return,
and recovered successfully in the same process.

The local receipts are
`target/stdlib-work/graph-components-resources-first.log` and
`target/stdlib-work/graph-components-scale-first.log`. Each selector passed
as one Rust test, with the other selector filtered out. The times include
the focused test's compilation and native work; they are not performance
benchmarks.

A bounded host-only control independently checked the small partition by
all 64 mutual-reachability pairs. It also enumerated all original edges of
the three scale shapes, verified canonical input rows and every offset
formula, and derived their cross-component edge sets and counts. Those
controls validate fixture expectations; they are not native runtime cases.

This coverage makes no claim about other targets, execution as a GPU user
program, formal verification, elapsed-time complexity or throughput ratios.
