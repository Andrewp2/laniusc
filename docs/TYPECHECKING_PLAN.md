The plausible answer is: do not port a normal type checker to the GPU. Redesign type checking as a bulk constraint problem.

The existing GPU compiler gets away with parallel type analysis because its type system is simple: types are inherited through one edge, reference adjustments are associative, and final checks are node-local. The thesis explicitly says it is unknown whether that technique extends to more complicated languages.  For a Rust-like system, I would not try to preserve that exact algorithm. I would keep the same GPU-friendly principle, namely array-backed representations, but replace simple type propagation with a relational constraint engine.

## Core representation

Everything should be interned into flat tables:

```text
AstNode[id]         -> kind, parent, child span, source span
Type[id]            -> kind, arg span, symbol id
TypeVar[id]         -> current representative, universe, flags
Trait[id]           -> methods, assoc types, supertraits
Impl[id]            -> trait id, self type pattern, where-clause span
Obligation[id]      -> trait goal, param env, source node
Region[id]          -> function id, universe, liveness set
Loan[id]            -> place, mutability, issuing point
Point[id]           -> MIR location, basic block, statement index
Fact[id]            -> relation tag plus packed columns
```

The current papers already point in this direction: they avoid pointer-linked trees and recursive traversals, store trees as arrays, and use parallel primitives such as map, reduction, scan, and prefix sum.  Their semantic analysis also creates arrays where each array stores one node property, such as data type, parent index, depth, and literals, so later passes can avoid tree walks. 

The design target would be:

```text
source
  -> AST/HIR arrays
  -> MIR arrays
  -> constraint/fact tables
  -> GPU bulk solving
  -> compact error table
  -> CPU or GPU diagnostic formatting
```

Diagnostics are not worth doing on the GPU. The GPU should produce precise error records. The CPU can format the error messages.

## Type inference and generics

For ordinary expression typing, use constraint generation followed by parallel unification.

Each AST or MIR node emits constraints independently:

```text
x + y           -> type(x) == type(y), type(expr) == type(x), type(x): Add
let a: T = e    -> type(e) == T
foo(a, b)       -> type(foo) == fn(type(a), type(b)) -> type(expr)
&mut p          -> type(expr) == &mut region place_type(p)
```

The emission phase is highly parallel. Each node computes how many constraints it emits, a prefix sum allocates space, then the node writes its constraints. This is very similar to how the uploaded compiler counts and emits later structures in parallel.

Then solve equality constraints with a GPU union-find or connected-components pass:

```text
TypeVar equality graph
  -> connected components
  -> canonical representative per component
  -> structural validation
```

Structural validation is iterative. If `Vec<T>` must equal `Vec<U>`, emit `T == U`. If `Vec<T>` must equal `Option<U>`, emit an error. If a type variable becomes bound to a type containing itself, report an occurs-check cycle. That last part can be done with SCC or cycle detection over the type DAG.

Generics should not be monomorphized during type checking. Type check generic functions once using symbolic type variables and their bounds. Rust similarly has to resolve concrete generic types before code can execute, and it monomorphizes generic code by stamping out concrete copies for each needed concrete type during backend/codegen; rustc’s monomorphization collection determines which concrete items need code generated. ([Rust Compiler Development Guide][1])

On the GPU, monomorphization collection is a graph reachability problem:

```text
root mono items
  -> instantiate callees
  -> sort/unique new mono items
  -> repeat until no new items
```

That is a good GPU workload because each discovered concrete function/type instantiation can be expanded independently, and each round can deduplicate with sort/unique.

## Trait solving

Rust-like traits are the hard part. A normal trait solver is a recursive search engine. That shape is bad for GPUs. The GPU version should become a batched obligation solver.

The Rust compiler development guide describes trait resolution as selection, fulfillment, and evaluation. Selection decides how an obligation is resolved, fulfillment tracks a worklist of obligations and enqueues nested obligations, and evaluation checks whether obligations hold without constraining inference variables. ([Rust Compiler Development Guide][2]) The GPU-friendly version is the same idea, but processed in bulk:

```text
Obligation table:
  Vec<T>: Clone
  T: Copy
  <I as Iterator>::Item == U
  &'a mut T: Send
```

Each round:

```text
1. Canonicalize obligations.
2. Sort and deduplicate equivalent obligations.
3. Join obligations against impl candidates.
4. Run candidate matching in parallel.
5. Classify each obligation: proven, failed, ambiguous, or deferred.
6. Emit nested obligations from selected impls.
7. Repeat until the worklist is empty or no progress is made.
```

Candidate assembly should be indexed aggressively:

```text
trait id
self type head constructor
arity
const/generic shape
crate/module visibility
```

So instead of comparing every obligation against every impl, you do segmented joins:

```text
Obligation(Trait = Clone, SelfHead = Vec)
  joins
ImplIndex(Trait = Clone, SelfHead = Vec)
```

Canonicalization is important because many goals repeat. rustc canonical queries look for an unambiguous answer and distinguish proven, ambiguous, and no-solution outcomes. ([Rust Compiler Development Guide][3]) On a GPU, this is even more valuable: solve one canonical obligation once, then scatter the answer back to all duplicate sites.

Associated types can be handled as rewrite constraints:

```text
<T as Iterator>::Item == U
```

If the solver selects a unique impl for `T: Iterator`, it emits the impl’s associated-type equation. If more than one impl candidate remains, the projection stays ambiguous unless surrounding constraints resolve it later.

I would explicitly split the trait solver into the GPU-supported subset and explicit unsupported cases:

```text
GPU path:
  first-order trait goals
  ordinary where clauses
  associated type projections
  auto traits
  simple higher-ranked bounds with canonical universes

Unsupported/error-record path until implemented on GPU:
  deeply recursive trait goals
  specialization corner cases
  complex negative reasoning
  pathological ambiguity
```

This keeps the common case wide and batched without hiding semantic work behind a CPU implementation. A case outside the GPU solver should produce a compact error record, not call a CPU solver.

## Borrow checker

The borrow checker should be compiled into a fact engine over MIR, not implemented as a recursive source-level analysis.

Rust’s MIR-based region inference collects constraints first. The rustc guide describes outlives constraints, liveness constraints, and propagation of region contents through those constraints. ([Rust Compiler Development Guide][4]) Polonius describes loan analysis as tracking loans from issue points through origins and CFG points, using relations such as loan issued, loan killed, subset relationships, origin liveness, and invalidations. It then computes illegal access errors when a live loan is invalidated. ([rust-lang.github.io][5])

That is close to a GPU-friendly relational workload.

For every function, lower to MIR-like arrays:

```text
BasicBlock[id]  -> statement span, successor span
Statement[id]   -> kind, place ids, operand ids
Place[id]       -> base local, projection span
Projection[id]  -> field, deref, index, etc.
```

Then emit facts:

```text
loan_issued_at(origin, loan, point)
loan_killed_at(loan, point)
loan_invalidated_at(loan, point)
origin_live_at(origin, point)
subset(origin1, origin2, point)
cfg_edge(point1, point2)
place_conflicts(place1, place2)
move_at(place, point)
use_at(place, point)
```

Then solve with repeated sparse joins:

```text
origin_contains_loan(origin, loan, point)
loan_live_at(loan, point)
errors(loan, point)
```

A GPU Datalog-ish engine can implement this with:

```text
sort by key
segmented join
parallel filter
parallel unique
frontier iteration
```

The important performance choice is sparse relations, not dense bitsets over every `origin × loan × point`. Dense bitsets can explode. Sparse triples stay closer to the real amount of borrowing activity in typical code.

For control flow, use per-function parallel dataflow:

```text
1. Build CFG arrays.
2. Compute liveness facts for locals and origins.
3. Propagate loans along CFG edges.
4. Apply kills and invalidations.
5. Join live loans with invalidations to produce errors.
```

Small functions can be assigned one block or warp each. Large functions need block-level parallelism:

```text
basic block summaries
  -> parallel fixpoint over CFG SCCs
  -> expand inside each block
```

