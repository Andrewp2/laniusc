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

The parser/type handoff must fail closed when a supported HIR record shape is
still bounded. For example, call arguments are currently published as flat
parser-owned rows with a packed owner/ordinal field. The readback contract
rejects argument counts that exceed the packed ordinal width or rows whose
owner/ordinal set is incomplete, so type checking never has to rediscover call
arguments from source text to compensate for a truncated parser record. Array
literals follow the same fail-closed handoff shape: readback rejects malformed
element owner/count/ordinal/next chains before type checking consumes those
parser-owned rows, including cross-file element edges that would otherwise
look in-span under source-pack-local token offsets. Struct literals do the same
for parser-owned field first/count/owner/next/value rows, so a malformed field
chain fails during readback instead of falling back to field-name or
source-shape recovery. Module
and path-import item rows also have parser-owned path-node anchors; readback
rejects path spans that are detached from those nodes, so import resolution does
not need to reconstruct module paths from source bytes. Each path-node anchor is
owned by only one module/import row, so resolver input is a flat owner-to-path
record relation rather than an inferred source-neighborhood relation. Path-type
records follow the same edge contract: their path edge must point at a
parser-owned path row, not merely at a same-span or same-spelled child, and
their leaf must match that path row's parser-owned terminal leaf. Their type
row span must also start at the parser-owned path row; generic arguments may
extend the type row, but an earlier sibling token cannot become part of the
type span. Readback rejects leaves that sit inside the path span but do not end
at the path row, so module/type resolution consumes the published terminal
segment rather than reconstructing path endings from source text or sibling
shape.
Call expression rows also keep their parser-owned callee edge as the span
anchor: readback rejects call spans that start before the callee row, so call
typing consumes the published callee/argument relation instead of compensating
with source-neighborhood recovery. Call argument rows also stay in the call
owner's source-pack file; matching token offsets from another file are rejected
at readback instead of becoming implicit argument-discovery hints. Their
published argument spans must also follow ordinal source order without overlap
inside the owning call span, so type checking can trust the flat argument rows
as the complete ordered call input.
Language declarations follow the same materialize-once rule: the language
declaration pass publishes dense name-id lookup tables for entrypoints,
intrinsics, and primitive type codes, and later call/entrypoint consumers read
those tables directly instead of looping over the declaration list at each use.
Enum variant declarations follow that same handoff: the parser publishes
`hir_variant_parent_enum` after pointer-jumping enum variant list links, and the
module declaration scatter uses that row to materialize `decl_parent_type_decl`
instead of climbing declaration ancestors in the consumer. Bounded enum payload
slots must also be complete, source-ordered, and non-overlapping before
downstream enum typing can consume them.
Match arm rows follow the same parser-owned chain contract: readback validates
the published arm rank metadata against the source-order arm chain, so
downstream match typing can consume flat match/ordinal rows without rebuilding
arm order from source adjacency.
Match payload rows are also anchored to their owning pattern span, not just the
whole arm span, so enum-payload typing cannot accidentally consume a same-arm
row that was scattered outside the pattern. Payload binder rows must also start
after the owning pattern head token, keeping the enum variant head as the
variant lookup anchor rather than a binder token. Payload rows must also share
the owner arm's source-pack file id, so matching token offsets from another
file cannot be treated as implicit binder adjacency.

## Current Implementation Alignment

The current implementation has moved some hot semantic consumers toward this
shape, but it is not there yet.

- The paper front-end sequence does not end at expression type assignment.
  GPU semantic passes now validate explicit return expression types and a
  bounded return-convergence contract for concrete non-void functions before
  backend codegen consumes the program. The current convergence rows are
  parser-owned HIR facts for direct top-level returns, direct `if`/`else` arms
  that both return, and one ordered propagation through an enclosing block for
  nested direct `if`/`else` rows. Broader nested control-flow convergence still
  needs compact control-flow rows, reductions, and stable unsupported
  diagnostics before this can be called a full production convergence model.
