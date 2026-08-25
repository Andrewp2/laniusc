# The core design

The material migration from the current compiler to this architecture is
defined in [`OPTIMIZER_MIGRATION_PLAN.md`](OPTIMIZER_MIGRATION_PLAN.md).
[`OPTIMIZER_ROADMAP.md`](OPTIMIZER_ROADMAP.md) records detailed implementation
status and measurements. `PLAN.md` describes the destination and its rationale.

I would build Lanius around one GPU-resident, anytime optimizer with three nested mechanisms:

1. A traditional optimizer computes facts and forces every candidate into a cheap canonical form.
2. Bounded local e-graphs represent dense spaces of equivalent expressions and instruction selections.
3. A massively parallel population search explores global choices such as inlining, loop transformations, scheduling, and register allocation.

The e-graph should not be the optimizer’s top-level state. It should be a local equivalence memory used by a broader search system.

That is the useful interpretation of the bitter lesson here. The optimizer should have a small set of general mechanisms whose output improves as you add search work, training data, memory, and parallel evaluation. Its optimization ceiling should not be the fixed sequence of passes that happened to be implemented by hand. Sutton’s actual lesson emphasizes general-purpose methods that continue to scale with computation, rather than elaborate domain knowledge that stops scaling. ([Incomplete Ideas][1])

Recent work directly comparing equality saturation with stochastic rewriting supports the hybrid: neither dominates across problems. E-graphs can coordinate long chains of related rewrites through compact sharing, while stochastic search is embarrassingly parallel, naturally bounded in memory, and scales well through independent restarts. The authors explicitly suggest stochastic global exploration with e-graphs for local exploration. ([arXiv][2])

The overall pipeline would be:

```text
checked HIR
    ↓
semantic LIR
    ↓
OptIR: structured SSA + explicit effects
    ↓
fact saturation + deterministic normalization
    ↓
bounded local e-graphs
    ↓
population search over global choices
    ↓
target-level alternatives
    ↓
scheduling + register-allocation search
    ↓
verified target LIR
    ↓
artifact emission
```

This remains one optimizer. Low and high optimization levels merely give it different work budgets.

# The optimization contract

The optimizer needs an explicit mathematical contract. Let:

```text
N(p)       = deterministic normalization of program p
Apply(a,p) = apply verified optimization action a to p
C_M(p)     = cost of p under machine model M
A(B)       = candidates verified and evaluated within budget B
```

Every search transition is:

```text
p' = N(Apply(a, p))
```

The returned program is:

```text
result(B) = argmin p ∈ A(B) of C_M(p)
```

The archive is append-only with respect to the selected objective. With nested budgets:

```text
B1 ≤ B2  ⇒  A(B1) ⊆ A(B2)
```

Therefore:

```text
C_M(result(B2)) ≤ C_M(result(B1))
```

So more optimizer compute cannot worsen the result under the stated model. This is a valuable property that ordinary `-O1`, `-O2`, and `-O3` pipelines do not provide.

There is one unavoidable caveat. For an exact abstract model, such as instruction count, circuit depth, or a precisely defined RAM model, this is a real guarantee. For an x86 cost model, it guarantees predicted performance, not measured performance. Actual runtime can still regress because the model is wrong, the profile is wrong, or the hardware behaves in ways the model omitted. The right response is to improve and calibrate the model, not to weaken the search architecture.

The separation should be:

```text
LanguageSemantics:
    decides equivalence and legality

MachineModel:
    maps a legal candidate to a cost vector

Objective:
    ranks or constrains cost vectors
```

The same search engine can then optimize for:

```text
abstract work
critical-path depth
x86 runtime
Wasm runtime
code size
energy
peak memory
a weighted or lexicographic combination
```

# Add an optimizer IR

Lanius’s current semantic LIR is already GPU-friendly in layout, with fixed-width core and operand records, explicit scheduling metadata, and separate target LIRs. But it still contains mutable `VALUE_GET` and `VALUE_SET` operations, structured control markers, calls, loads, and stores. That is a good lowering representation, but a poor substrate for whole-program equality saturation.