The caution here is that long functions are exactly where GPU compilers can lose. The uploaded code-generation thesis found that register allocation became expensive because lifetime analysis was sequential within a function and only parallel across functions.  A borrow checker has the same danger if implemented as one thread walking one function. The solution is to parallelize inside large functions through CFG-level dataflow summaries.

## Place conflict and aliasing

Borrow checking depends on whether two places conflict:

```text
x
x.a
x.b
*x
arr[i]
```

Represent places as projection paths. For field projections, many conflicts can be computed structurally:

```text
x.a conflicts with x
x.a does not conflict with x.b
*x may conflict through the referent loan
arr[i] may conflict with arr[j] unless indices are statically disjoint
```

Build a `place_conflicts` relation with parallel comparisons grouped by base local. Avoid all-pairs across the function. Sort places by base local, then only compare places in the same segment. For structs, encode field paths as prefix intervals so prefix conflict can be checked cheaply.

This makes the borrow checker more like a sparse graph problem than an alias-analysis oracle.

## How to make it mildly performant

The performance recipe is:

```text
Batch everything.
Intern everything.
Sort and deduplicate aggressively.
Use sparse relations.
Run fixed-point algorithms in rounds.
Keep diagnostics and rare recursive cases off the GPU.
```

The GPU wins when there are thousands or millions of obligations, constraints, facts, or MIR points. It loses when each obligation launches its own recursive search. So the type checker should never say, now solve this one expression. It should say, here are 10 million facts, reduce them.

A realistic pass layout:

```text
1. Name resolution
   Parallel symbol table construction, scope intervals, declaration-use joins.

2. HIR typing constraint emission
   One node emits zero or more equality, trait, projection, and region constraints.

3. Type equality solving
   Parallel union-find, structural decomposition, occurs checks.

4. Trait obligation solving
   Batched canonical goal solving with sort/join/dedup/fixed-point rounds.

5. MIR lowering
   Produce simpler control-flow and place arrays.

6. Borrow fact emission
   Emit loan, liveness, subset, invalidation, move, and use facts.

7. Region and loan solving
   Sparse dataflow or Datalog-style fixed point.

8. Monomorphization collection
   Parallel graph expansion and dedup of concrete items.

9. Error extraction
   Compact failing constraints and borrow errors into an error table.

10. Diagnostics
   CPU formats messages using source spans and compact proof traces.
```

## The main compromise

I would not try to support full Rust semantics first. I would start with a deliberately Rust-like subset:

```text
generics
where clauses
traits
associated types
auto traits
lifetimes
moves
shared and mutable borrows
field-sensitive place conflicts
monomorphization
```

Then add the hard features later:

```text
higher-ranked trait bounds
generic associated types
specialization
negative impls
const generics
async lowering
closures with captured lifetimes
```

The architecture can accommodate them, but each one increases solver irregularity.

## The critical trick

The current paper’s type checker is parallel because it turns recursive type propagation into array-local checks and prefix sums. For a modern type system, the analogous move is:

```text
recursive type checker
  -> constraint emitter

recursive trait solver
  -> batched canonical obligation solver

borrow checker walk
  -> sparse relational dataflow engine

monomorphization recursion
  -> graph reachability plus sort/unique
```

That is the version I would expect to be at least mildly performant. Not because GPUs are naturally good at type systems, but because a modern type system can be rephrased as a lot of uniform graph, relation, and fixed-point work.

[1]: https://rustc-dev-guide.rust-lang.org/backend/monomorph.html "Monomorphization - Rust Compiler Development Guide"
[2]: https://rustc-dev-guide.rust-lang.org/traits/resolution.html "Trait solving - Rust Compiler Development Guide"
[3]: https://rustc-dev-guide.rust-lang.org/traits/canonical-queries.html "Canonical queries - Rust Compiler Development Guide"
[4]: https://rustc-dev-guide.rust-lang.org/borrow-check/region-inference.html "Region inference - Rust Compiler Development Guide"
[5]: https://rust-lang.github.io/polonius/rules/loans.html "Loan analysis - Polonius"