- Visible declaration scattering now consumes the parser-owned
  `hir_stmt_scope_end` row instead of walking parent/block syntax in
  `type_check_visible_03c_scatter_hir_decls.slang`.
- HIR visible-name resolution consumes the sorted declaration table and
  prebuilt scope-end tree. Its final lookup computes the declaration-tree leaf
  base with fixed bit expansion and rejects malformed tree shapes instead of
  carrying a runtime loop over declaration leaves.
- Predicate obligation generation now consumes parser-owned
  `hir_expr_result_root_node` records for argument result discovery instead of
  walking descendant and sibling source shape in
  `type_check_predicates_02_obligations.slang`. The root table is produced from
  parser expression-result edges by pointer-jump passes, and resident readback
  now rejects non-expression roots, cross-file roots, roots outside the owner
  expression span, and roots that are not canonical after pointer jumping. That
  keeps consumers from carrying their own bounded result-edge chase or falling
  back to source spelling when the handoff is malformed.
- Those changes are transitional records, not a full relational type checker.
  `hir_stmt_fields.slang` still derives some records from local production
  parent/child/sibling relations, and predicate obligations still have bounded
  obligation windows rather than a general bulk obligation solver.
- Struct member and struct-literal field typing now consume a GPU-produced
  sorted field-key table. The type-instance pass seeds parser-published struct
  field rows, radix-sorts them by `(struct_node, field_name_id)`, and the member
  and struct-init consumers perform range queries instead of scanning
  `hir_struct_decl_field_start` through `hir_struct_decl_field_count`. The
  aggregate-access validator also checks adjacent equal sorted field keys and
  rejects duplicate field declarations before later member or literal use can
  depend on an ambiguous first-match result. That validation is a row-local
  sorted-table check, not a declaration subtree walk. The
  final aggregate-access validator consumes `hir_expr_result_root_node` for
  field value roots and the method-call key relation (`method_call_name_id`) for
  member-call classification; it no longer imports the tree-walk helper. If a
  member call is not marked by the method-call relation, aggregate validation
  treats it as an unsupported field selection and reports the existing invalid
  member diagnostic instead of rediscovering call structure from descendants.
- Struct literal context now comes from parser-owned nearest-statement rows:
  parser semantic rows use pointer jumping to publish
  `hir_struct_lit_context_stmt_node`, then type checking maps those statement
  rows into literal-keyed contextual type rows before struct-init field typing.
  This removes the per-consumer bounded ancestor walk. It is still not full
  contextual type propagation for nested literals; that should be another
  explicit relation/constraint pass rather than a tree walk.
- The parser also publishes `hir_nearest_stmt_node` and
  `hir_nearest_fn_node` for every semantic HIR node using the same
  pointer-jump pass. These are the generic nearest-statement/function rows:
  `hir_struct_lit_context_stmt_node`, `hir_array_lit_context_stmt_node`, and
  `hir_call_context_stmt_node` remain narrower contextual-typing rows and only
  carry nearest let/return contexts. Downstream consumers that need statement
  or function membership should consume these parser-owned rows instead of
  overloading contextual-typing rows or walking parents. Parser readback now
  also validates the durable function-context boundary: function rows must
  publish themselves as their nearest function, and return-statement rows must
  carry a nearest-function relation before downstream return checking can
  consume them.
- The same context pass now publishes `hir_nearest_loop_node` separately from
  `hir_nearest_enclosing_control_node`. This matters for `break` and
  `continue` inside an `if` nested in a loop: the nearest control row remains
  the inner `if`, while the nearest-loop row points directly at the enclosing
  `while`/`for`, giving later loop-control consumers a flat parser-owned
  relation instead of a token loop-depth or ancestor-shape guess. Parser
  readback now also rejects loop rows that do not publish themselves as their
  nearest loop and rejects contradictory loop-control/context rows where the
  nearest enclosing control is a loop but the nearest-loop row points elsewhere.
