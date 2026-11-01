# Directed-graph direct contracts

All three registered direct tests passed in separate commands:

| Receipt | Accepted scope | Time |
| --- | --- | --- |
| `target/stdlib-work/directed-graph-admission-first.log` | One admission test and native process | 7.69s |
| `target/stdlib-work/directed-graph-preflight-first.log` | One allocation-free four-scenario test and native process | 7.94s |
| `target/stdlib-work/directed-graph-owners-first.log` | One four-scenario owner test and native process | 7.04s |

Root ran the compiler, Cargo and native commands. These receipts do not claim
a single combined three-test run.

`admission.lani` constructs a graph from unsorted duplicate edges, borrows its
canonical neighbors, executes nested Result/Option BFS queries, checks a literal
topological order and rejects a cycle. Owners are explicitly destroyed and
repeated cleanup is checked. All accepted producers passed strict x86_64 ELF
checks. Admission and owner full syscall traces contained only process
entry/exit and allocations/releases matched by complete address and size;
no live owner remained.

`contracts.lani` has four finite allocation-free scenario functions. They check
descriptor/limit/work admission before inaccessible backing, exact error kinds
and node/edge payloads, complete offset scanning before targets, endpoint order
before input sorting, and original relative edge indices. Work cases include
below/exact validation boundaries, constructor and algorithm preflight, and a
100,000,000-edge descriptor rejected before access using a work estimate above
32-bit range. No huge graph is allocated or traversed. Raw edge limits apply
before duplicate collapse, and native staging capacity is admitted first.

Canonical nonzero-start integer views preserve actual +4 native/packed i32
strides, guards and relative neighbor ranges. Edge records use their actual
descending stride. Invalid neighbor/BFS-source Bounds occur after complete
graph validation and before algorithm-body work admission. The accepted pure
gate's full syscall trace contained only process entry and exit.

`owners.lani` has four finite scenario functions. Exact work thresholds succeed
for construction, from_view, BFS and topology; input remains unchanged and
constructed backing is independent. A FIFO witness chooses predecessor 5 over
3 at equal hop distance. A separate ready-set case requires the literal
lexicographically smallest topological order. Cases retain isolated nodes,
collapse duplicates, preserve self-loops, reject cycles after partial ordering,
and check empty/singleton behavior. Owned BFS/order results remain usable after
the input Graph is destroyed. Closed-query precedence and repeated cleanup are
checked with all live allocations matched to their exact releases.

Independent models, guarded physical boundaries, reached allocation denials,
reserved scale cases and the application have separate focused gates. Logical
validation does not establish backing/lifetimes; physical traps have no rollback
claim.

Accepted fixture and production source hashes:

| Source | SHA-256 |
| --- | --- |
| `admission.lani` | `d3cfa12d92b552c298ff6c52496d02c457200b1b665d73608f97cec9016732f7` |
| `contracts.lani` | `096b62164b88289810559802a7ff4b81d39078015835aced976924e4aa7da2ab` |
| `owners.lani` | `7cb43f63408c69c8decd44c8ffa9edcd8fee4bcfb0bd334bf5ed2547134873dd` |
| `extended/ext/graph.lani` | `d8e5216346edfc3bcf554d17526d4e05ad71b0843a29a51185442085b36b074c` |
| `extended/ext/graph_algorithms.lani` | `57ba3bcf02b04da8d6aa0fe0e1b387a7cb25cf1d0fc735770097e56df7bdadce` |

```text
cargo test --test extended_graph_execution directed_graph_native_admission_executes_nested_bfs_topology_and_cycle -- --exact
cargo test --test extended_graph_execution directed_graph_preflight_rejections_and_canonical_views_allocate_nothing -- --exact
cargo test --test extended_graph_execution directed_graph_owners_bfs_ties_topology_and_closed_results_execute -- --exact
```

Accepted target scope is native Linux x86_64 CPU execution of GPU-compiler output.
GPU device execution, other targets and formal correctness are unclaimed.