Introduce an OptIR between semantic LIR and target lowering. It should be structured SSA with explicit data, control, and effect dependencies:

```text
Function
    Region
        Block
            immutable SSA nodes
            block arguments
            terminator
```

A GPU-friendly layout could look like:

```c
struct OptNodeCore
{
    uint op;
    uint type_id;
    uint block_id;
    uint region_id;
    uint flags;
};

struct OptNodeOperands
{
    uint a;
    uint b;
    uint c;
    uint effect_in;
};

struct OptNodeResults
{
    uint value_out;
    uint effect_out;
};
```

The common case stays fixed-width. Calls, aggregates, block arguments, switch targets, and other variadic material go into side tables, matching the structure-of-arrays approach Lanius already uses.

Control flow should be represented both ways:

```text
region tree:
    loops, conditionals, nested scopes

CFG arrays:
    block successors, predecessors, dominators, loop headers
```

The region tree makes structured transformations easy. The CFG representation supports ordinary dataflow analysis and permits later support for less structured control flow.

Effects need to be explicit edges, not just flags that optimizations must rediscover. A pure node has no effect edge. A load, store, trapping operation, call, or host operation consumes and produces an effect token. The first implementation can conservatively use one memory token per function. Later, alias analysis can split this into tokens for independent memory regions, allowing unrelated operations to move independently.

This gives you three useful classes of region:

```text
pure expression region:
    unrestricted local e-graph optimization

readonly region:
    loads may participate when provenance proves immutability

effectful region:
    transformed through ordered, proof-carrying actions
```

Current research on effectful and CFG-level e-graphs is promising, but it is not yet the foundation I would bet Lanius on. Effect-safe extraction is computationally hard in general, and current CFG equality-saturation prototypes still acknowledge restrictions around reducible control flow, aliasing, memory effects, and speculation. ([SPLASH 2026][3])

Initially, convert semantic LIR to OptIR with batched SSA construction and dataflow passes. Eventually, semantic lowering should emit block arguments and SSA values directly, taking advantage of Lanius’s structured source control flow.

# Build a GPU relational optimizer substrate

The deepest architectural move would be to implement optimization as a GPU relation and fixed-point engine, rather than a collection of pointer-heavy graph algorithms.

Useful logical relations include:

```text
Node(node_id, op, type, block, flags)
Arg(node_id, slot, value_id)
Use(value_id, node_id, slot)
Edge(predecessor, successor)
Dominates(block_a, block_b)

Const(value, bits)
Range(value, low, high)
KnownBits(value, zero_mask, one_mask)
Alias(value, alias_class)
Effect(node, effect_class)
Live(value, block)

Equal(graph_id, eclass_a, eclass_b)
Candidate(candidate_id, parent_id, patch_range)
Proof(step_id, rule_id, source, result)
```

Every analysis or optimization round becomes some combination of:

```text
filter
count
prefix scan
emit
radix sort
join
segmented reduction
compaction
```

This is an excellent match for a GPU. It also unifies several otherwise separate systems:

```text
dataflow analysis
e-matching
congruence rebuilding
candidate deduplication
proof checking
cost aggregation
```

Egglog’s unification of Datalog-style reasoning with equality saturation is the conceptual precedent. Relational e-matching has also shown that matching e-graph patterns can be reduced to relational joins with optimized query plans rather than recursive top-down traversal. My proposed sort-and-scan GPU implementation is an inference from that work, rather than something those systems already provide as a drop-in GPU compiler. ([arXiv][4])

The fixed-point engine should be seminaive. Each round operates primarily on facts or e-nodes added in the previous round, instead of rescanning the entire database. That matters enormously once the optimizer begins spending large budgets.

# Traditional optimization becomes the normalization closure

Traditional optimization is still essential. It should stop being a manually ordered pass pipeline and become a canonicalization closure that runs after every meaningful search mutation.

