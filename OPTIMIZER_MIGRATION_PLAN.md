# Optimizer Architecture Migration Plan

Status: active migration plan

This document explains how Lanius can move from the compiler that exists today
to the optimizer described in [`PLAN.md`](PLAN.md). It is deliberately about
migration rather than aspiration: each boundary leaves a working compiler,
identifies what becomes the new source of truth, and names the old machinery
that must be deleted.

[`PLAN.md`](PLAN.md) defines the destination and the research rationale.
[`OPTIMIZER_ROADMAP.md`](OPTIMIZER_ROADMAP.md) records detailed implementation
status, measurements, and per-slice evidence. This document owns the durable
route between them.

## Objective

The destination is one GPU-resident optimizer with three nested mechanisms:

1. a deterministic normalizer that computes facts and performs ordinary,
   reliably profitable optimization;
2. bounded local e-graphs that retain equivalent expressions and target
   recipes where sharing is useful; and
3. population search over interacting global choices such as inlining,
   scheduling, and register allocation.

All three mechanisms operate under the same semantic legality, machine-cost,
budget, proof, and incumbent contracts. They are not three unrelated optimizer
pipelines.

The final production path is:

```text
checked HIR
    -> semantic LIR
    -> structured SSA OptIR with explicit effects
    -> deterministic normalization
    -> optional local and global alternatives
    -> selected target LIR
    -> scheduling and register/local allocation
    -> artifact bytes
```

The optimizer remains GPU-resident from OptIR construction through target
emission. The host constructs and submits a bounded compiler graph; it does not
recover program semantics, choose individual rewrites, or wait between
optimizer rounds.

## Where the compiler is today

The important architectural seam already exists:

```text
semantic LIR
    -> GpuOptimizationStage
    -> GpuOptIrView
    -> x86-64 or Wasm target lowering
```

Both targets consume the OptIR view. The compiler graph owns logical resource
lifetimes and aliases them into reusable physical workspace. Compilation units
bound peak memory, so total project size does not need to determine peak VRAM.

The OptIR behind that seam is not yet the desired optimizer representation.
It is still close to an identity view of semantic LIR:

- mutable declarations are represented by value-get and value-set operations;
- target lowering still reconstructs some definition, lifetime, and control
  information;
- target-independent optimization remains embedded primarily in x86 lowering;
- explicit def-use and effect dependencies are incomplete;
- the optimizer has no production fact fixed point, costed incumbent, local
  alternative store, or global search yet.

Phase 2 construction has already produced dense blocks, CFG edges, reverse
edges, immediate dominators, a compact dominator tree, sparse declaration
access state, the structured-region tree with node/block ownership and edge
validation, and a sparse GPU-resident block-entry demand relation. It also
materializes block arguments and incoming values, resolves demand aliases,
builds reverse block-argument users, and removes trivial block arguments. The
relations pass the current reflection checks and physical-GPU x86-64/Wasm
semantic tests.

The first dense-value slice is also in production construction. It assigns one
canonical dense domain across parameters, ordinary value-producing nodes, and
surviving block arguments; emits an inverse definition row for every value;
and independently validates the count, prefix, and definition bijections on
the GPU. Ordinary operands still name semantic instruction rows, however, and
`VALUE_GET` still needs to resolve through the reaching-definition relation.
Dense assignment is therefore a construction result, not yet the production
value contract consumed by the backends.

The pruned-merge representation is now an accepted construction boundary. An
initial physical implementation gave every persistent worker its own visited
and queue slabs. On the 1 MiB performance case, that raised tracked buffers
from about 1.051 GB to 3.645 GB and raised the warm x86-64 median from 75.11 ms
to 81.48 ms. It was rejected and replaced rather than optimized locally.

The accepted implementation uses one exact global sparse set and one reusable
global queue. Worker count controls execution occupancy rather than semantic
storage capacity, and a 100-job physical-GPU stress run exercised the corrected
atomic publication protocol. Queue consumers reserve published work in
warp-sized batches, so each warp performs one queue-head update and one
completion update instead of one pair per row. The measured demand closure
fell from 2.77 ms to 0.14 ms and trivial-block-argument propagation from
1.09 ms to 0.03 ms on the retained profile.

