# Directed graph independent state and path model

This fixture checks real `ext::graph` and `ext::graph_algorithms` operations
against independent sets, all-pairs shortest paths and exhaustive valid
permutations. Production remains Lanius. Python and binary framing are test
infrastructure only; no BFS queue, Kahn heap or storage-sort engine is copied.

## Independent references

Construction canonicalizes input edges as a mathematical set, retaining loops
and isolated nodes while collapsing duplicates idempotently. CSR shape and
complete adjacency values are compared exactly. Original edge order is retained
for Source/Target error indices and source-before-target precedence. Validation
checks all offset constraints before inspecting any target, then rows/edges in
order, with exact node and relative-edge payloads.

Distances come from an independent all-pairs path-length recurrence. For each
reachable source/target pair, the oracle enumerates simple paths of that minimum
length and takes the lexicographically earliest complete vertex path. Its
penultimate vertex supplies the ascending-neighbor FIFO predecessor. This is
not the smallest predecessor ID: the explicit six-node witness reaches node 4
from source 0 through parent 5, before an equally short route through parent 3.

Topological expectations enumerate every vertex permutation for each small
graph and retain every order satisfying all directed edges. The minimum valid
tuple is expected, or Cycle if no valid order exists. Empty, disconnected and
looped graphs are included. No heap/bag/indegree recurrence is reproduced.

Every successful owned construction checks public open/count/view state,
canonical CSR, validation count, every neighbor row and invalid neighbor
queries, BFS for every source plus invalid sources, topology and unchanged
graph CSR afterward. BFS results check every distance/predecessor, Bounds
queries, source metadata, idempotent destruction and Closed-before-Bounds
queries. Graph destruction similarly checks empty closed state. All temporary
owners are explicitly released; allocation accounting has separate gates.

## Finite corpus

There are **4,570 distinct cases**, seed `0x6a4f0261103`:

| Selected API | Cases |
| --- | ---: |
| from_edges | 2,786 |
| from_view | 422 |
| validate | 256 |
| view factory | 256 |
| neighbors | 294 |
| bfs | 298 |
| topological_order | 258 |

The corpus includes all 531 directed labeled graphs on 0..3 nodes, including
every self-loop subset. Construction variants reverse raw order and add
duplicates. Every upper-triangular four-node DAG and reversed-label variant,
empty/isolated/chain/star/cycle/disconnected examples, the non-minimum-parent
witness and 200 seeded graph candidates supplement that domain. Successful
traversal graphs contain at most **six nodes**; no scale-test receipt is inherited.

Separate cases cover malformed offsets/targets, duplicate or descending stored
neighbors, original-order endpoint errors, every selected API's exact work
estimate and adjacent budgets, negative limits, node/edge caps, query bounds,
metadata failures and hard-ceiling admission. Work uses arbitrary-precision
weighted size formulas and integer bit length for ceil(log2). `from_view`
admits its full `2V` budget before adjacency reads; traversal operations validate
before admitting body work. This native profile has 16-byte Edge staging
elements, so `from_edges` also applies the 134,217,727-element staging ceiling
before work or backing access. Huge declared shapes are arranged to reject before
backing access/allocation; they do not establish large physical backing.

Two source layouts use native stack arrays and independently prepared typed
storage, with nonzero View starts. No alternate ABI stride magnitude is invented.
Every case emits all 100 original Edge values, 12 offsets and 100 targets,
including guards, after the selected operation. They must exactly match the
initial arrays, even on rejection. Recoverable AllocationFailed is not injected
here; an unexpected allocation failure rejects the nominal model.

Independent literal controls pin duplicate/loop storage, offset-before-target
precedence, original endpoint indices, source Bounds before body work,
copy-work admission before malformed adjacency, native staging capacity before
work, minimum-hop parent ties, lexicographically minimal order and empty/cycle cases.
Eight deliberately corrupted serialized outputs check the verifier's rejection
of count, precedence, index, parent, order and input-guard mismatches. These are
verifier controls, not production-code mutations or an independent proof.

## Protocol and acceptance

Each request has sixteen little-endian u64 header words for selected API,
layout, nodes/query, limits, three View descriptors and actual payload counts.
It is followed by raw edge pairs, offsets and targets; all signed i32 fields
retain their bit patterns. Result records have explicit success/error headers
and typed payloads. Owned results include nested public-query observations,
followed by every original source/guard element. Exact framing and full outputs
are checked with complete case/index/seed diagnostics.

The registered native test **passed**: one test in **7.99 seconds**, with all
**4,570 cases / seven operations / two layouts**, seed `0x6a4f0261103`.
The receipt is `target/stdlib-work/directed-graph-model-first.log` (test build
1.72 seconds). The registered test is
`independent_directed_graph_models_match_canonical_storage_paths_order_and_errors`
in `extended_graph_model_execution`. It checks executable ELF admission and
shared strict x86 jumps, then runs one batched native process with a 90-second
outer timeout and 75-second child timeout. Accepted scope is finite native
Linux x86_64 CPU output from the GPU compiler. Physical access, allocation
failure, reserved large traversals and the real dependency program have
separate gates. No GPU-device, automatic ownership, unbounded complexity or
formal verification guarantee is claimed.

Before the first native run, independent review corrected two oracle admission
precedence assumptions: `from_view` admits `2V` before adjacency reads, and
`from_edges` admits native staging capacity before work. Literal CPU controls
pin both corrections. The producer and production modules did not change;
neither issue was a compiler or library failure.

Tested SHA256 identities:

| Source | SHA256 |
| --- | --- |
| `extended/ext/graph.lani` | `d8e5216346edfc3bcf554d17526d4e05ad71b0843a29a51185442085b36b074c` |
| `extended/ext/graph_algorithms.lani` | `57ba3bcf02b04da8d6aa0fe0e1b387a7cb25cf1d0fc735770097e56df7bdadce` |
| `model.lani` | `517b59dd13d65c49f7d053b1a09761720a712417af82e81522a7a45eec41d134` |
| `oracle.py` | `3ca87603a9bc29ccbe813813d4fcf63d8b836ad438742586ab7ef97595e8a9e9` |

```sh
python3 -B tests/fixtures/extended_graph_model/oracle.py controls
cargo test --test extended_graph_model_execution independent_directed_graph_models_match_canonical_storage_paths_order_and_errors -- --nocapture
```