The first normalizer should contain:

```text
constant and copy propagation
sparse conditional constant propagation
dead-code and unreachable-block elimination
branch folding
GVN and CSE
known-bits and range propagation
simple strength reduction
load forwarding
dead-store elimination
escape and scalar-replacement analysis
loop canonicalization
unambiguously profitable LICM
```

These operations are either obvious wins, critical analyses, or both. Search should never waste compute deciding whether to remove `x + 0`, propagate a known constant, or delete an unused pure instruction.

The normalizer maps many superficially different programs into the same state. In effect, global search operates over the quotient space induced by cheap traditional optimization:

```text
search state = program modulo Normalize
```

This is how traditional optimization and search reinforce one another. The traditional part collapses boring dimensions of the search space. Search spends its compute on decisions where heuristics are actually uncertain.

The normalizer’s analyses also provide legality and features for everything else:

```text
purity
may-trap
integer ranges
known bits
alignment
pointer provenance
alias classes
escape information
block frequencies
loop structure
live ranges
register-pressure estimates
```

Each fact should optionally retain compact provenance. A rewrite can then point to the exact facts justifying its side conditions.

# The local GPU e-graph

Use e-graphs on pure or tightly controlled SSA slices, not on the entire function.

A single GPU invocation should process many e-graphs together. Every record carries a `graph_id`, allowing thousands of regions from different functions and search candidates to share the same kernels:

```c
struct ENode
{
    uint graph_id;
    uint op;
    uint type_id;
    uint attribute;
    uint child_start;
    uint child_count;
    uint owner_eclass;
};

struct EClass
{
    uint graph_id;
    uint parent;
    uint analysis_id;
    uint flags;
};
```

Avoid per-eclass hash maps and linked structures. Rebuilding should be a batch operation:

```text
1. Pointer-jump all eclass IDs to canonical roots.
2. Replace every child with its canonical root.
3. Construct signatures:
       graph_id, op, type, attributes, canonical children
4. Radix-sort e-nodes by signature.
5. Adjacent equal signatures emit union requests.
6. Apply unions through parallel hooking and path compression.
7. Compact dead and duplicate rows.
8. Repeat while new unions remain.
```

This is less incremental than a CPU e-graph, but much more GPU-shaped.

Rewrite rules should be compiled into GPU matching plans. A rule compiler can turn each pattern into:

```text
root-op filter
relational join plan
side-condition queries
RHS construction recipe
proof recipe
```

Simple shallow patterns can use generated direct matchers. Larger patterns can use sorted relational joins. Rules should be grouped by root opcode and matcher shape so GPU warps do similar work.

Associativity and commutativity deserve specialized representation. Do not repeatedly fire rules like:

```text
a + b  ↔  b + a
(a + b) + c  ↔  a + (b + c)
```

That is an industrial-strength e-graph inflator. Where language semantics permit it, represent associative-commutative operations as canonical n-ary nodes with sorted children. Where overflow, trapping, floating-point behavior, or evaluation order makes reassociation illegal, keep the original ordered binary operation.

Each eclass should carry lattice analyses used by guarded rewrites:

```text
constant value
range
known zero and one bits
nonzero
alignment
finite / not-NaN
may trap
effect summary
minimum and maximum expression depth
```

The e-graph should be pulsed rather than saturated without limit:

```text
grow for R rounds or E enodes
extract K diverse Pareto candidates
send them to the outer search
discard or compact the local e-graph
optionally reseed another pulse from promising extracts
```

This converts VRAM into a hard budget rather than an eventual crash. It also lets more compute produce more pulses, larger local graphs, and more extracted alternatives. The recent stochastic-search comparison specifically identifies e-graph memory growth as a constraint and pulsing as one mitigation. ([arXiv][2])

Extraction should retain a small Pareto set per eclass instead of one cheapest expression. Useful summary dimensions are:

```text
estimated work
critical-path depth
code size
memory operations
live temporary count
target-specific lower bound
```