- The scalar WASM HIR body emitter now follows that contract for statement
  membership, block membership, enclosing-control/loop membership, and
  expression roots. The parser publishes `hir_nearest_stmt_node`,
  `hir_nearest_block_node`, `hir_nearest_enclosing_control_node`,
  `hir_nearest_loop_node`, and `hir_nearest_fn_node` from the dense
  semantic-HIR parent relation with pointer-jump passes before consumers need
  context membership. Parser readback rejects incoherent context chains where
  function membership does not contain the published statement/block/control/loop
  relation, where nearest-block membership does not contain the nearest-statement
  relation for non-block rows, or where loop membership does not contain the
  published enclosing control relation. It also rejects specialized
  call/array/struct context rows that omit the generic nearest-statement row,
  disagree with their statement's parser-owned block/function/control/loop
  context, or publish extra peer context rows that the owning statement did not
  publish. That keeps call and literal contexts inside nested control from
  carrying stale nearest-`if` or nearest-loop membership into downstream type
  passes.
- WASM codegen now starts fail-closed and only lets parser/type-owned relation
  consumers clear the unsupported-shape status. Legacy source/token-shape WASM
  body passes remain quarantined as source-only migration scaffolding when they
  are not record-driven; the active handoff skips their dispatch until those
  helper slices are rebuilt as count/scan/scatter byte-placement relations.
- Array literal validation now consumes the same parser-published
  nearest-statement relation through `hir_array_lit_context_stmt_node`, and it
  consumes `hir_expr_result_root_node` for result-expression roots. The
  array-literal type pass no longer imports the tree-walk helper or carries its
  own bounded expression-forward chase.
- Array return projection now consumes parser-published
  `hir_expr_result_root_node`, direct HIR call-argument rows, and the
  `enclosing_fn` function-membership relation for `return values;` and
  `return copy(values);` cases. It no longer imports tree-walk helpers or
  scans expression/function subtrees to rediscover the returned declaration or
  enclosing function.
- Array index result typing also consumes `hir_expr_result_root_node` for the
  indexed base and index operand, so it no longer chases `HIR_EXPR_FORWARD`
  records inside the consumer. Parser readback also requires the index row's
  source span to start at the parser-owned base operand, keeping stale or
  over-wide index spans from becoming source-shape recovery hints for
  downstream passes.
- Generic array/slice call inference now consumes parser-published
  `hir_expr_result_root_node` plus direct HIR call-argument rows when mapping
  declaration-backed actual arguments to generic return slots. Its remaining
  four-slot parameter scans are the bounded call-record shape, not an
  expression-forward walk.
- HIR control/scalar-expression validation now consumes the same parser-owned
  `hir_expr_result_root_node` relation for binary, index, name, and diagnostic
  operand roots instead of carrying a bounded forward-edge chase in the
  consumer. Loop-control validation now consumes parser-owned
  `hir_nearest_loop_node` rows for `break` and `continue` instead of the
  token-keyed `loop_depth` bridge.
  Assignment validation no longer accepts an aggregate literal merely because
  one appears somewhere under the RHS subtree. Contextual aggregates must come
  from the parser-published literal-to-statement row. Source-pack HIR readback
  now carries and validates the same nearest-statement/block/control/loop/function
  and call/array/struct contextual-statement rows as resident debug readback,
  including direct array-literal assignment contexts, so downstream consumers
  can fail closed on those parser-owned relations instead of rediscovering the
  RHS shape from source or descendants. The readback contract now also rejects
  call/array/struct context owners that have a parser-owned nearest-statement
  row but omit their specialized contextual-statement row.