The retained relations are also materially smaller. Demand queue capacity is
one row per possible access rather than four; incoming sources, SSA value
references, and each block-argument row use one, one, and two packed words;
and CFG edges use two words. Counted prefix scans reuse their input as their
output. After scattering incoming values, that consumed prefix storage becomes
the demand-resolution column. The canonical radix order is materialized once
into physical demand-row order, so downstream passes do not retain or bind an
extra order indirection.

On the daemon-capacity 1 MiB corpus, the accepted x86-64 representation retains
1,051,350,670 tracked bytes in 228 allocations, leaving 22,391,154 bytes below
the binary 1 GiB gate. Wasm retains 1,064,867,470 bytes in 229 allocations,
leaving 8,874,354 bytes. Twenty retained-workspace samples measure 75.15 ms
median on x86-64 and 38.17 ms on Wasm. Both targets record 86 compute passes,
create no timed buffers, bind groups, or pipelines, pass the focused semantic
suite, and pass the scalar prefix-scan fallback. The final physical layout is
therefore accepted; it does not need another round of local memory shaving
before SSA work continues.

Executable semantic-property tables and the identity OptIR cutover are already
complete. They are foundations to retain, not phases to repeat.

This means the next task is not to add more peephole optimizations. It is to
resolve declaration reads into the assigned dense domain, rewrite ordinary and
side-table operands, compact def-use, make effects explicit, and then remove
the declaration-recovery machinery from both backends. That cutover creates
the representation on which every later optimizer mechanism can be sound,
shared by both targets, and efficient to compute on the GPU.

## Migration at a glance

| Boundary | Material addition | What becomes removable or newly possible |
| --- | --- | --- |
| Current foundation | Executable semantic properties, identity OptIR seam, compiler-graph workspace | Direct semantic-LIR-to-target construction is already gone |
| Structured optimizer | Regions, CFG, dominance, block arguments, SSA values, def-use, explicit effects | Delete mutable-declaration recovery in both backends |
| Production normalizer | Seminaive facts and deterministic canonical rewrites | Delete shared semantic optimization embedded in x86 lowering |
| Clean target boundary | Both targets receive the same normalized OptIR | Wasm gains shared optimization; backends retain only machine decisions |
| Anytime core | Machine costs, nested work budgets, incumbent and bounded archive | Optional mechanisms can stop safely and cannot lose the best predicted result |
| Local alternatives | Bounded pure-region e-graphs and top-K extraction | Explore related local rewrites without making the whole program an e-graph |
| Target alternatives | Bounded instruction, schedule, and allocation choices | Delay machine decisions whose quality depends on surrounding choices |
| Global search | Persistent candidate patches and GPU work queues | Spend more GPU work on interacting whole-program choices without copying programs |
| Durable research system | Proofs, persistent results, learned guidance, verified target windows | Reuse expensive work and improve guidance without weakening legality |

## Relationship to the implementation roadmap

This document groups work by architectural cutover. The numbered phases in
[`OPTIMIZER_ROADMAP.md`](OPTIMIZER_ROADMAP.md) remain the implementation and
measurement record:

| This document | Optimizer roadmap |
| --- | --- |
| Current foundation | Phases 0 and 1 |
| Milestone 1: structured SSA OptIR | Phase 2 |
| Milestone 2: deterministic normalizer | Phase 3 |
| Milestone 3: clean backend boundary | Phase 4 |
| Milestone 4: anytime contract | Phase 5 |
| Milestone 5: bounded local e-graphs | Phase 6 |
| Milestone 6: target alternatives | Phase 7 |
| Milestone 7: global population search | Phase 8 |
| Milestone 8: durable research system | Phase 9 |

The critical path is therefore linear through Milestone 4: finish SSA, prove a
shared normalizer, remove shared optimization from the backends, then establish
cost, budget, and incumbent semantics. Local e-graphs and target alternatives
can develop independently after that contract exists. Global population search
depends on both. Proofs and persistence attach only after the representations
and action contracts stop changing rapidly.

An implementation slice crosses a boundary only when it does all five of the
following:

1. produces the new representation or result in the production compiler graph;
2. makes both x86-64 and Wasm consume it where the responsibility is shared;
3. deletes the superseded production analysis, adapter, or transform;
4. preserves checked semantics, bounded memory, and the warm compile-time gate;
   and
5. records its measurements and remaining work in the optimizer roadmap.

Building a relation that no production consumer reads is useful exploration,
but it does not count as crossing an architectural boundary.

## Architectural rules during migration