A single additive node cost will make the e-graph select expressions that look cheap before scheduling and spill horribly afterward. Local extraction can use iterative dynamic programming over these summaries, materialize the top variants, run global CSE, and then subject the concrete candidates to the real target evaluator.

# The global search

The outer optimizer should be a stochastic beam or island search over concrete programs represented as persistent deltas.

A candidate does not copy the whole OptIR:

```c
struct Candidate
{
    uint parent_id;
    uint patch_start;
    uint patch_count;
    uint score_id;
    uint generation;
    uint rng_counter;
};
```

A patch records choices such as:

```text
replace region with local e-graph extraction 7
inline call site 41 using callee variant 3
unroll loop 8 by 4
interchange loop pair 2
select vector width 8
choose target recipe 5
use block layout 12
use instruction schedule seed 29
use register-allocation seed 93
```

Every few generations, selected candidates are squashed into new canonical OptIR arrays so patch chains do not grow indefinitely.

A search epoch looks like:

```text
select candidate and optimization site
    ↓
propose several legal actions
    ↓
construct sparse child patches
    ↓
run deterministic normalization
    ↓
compute cheap facts and cost bounds
    ↓
discard clearly dominated candidates
    ↓
run local e-graph pulses where useful
    ↓
run higher-fidelity target evaluation
    ↓
verify finalists
    ↓
retain elites, diverse alternatives, and the incumbent
```

I would use multiple islands. Each island has its own seed, frontier, and local archive. Occasionally, good candidates migrate between islands. This gives you clean scaling from one workgroup to multiple GPUs without requiring a globally synchronized search tree.

I would not rely much on genetic crossover. Compiler decisions have strong structural dependencies, and arbitrary crossover tends to create garbage. Branching from shared parents, stochastic action selection, local e-graph search, and independent restarts are enough.

The archive always retains the best verified candidate for the active objective. The frontier may discard candidates, but the incumbent never disappears. This is what gives the optimizer its monotone best-so-far behavior.

# A GPU work market instead of hard-coded optimization levels

The cleanest bitter-lesson version uses a work queue whose entries compete for optimizer compute:

```c
struct OptimizationJob
{
    uint candidate_id;
    uint site_id;
    uint action_family;
    uint estimated_work;
    float expected_gain;
    float uncertainty;
};
```

A priority might begin as:

```text
priority =
    expected improvement
    × uncertainty or exploration bonus
    ÷ estimated GPU work
```

Jobs are then bucketed by action family so the GPU executes homogeneous batches:

```text
egraph expansion jobs
inlining jobs
loop-transform jobs
instruction-selection jobs
schedule-evaluation jobs
register-allocation jobs
proof-checking jobs
```

At a tiny budget, the queue naturally consumes high-confidence normalizations and cheap local rewrites. At a large budget, it begins exploring dubious inlining choices, alternative loop schedules, many coloring seeds, larger e-graph pulses, and superoptimization windows.

This avoids implementing optimization levels as different compilers. The canonical user knob becomes optimizer work:

```rust
struct OptimizationBudget {
    work_units: u64,
    max_vram_bytes: u64,
    max_candidates: u32,
    max_enodes: u32,
    pareto_width: u32,
    detailed_evaluations: u32,
    proof_steps: u64,
    seed: u64,
}
```

`-O1`, `-O2`, and `-O3` can remain convenient aliases, but they should only populate this structure. `-Oz` changes the objective, not the compiler architecture.

A deterministic seed and deterministic conflict resolution should make:

```text
source hash
target-model hash
optimizer version
budget
seed
```

fully determine the artifact.

# The machine model

The machine model should be data consumed by GPU evaluators, not logic baked throughout the optimizer.

For an x86 target it might contain:

```text
instruction latency and throughput
execution-resource occupancy
fusion rules
addressing-mode costs
branch penalties
load/store costs
register classes
calling convention
code-byte encodings
microarchitecture-specific constraints
```

Candidate features should include:

```text
dynamic operation count from profile weights
dependency-chain length
execution-port pressure
loads, stores, and address generations
branch probabilities
code and hot-loop size
live-value pressure
predicted spills
call overhead
```

For Wasm, the model might instead emphasize:

```text
byte size
stack height
local count
control nesting
loads and stores
engine-lowering priors
host-call boundaries
```

Use multi-fidelity evaluation.

The cheapest evaluator is compositional and runs over every candidate. It produces lower bounds and rough estimates. A learned residual model then corrects systematic errors for promising candidates. Finally, a more expensive static scheduler, register allocator, or trace-level target simulator evaluates the small surviving cohort.

Keep an uncertainty estimate. High uncertainty should sometimes cause promotion rather than rejection, giving the search a reason to investigate unfamiliar programs.

A Pareto archive is preferable internally:

```text
runtime
code size
compile work
peak memory
energy estimate
```

Only collapse it to a scalar or lexicographic objective at the API boundary. This prevents an early local decision from destroying a slightly larger candidate that becomes much faster after inlining or scheduling.

# Learning belongs in guidance and valuation

A learned system should propose where to spend compute and estimate cost. It should not decide semantic equivalence.

There are two models worth training:

```text
proposal policy:
    which action is promising at this candidate and site?

cost residual:
    how is the analytic target model systematically wrong?
```

The training loop can be self-reinforcing:

```text
generate random and real Lanius programs
    ↓
run high-budget search
    ↓
measure variants on actual target machines
    ↓
train cost and proposal models
    ↓
use the models to make subsequent search more efficient
```

The high-budget optimizer becomes the teacher for the cheap optimizer. You can distill expensive search trajectories into a small policy that runs on the GPU during ordinary compilation.

Halide’s autoscheduler demonstrated the basic pattern of a much larger schedule space, beam search, random program generation, and a learned cost model. Ansor similarly uses search and learned prediction for program schedules. Those systems operate in more constrained domains than a general-purpose systems compiler, but they are good evidence for separating search from learned valuation rather than replacing the compiler with a neural generator. ([Halide][5])

A larger learned model should be optional fidelity, not a required compiler component. The optimizer remains correct and useful with tables and analytic costs alone.

# Correctness and proof production

Every optimization action must produce a compact proof certificate. A rewrite rule should include:

```text
typed source pattern
typed result pattern
semantic mode
effect requirements
side conditions
fact dependencies
proof constructor
```

For example:

```text
rule unsigned_div_power_of_two
    udiv(x, 1 << k)  =>  lshr(x, k)

requires:
    k < bit_width(x)
    shift operation is defined
```

A proof step can be compact:

```c
struct ProofStep
{
    uint rule_id;
    uint source_node;
    uint result_node;
    uint substitution_start;
    uint substitution_count;
    uint witness_start;
    uint witness_count;
};
```

The GPU verifier checks:

```text
types match
SSA dominance holds
source pattern matches
result construction is correct
effects retain required order
side-condition facts are present
the cited facts have valid provenance
```

Each e-graph union stores its justification. Extraction reconstructs a proof from the chosen e-nodes back to the original root. Traditional transformations such as inlining, DCE, block folding, and loop transformations use their own proof schemas but feed the same checker.

Semantic modes must be explicit:

```text
wrapping integer
checked integer
strict floating point
fast floating point
may trap
cannot trap
volatile or atomic memory
ordinary memory
```

This is especially compatible with Lanius’s stated emphasis on explicit, predictable semantics. The language already aims for formal semantics in the future, which could eventually allow the rule checker and rule schemas to be generated from mechanically proved theorems.

For target superoptimization, begin with only certified machine-level rewrites. Later, add arbitrary stochastic or enumerative proposals for small straight-line windows and verify them with a GPU bit-vector SAT solver. Random testing is an excellent rejection filter but must never be the final proof.

STOKE showed that stochastic search can discover strong machine-code sequences, while Souper demonstrated solver-backed synthesis for compiler optimization. Lanius can eventually combine both ideas, with the important difference that proposal, equivalence checking, and selection can all be GPU-resident. ([arXiv][6])

