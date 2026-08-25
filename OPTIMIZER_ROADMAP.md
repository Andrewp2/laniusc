# Optimizer Architecture Roadmap

Status: active implementation record

[`OPTIMIZER_MIGRATION_PLAN.md`](OPTIMIZER_MIGRATION_PLAN.md) owns the durable
path from the compiler that exists today to the architecture in `PLAN.md`.
This document records the detailed phase gates, implementation status,
measurements, and accepted vertical slices. The central decision is still to
build the optimizer in layers: Lanius first gains a sound, target-independent
optimizer IR and a fast deterministic optimizer. Bounded e-graphs and
population search come after that foundation works on real programs.

The shortest path to the proposed architecture is:

```text
define executable semantic contracts
    -> insert an identity OptIR stage
    -> construct structured SSA and explicit effects
    -> add deterministic normalization and dataflow
    -> move target-independent optimization out of x86 lowering
    -> add cost, budget, and incumbent infrastructure
    -> add bounded local alternatives
    -> add global population search
    -> add proof certificates, persistence, and learned guidance
```

Each arrow is a working compiler boundary. We do not keep two permanent
compiler architectures, and we do not wait for the final research system
before improving generated code.

The material change across the roadmap is:

| Boundary | What exists at that boundary | What has been removed |
| --- | --- | --- |
| Today | Checked HIR lowers through semantic LIR into an identity OptIR view, then into x86-64 or Wasm target LIR. | Direct semantic-LIR-to-backend construction. |
| Structured optimizer | OptIR owns dense functions, regions, blocks, CFG edges, SSA values, def-use rows, and explicit effect chains. | Mutable-declaration recovery and implicit row-order dependencies in target lowering. |
| Production normalizer | Shared GPU dataflow and deterministic normalization optimize both targets before instruction selection. | Duplicated target-independent optimization embedded in x86 lowering. |
| Anytime optimizer | A costed incumbent is always available; bounded local alternatives and global search can improve it as budget increases. | Optimization levels implemented as unrelated fixed pass pipelines. |
| Research destination | Verified rewrites, persistent facts and candidates, learned guidance, and optional superoptimization all use the same legality, budget, and incumbent contracts. | Unverified optimization mechanisms and architecture-specific semantic shortcuts. |

The first three boundaries are conventional compiler engineering and are the
critical path. The later search layers are optional capabilities built on that
foundation; they cannot compensate for an unsound IR or an expensive normal
compile path.

## Implementation progress

Phase 0 implementation is complete as of August 22, 2026. Its production
cutover is active; repository-wide green-suite status remains blocked by the
dirty branch's existing frontend and source-pack failures described below.

Phase 1 is now implemented through the first end-to-end production cutover:

- Rust and Slang share fixed-width OptIR node records for the operation, type,
  operands, control/effect links, and results. Semantic-row and source-HIR
  provenance are separate 32-bit columns so hot target passes fetch only the
  source ownership they use.
- `lir.opt.project` materializes one identity OptIR node per semantic row on
  the GPU. It runs between semantic lowering and target lowering in the same
  command stream, with no readback or host semantic reconstruction.
- Identity OptIR core and operand columns are binary-compatible aliases of the
  semantic producer output. The projection does not copy those two large hot
  columns; it materializes only count, control, results, and provenance.
- The compiler graph owns an explicit `Optimization` phase and OptIR node
  resources. The optimization stage aliases those resources from the resident
  lowering workspace rather than allocating a separate unmanaged arena.
- Both production target constructors require `GpuOptIrView`. Their count,
  scatter, analysis, relocation, function-table, and target-page operations
  consume the OptIR operation stream and OptIR row count; the former direct
  semantic-instruction route has been removed.
- Target stages no longer receive `GpuSemanticLirView`. Immutable variable-
  arity rows, declarations, strings, layout data, and execution order transfer
  through `GpuOptIrMetadataView`. The redundant semantic-operation column was
  deleted, and semantic source ownership remains live only through projection.
- Lowering diagnostics now retain semantic row, OptIR row, and source HIR and
  display all three identities on an unsupported target operation.
- Shader/reflection contract tests, OptIR record-layout tests, the physical-GPU
  dual-target workspace test, and the generated x86/Wasm differential program
  pass after the cutover. The physical-GPU test also confirms that compiling
  the two target jobs creates no pipelines after compiler preparation.

Phase 1's production architecture and performance gates are complete against
the recorded branch baseline. The ownership seam, diagnostic traceability,
target cutover, warm regression gate, and 1 GiB tracked-memory gate all pass.
The checked suites reproduce the branch's existing x86 and Wasm results
without adding a target failure; their pre-existing failures remain project
work and are not reclassified as acceptable language behavior.

The first 1 MB x86 profile measured the identity projection at about 0.03 ms.
An A/B run that fed the two long x86 per-function walks from semantic core rows
instead of the layout-identical OptIR core did not improve total time. The
current roughly 79 ms warm median is dominated by the pre-existing x86
normalization and register-allocation walks (roughly 17 ms and 29 ms in the
captured job), not by OptIR materialization. The retained 41.86 ms artifact
predates the current versions of those walks and therefore cannot by itself
serve as the Phase 1 baseline. The directly comparable retained packed-OptIR
measurements were 76.38 ms median and 1.407 GB of tracked buffers for x86 and
41.81 ms median and 1.312 GB for Wasm. The accepted Phase 1 measurements are
78.80 ms for x86 and 41.67 ms for Wasm, a 3.2% x86 regression and a 0.3% Wasm
improvement relative to those packed baselines. Both targets retain exactly
1,051,348,342 tracked bytes across 224 allocations, 22,393,482 bytes below
1 GiB, and both timed jobs create zero pipelines, buffers, or bind groups.

Phase 2 is in progress. The current validated slice establishes generated
control-role metadata, compacts structured control into dense OptIR blocks,
emits dense CFG edges, and reduces those blocks into compact function ownership
records on the GPU. Function finalization checks contiguous block ownership,
entry blocks, and node/block bounds before exposing the table. Structured
branch and loop programs pass on both physical x86-64 and Wasm paths. SSA
construction now begins from a compact, phase-local access relation: scheduled
declaration reads/writes and memory reads/writes are compacted with a GPU prefix
scan, then parameter definitions and local declarations are appended from their
compact metadata. Each row is checked against its function, block, position,
and declaration/address domain. The access buffers reuse compiler-graph
workspace and do not become retained backend artifacts. Structured regions,
node/block ownership, merge arguments, dense values, and compact def-use
relations are now constructed and validated. Explicit effect values and the
backend cutover remain; target lowering therefore still observes identity-style
value operations through OptIR today.

Access ordering and block-local definition resolution are now complete. A
capacity-derived stable radix sort groups accesses by declaration-versus-memory
domain and subject while preserving metadata-before-control order. Its bucket
prefix scan has no former 4,096-block ceiling. One compact group is emitted per
declaration, and one 256-lane workgroup per group resolves the nearest preceding
definition inside each basic block. The associative lane-summary scan carries a
definition only across slices of the same block; reads at a real block entry
remain unresolved for CFG propagation. A separate GPU validator checks the
exact nearest-definition recurrence in constant work per access row. The
partial CFG remains optimizer-private until structured SSA becomes the target
input, so incomplete blocks and edges do not masquerade as a retained backend
artifact. The next representation boundary is cross-CFG reaching-definition
propagation and merge-value construction.