These rules apply to every milestone:

1. **One semantic direction.** Later phases consume the output of earlier
   phases. No optimizer or backend rediscovers meaning from raw tokens, source
   text, filenames, or incidental program shapes.
2. **One production representation per boundary.** Old and new paths may run
   together only in tests or diagnostic comparison mode. The old path is
   deleted when the new boundary passes its acceptance gate.
3. **Working vertical slices.** Every accepted change still emits and runs both
   x86-64 and Wasm programs. A disconnected data structure is not a completed
   milestone.
4. **GPU-sized relations, not Cartesian products.** Storage scales with actual
   nodes, edges, uses, facts, and candidates. It must not scale as
   declarations multiplied by blocks, candidates multiplied by whole-program
   size, or project bytes multiplied by compilation-unit workspace.
5. **No serial semantic fallback.** CPU implementations are useful as test
   oracles, not as production escape hatches for unusual or large programs.
6. **Capacity has defined semantics.** Required state either fits the declared
   compilation-unit capacity or reports a capacity error. Optional optimizer
   state compacts or stops admitting work and returns the incumbent.
7. **The normal path stays cheap.** Search-disabled compilation does not
   initialize, clear, bind, or dispatch optional search arenas.
8. **Deletion is part of implementation.** A migration that leaves the old
   target analysis, adapter, or duplicate operation framework in place is not
   finished.

## Workstream A: make the compiler graph an optimizer substrate

The existing compiler graph is capable, but too much code still describes the
mechanics of individual passes: resources, access modes, pipelines, bindings,
dispatch counts, and scratch buffers are often repeated separately. That is
manageable for a backend, but it will become untenable for a relational fixed
point, e-graph rebuilds, and a population work market.

The graph should gain typed, reusable GPU operations. Rust code should be able
to express operations at roughly this level:

```rust
let live = graph.filter(nodes, is_live);
let compact = graph.compact(nodes, live);
let ordered = graph.sort_by(compact, key);
let groups = graph.group_reduce(ordered, reducer);
let joined = graph.merge_join(groups, facts, join_key);
graph.fixed_point(delta, max_rounds, |round| update(round));
```

This is not a second compiler language and it is not permission to hide
algorithms behind opaque magic. Each operation has an explicit relation
schema, capacity formula, access contract, dispatch contract, and validation
mode. Its implementation owns the shaders, pipelines, bind groups, indirect
dispatch arguments, and reusable scratch it requires.

The graph builder derives read/write hazards and lifetimes from typed operation
arguments. Call sites should not manually repeat whether every buffer is read,
written, or read-write. Explicit escape hatches remain for genuinely unusual
kernels, but the common optimizer vocabulary is declarative.

Build this layer incrementally, driven by real consumers:

1. consolidate the existing prefix scan, compaction, and radix sort behind
   typed operation contracts;
2. add sort-and-unique and segmented reduction when def-use and facts need
   them;
3. add merge join and grouped lookup when the deterministic fact engine needs
   them;
4. add delta-driven repeated regions when the first fixed point is real; and
5. add a reusable sparse work-market operation now for SSA closure, then reuse
   it for fact closure and candidate search.

Do not pause the optimizer migration to build a general-purpose GPU language.
Every abstraction must replace repeated production plumbing and have at least
two real uses before it becomes a general operation.

The work-market operation owns a global sparse set and queue rather than one
capacity slab per persistent worker:

```text
Set<Key, Row>       claims each logical item once
Queue<Row>          stores only admitted work
head / tail         distribute queue rows to persistent workgroups
outstanding         proves global quiescence without a host readback
optional next queue supports deterministic round boundaries
```

Persistent workgroups are execution agents, not owners of logical capacity.
Changing the worker count must affect occupancy and scheduling only; it must
not multiply semantic storage. The set resolves duplicate discoveries, the
queue is bounded by a proved relation capacity, and a full required queue
produces a capacity diagnostic. Optional optimization queues stop admission
and return the incumbent instead.

The physical workspace remains a small collection of arenas:

```text
immutable OptIR
current and next relations
sort/scan scratch
target lowering
optional alternatives and proofs
control and indirect-dispatch arguments
```

The compiler graph colors logical lifetimes into these arenas and validates
that overlapping writable views are never bound together. Pipelines and
layouts are daemon-static. Job buffers are capacity-based and reusable; a
preallocated daemon job performs no timed buffer or bind-group creation.