# Target-level optimization

Use a second, target-level e-graph after semantic optimization.

This e-graph is ideal for:

```text
instruction selection
addressing-mode formation
constant materialization
compare and branch idioms
strength reduction
boolean and flags idioms
Wasm stack/local alternatives
```

For x86, one semantic operation can enter the graph with alternatives such as separate shifts and adds, an addressing mode, or a target pseudo-instruction. Extraction should retain several variants because the best choice can change after register allocation.

Instruction scheduling and register allocation should remain in the outer search because their cost is contextual and non-additive.

For scheduling, generate many legal list schedules with different learned or randomized priorities:

```text
critical-path priority
latency priority
register-pressure priority
load-hoisting priority
code-size priority
mixed learned priority
```

Evaluate all of them in parallel.

For register allocation, run many coloring or allocation orders from the same interference graph. Cheaply score pressure and anticipated spills for the full population, then perform exact allocation and spill insertion for the finalists. More compute directly translates into more orderings, coalescing choices, splitting choices, and spill strategies.

After allocation, a small-window superoptimizer can operate on register and flag sequences. Because windows are independent, this is another naturally massive GPU workload.

# Incremental and persistent optimization

Lanius is explicitly designed around fast, GPU-resident iteration, so high-budget optimization should be reusable rather than thrown away after each build.

Cache results by:

```text
semantic region hash
language-semantics version
rewrite-set version
target and microarchitecture
profile hash
objective
```

The cache can retain:

```text
analysis facts
normalized OptIR
top local e-graph extractions
function-level Pareto variants
best inlining contexts
target instruction variants
cost-model features
proof certificates
```

An edit to one function should invalidate that function and affected callers, not the entire optimizer state. Unchanged regions can reuse high-budget results immediately.

This produces another dimension of scaling: compute spent once continues paying off across builds. A cheap interactive compile can retrieve a candidate previously discovered by a much larger search.

# Fitting this into the current Lanius compiler

The current lowering pipeline constructs the target stage directly from `semantic.output()`, then records semantic lowering followed by target counting and emission. The compiler graph already tracks logical resources, resource lifetimes, repeated regions, paged streams, physical arena reuse, and upstream storage reuse. That is unusually good groundwork for this optimizer.

The Rust-side shape becomes:

```rust
pub(crate) struct GpuLoweringPipeline {
    capacities: LoweringCapacities,
    workspace: CompilerGraphWorkspace,
    semantic: GpuSemanticLoweringStage,
    optimizer: GpuOptimizationStage,
    target: TargetStage,
    status_readback: LaniusBuffer,
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

Recording becomes conceptually:

```rust
self.semantic.record(
    device,
    encoder,
    hir,
    semantic_inputs,
)?;

self.optimizer.record(
    encoder,
    self.semantic.output(),
    optimization_budget,
)?;

self.target.record_count_pages(
    encoder,
    self.optimizer.output(),
)?;

self.record_target_pages(
    encoder,
    false,
)?;
```

Add a compiler phase:

```rust
pub enum CompilerPhase {
    Source,
    Lex,
    Parse,
    Hir,
    TypeCheck,
    SemanticLowering,
    Optimization,
    X86Lowering,
    WasmLowering,
    Artifact,
}
```

Add logical resource domains such as:

```text
OptInstructions
OptOperands
OptBlocks
OptEdges
OptUses
AnalysisFacts
ENodes
EClasses
MatchTuples
Candidates
CandidatePatches
CostSummaries
ProofSteps
```

These should be logical arrays over a small number of physical arenas, perhaps:

```text
immutable OptIR arena
current relation/e-graph arena
next relation/e-graph arena
sort and scan scratch arena
candidate, patch, and proof arena
control and indirect-dispatch arena
```

The compiler graph can color and alias these logical resources based on lifetime, rather than exposing one physical buffer per relation.

Optimization rounds should not require CPU readback. Record a maximum repeated sequence. GPU-produced active counts feed indirect dispatches, and converged or exhausted rounds dispatch zero work. The existing repeated-region and paged-resource abstractions are already aligned with this execution model.

Capacity overflow should usually trigger a controlled optimizer action:

```text
e-graph full:
    extract, pulse, and compact