Sparse block-entry state is also complete. The stable access order is compacted
again into one row for each `(declaration, basic block)` that actually contains
an access. It does not allocate a declaration-by-block matrix. Each row stores
only its access-range start; declaration, block, range end, last local
definition, and outgoing definition are derived from the canonical access
relation. A parallel one-word state distinguishes an unused entry from an
unresolved incoming value and later holds the incoming definition or merge identity.
The declaration-group flag and prefix arrays are reused for this second
compaction rather than adding another pair of full-capacity scan columns. An
independent GPU validator reconstructs every populated pair and its initial
incoming-value state.

The first access-relation memory/performance gate retains exactly the Phase 1
peak: 1,051,348,342 tracked bytes across 224 allocations on both targets. Over
20 retained-workspace samples, x86-64 compiles at a 73.60 ms median and Wasm at
36.46 ms, with zero timed pipeline, buffer, or bind-group creation. These runs
establish non-regression rather than attributing the lower medians to the new
passes; driver and machine noise remain part of the comparison.

The accepted access-ordering and block-local-definition slice remains at
1,051,349,122 tracked bytes across 226 allocations on both targets: 780 bytes
above the prior slice and 22,392,702 bytes below 1 GiB. Twenty retained-workspace
samples measure 74.25 ms median on x86-64 and 37.56 ms on Wasm, respectively
0.88% and 3.02% above the first access-relation medians. Timed jobs create zero
pipelines, buffers, and bind groups. The first implementation exceeded the
memory gate because it retained an incomplete CFG and reserved empty effect,
region, and block-argument fields. The accepted representation keeps the
partial CFG phase-local, stores node control ownership in eight bytes, stores
block core/edge range in sixteen bytes, and leaves effects, regions, and block
arguments as compact relations for the slices that actually materialize them.

The accepted sparse declaration-block slice retains 1,051,349,134 tracked
bytes across 227 allocations on both targets, only twelve bytes above the
previous slice and 22,392,690 bytes below 1 GiB. Twenty retained-workspace
samples measure 72.25 ms median on x86-64 and 35.07 ms on Wasm. The slice adds
seven compute dispatches but no recorded compute pass because command-pass
batching keeps compatible operations together; timed jobs create zero
pipelines, buffers, and bind groups. An initial 32-byte-per-row design was
rejected after it raised the tracked peak to 1,150,660,738 bytes. The accepted
design uses one four-byte range row and one four-byte incoming-state row, and
reuses the declaration-group scan storage.

The reverse CFG and the immediate-dominator relation are now complete for the
current structured OptIR. Incoming
edge IDs are compacted by destination block after successor ranges have been
sealed, reusing the forward count/prefix scan workspace. A second three-dispatch
slice then classifies every block as a function entry, unreachable, an exact
single-forward-predecessor block, or a forward join. Forward joins are resolved
from their structured `CONTROL_END` and matching owner-local opener. Synthetic
control recipes have stable contiguous OptIR identities even when their child
instructions are interleaved in execution order, so this matching work is
bounded by the recipe rather than by function size. A validator rejects every
remaining unresolved or cross-function dominator. The sole persistent relation
is one immediate-dominator word per block; the graph allocator aliases it with
dead predecessor scratch. This replaces the earlier plan to propagate each
declaration through every transparent CFG block, which could still approach
declaration-by-block amplification on long control-only paths. The remaining
cross-CFG work is pruned merge placement and dominator-tree renaming over
compact access rows.

The accepted reverse-CFG slice retains 1,051,349,134 tracked bytes across 227
allocations on both targets. Twenty retained-workspace samples measure 74.68 ms
median on x86-64 and 37.45 ms on Wasm. The accepted dominance-seed slice retains
the same byte and allocation peak while measuring 71.56 ms and 34.75 ms. The
second measurement adds three dispatches and no recorded compute pass; both
slices create zero timed pipelines, buffers, and bind groups. The lower medians
are treated as non-regression rather than attributed to the new work.

The accepted structured-join resolver still retains exactly 1,051,349,134
tracked bytes across 227 allocations. Twenty retained-workspace samples measure
73.00 ms median on x86-64 and 35.57 ms on Wasm. It adds two dispatches without
adding a recorded compute pass, and timed jobs again create zero pipelines,
buffers, or bind groups.

The compact dominator-tree child relation is also complete. It counts children
by immediate dominator, uses a prefix scan to assign parent ranges, scatters one
child ID per reachable non-entry block, and validates one parent cursor and one
child row per invocation. No invocation walks a potentially project-sized child
list. The graph reuses dead predecessor count, cursor, total, and scan workspace;
the child-ID column aliases existing phase storage. The tracked peak therefore
remains 1,051,349,134 bytes across 227 allocations. Twenty retained-workspace
samples measure 74.86 ms median on x86-64 and 38.30 ms on Wasm, still below the
accepted Phase 1 medians. Timed jobs create zero pipelines, buffers, or bind
groups.

The structured-region slice is complete. Opening control rows are compacted
into dense, function-contiguous region records with half-open scheduled-position
intervals and exact nearest-parent identities. A phase-local range-max segment
tree assigns the innermost region to every node and block with one logarithmic
query per row; its `2 * semantic_capacity` words alias dead workspace and do
not become a retained backend artifact. Region openers independently validate
their nearest parent against the ownership tree. A final edge-parallel
validator checks every CFG edge against the completed immediate-dominator
relation; each invocation follows only its source block's compact parent chain,
and no invocation owns a function-wide traversal. This replaced an initially
attempted region-containment heuristic that rejected valid ordinary CFG
shapes. The accepted implementation passes the generated scalar, projected
memory, and nested structured-control programs on both physical x86-64 and
Wasm paths.

The accepted region-ownership slice retains 1,051,349,134 tracked bytes across
227 allocations on both targets. Twenty retained-workspace samples measure
71.31 ms median on x86-64 and 34.40 ms on Wasm. It adds five dispatches without
adding a recorded compute pass; timed jobs create zero pipelines, buffers, or
bind groups. The lower medians relative to the region-tree-core slice are
treated as non-regression rather than attributed to the new work.

Merge placement now has a validated dominator-depth index. Binary lifting
accumulates one depth per block in logarithmic GPU rounds, then an independent
pass checks that every reachable non-entry block is exactly one level below
its immediate dominator and that unreachable chains remain explicit. The
accepted representation retains only one depth word per block; its two
temporary `(ancestor, distance)` columns are phase-local workspace. An initial
attempt to derive subtree intervals directly from scheduled block order was
rejected by the nested-control and `break`/`continue` acceptance cases: that
order is not dominator preorder.

The replacement is an exact dominator-tree Euler index. A compact inverse
child row connects two directed tour arcs per reachable non-root block;
parallel list ranking then emits one true preorder and one half-open subtree
end per block in logarithmic GPU rounds. A separate inverse scatter and
validator reject duplicate preorder identities, cross-function parents, and
incorrect parent/subtree containment. The two ranked-link columns are
phase-local linear workspace, and only the two four-byte interval words survive
for SSA validation and later optimizer queries. This gives constant-time
ancestry tests without source-order assumptions or a retained
`O(blocks log blocks)` ancestor table.

An initially implemented dominance-frontier path relation was removed after
the next consumer was derived. A pruned iterated-dominance-frontier algorithm
requires a completed per-declaration live-in relation; the available compact
rows only identify upward-exposed reads that *seed* that liveness computation.
Intersecting definitions with frontier paths would therefore have required a
second backward fixed point plus a heavy-path range index before producing one
block argument. The path rows, their two shaders, the actual-definition index,
and the paired scan were speculative infrastructure rather than the shortest
production route.