## Milestone 1: finish structured SSA OptIR

This is the current critical path. The result must be a representation on
which an optimizer can reason without reconstructing mutable source state.

### 1. Complete structured-region ownership

- Assign every node and block to the innermost half-open structured region.
- Validate nesting, function ownership, opener/closer pairing, and region/CFG
  consistency on the GPU.
- Validate the completed dominator tree against every CFG edge.
- Retain only compact region rows and ownership columns; release construction
  flags, scans, parent-jump pairs, and interval scratch.

### 2. Construct pruned block arguments from value demand

Use the
[lazy backward construction described by Braun et al.](https://pp.ipd.kit.edu/publication.php?id=braun13cc&lang=en)
rather than building dominance frontiers and then running a second liveness analysis. The
compact declaration/block rows whose first read precedes every local definition
are exactly the initial reaching-definition demands.

- Seed a sorted relation `Demand(declaration, block)` from those upward-exposed
  reads.
- Treat a row as a demand for the declaration's value at that block's entry.
  For each predecessor, stop when its outgoing local definition supplies the
  value; otherwise demand the same declaration at the predecessor's entry.
- Compute the transitive closure with a fixed pool of persistent GPU
  workgroups over one global sparse set and work queue. The set admits each
  `(declaration, block)` pair once; the queue stores admitted sparse-set slot
  IDs. Consumers reconstruct the immutable key through atomic loads, while
  canonical demand rows are output-only until the following dispatch.
  Atomic head, tail, and outstanding counters distribute work and detect
  quiescence without a host round for each CFG depth.
- Size the hash table and queue from the maximum number of actual demand rows,
  not from `worker_count * block_capacity`. Reuse the same physical queue for
  later block-argument propagation after demand closure has ended.
- Canonically radix-sort the completed relation by `(declaration, block)` and
  validate both strict uniqueness and closure independently of the construction
  traversal.
- At a block with multiple predecessors, create the block argument before
  requesting its incoming values. This placeholder breaks loop cycles in the
  same way as an operandless phi in the sequential algorithm.
- Emit one incoming-value row per actual predecessor. Each row refers either to
  that predecessor's outgoing local definition or to its canonical demand row.
- Remove trivial merge values and merge-only strongly connected components
  before assigning final dense values. Propagate triviality through the same
  global bounded work queue; a block argument changes lattice state at most
  twice, so queue capacity has a direct proof.
- Handle loops, conditionals, `break`, and `continue` through the same demand
  and block-argument relations; there is no separate loop patch-up path.

This constructs pruned SSA because every block argument is created by an
ordinary use or another demanded block argument. Lanius's source CFG is
reducible, so eliminating trivial merge cycles also yields minimal SSA under
the result proved by Braun et al. The dominance tree and exact subtree
intervals remain valuable for independent validation and later optimization;
they are not prerequisites for placement.

The implementation remains sparse. It stores only actual demanded
`(declaration, block)` pairs, their resolutions, real block arguments, and
incoming edges—not a declaration-by-block matrix or a block-squared frontier.
No workspace allocation may multiply one of those relation capacities by the
number of resident worker groups.

### 3. Assign dense SSA values and rewrite operands

- Give parameters, constants, operation results, and block arguments dense
  value IDs.
- Resolve each declaration use through a batched nearest-dominating-definition
  query over the dominator tree. Same-block ordering comes from the existing
  access relation; cross-block ownership comes from dominance.
- Rewrite ordinary operands to dense value IDs.
- Remove value-get and value-set nodes from the compacted OptIR.
- Validate that every use has one definition and that the definition dominates
  the use.

The GPU implementation operates on actual sparse demand and definition rows,
using sort/scan or grouped nearest-ancestor operations where rewriting requires
them. Scheduled block order is not dominator preorder and must never be treated
as one. Exact dominance intervals remain useful for validation and later
optimizer queries, but block-argument placement does not depend on dominance
frontiers or a dense Euler-indexed declaration table. The implementation must
not launch one thread that walks a function, retain an `O(blocks log blocks)`
ancestor table, or copy declaration state through every transparent block.

### 4. Build explicit def-use and effects

- Compact `(value, user, operand)` rows and group them by value.
- Introduce one conservative effect token per function first.
- Thread loads, stores, calls, host operations, traps, and effectful control
  through effect inputs and outputs.
- Insert effect block arguments at control-flow merges with the same machinery
  used for ordinary values.
- Mark pure nodes by the absence of an effect edge.

Alias analysis can later split the single chain into independent memory
regions. The conservative chain is intentionally less optimizable, but it is
sound and gives every later transform an explicit ordering contract.

### 5. Cut production consumers over

- Make both target stages reject mutable declaration operations.
- Make x86 lifetime and register analysis consume SSA def-use and effects.
- Make Wasm stack/local placement consume the same values and control facts.
- Delete target analyses whose only purpose was recovering declaration state.
- Delete the identity representation and any permanent compatibility adapter.

### Milestone 1 acceptance gate

- Every ordinary use has exactly one dominating definition.
- Every block argument has one incoming value per predecessor.
- Every block has one terminator and belongs to one function and region.
- Effectful or trapping nodes cannot cross an effect dependency.
- No value-get or value-set reaches either target.
- Generated nested-control, mutation, call, aggregate, trap, and memory tests
  agree across a test oracle, x86-64, and Wasm.
- There is no CPU barrier from SSA construction through target recording.
- The 1 MiB tracked-memory gate and warm compile-time gate remain satisfied.

## Milestone 2: build the deterministic relational normalizer

The normalizer is the production optimizer. It must be useful and fast even if
all optional search budgets are zero.

### 1. Establish canonical current/next OptIR

Normalization should not perform uncontrolled in-place mutation. Each round
reads a canonical OptIR and fact snapshot, emits a compact change set, then
materializes or aliases the next canonical snapshot. Unchanged columns are
reused. Changed nodes are compacted, assigned stable new IDs, and accompanied
by an old-to-new map for values, blocks, and uses.

### 2. Establish the seminaive fact engine

Start with relations that have immediate consumers:

```text
Constant(value, bits)
Copy(value, canonical_value)
Reachable(block)
ExecutableEdge(edge)
Use(value, user, operand)
KnownBits(value, zero_mask, one_mask)
Range(value, lower, upper, flags)
MemoryFact(node, region, access)
CallEffect(function, mask)
```

Each round joins the previous delta with indexed relations, emits new facts,
sorts and deduplicates them, and produces the next delta count. Indirect
dispatch turns converged rounds into zero work without host readback.

### 3. Add normalization in dependency order

Implement the first closure in this order:

1. constant folding and copy propagation;
2. reachable-edge discovery and sparse conditional constant propagation;
3. branch folding and unreachable-block removal;
4. dead pure-node and dead block-argument elimination;
5. global value numbering and common-subexpression elimination for pure nodes;
6. known-bit and integer-range simplification;
7. simple algebraic and strength-reduction rules allowed by the executable
   language semantics; and
8. conservative load forwarding and dead-store removal where provenance and
   effects prove legality.

Every rule produces either a fact or a compact rewrite action. Rules do not
directly mutate unrelated graph state.

### Milestone 2 deletion and acceptance gate

- Delete duplicate constant, copy, reachability, and dead-code logic from
  target lowering as its shared replacement lands.
- Normalizing an already normalized program produces the same semantic hash.
- The same compiler version, target, and inputs produce the same normalized
  OptIR.
- Search-disabled Wasm and x86 both benefit from the same transformations.
- The checked and generated differential suites preserve outputs, exits, and
  traps.
- Performance artifacts expose normalizer rounds, relation sizes, phase time,
  passes, and peak workspace.

## Milestone 3: move optimization out of the backends

Once the normalizer is real, migrate the useful optimization that currently
lives in x86 lowering one transform at a time:

1. add the target-independent OptIR form;
2. compare it against the existing x86 behavior;
3. enable it for both x86 and Wasm;
4. measure compile time and generated-code quality; and
5. delete the old backend implementation and plumbing.

The first migrations are constant/copy cleanup, dead values, control
simplification, and small-function inlining. Inlining eligibility moves to
OptIR call, effect, CFG, and size facts. It must not depend on x86 register
locations or a bounded target-row recipe.

Target lowering continues to own only decisions that truly depend on the
machine:

- ABI classification;
- instruction and addressing-mode selection;
- scheduling;
- x86 register allocation and spilling;
- Wasm stack and local placement;
- relocation and artifact layout.

This milestone should make the codebase smaller. A transform is not considered
migrated until the superseded Rust and Slang implementation is gone.

## Milestone 4: add the anytime contract

Before Lanius stores many alternatives, it needs a precise answer to “which
program wins?” and “what happens when work or memory runs out?”

Add:

- versioned language-semantics and machine-model identifiers;
- target cost vectors for predicted latency, code size, spill traffic,
  critical path, and peak temporary memory;
- an objective that ranks or constrains those vectors;
- deterministic work budgets measured in nodes, matches, candidates, and
  evaluations rather than host milliseconds;
- a normalized-program incumbent available before optional work begins; and
- a bounded archive of nondominated candidates with semantic hashes and
  provenance.

For nested budgets, the larger run retains the smaller run's accepted archive.
Predicted incumbent quality therefore cannot worsen with more optimizer work.
Measured runtime can still disagree with the model; performance artifacts must
show that error explicitly.

Capacity exhaustion in an optional arena stops admission, compacts, or ends
that search mechanism. It returns the incumbent. It does not fail compilation
and does not switch to a CPU implementation.

## Milestone 5: add bounded local e-graphs

The first e-graph handles only pure scalar integer and boolean regions. It is a
local equivalence memory, not the optimizer's top-level program
representation.

- Batch many regions by attaching a graph ID to e-nodes, e-classes, matches,
  and unions.
- Implement matching as relational joins over indexed e-node columns.
- Implement rebuild with sort, unique, merge join, and segmented reduction.
- Maintain type, constant, known-bit, range, effect-class, and lower-bound-cost
  analyses per e-class.
- Bound nodes, matches, unions, rounds, and top-K extractions.
- Pulse full graphs: extract useful candidates, discard dominated state,
  compact, and continue only while budget remains.
- Admit extracted alternatives through the same verifier and incumbent archive
  as every other optimizer action.

Do not start with effectful CFG equality saturation. Control and effects remain
in canonical OptIR; e-graphs optimize regions whose boundaries provide an
auditable type and effect signature.

## Milestone 6: expose target alternatives

Target lowering currently commits early to instruction forms, schedules, and
locations. Replace selected irreversible decisions with bounded alternatives:

```text
x86-64:
    instruction recipes, addressing modes, compare/select forms,
    schedules, register-allocation and spill seeds

Wasm:
    local reuse versus recomputation, stack order, block encoding,
    code-size versus runtime recipes
```

Each alternative retains the same semantic and effect boundary and enters the
same costed archive. The low-latency path still selects one deterministic
recipe without initializing search state.

## Milestone 7: add global population search

Global candidates must not copy the whole program. Keep one immutable
normalized OptIR and represent each candidate as a persistent patch list:

```text
choose local extraction E
inline call C with variant V
choose target recipe R
choose schedule seed S
choose allocation seed A
```

Compact or materialize a candidate only when patch depth crosses a threshold
or target evaluation requires it. Candidate memory then scales with the base
program plus admitted patches, not candidates multiplied by program size.

GPU work queues cover analysis, matching, extraction, mutation, target
evaluation, verification, and archive insertion. Independent deterministic
islands claim work through indirect dispatch and occasionally exchange strong
candidates. Start with local extraction, inlining, target recipes, scheduling,
and allocation. Add loop transformations only after these choices show a
useful quality-versus-work curve.

The defining gate is not one impressive `-O3` result. Across the stored runtime
suite, more work must improve or preserve the predicted incumbent frontier,
and ablations must show what came from normalization, e-graphs, global search,
and their combination.

## Milestone 8: make the system durable

Proofs, persistence, learning, and superoptimization build on the same
contracts rather than introducing another compiler path.

### Proofs

Each rewrite records a rule ID, substitution, source and target semantic hash,
and required dominance/effect/range/alias witnesses. A GPU verifier checks the
certificate before archive admission. A small CPU checker may replay sampled
proofs in tests and offline corpus generation.

### Persistence

Cache normalized OptIR, facts, local alternatives, patches, proofs, and measured
outcomes by semantic content hash, compiler version, target model, profile, and
objective. An edit invalidates the affected function and dependent callers,
not unrelated units. The cache remains optional and never establishes
correctness.

### Learning

Learned models rank work and correct residual machine-cost error. They do not
decide semantic legality. Disabling learned guidance must preserve the
deterministic normalizer and all correctness properties.

### Superoptimization

Solver-generated target windows enter through the existing target-alternative
and proof contracts. No solver is placed on the normal production path, and no
generated rule becomes trusted without a retained proof or a separately
checked general rule.

## The next concrete change sequence

The immediate implementation order is:

1. **Complete:** dump the logical-resource-to-arena assignment and replace
   worker-local storage with one exact global sparse set and queue.
2. **Complete:** derive relation capacities from access, demand, predecessor,
   and block-argument domains; add explicit overflow diagnostics; compact
   incoming sources, block arguments, CFG edges, and SSA references.
3. **Complete:** add in-place counted prefix scans, reuse block-argument flags
   and incoming counts as their own prefixes, and compact each block-argument
   row to two words. This removed 54,067,200 tracked bytes from the
   daemon-capacity 1 MiB case.
4. **Complete:** hand storage ownership from the consumed incoming-prefix
   relation to demand resolutions and physically canonicalize the demand
   relation, releasing its order indirection before downstream consumers.
5. **Complete:** prove the final physical boundary on x86-64 and Wasm. Both
   targets are below the binary 1 GiB gate, within the warm-latency gate, pass
   the focused semantic and scalar-prefix-fallback suites, and create no timed
   GPU resources.
6. **In progress:** dense SSA values and inverse definitions are assigned and
   validated; resolve declaration reads and rewrite ordinary and side-table
   operands into that domain;
7. compact def-use rows;
8. add conservative effect values and effect block arguments;
9. switch both target stages to SSA-only OptIR;
10. delete mutable-declaration recovery from target lowering;
11. turn the accepted global sparse set and queue protocol into a typed
    compiler operation before the normalizer needs another fixed-point work
    market, deleting the demand-closure and trivial-propagation plumbing that
    the operation replaces;
12. introduce typed sort/unique and grouped-reduction operations while
    building the first fact relations;
13. implement constant/copy propagation, SCCP, branch folding, and DCE as the
    first deterministic closure; and
14. migrate and delete the existing x86-only small-function inliner.

Steps 1–5 turn the semantically correct sparse relations into an accepted,
reusable physical architecture. Steps 6–10 finish the representation boundary.
Steps 11–14 prove that the new representation and graph substrate actually
simplify production optimization. Only after that proof should work begin on
cost archives or e-graphs.

## Project scaling and memory

Optimizer capacity is per compilation unit. A large project is scheduled as
dependency-ready units of no more than roughly 5 MiB; an individual source
file must fit within that supported unit limit. The same GPU workspace is
reused from unit to unit. Persisted interfaces, objects, semantic hashes, and
optional optimization summaries cross unit boundaries; raw per-unit optimizer
relations do not.

Cross-unit optimization begins with compact interface and call-summary facts.
It must not merge an entire 1 GiB project into one resident OptIR or make peak
VRAM proportional to total project bytes. Whole-program choices can reference
unit-local variants by content hash and patch ID.

Every milestone records:

- peak tracked and physical VRAM over time;
- bytes per source byte and bytes per OptIR node;
- logical relation sizes and physical arena occupancy;
- recorded operations, compute passes, submissions, and readback barriers;
- pure-cold, daemon-cold-workspace, and preallocated-daemon latency; and
- generated-code runtime, code size, spills, and instruction counts.

The current 1 MiB / 1 GiB tracked-memory gate remains a regression guard, not
the final optimization target. Optional search memory has separate named
budgets and must never make a zero-search compile pay its full capacity.

## Definition of material progress

The migration is materially advancing only when old responsibilities disappear
and the new boundary improves more than its own demo:

- **Near term:** neither backend sees mutable declaration operations; SSA,
  def-use, regions, CFG, dominance, and effects are complete and validated.
- **Production optimizer:** one deterministic normalizer improves both targets,
  and duplicated x86 semantic optimization has been deleted.
- **Anytime optimizer:** optional mechanisms all improve one retained incumbent
  under one nested budget and bounded memory model.
- **Research destination:** local e-graphs, global search, proofs, persistence,
  learning, and target alternatives use the same relations and legality
  contracts rather than forming separate subsystems.

At each boundary, compiler correctness, warm compile speed, generated-code
quality, and bounded VRAM are acceptance criteria. The architecture is not
successful merely because the final data structures exist; it is successful
when Lanius becomes simpler at its phase boundaries, faster at compiling real
programs, and able to spend additional GPU work on progressively better code
without changing compiler architecture again.