- Inherent method declaration collection now consumes parser-owned
  HIR-function-keyed `hir_method_*` rows for impl owner, method name token,
  first parameter token, receiver mode, visibility, and impl receiver type.
  The method name is copied from the parser-owned `hir_item_name_token` row,
  not inferred from token adjacency around `fn`.
  Syntax validation now also consumes the semantic `TK_PARAM_LPAREN` row from
  token classification when locating function parameter lists, instead of
  scanning forward through the source until it finds a parenthesis.
  `type_check_methods_02_collect.slang` now only projects those rows into the
  token-keyed method table; it no longer imports tree-walk helpers or derives
  method ownership from parse-tree ancestors/child lists. Method `self`
  receiver binding separately consumes parser-owned `hir_member_receiver_*`
  rows plus the token-level `enclosing_fn` relation.
- Generic enum-constructor payload validation now consumes parser-published
  call nearest-statement rows through `hir_call_context_stmt_node`, removing
  the consumer-local bounded parent climb in the module value enum-call pass.
  Constructor handling is ordered as prepare, per-payload validation, then
  finalize, so payload checks run as one thread per payload slot instead of a
  consumer-local loop. The parser record is still bounded to four payload slots;
  larger constructors fail closed until the payload rows are compacted into an
  unbounded relation.
- Ordinary resolved value-call typing now consumes parser-published
  `hir_expr_result_root_node` and `hir_call_context_stmt_node` rows instead of
  chasing expression-forward wrappers or rediscovering let/return ancestors in
  `type_check_modules_10h_consume_value_calls.slang`. Its remaining bounded
  shape is the four-slot call/type-instance argument cache; larger argument
  lists need compact argument rows plus prefix-summed validation rows rather
  than expanding an in-shader loop. Parser readback now validates the direct
  call-argument span order against the parser-owned ordinals, so consumers do
  not infer argument ordering from source adjacency.
	  Direct scalar call resolution in `type_check_calls_03_resolve.slang` now
	  consumes the same parser-owned expression-root relation while inferring
	  simple generic call returns and checking argument consistency. That evidence
	  currently covers direct argument rows, including source-pack qualified
	  helper forwarding through generic calls and direct scalar returns inferred
	  from nominal instance arguments, such as `unbox(Boxed<i32>) -> T`.
	  Nested direct calls that return generic instances still need compact
	  return-instance relation joins before their planned rows can be promoted to
	  supported semantic-contract evidence.
  The paper-aligned replacement is a multi-pass relation, not a local unroll:
  count and scan qualified value-call argument pairs, scatter
  `module_value_call_arg_rows(call_token, fn_token, ordinal, arg_node,
  param_type_code, param_ref_tag, param_ref_payload, actual_ref_tag,
  actual_ref_payload)`, flatten nested type refs into bounded-depth
  `type_ref_leaf_rows(root_ref, leaf_path, leaf_ref, generic_slot)` with
  explicit fail-closed overflow rows, sort/join argument leaves against formal
  leaves, reduce generic binding candidates by `(call_token, generic_slot)`,
  then run a final map pass that writes `call_fn_index`, `call_return_type`, and
  `module_value_path_status`.
- Method declaration collection is moving in the paper-aligned direction:
  parser/HIR passes publish method relation rows before predicate consumers run.
  Trait declarations, inherent impl methods, and trait impl methods now expose
  parser-owned `hir_method_owner_node`, name, visibility, receiver, and
  parameter rows, and predicate collection reads those rows instead of
  rediscovering owners from local source shape. Impl method rows are method-only
  declarations: they must not also publish module value item metadata, so
  downstream name lookup cannot accidentally consume a method as a free
  function item.
  Trait and inherent impl header consumers also read the parser-owned
  `hir_method_impl_receiver_type_node` relation for the impl receiver/target
  type; if that relation is absent, predicate collection fails closed with the
  unsupported target-shape status instead of falling back to a sibling walk.
- Method-signature status follows the same order. Parser/HIR now publishes
  method return-type facts through `hir_fn_return_type_node` and method-level
  generic/where flags through `hir_method_signature_flags`; predicate
  collection consumes those rows directly instead of scanning method child
  lists for unsupported signature shape detection.