candidate arena full:
    select and compact

proof arena full:
    stop admitting unverified candidates

work budget exhausted:
    return incumbent
```

Only an inability to represent the incumbent should be a compilation failure.

# What I would implement first

## Stage 1: OptIR and deterministic GPU optimization

Create structured SSA, def-use indexing, CFG metadata, effects, and the fact engine. Implement constants, SCCP, DCE, GVN, known bits, ranges, alias facts, and basic memory cleanup.

This gives Lanius a respectable optimizer before any search machinery exists. More importantly, it establishes the legality and cost infrastructure every later mechanism needs.

## Stage 2: Pure-region e-graphs

Implement the batched sort-based e-graph, a small audited rule set, eclass analyses, pulsed growth, and top-K extraction. Start with scalar integer and boolean expressions, then add strict floating point only where identities are unquestionably valid.

Next, apply the same engine to target instruction selection.

## Stage 3: Population search

Add persistent patch candidates and search over:

```text
local e-graph extraction
inlining
unrolling
target recipe selection
instruction scheduling
register-allocation seeds
```

Avoid ambitious polyhedral transformations at first. The immediate goal is to prove that optimization quality rises smoothly with candidate count and work budget.

## Stage 4: Learned guidance and superoptimization

Collect real measurements, train the residual cost model and proposal policy, add rule discovery, and introduce solver-verified target windows.

Ruler is particularly relevant to the rule-discovery portion: it uses equality saturation to synthesize compact general rewrite sets rather than relying entirely on human-authored rules. ([Zachary Tatlock][7])

# How to judge whether the architecture works

Do not benchmark only an `-O3` endpoint. The primary artifact should be a family of scaling curves:

```text
target quality versus optimizer work units
target quality versus candidates evaluated
target quality versus VRAM
compile latency versus source size
cost prediction error versus evaluator fidelity
quality from normalizer only
quality from e-graph only
quality from stochastic search only
quality from the hybrid
```

The defining test is whether the best verified result keeps improving over multiple orders of magnitude of optimizer work. It does not need to improve smoothly on every program, but the aggregate frontier should continue moving rather than hitting an immediate pass-engineering ceiling.

The design in one sentence is: Lanius should have a GPU-resident relational optimizer whose semantic backbone is traditional dataflow, whose local alternative store is bounded e-graphs, and whose global policy is population search over proof-producing transformations, all governed by one monotonically nested compute budget.

That gives traditional optimization the role it is best at, gives e-graphs the domains where their compression is genuinely magical, and puts unbounded search and learned valuation at the top level where additional compute can keep buying better programs.

[1]: https://www.incompleteideas.net/IncIdeas/BitterLesson.html?utm_source=chatgpt.com "The Bitter Lesson"
[2]: https://arxiv.org/html/2605.19005v2 "Rewrite System Showdown: Stochastic Search vs. EqSat"
[3]: https://2026.splashcon.org/details/oopsla-2026/156/Efficient-Extraction-for-Effectful-E-Graphs "Efficient Extraction for Effectful E-Graphs (SPLASH 2026 - OOPSLA) - SPLASH 2026"
[4]: https://arxiv.org/abs/2304.04332 "[2304.04332] Better Together: Unifying Datalog and Equality Saturation"
[5]: https://halide-lang.org/papers/autoscheduler2019.html "Learning to Optimize Halide with Tree Search and Random Programs"
[6]: https://arxiv.org/abs/1211.0557 "[1211.0557] Stochastic Superoptimization"
[7]: https://ztatlock.net/pubs/2021-oopsla-ruler/ "Rewrite Rule Inference Using Equality Saturation"