Phase 2 now follows the
[lazy backward construction of Braun et al.](https://pp.ipd.kit.edu/publication.php?id=braun13cc&lang=en)
Those same upward-exposed reads seed `Demand(declaration, block)`, where a row
means that the declaration's value is required at the block's entry. For every
predecessor, an outgoing local definition stops propagation; otherwise the
same declaration is demanded at the predecessor's entry. A fixed pool of GPU
workgroups computes that transitive closure through one exact global sparse set
and one reusable global queue. Warp-sized queue reservations amortize the
global head and completion atomics without making semantic storage capacity
depend on worker count. This avoids host-driven rounds proportional to CFG
depth, a declaration-by-block resident matrix, and the rejected per-worker
visited and queue slabs. The completed relation is radix-sorted by
capacity-derived `(declaration, block)` keys, then independently validated for
strict uniqueness, seed retention, and predecessor closure.

The production graph now stores explicit eight-byte demand keys because
transparent predecessor blocks need not have a canonical declaration-access
row. A scalar seed scan, persistent closure operation, canonical radix order,
and independent validator replace the former paired definition/live-in
operation. Historical frontier-path and paired-relation artifacts remain
useful evidence for the rejected branch, but those relations are no longer
part of the compiler. The closure and validator pass the generated scalar,
projected-memory, nested-control, and loop-exit cases on both x86-64 and Wasm.
Block arguments and packed incoming values are now materialized, demand aliases
are resolved, reverse block-argument users are compacted, and trivial block
arguments reach a GPU-resident fixed point. The next construction slice assigns
one dense value domain across parameters, ordinary definitions, and surviving
block arguments. It resolves declaration-read aliases, rewrites fixed operands
and variable-arity call/aggregate inputs, rewrites merge inputs, and validates
every resulting use against exact dominator-tree intervals. Def-use, explicit
effects, and the backend cutover lie beyond that construction, so the accepted
pruned-merge baseline itself had not crossed the production SSA boundary.

The rejected per-worker implementation retained 3.645 GB and measured
81.48 ms median. The initial exact global representation retained 2.515 GB and
measured 80.90 ms. The first packed relation retained 1,132,451,470 bytes and
measured 82.73 ms, so it remained an intermediate rather than an accepted
boundary. Queue batching reduced demand closure from 2.77 ms to 0.14 ms and
trivial-block-argument propagation from 1.09 ms to 0.03 ms.

The accepted representation additionally reuses consumed incoming-count
prefix storage for demand resolutions and physically canonicalizes the sparse
demand relation after sorting. Downstream passes index canonical demand rows
directly and release the order indirection before block-argument processing.
On the daemon-capacity 1 MiB corpus, x86-64 retains 1,051,350,670 tracked bytes
across 228 allocations and Wasm retains 1,064,867,470 bytes across 229
allocations. Those results are 22,391,154 and 8,874,354 bytes below the binary
1 GiB gate respectively.

Twenty retained-workspace samples measure 75.15 ms median with 3.69 ms MAD on
x86-64 and 38.17 ms median with 0.55 ms MAD on Wasm. The targets record 1,115
and 1,123 dispatches respectively in 86 compute passes and create zero timed
pipelines, buffers, or bind groups. The focused x86-64/Wasm optimizer semantics,
graph/reflection contracts, memory-capacity checks, and scalar prefix-scan
fallback all pass. At that retained baseline, dense SSA values, operand
rewriting, def-use, explicit effects, and the backend cutover were still
pending; the pruned merge-value slice itself is accepted independently of the
subsequent implementation described below.

Dense SSA construction is now implemented after that accepted baseline. One
prefix-compacted domain assigns a unique value ID to every parameter, ordinary
value-producing OptIR node, and surviving block argument. An inverse definition
row is emitted for every value, declaration reads resolve through the sparse
reaching-definition relation, and logarithmic GPU pointer jumping collapses
read-to-read alias chains. Separate canonical columns rewrite fixed operands,
call arguments, aggregate elements, and block-argument incoming values. An
independent final pass checks the value/definition bijection, exact operand
projection, CFG predecessor identity, and dominance at each use site.

That validation exposed a latent CFG error rather than being weakened around
it: an `IF` false edge with an `ELSE` had targeted the row after the `ELSE`
marker instead of the first row after the complete else arm. It also exposed
that predecessor counts must exclude edges from unreachable blocks. The CFG
target is corrected, and reachability is now computed explicitly with one
bounded GPU work queue before dominators. Sparse SSA passes consume that exact
reachability relation instead of inferring it from whether a dominator preorder
number happened to be assigned. The graph/reflection contract and all four
focused structured x86-64/Wasm semantic programs pass after the correction.

Def-use construction is also complete. Fixed operands and active call,
aggregate, and block-argument inputs are prefix-compacted into one canonical
use relation. Call and aggregate source tables are filtered rather than treated
as executable merely because their semantic metadata rows exist. A
capacity-derived stable radix order groups the compact relation by dense value
ID, and one `OptIrUseGroup { value, start, count }` row is emitted per used
value. Independent validators reconstruct the source relations, prove the
stable use permutation, and prove that the groups cover every use exactly once.
The radix layout has no fixed block-count ceiling and all storage remains
compiler-graph workspace until the production OptIR cutover retains it.

The scale gate exposed two pre-existing concurrency defects before accepting
the relation. The local-definition validator read access order and position
columns that were missing from its graph liveness contract, allowing workspace
coloring to reuse them too early. The trivial block-argument fixed-point worker
also read an atomically updated lattice through an ordinary cross-workgroup
load. Complete reflected access coverage now includes the access passes, and
fixed-point propagation reads the lattice through its atomic coherence domain.
Five repeated 100 KB jobs, three repeated 1 MB jobs, and the four dual-target
optimizer semantic programs pass after those corrections.

Twenty retained-workspace samples measure 71.01 ms median wall time (68.88 ms
compiler time, 3.82 ms MAD) on x86-64 and 38.19 ms (36.02 ms compiler time,
0.71 ms MAD) on Wasm. Timed jobs create zero pipelines, buffers, or bind groups.
This is a roughly 5.5% x86 improvement and an effectively unchanged Wasm result
relative to the accepted 75.15 ms and 38.17 ms pruned-merge baseline. The
uncut construction retains 1,514,609,050 tracked bytes across 235 allocations,
however, versus 1,051,350,670 bytes at that baseline. Def-use semantics and
warm time are therefore accepted, but this is not yet a memory-accepted Phase 2
boundary: production cutover must retain only the compact grouped relation and
release its construction columns before the 1 GiB gate is rerun.

The x86 backend's two function-serial GPU kernels have now been removed from
the engineering branch. Exact liveness uses a fixed pool of persistent GPU
workgroups over one global node queue. Spill widths are computed per scheduled
OptIR node, globally prefix-scanned, and translated to function-relative stack
locations in parallel; the remaining per-function finalizer reads only the two
prefix endpoints and performs constant work. Short scalar intervals use a
bounded deterministic coloring whose local inspection is at most seven
scheduled positions. A function is segmentation metadata, never the unit of
serial shader work.

On the same 1 MB retained x86 corpus, the GPU optimizer interval fell from
16.22 ms to 1.06 ms and the allocator interval fell from 29.52 ms to 0.09 ms.
Twenty warm samples now measure 38.56 ms median wall time and 36.02 ms median
compiler time, with 0.35 ms and 0.28 ms MAD respectively. The replacement uses
667 lines across six focused shaders in place of the deleted 1,558-line
combined shader. The graph/reflection contract, four x86/Wasm optimizer
differentials, and representative scalar x86 execution pass. This result is a
performance and architecture checkpoint, not a full-suite acceptance boundary:
the current dirty branch still has target-independent OptIR structure failures,
and x86 code-quality tests still identify normalization and coalescing behavior
that must move into parallel target-independent or target-specific operations.

This construction is not yet an accepted Phase 2 boundary: the target view
still exposes the original operation and operand columns, so mutable
`VALUE_GET` and `VALUE_SET` rows still reach both backend lowerings. The next
cutover must make the canonical SSA columns the sole target-independent source
of truth, remove those operations from final OptIR, and retain the compact CFG,
block-argument, incoming-value, and def-use relations for explicit effect
construction. Memory, pass-count, and warm-time gates must then be measured
again rather than inherited from the pruned-merge baseline.

The accepted demand-seed cleanup retains exactly 1,051,349,134 tracked bytes
across 227 allocations on both targets. Twenty retained-workspace samples
measure 75.11 ms median with 3.58 ms MAD on x86-64 and 38.19 ms median with
0.54 ms MAD on Wasm. The current profiler records 1,067 x86 dispatches and
1,075 Wasm dispatches, two fewer on each target than the exact-preorder slice.
Timed jobs create zero pipelines, buffers, or bind groups. The lower medians
are treated as non-regression rather than attributed to the cleanup.

The accepted exact-preorder slice also retains exactly 1,051,349,134 tracked
bytes across 227 allocations on both targets. Twenty retained-workspace
samples measure 77.67 ms median on x86-64 and 39.95 ms on Wasm, both below the
accepted Phase 1 medians. Its logarithmic Euler ranking adds 29 dispatches but
still records 81 compute passes; timed jobs create zero pipelines, buffers, or
bind groups. The exact intervals remain the independent proof surface for the
upcoming SSA dominance validator and later optimizer ancestry queries.

The memory gate required three compiler-graph corrections rather than smaller
individual arrays. Retained graph outputs now occupy exact output slots instead
of pinning an earlier oversized transient slot. Compact canonical-HIR columns
use the token-anchor capacity rather than raw grammar-amplified tree capacity.
Finally, cross-phase imports have an explicit consumer-boundary reset and a
phase-specific output policy: type-check semantic outputs stay in dedicated
allocations so they do not pin parser scratch, while terminal lowering outputs
may reuse wholly dead frontend arenas. This preserves WGPU's prohibition on
binding one physical buffer as both input and writable workspace while still
carrying phase-local storage forward.

Completed:

- `shaders/codegen/lowering_ir.slang` now contains one indexed property row for
  every semantic opcode. Each row defines flags, operand roles, result shape,
  type rule, effect class, variable-length side-table kind, and arithmetic
  behavior.
- `crates/laniusc-compiler/build.rs` generates the Rust property table and
  rejects missing, duplicate, unknown, or non-contiguous semantic opcodes and
  property rows.
- Slang and Rust query the same property rows. The x86 optimizer,
  if-conversion, x86 counting/scattering, and semantic short-circuit lowering
  no longer keep independent lists of call operations.
- Integer and strict floating-point reference evaluators cover the defined
  scalar edge cases used by later differential tests.
- Focused contract tests, shader/reflection validation, an x86 integer
  arithmetic execution test, and a Wasm floating-point execution test pass.
- A generated scalar program is evaluated by the test reference semantics,
  compiled through the physical-GPU path to both x86-64 and Wasm, executed on
  both targets, and produces the same result on all three paths.

The schema cutover introduced no newly observed target-suite failure. The x86
suite reproduces the branch's established 260/281 baseline exactly. The Wasm
suite currently passes 99/112 tests; twelve failures stop during existing
frontend name/type resolution and one large-function test emits incorrect
zero values. These failures remain real repository work, but occur outside the
new semantic-property lookup path. Phase 1 may establish the identity OptIR
boundary against this recorded baseline; it may not redefine these failures as
acceptable final compiler behavior or add new ones.

## The compiler today

The current lowering path after the Phase 1 cutover is:

```text
compact semantic HIR
    -> GpuSemanticLoweringStage
    -> GpuSemanticLirView
    -> GpuOptimizationStage (identity OptIR projection)
    -> GpuOptIrView
    -> GpuX86LirStage or GpuWasmLirStage
    -> object or executable artifact
```

This is a useful starting point:

- Semantic LIR already uses fixed-width GPU records and compact side tables.
- x86 and Wasm already have separate target LIRs.
- The compiler graph tracks logical resources, read/write behavior, lifetimes,
  repeated regions, indirect dispatch, and physical workspace reuse.
- The lowering workspace is capacity-based and can remain resident across
  daemon jobs.
- Compilation units bound peak GPU memory instead of making workspace scale
  with total project size.

The ownership boundary between semantic lowering and target lowering now
exists, but the representation behind it is deliberately still an identity
projection. Much of the current x86 analysis therefore still sees operations
such as `VALUE_GET` and `VALUE_SET` through OptIR, makes x86 ABI and register
decisions, and performs optimization inside the target stage. The new
small-function inliner is valuable, but it is also an example of work that has
not yet reached its durable owner: eligibility depends on x86 locations, the
x86 calling convention, and a bounded target-row recipe. Wasm does not receive
the same semantic optimization. Phase 2 and Phase 4 remove those remaining
representation and ownership limitations without reopening the target API.

The result is not a bad compiler. It is a compiler whose first optimization
work grew inside the only backend that needed it. The migration should retain
the working code while moving each responsibility to its durable owner.

## Definition of done

The architecture described in `PLAN.md` is materially established when all of
the following are true:

1. Both x86-64 and Wasm consume a GPU-resident `GpuOptIrView`, not mutable
   semantic-LIR declaration operations.
2. OptIR is structured SSA. Every value use has one definition, merge and loop
   values use block arguments, and effectful operations are ordered by explicit
   effect dependencies.
3. A deterministic GPU normalizer performs the ordinary optimization work
   expected of a production compiler before any search is enabled.
4. Target-independent optimization exists once and benefits both backends.
   Target-specific instruction selection, scheduling, and register allocation
   remain in target stages.
5. Every accepted transformation has an executable legality contract. Search
   cannot bypass type, control, effect, trapping, or target constraints.
6. A compile with a larger optimization budget always retains the best
   previously accepted candidate under the selected cost model.
7. Optimizer rounds require no CPU readback or CPU semantic fallback. Active
   counts and convergence state drive GPU indirect dispatch.
8. Optimizer memory is capacity-bounded per compilation unit and uses the
   compiler graph's reusable physical arenas. Total project size does not
   increase per-unit peak VRAM.
9. The old target-specific copies of migrated analyses and transforms are
   deleted. Temporary differential paths are test-only and have explicit
   removal gates.
10. The checked program suite still compiles and runs on both targets, and the
    compiler's stored performance artifacts show the cost and benefit of every
    enabled optimizer layer.

## Target ownership boundaries

The final lowering pipeline should have four owners:

```text
GpuSemanticLoweringStage
    owns source-semantic projection from checked HIR

GpuOptimizationStage
    owns OptIR, facts, normalization, alternatives, budgets, and incumbents

GpuX86LirStage / GpuWasmLirStage
    own target selection, target ABI, scheduling, register or local placement,
    and target-specific alternatives

Artifact stages
    own object/module layout, relocations, linking, and final bytes
```

The Rust-side shape becomes:

```rust
pub(crate) struct GpuLoweringPipeline {
    capacities: LoweringCapacities,
    workspace: CompilerGraphWorkspace,
    semantic: GpuSemanticLoweringStage,
    optimizer: GpuOptimizationStage,
    target: TargetStage,
    status_readback: LaniusBuffer<u8>,
}
```

Construction changes from:

```text
target <- semantic.output()
```

to:

```text
optimizer <- semantic.output()
target    <- optimizer.output()
```

The compiler graph gains an `Optimization` phase and domains for OptIR nodes,
blocks, edges, uses, facts, alternatives, candidates, patches, costs, and
proofs. These are logical resources. They should occupy a small set of aliased
physical arenas rather than one allocation per relation.

## Migration rules

The following rules apply to every phase:

- Keep production semantics on the GPU. CPU reference implementations may
  exist in tests, but never as a fallback compiler path.
- Preserve the phase order: checked HIR produces semantic LIR, semantic LIR
  produces OptIR, OptIR produces target LIR, and target LIR produces bytes.
  Later phases must not rediscover semantics from raw tokens or source shape.
- Cover all operations at a boundary before switching production consumers.
  An operation may be conservatively represented, but it may not be silently
  dropped or recognized by a program-specific special case.
- Build vertical slices. Every phase ends with working x86-64 and Wasm output,
  not a disconnected data structure.
- Keep one source of truth. A temporary old/new differential mode is allowed
  only in tests or an internal diagnostic flag and is removed at the phase's
  deletion gate.
- Reuse the compiler graph and workspace. The optimizer must not introduce a
  second allocator, pass scheduler, resource registry, scan, or radix-sort
  framework.
- Preserve the normal fast path. Search machinery may dispatch zero work, and
  a normalizer-only compile must not pay to initialize unused e-graph or
  population arenas.
- Treat capacity as part of the algorithm. When optional search storage fills,
  extract and retain the incumbent. Only failure to retain or lower the
  incumbent is a compilation error.
- Do not preserve internal compatibility layers after their callers migrate.
  This is an internal compiler refactor, so deletion is part of completion.

## Phase 0: Make semantic legality executable

This phase creates the contract used by every later phase. It is not a prose
audit.

### Deliverables

1. Extend the generated semantic-op definition so every semantic LIR operation
   has machine-readable properties:

   ```text
   result shape
   operand roles
   type rule
   control role
   effect class
   may trap
   commutative
   associative under the language's arithmetic semantics
   terminator
   variadic side-table kind
   ```

   Slang and Rust must consume generated values from one definition. Hand-made
   operation lists in target shaders should be replaced by queries to this
   table when the property is semantic rather than target-specific.

2. Define the initial effect classes:

   ```text
   pure
   readonly memory
   memory write
   call with declared effects
   host effect
   control effect
   may trap
   ```

   Calls without a proven narrower summary are conservatively effectful.

3. Define arithmetic and trapping semantics for every scalar operation. The
   table must say whether overflow wraps, division traps, shifts mask or reject
   out-of-range counts, floating-point operations are strict, and conversions
   may trap.

4. Add an exhaustive build-time check: every generated semantic opcode has one
   property row, and every property row names a real opcode.

5. Add a small test-only semantic reference evaluator for pure scalar
   operations. It is used for differential and generated tests; it is not part
   of production compilation.

### Acceptance gate

- Adding a semantic opcode without semantics metadata fails the build.
- Rust and Slang agree on opcode values and property bits.
- Generated scalar cases agree between the reference evaluator, x86-64 output,
  and Wasm output.
- No existing target behavior changes in this phase.

## Phase 1: Insert a real identity OptIR stage

Status: complete against the recorded production baseline as of August 22,
2026. Repository-wide pre-existing frontend and source-pack failures remain
tracked separately.

The first OptIR implementation should preserve behavior rather than optimize.
Its purpose is to establish the ownership boundary and exercise it end to end.

### Data model

Use fixed-width structure-of-arrays records for the common case and compact
side tables for variable arity:

```text
OptNodeCore       { type_id, type_ref_payload, flags, value_word_count }
OptNodeOperands   { result, a, b, c }
OptNodeControl    { block_id, region_id }
OptEffectLink     { node_id, effect_in, effect_out, effect_class }
OptNodeResults    { value_out, effect_out }
OptSemanticRow[]  u32
OptSourceHir[]    u32
OptBlock          { function_id, position_start, term_node, packed_edge_range }
OptEdge           { from_block, to_block, ordinal, flags }
OptBlockRegion    { block_id, region_id }
OptBlockArgument  { block_id, type_id, incoming_start, incoming_count }
OptIncomingValue  { predecessor, value_id }
OptFunction       { node_start, node_count, block_start, block_count, flags }
```

During the identity phase the opcode remains packed in `OptNodeCore.flags`,
using the generated semantic-property accessors. This preserves a coalesced
16-byte stride in the backend's hot per-function walks. Widening the record to
20 bytes merely to unpack the opcode was measured and rejected; a future phase
may split opcode into its own structure-of-arrays column if a pass benefits
from reading it independently.

Calls, aggregates, switch targets, and other variable-length inputs keep their
own compact side tables. Every reference uses a dense OptIR ID. Semantic-row
and source-HIR provenance remain separate structure-of-arrays columns: normal
target passes read source HIR, while diagnostic passes also read semantic row.
Effect links are compacted only for effectful nodes, so pure nodes do not
reserve empty effect words merely because a later Phase 2 slice needs them.

### Deliverables

1. Add `GpuOptimizationStage` and `GpuOptIrView` between semantic and target
   stages.
2. Register OptIR resources in the existing lowering compiler graph. Assign
   their storage through the existing workspace arenas.
3. Materialize every semantic LIR operation into an equivalent OptIR node.
   Control markers may initially map to explicit region and block records while
   values still preserve their pre-SSA declaration form.
4. Make both target constructors accept `GpuOptIrView`.
5. Record semantic lowering, OptIR projection, and target lowering in the same
   command stream. Add no readback between them.
6. End semantic-LIR workspace lifetimes after OptIR materialization wherever a
   later target no longer needs them. This keeps the extra IR boundary from
   becoming permanent memory amplification.

### Acceptance gate

- The complete checked example suite compiles and runs on x86-64 and Wasm.
- Every semantic operation reaches the same target behavior through OptIR.
- A diagnostic reports semantic row, OptIR row, and source HIR provenance for
  unsupported or malformed lowering.
- Warm 1 MB compilation regresses by no more than 5% on either target. A larger
  regression blocks the next phase and must be removed at this boundary.
- The current 1 MB tracked-memory gate remains at or below 1 GiB, and the
  current per-file compilation-unit limit remains at most 5 MiB.
- Timed warm jobs create no pipelines, buffers, or bind groups.

### Deletion gate

Delete the direct `semantic.output() -> TargetStage` construction path. Keep
old/new comparison only in tests until parity is established, then delete it.

## Phase 2: Convert OptIR to structured SSA with explicit effects

This is the most important correctness phase. Equality saturation and global
search must not operate on mutable declarations or infer effect order from row
position.

### GPU construction

1. Mark block boundaries from structured control, compact them with a prefix
   scan, and emit dense blocks and CFG edges.
2. Emit `(function, declaration, block, order, definition/use)` tuples for
   semantic `VALUE_GET`, `VALUE_SET`, loads, stores, parameters, and locals.
3. Sort tuples by declaration and control position. Resolve definitions inside
   each block in parallel.
4. Build the reverse CFG once, then construct immediate dominators and the
   dominator tree with CFG-sized GPU state. Seed entries, unreachable blocks,
   and single-forward-predecessor blocks directly; resolve genuine joins from
   the structured region relation and validate the result against the CFG.
5. Seed backward block-entry demand from upward-exposed reads. Use a fixed pool
   of declaration workers to propagate through predecessors without outgoing
   local definitions, canonicalize the sparse `(declaration, block)` closure,
   create one block argument at each demanded join, and compact one
   incoming-value row per actual predecessor.
6. Rename along the dominator tree and rewrite every value operand to a dense
   SSA value ID. `VALUE_GET` and
   `VALUE_SET` disappear from final OptIR.
7. Build compact def-use relations as `(value, user, operand_ordinal)` rows,
   sorted by value.
8. Construct a conservative effect chain for each function. Effectful and
   trapping nodes consume and produce effect values; merges and loops use
   effect block arguments.
9. Preserve the region tree alongside CFG arrays. Source constructs are
   structured, so region ancestry should remain the cheap source of loop and
   conditional facts. The CFG is the source of truth for dataflow.

A linear "last write wins" walk is not sufficient here. It fails at branches
and loops and would reproduce the unsound raw-token shortcuts this architecture
is meant to prevent.

### Invariants

- Each value ID has exactly one definition.
- Each ordinary value use is dominated by its definition.
- Each block argument has one incoming value per predecessor.
- Each block has one terminator.
- Region and CFG ownership stay within a function.
- Pure nodes have no effect edge.
- Effectful and trapping nodes cannot be reordered across an effect dependency.
- Every OptIR node is reachable from a function, block, or retained diagnostic
  root.

### Acceptance gate

- Runtime assertions check all invariants above immediately after SSA
  construction in validation builds.
- Generated structured programs cover nested conditionals, loops, early
  returns, calls, aggregates, mutation, loads, stores, and traps. Each seed is
  recorded on failure.
- A test-only interpreter and both emitted targets agree on observable results
  and traps for generated programs within the interpreter's supported subset.
- No `VALUE_GET` or `VALUE_SET` operation reaches target lowering.
- No CPU readback occurs between SSA construction and artifact status/length
  readback.
- Memory remains bounded by per-unit capacities; project file count does not
  change optimizer workspace size.

### Deletion gate

Delete target analyses whose only purpose was to recover mutable-declaration
def/use information. Keep ABI location assignment and target register/local
placement in the target stages.

## Phase 3: Build the deterministic normalizer

The normalizer is the production optimizer, not a prelude that exists only to
support later research. It must remain useful when all search budgets are zero.

### Relational substrate

Build optimizer operations on the GPU primitives the compiler already owns:

```text
map and filter
prefix scan and compaction
sort and unique
segmented reduction
merge join
grouped lookup
frontier/active-set iteration through indirect dispatch
```

Relations live in compiler-graph resources and use aliased workspace arenas.
Do not add bespoke allocation or bind-group systems. Add a general operation
only after at least two optimizer consumers need the same contract; otherwise
keep the specialized shader.

### First fact relations

```text
Constant(value, bits)
Copy(value, canonical_value)
Use(value, user, operand)
Reachable(block)
ExecutableEdge(edge)
KnownBits(value, zero_mask, one_mask)
Range(value, lower, upper, flags)
MemoryFact(node, region, access)
CallEffect(function, effect_mask)
```

### First normalization closure

Run the following to a bounded fixed point:

1. constant folding;
2. copy and block-argument propagation;
3. sparse conditional constant propagation;
4. unreachable block removal;
5. dead pure-node elimination;
6. dead store cleanup when provenance proves the store unobservable;
7. global value numbering and common-subexpression elimination for pure nodes;
8. known-bit and integer-range simplification;
9. algebraic identities that are valid under Phase 0 semantics;
10. branch and select simplification.

GPU-produced delta counts control subsequent rounds. A converged round records
zero-work indirect dispatches rather than forcing a host decision.

### Acceptance gate

- Normalization is deterministic for the same OptIR and compiler version.
- Normalizing an already normalized program produces the same semantic hash.
- Every rule has a focused semantic property test, not an assertion about
  incidental row order.
- Generated programs agree before and after normalization on both targets.
- Stored runtime benchmarks show no aggregate generated-code regression.
- Stored compile benchmarks report normalizer time, pass count, peak VRAM, and
  bytes or nodes processed per second.
- Normalizer-only warm compilation remains within the active performance
  budget. If a rule costs more compilation time than its measured value, it is
  removed from the default closure or made demand-driven.

## Phase 4: Move existing optimization to its proper owner

Once OptIR normalization is real, migrate the useful work currently embedded
in x86 lowering. Do this one optimization at a time: add the OptIR version,
differentially compare it, switch both targets to it, and delete the old
semantic version.

### Move to target-independent OptIR

- constant and copy propagation;
- dead value and dead declaration removal;
- single-use small-function inlining;
- control simplification;
- reusable known-bit and range facts;
- target-independent aggregate simplification;
- effect-safe common-subexpression elimination.

The current small-function inliner becomes two things:

1. a cheap deterministic rule for obvious, bounded, single-use calls; and
2. later, an optional inlining action considered by the global search.

Inlining legality must use OptIR effects, CFG and size facts, not x86 register
locations. x86 and Wasm then receive the same inlined OptIR.

### Keep in target stages

- x86 ABI classification and physical register constraints;
- Wasm parameter, local, and stack encoding;
- x86 addressing modes and instruction recipes;
- target instruction scheduling;
- x86 register allocation and spilling;
- Wasm stack/local placement;
- relocation and artifact layout.

If-conversion may be target-independent as a legal transformation, but its
profitability is target-dependent. Represent the transformed alternative in
OptIR and let the machine model choose it rather than baking x86 profitability
into semantic legality.

### Acceptance gate

- Wasm receives measurable benefit from at least constant propagation, dead
  code elimination, and small-function inlining.
- x86 generated-code performance is no worse than the pre-migration baseline
  over the stored runtime suite.
- The migrated x86 shaders and their Rust plumbing are deleted, producing a net
  reduction in duplicated code.
- Target stages consume SSA values and target facts, not source declarations.

## Phase 5: Add cost, budget, and incumbent infrastructure

This phase makes optimization an anytime process before adding large search
spaces.

### Deliverables

1. Define an `OptimizationBudget` in work units, not wall-clock milliseconds.
   Initial units include nodes visited, rule matches admitted, candidates
   evaluated, and target evaluations performed.
2. Define target cost vectors:

   ```text
   predicted latency
   code size
   spill traffic
   critical path
   peak temporary memory
   ```

3. Add versioned x86-64 and Wasm machine-model tables. Keep language legality
   separate from machine cost.
4. Make the normalized program the first incumbent. Optional mechanisms can
   propose candidates, but failure or capacity exhaustion always returns the
   best verified incumbent.
5. Store a compact append-only archive of nondominated candidates and their
   semantic hashes, costs, provenance, and proof references.
6. Record budget use and quality in performance artifacts.

### Acceptance gate

- A zero optional budget returns the deterministic normalized program.
- Repeating a compile with the same seed, model, and budget returns the same
  candidate and semantic hash.
- For nested budgets, every smaller-budget incumbent remains available to the
  larger-budget run.
- Predicted best cost cannot worsen as budget increases.
- Measured runtime may differ from the prediction, but the viewer exposes model
  error rather than hiding it.

## Phase 6: Add bounded local e-graphs

The first e-graph is deliberately narrow: pure scalar integer and boolean
regions. It is not a whole-program graph and it does not own effectful control
flow.

### Deliverables

1. Batch many small graphs by attaching `graph_id` to e-nodes, e-classes,
   matches, and union requests.
2. Implement rebuild with sort, unique, segmented reduction, and merge joins.
   Reuse the compiler's radix-sort, scan, compaction, and workspace operations.
3. Start with a small audited rewrite set whose legality follows directly from
   Phase 0 semantics.
4. Maintain e-class analyses for constants, known bits, ranges, type, effect
   class, and lower-bound cost.
5. Bound e-nodes, matches, unions, rounds, and top-K extractions per region.
6. On capacity pressure, extract the best candidates, discard dominated graph
   state, compact, and continue only if budget remains.
7. Return several local extractions to the incumbent/candidate system rather
   than committing immediately to one expression.

### Acceptance gate

- E-graph memory never exceeds its declared per-unit arena.
- Search-disabled compilation does not initialize or dispatch e-graph work.
- Every extracted expression type-checks against its region boundary and
  preserves the region's effect signature.
- Differential generated tests validate every extracted expression.
- Quality-versus-work and quality-versus-VRAM curves are stored for the
  e-graph-only and normalizer-plus-e-graph configurations.
- The default warm compiler enables this layer only where its measured runtime
  benefit justifies its compile cost.

## Phase 7: Add target alternatives

Target lowering should stop making every profitable choice in one irreversible
pass. It should expose bounded alternatives where later scheduling and
allocation materially affect the answer.

### x86-64 alternatives

- instruction recipes and immediate forms;
- addressing modes;
- compare/branch versus compare/set/select forms;
- destructive versus non-destructive placement choices;
- call and return shuffles;
- schedule choices;
- register-allocation seeds and spill choices.

### Wasm alternatives

- local reuse versus recomputation;
- stack ordering;
- block and branch encoding choices;
- call argument evaluation order where semantics permit it;
- code-size versus runtime recipes.

Target alternatives use the same budget and incumbent contract as OptIR
alternatives. They do not change language semantics and cannot remove effect or
trap dependencies.

### Acceptance gate

- Both targets can evaluate more than one target candidate without rematerializing
  semantic HIR or reading data back to the CPU.
- Target evaluation includes final scheduling and location assignment costs.
- The emitted candidate is always one that passed target validation.
- Normalizer-only target lowering remains available as the low-latency path.

## Phase 8: Add global population search

Only after legality, normalization, cost, and bounded alternatives work should
Lanius add a global search over interacting choices.

### Candidate representation

Keep one immutable normalized OptIR base and represent candidates as persistent
patch lists:

```text
replace region with extraction K
inline call site C with callee variant V
select loop action L
select target recipe R
select schedule seed S
select allocation seed A
```

Materialize a full candidate only for target evaluation or when patch depth
crosses a compaction threshold. This prevents population memory from scaling as
`candidate_count * program_size`.

### Work market

Maintain GPU queues for analysis, rewrite matching, extraction, mutation,
target evaluation, proof validation, and archive insertion. Jobs carry an
estimated cost and expected value. GPU kernels claim work from queues; active
counts drive indirect dispatch. Independent islands use distinct deterministic
random streams and periodically exchange strong candidates.

Start with these action families:

1. choose a local e-graph extraction;
2. inline or retain a call;
3. choose a target recipe;
4. perturb an instruction schedule;
5. perturb a register/local-placement seed.

Loop unrolling and more ambitious loop transforms come after this search shows
useful scaling on the first action families.

### Acceptance gate

- Candidate memory is bounded independently of source size beyond the immutable
  base and declared patch capacity.
- More work improves or preserves predicted incumbent cost over aggregate
  workloads.
- Independent restarts produce diverse candidates and reproducible results for
  a fixed seed.
- Ablation results separate the value of normalization, e-graphs, population
  search, and the hybrid.
- The compiler returns the incumbent when any optional search arena fills.

## Phase 9: Proofs, persistence, learning, and superoptimization

These features complete the research architecture, but they must build on the
same contracts rather than changing the compiler pipeline again.

### Proof production

- Each normalization rule and e-graph union records a compact rule ID,
  substitution, and source/target semantic hash.
- Structural transformations record their legality witnesses: dominance,
  effect, range, alias, or control facts.
- A GPU verifier checks certificates before archive admission.
- A small CPU checker may validate sampled certificates in testing and offline
  corpus production; production compilation does not depend on it.

### Persistent cache

Cache normalized OptIR, facts, useful local alternatives, incumbent patches,
proofs, and measured outcomes by semantic content hash, compiler version,
target model, and profile. Cache data is optional and invalidates cleanly; it
never changes correctness.

### Learned guidance

Train proposal policies and residual cost corrections from stored compiler and
runtime measurements. Learned components may rank work or refine predicted
cost, but they may not establish legality. A bad model can waste budget; it
cannot admit an invalid program.

### Superoptimization

Add solver-verified target windows only after target alternatives and proof
checking are established. Imported rules enter the same audited rewrite system
as handwritten rules.

### Acceptance gate

- Certificates replay against the exact input and output semantic hashes.
- Cache hits reproduce a result that passes the current verifier.
- Disabling cache and learned guidance preserves semantics and the deterministic
  normalizer result.
- Learned guidance beats unguided search at equal work on held-out workloads.
- Solver-generated rules cannot enter production without a retained proof or
  a separately checked general rule.

## Performance and correctness gates for every phase

Every phase records evidence in the repository's performance-result format.
The comparison corpus remains frozen unless the workload itself is intentionally
changed.

### Compiler correctness

- Run the checked x86-64 and Wasm program suites.
- Run the filesystem, stdio, environment, process, random, time, allocation,
  aggregate, control-flow, and PPM raytracer examples.
- Generate valid programs with biased distributions that cover nested control,
  mutation, calls, aggregates, large functions, and many small functions.
- Record random seeds and minimized failing sources.
- Compare observable output, exit status, traps, and artifact validation, not
  incidental internal row order.

### Generated-code quality

- Keep TCC, GCC `-O0`, GCC `-O2`/`-O3`, Rust, C++, and Zig runtime baselines in
  the stored viewer data where applicable.
- Report runtime, code size, spill traffic, and target instruction counts.
- Track each optimizer layer separately so an improvement cannot be attributed
  to the wrong mechanism.

### Compiler performance

- Report pure cold process time, daemon with cold workspace, and daemon with
  preallocated workspace.
- Use at least 20 warm samples and store median, mean, MAD, distribution,
  throughput, command, input bytes, SLOC, file count, and machine information.
- Report phase time, GPU execution time, host orchestration, queue submission,
  readback waits, recorded passes, submissions, and peak tracked VRAM.
- Run single-file workloads through the supported per-file range and typical
  projects with 1, 10, 100, 1,000, and 10,000 files.
- Compare Lanius with Pareas at comparable input sizes and separate Pareas
  process/device initialization from GPU compiler execution when the data
  permits it.

### Resource behavior

- No timed warm job creates a pipeline, bind group, or buffer within retained
  capacity.
- No semantic optimizer decision waits for CPU readback.
- The 1 MB job remains within the current 1 GiB tracked-memory gate.
- A project larger than one compilation unit processes dependency-ready units
  independently; total project bytes do not determine peak optimizer VRAM.
- Simultaneously writable graph resources cannot alias overlapping physical
  ranges.
- Optional optimizer state has a named capacity and a defined full-arena
  behavior.

## Concrete change series

Phase 1 established the optimizer boundary through these reviewable changes:

1. **Semantic properties (complete):** generate exhaustive Rust and Slang semantic-op
   property tables from the existing opcode source of truth.
2. **OptIR records (complete):** add shared Rust/Slang record definitions, layout tests,
   capacity formulas, and graph domains.
3. **OptIR projection (complete):** materialize a behavior-preserving OptIR node and side
   tables for every semantic operation.
4. **Graph integration (complete):** add the Optimization phase, logical resources,
   lifetimes, reflected bindings, and phase timing.
5. **x86 vertical slice (complete):** make x86 target lowering consume `GpuOptIrView` and
   pass the checked x86 suite.
6. **Wasm vertical slice (complete):** make Wasm target lowering consume the same view and
   pass the checked Wasm suite.
7. **Memory lifetime (complete):** isolate retained outputs, reset imported
   storage at consumer boundaries, reuse wholly dead phase arenas, and
   demonstrate the 1 GiB memory gate on both targets.
8. **Production cutover (complete):** remove direct semantic-to-target construction and
   the temporary differential route.

This series deliberately does not implement SSA, an e-graph, or stochastic
search. Its output is a working compiler with the correct new seam. Phase 2 can
then change the representation behind that seam without another target-wide
rewrite.

Phase 2 should proceed through the following vertical slices. Each slice must
leave both target pipelines runnable; a disconnected SSA implementation does
not count as progress.

1. **Control ownership (complete):** compact structured control markers into
   dense blocks, CFG edges, and function ranges; validate entry blocks,
   terminators, ownership, and range bounds on the GPU.
2. **Access relation (complete):** compact declaration reads and writes,
   projected memory accesses, parameter definitions, and local declarations
   into one phase-local relation with source node, block, and control position.
3. **Access ordering (complete):** stable-sort declaration accesses by a capacity-derived
   packed key. Group by declaration and block while retaining source order.
   The key width must follow active capacities rather than using a fixed wide
   sort for every job.
4. **Block-local definitions (complete):** use a reusable segmented last-definition scan
   to resolve reads after writes inside each block. Emit unresolved block-entry
   reads for CFG processing; do not add a serial per-function walk.
5. **Sparse block-entry state (complete):** compact the stable access order into
   one row per populated `(declaration, block)` pair. Store only the access
   range start and one incoming-definition word; derive declaration, block,
   range end, local definition, and outgoing definition from canonical rows.
   Reuse the declaration-group scan columns and reject a dense
   declaration-by-block representation.
6. **Reverse CFG and dominance seeds (complete):** compact canonical edge IDs
   by destination block. Seed one immediate-dominator word per block: entries
   dominate themselves, blocks with one forward predecessor are exact,
   unreachable blocks are explicit, and only genuine forward joins remain
   unresolved. Reuse predecessor scan storage and dead scatter scratch.
7. **Structured join dominators (complete):** match every unresolved merge
   label to its owner-local structured opener, publish the opener block as its
   immediate dominator, and reject unresolved or cross-function parents. The
   work per merge is bounded by the synthetic control recipe, not by the
   surrounding function.
8. **Dominator tree (complete):** count children by immediate dominator, prefix
   scan parent ranges, scatter one child ID per reachable non-entry block, and
   validate the compact relation without a serial child-list walk.
9. **Structured regions (complete):** compact opening/closing control markers
   into a region tree and assign node/block region ownership. Validate region
   nesting and the completed dominator tree against every CFG edge. State
   remains proportional to nodes, blocks, edges, and regions—not declarations
   multiplied by blocks.
10. **Pruned merge values (complete):**
   compact upward-exposed reads into initial block-entry demands. A fixed pool
   of persistent GPU workers builds and canonically orders the sparse
   `Demand(declaration, block)` closure through one exact global sparse set and
   a warp-batched shared queue. Predecessor propagation stops at an outgoing
   local definition. The compiler materializes a block argument and one packed
   incoming requirement per predecessor at each demanded join, resolves demand
   aliases, builds reverse block-argument users, and removes trivial merge
   values before final value IDs. The dominator depth and exact subtree
   intervals remain the independent validation index, not the placement
   algorithm. The canonical x86-64 and Wasm measurements pass the 1 GiB,
   warm-latency, semantic, scalar-fallback, and zero-resource-creation gates.
11. **SSA rewrite:** rename definitions along the dominator tree, assign dense
   value IDs, rewrite all ordinary operands, and
   validate dominance. No `VALUE_GET` or `VALUE_SET` may remain in the OptIR
   consumed by either target.
12. **Def-use relation:** compact and group `(value, user, operand)` rows for
   later dataflow, dead-node removal, and equality saturation.
13. **Explicit effects:** construct conservative effect values and effect block
   arguments for memory, calls, host effects, traps, and control. Pure nodes
   have no effect edge.
14. **Production cutover:** switch target lowering to the structured SSA and
    effect representation, run the Phase 2 acceptance corpus, then delete the
    target analyses that recover mutable declaration state.

The order matters. Access grouping and local resolution shrink the unresolved
problem before CFG work. Dominance summarizes transparent control paths once,
without copying declaration state across them. Pruned frontiers establish only
the merge points that can affect a live value; dominator-tree renaming then
establishes stable SSA identities for def-use and optimization facts. E-graphs
and search remain out of the production path until this entire representation
boundary passes its deletion gate.

## What not to build yet

The following work should wait until the earlier acceptance gates hold:

- whole-program e-graphs;
- effectful CFG equality saturation;
- a learned cost model;
- a solver in the production compile path;
- cross-unit inlining that defeats bounded compilation-unit memory;
- a second graph scheduler or GPU allocator;
- a large rule catalog without executable semantic contracts;
- optimization-level-specific pass pipelines;
- CPU fallbacks for overflow, convergence, or uncommon program shapes;
- a permanent adapter that lets one backend bypass OptIR.

These are not rejected ideas. Building them early would create search capacity
before Lanius has a sound state space, a reliable evaluator, or a stable place
to store the result.

## How we know the migration is working

The roadmap is working if the compiler becomes simpler while its optimization
ceiling rises:

- the direct semantic-to-target edge disappears;
- mutable declaration recovery disappears from target lowering;
- x86 and Wasm share semantic optimization code;
- migrated target-specific shaders and Rust plumbing are deleted;
- normalizer-only compile time remains competitive;
- generated-code performance improves before search exists;
- optional work produces a non-worsening predicted-cost frontier;
- memory remains bounded per compilation unit;
- the performance viewer can attribute time, VRAM, passes, and runtime quality
  to each optimizer layer.

The immediate goal is the remaining Phase 2 production boundary: make the
canonical dense operands, merge inputs, and compact grouped def-use relation
the final OptIR consumed by both targets; remove `VALUE_GET` and `VALUE_SET`;
construct explicit effects; and release every construction-only column before
backend lowering. That cutover must restore the 1 GiB unit-memory gate, keep
timed resource creation at zero, and remain within the defined warm-time
budget.