- `type_check_predicates_01_collect.slang` remains a transitional collection
  pass. It emits GPU records and sorted keys for the bounded trait-contract
  slice, but it still carries several bounded parent/path walks while discovering
  trait and impl shape. That is acceptable only as fail-closed alpha scaffolding:
  the paper-aligned endpoint is parser/type-owned relation rows feeding
  count/scan/scatter collection and sorted joins, not larger local loops.
  `type_check_predicates_00c_collect_method_contracts.slang` now consumes
  parser-owned HIR method name rows, `hir_method_owner_node`,
  owner/visibility rows, `hir_method_signature_flags`,
  `hir_fn_return_type_node`, and `hir_param_record` / `hir_param_type_node` rows
  for trait and impl method metadata. Impl method ownership is accepted from the
  parser-owned method-owner relation, not rediscovered by checking parse parents.
  Parser readback now also rejects method rows that publish a first-parameter
  token without a receiver/first-parameter mode, and rejects explicit first
  parameters without a parser-owned type edge, so predicate signature comparison
  does not need to recover the parameter type from local source shape. It also
  rejects impl method rows that carry value item metadata, keeping the method
  relation separate from the module value namespace. The same
  readback boundary now requires the method row to live inside its parser-owned
  trait/impl owner span, and requires the ordinal-zero parameter row plus the
  explicit receiver type row when present to share the method source-pack file
  and live inside the method/parameter spans; same local token offsets or
  spelling cannot substitute for a stale parser-owned HIR record.
  The remaining predecessor bridge for method parameter chains now validates
  every locally linked predecessor against the parser-owned owner/ordinal row and
  fails the whole method contract if those facts disagree.
  Trait impl arguments that name the impl header's own generic parameters now
  fail closed before predicate collection resolves the same leaf spelling as a
  concrete type declaration, and the predicate status row retains the offending
  argument token for the stable diagnostic. This keeps generic impl headers out
  of the compact predicate key space until impl-argument rows can carry
  generic-parameter refs through a sorted relation rather than a leaf-token key.
  `type_check_predicates_01_collect.slang` now consumes those predicate
  method-contract rows for method name identity instead of falling back to local
  token arithmetic. Bound-argument owner/ordinal extraction remains a bounded
  bridge, but it now fails closed: if the capped parent-chain relation cannot
  prove the bound-argument owner/ordinal, if the top-level predicate-owner walk
  itself exhausts, or if a top-level bound has a direct argument list but no
  published argument fact rows, predicate collection emits
  `PREDICATE_STATUS_UNSUPPORTED_BOUND_ARG_RELATION`. The predicate obligation
  pass also surfaces that relation status directly so a capped walk cannot turn
  an unsupported predicate into an ignored row. The fix for that status is
  not increasing `MAX_PARENT_WALK`; it is replacing the bridge with
  parser-owned compact `bound_arg(method_or_predicate, ordinal, arg_node,
  status)` rows produced by count/scan/scatter. Predicate bound and impl type
  paths also fail closed when their path subtree exceeds the current 64-node GPU
  extraction window, rather than letting predicate collection perform an
  arbitrary source-shaped path walk. Invalid bound argument types now keep the
  parser-owned argument token in the predicate row, so `Rel<T, Missing>` reports
  the missing argument type instead of falling back to the outer predicate path.
  It is not fully clean yet: broader
  trait/impl header shape discovery, method-parameter predecessor links, and
  nested signature type comparison still have bounded transitional walks.
  Those should be replaced by compact count/scan/scatter records and consumed
  through sorted owner/name, bound-argument, method-parameter, and type-ref
  joins.

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

The bounded trait-method contract slice is only partway through that pass
shape. The intended order is:

```text
parser/HIR method signature rows
  -> predicate method-contract row mark
  -> prefix scan and compact scatter
  -> radix sort by (owner, method name)
  -> segmented joins/reductions for required, duplicate, extra, visibility,
     arity, parameter, and return-type checks
  -> explicit validation result rows
```

That order matters. Trait declarations, inherent impls, and trait impl method
rows should all enter predicate validation as the same kind of method-contract
relation: owner node, method name id/token, visibility, receiver mode, return
type ref, method-level generic/where status, and compact parameter rows keyed by
`(method, ordinal)`. The current implementation already validates reordered impl
methods through sorted
`(owner, name)` method-contract joins instead of source-order pairing, classifies
extra, malformed, and duplicate impl-method rows through explicit per-method
validation records, classifies the compact count case where an impl owner range
has fewer rows than the resolved trait owner range as a missing required method,
and checks malformed owner/name ranges before accepting them. Per-method
validation rows now also reflect trait-side generic/where contract statuses
through each matching impl method row, so late trait methods can produce the
specific contract diagnostic instead of only the old owner-window failure. Method
parameter publication is fail-closed for its current bounded record shape: if a
parameter is found under a method but no ordinal or next-parameter row can be
published, the collector marks the method as over the signature window so later
signature comparison rejects the whole contract instead of validating a
truncated prefix.
Impl-method parameter owner/ordinal/type publication consumes the parser-owned
`hir_param_record` / `hir_param_type_node` rows produced by pointer-jump parser
passes for trait declarations, inherent impl methods, and trait impl methods;
the local predecessor relation is accepted only when the previous parameter's
parser-owned owner/ordinal is exactly the same owner and one lower ordinal.
Parser readback also rejects parameter owner/ordinal rows whose sibling spans
overlap, so signature consumers cannot recover a malformed parameter list from
token adjacency.

The current evidence should not be overstated. Trait impl method owner rows
now come from parser-owned method rows rather than a predicate-pass fallback.
Method return types also come from parser-owned function return rows. For
item-backed functions and extern functions, readback rejects return-type edges
whose target type row does not follow the parser-owned function name token, so
parameter or body-local type rows inside the same function span cannot be
reused as stale return-signature evidence.
Method-level generic/where detection now comes from parser-owned
`hir_method_signature_flags`. The remaining method-signature loop in
`type_check_predicates_01_collect.slang` walks the predicate-linked parameter
list and nested type-ref structure. It now fails closed for nested generic
instance arguments and top-level instance signatures whose direct argument list
exceeds the bounded bridge, so the compiler does not validate a truncated
signature prefix. The production relation family should be:
compact `method_param_signature_row(method_node, ordinal, param_kind,
param_type_ref, status)` rows sorted by `(method_node, ordinal)`, plus
`type_ref_leaf_row(root_type_ref, leaf_path, leaf_type_ref, kind, generic_slot,
decl_or_language_identity, array_len_value)` rows for nested refs, arrays, and
generic arguments. Trait/impl validation can then join required trait rows
against impl rows by method name and ordinal, reduce signature mismatches by
method, and scatter explicit validation status rows without per-method local
walks. Inherent method lookup now fails closed when exact concrete and generic
receiver keys both produce visible candidates for the same receiver/name,
rather than silently choosing a specialization before there is an explicit
  specialization/ambiguity relation. Cross-module inherent method lookup now
  accepts only empty or single-candidate sorted receiver/name visibility ranges;
  multi-candidate ranges fail unresolved until public candidate rows and a
  reduction/ambiguity pass exist. Inherent impl receiver target validation now
also rejects nested generic receiver arguments before method-key publication, so
the bounded top-level receiver key cannot erase nested instance arguments.
The next GPU-style step is to emit explicit validation result rows from those
sorted joins. That remains deliberately narrower than trait-method dispatch or
backend monomorphization.

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
  nested type-instance predicate arguments without predicate-row type refs
  trait impl method-level generic or where contracts without explicit method rows
    (currently fail closed with distinct GPU status records)
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
