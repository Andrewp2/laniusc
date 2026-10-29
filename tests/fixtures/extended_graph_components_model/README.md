# Independent graph component model

This focused model checks `ext::graph_algorithms::strong_components` and
`condensation` against Boolean transitive closure. Mutual reachability,
including zero-length paths, defines each equivalence class. The host assigns
dense component IDs by increasing smallest original node. It does not repeat
Tarjan's DFS, lowlink update, active stack, root test or component-pop algorithm.

The finite corpus has **3,218 operation/storage cases**. It includes all **531
directed labeled graphs on zero through three nodes**, with every possible
self-loop, through both constructors and two source storage preparations.
Another 128 seeded graph draws use 4–16 nodes and five edge densities. Explicit
witnesses exercise disconnected components, nested discovery cycles, active
cross links, edges into completed components, multiple original edges collapsing
to one condensation edge, a complete 16-node graph and component IDs opposite
the topological order. Duplicate generated cases are removed. Seed:
`0x5cc0261105`.

Both source preparations use interior views starting at index two, with guards
before and after the logical input. One uses native stack arrays; the other uses
independent backing converted through `typed_slice_from_raw_parts<i32>`. Both
have the actual supported i32 byte stride **+4**, observed in the output. They
are two storage preparations, not evidence for two different stride values.

For every successful construction the producer emits:

- All component IDs and all ordered `same_component` pairs.
- Open state, both counts, lower/upper/extreme node query errors, and left-before-
  right bounds precedence.
- For condensation, every offset and target of the exact canonical graph,
  plus the complete result of existing `topological_order`.
- First and repeated destruction, closed counts/view, and Closed-before-Bounds
  errors for every query kind.

The reference obtains condensation edges directly as a set of mapped original
edges, excluding intra-component edges. A scan of the predecessor relation
chooses the smallest remaining predecessor-free component at each position.
The oracle checks that this process finishes and that every edge increases in
position, providing an independent DAG and exact topological-order check.

The producer emits **all 24 offset and 260 target backing cells immediately
after each constructor**, including failures. Every one must match its initial
value. It then overwrites all input cells before any owner query; expected
mapping, adjacency and topology must remain valid independently of the input.
The adapter itself owns the stack input, so this is backing overwrite evidence,
not a claim to have tested releasing an input allocation.

Error cases cover invalid limits, metadata bounds, configured/hard node and
edge ceilings, exact validation and operation work boundaries, offset scan
precedence, invalid targets and duplicate/unsorted neighbors. Error kind and
both payloads are compared. Every physical successful graph is at most 16
nodes and 256 edges. Descriptor-only large ranges are used solely where a
specified preflight rejection prevents reading them. This gate does not fake a
valid graph large enough to reach condensation's Edge staging capacity limit.
Actual allocation failures and deep traversal belong to the separate resource
and scale gate.

## Protocol and execution

`model.lani` is a test-only stdin/stdout adapter. Each input is a 96-byte header
of twelve little-endian u64 words, followed by declared offset and target words.
Signed i32 values use their signed u64 representation. Output is also raw
little-endian u64 words. Framing is fixed by the input and the public results;
there is no JSON, text parsing, or production transport dependency. A single
native process receives the entire batch. The verifier rejects every mismatched
word, truncated output, extra output, nonzero exit and stderr, reporting the
seed, case, and first differing word.

Test selector:

```text
independent_graph_components_match_mutual_reachability_canonical_ids_condensation_and_errors
```

The Rust driver requires a Linux x86_64 ELF and the shared executable writer's
jump containment checks, then runs the host oracle with a 90-second timeout.
The native subprocess itself has a 75-second timeout. Root owns compilation
and executable runs under the repository's serial compiler lock.

## Evidence

Host-only controls passed for all 3,218 expected records and literal independent
empty, singleton/self-loop, merged-cross-edge and reverse-topology examples.
Ten deliberately corrupted outputs were rejected: stride, guard, count, ID,
pair relation, condensed target, topological order, closed error, truncation and
trailing output. These are verifier controls and are not runtime library cases.

The native gate passed all **3,218 cases** on its first run: 2,792 successful
constructions and 426 admission or graph errors matched the complete reference
output. The focused Rust test passed in **7.28 seconds**, after a separate
1.59-second Rust build. The local receipt is
`target/stdlib-work/graph-components-model-first.log`.

This receipt establishes finite runtime behavior on **native Linux x86_64 CPU
output from the GPU compiler**. No user GPU execution, other platform support,
arbitrary stride support or formal proof is claimed here.
