# GPU-Only Generics And Substitution Plan

This plan advances `stdlib/PLAN.md` by defining a GPU-resident path for
generic substitution. It assumes the normal compiler pipeline remains:

1. GPU lexer.
2. GPU syntax/HIR construction.
3. GPU type checking.
4. GPU codegen for the currently supported backend surface.

No CPU parser, CPU HIR parser, import expander, type-alias expander, semantic
precheck, generic erasure, or monomorphization fallback is allowed.

## Current Evidence

The syntax surface is ahead of semantic support:

- Generic declarations parse in `grammar/lanius.bnf` through
  `enum_type_params_opt` on functions, extern functions, type aliases, impls,
  traits, enums, and structs. Type parameters and const parameters are both
  represented by `enum_type_param`.
- Generic function declarations type-check as source shape today. The current
  focused coverage in `tests/type_checker_semantics.rs` and
  `tests/type_checker_generics.rs` covers direct generic helper calls such as
  `fn keep<T>(value: T) -> T`.
- Simple generic function calls now have GPU type-check substitution for direct
  calls inferred from value arguments. The acceptance tests cover `keep(7)`,
  `keep(true)`, generic forwarding through `return keep(value)`, and nested
  direct calls such as `keep(keep(7))` and `return keep(keep(value))`. Direct
  generic return substitution is also covered for nonzero generic slots, such
  as `second<T, U>(left: T, right: U) -> U`, and callers that expect the wrong
  concrete return type fail type checking. Generic instance arguments now also
  compare direct nominal arguments against scalar generic slots for the bounded
  scalar slice, so `score(Option<bool>, 0)` rejects when the `Option<bool>`
  argument conflicts with the fallback's `i32` slot. Scalar aliases used as
  direct call arguments normalize before bounded generic-slot consistency:
  `choose(Count, i32)` binds one `T`, while an alias to `bool` rejects against
  the same `i32` slot. Nested direct calls that return generic instances now
  contribute bounded return-instance argument refs to the outer call-site
  consistency pass: `score(wrap(1), 0)` type-checks, and `score(wrap(true), 0)`
  rejects at the conflicting fallback argument. If a
  generic instance argument participates in a call-site slot but the bounded
  records cannot recover the actual instance argument, the call fails closed
  instead of treating the unknown instance shape as a successful binding.
  Direct calls whose scalar generic return slot cannot be inferred from the
  current bounded argument records now fail closed at the call token instead of
  publishing an unresolved symbolic generic return for downstream consumers.
  Direct scalar generic returns from concrete nominal instance arguments now
  have bounded GPU semantic coverage. `unbox(Boxed<i32>) -> T` infers `T = i32`
  from the parser-owned call argument row plus the nominal instance argument
  refs, and the generic function body validates `return value.value` from
  member-result refs that publish the symbolic field type. The same focused
  contract rejects `Boxed<bool>` in an `i32` context.
  Source-pack qualified generic calls are checked per resolved declaration, not
  by leaf function name: same-named helpers in different modules can substitute
  different concrete return types in one caller, while assigning the imported
  `bool` instantiation to `i32` still fails. Qualified calls now also require
  every declared generic parameter to be inferred from the bounded call records,
  matching the direct-call fail-closed behavior for unused generic slots.
  Concrete nominal instance parameters now compare bounded scalar type-instance
  argument records for direct-name and direct-call arguments, so `Pair<bool>`
  is rejected for a `Pair<i32>` parameter instead of matching only the outer
  declaration. Repeated generic slots inside one nominal argument are checked
  against each other from the same bounded instance records, so `Pair<i32,
  bool>` is rejected for a `Pair<T, T>` parameter instead of only binding the
  first `T` slot.
  Direct-call formal instance arguments are also relation-validated before the
  outer nominal match is trusted: missing argument refs, error refs, and
  over-width arg lists fail closed with the normal type-mismatch diagnostic.
  Nested instance refs in formal parameter annotations now fail earlier with the
  GPU predicate-row diagnostic (`LNC0008`) until direct-call unification
  consumes compact nested relation records. This prevents shapes such as
  `Maybe<Boxed<i32>>` parameters from being accepted by comparing only the
  `Maybe` declaration.
  Trait-method signatures follow the same fail-closed rule while signature
  comparison remains a bounded bridge: top-level generic instance signatures
  with more than eight direct type arguments, and nested generic instance
  arguments such as `Maybe<Boxed<T>>`, are rejected with the trait-impl
  signature diagnostic until compact type-ref leaf rows carry every argument.
  That contract applies to return positions as well as parameter positions, so
  a matching-looking `fn wrap(value: T) -> Maybe<Boxed<T>>` trait method is not
  accepted by comparing only the outer `Maybe` head.
  Conflicting repeated generic arguments are rejected, including
  `choose(keep(1), keep(true))`.
  Direct generic calls wider than the current four-argument substitution window
  fail closed before any prefix slot binding can publish a partial instance:
  `choose_first(1, 2, 3, 4, true)` reports call-resolution failure instead of
  accepting the first four arguments as a concrete `T`. The same boundary is
  locked for source-pack qualified calls, so
  `core::wide::choose_first(1, 2, 3, 4, true)` also fails before resolved
  declaration lookup can publish a prefix-based monomorphization.
- Duplicate type/const generic parameter names now fail closed from compact GPU
  generic-parameter records. The pass sequence marks parameter facts, prefix
  scans them into compact rows, scatters declaration rows, sorts by
  `(owner declaration, name id)`, and validates adjacent equal keys before
  later use-slot inference consumes names. The shader filenames follow that
  dependency order: `00a` mark, `00a1` pointer-jump owner propagation, `00b`
  scatter declaration rows, `00c/00d` radix sort, `00e` validate/use slots.
  Slot publication consumes first-row facts from the compact record scatter
  instead of doing a per-use declaration walk; unsupported mixed type/const
  parameter ordering fails closed until a segmented-rank pass removes that
  limitation.
- Named type-instance argument refs now fail closed as a whole record: if the
  parser-owned HIR argument chain is over the current four-slot stride or cannot
  publish every expected top-level argument ref, the pass clears the instance
  argument slice and marks both the owner and leaf type refs as errors instead
  of leaving partial refs for later consumers.
- Generic structs and enums parse and partly type-check as declarations and
  annotations. The same acceptance test covers `struct Boxed<T>`, `enum
  Maybe<T>`, `Boxed<i32>`, and `Maybe<i32>` annotations.
- Generic struct substitution has bounded GPU semantic coverage for concrete
  `Range<i32>`-style uses. The acceptance tests cover `Range<i32>`
  construction, `Range<i32>.start` projection, concrete `Range<i32>` inherent
  method calls, method receivers that are already resolved GPU call results,
  same-name inherent methods selected by concrete receiver arguments, method
  receivers projected through concrete generic struct fields from
  `member_result_ref_*` records, generic inherent method return types
  substituted from concrete receiver type-argument refs, and the module-form
  `core::range` seed through resolver arrays. These are
  type-checker/resolver facts, not a broad executable backend guarantee.
  Nested inherent impl receiver target arguments such as
  `Holder<Boxed<i32>>` fail closed before method-key lookup because the current
  bounded receiver key records carry only top-level argument refs.
  Legacy aggregate and method Wasm gates for `core::range` helpers are not
  active execution evidence while Wasm lowering is fail-closed.
  Current x86 executable coverage is narrower than this semantic slice.
  An earlier attempt to substitute `Range<i32>.start` by walking the base
  value's annotation, struct generic parameter list, and field type compiled,
  but made the focused GPU type-check test hit both the 2s and 60s watchdogs.
  That route was backed out; generic struct projection needs precomputed GPU
  type-instance/substitution tables and bounded HIR/fact-table consumers. A
  later attempt to bridge those metadata buffers back into the retired
  source-shaped path still stalled compute-pipeline creation with both 15s and
  30s focused-test watchdogs. The working path keeps reusable type-instance
  metadata in GPU arrays and feeds bounded consumers from those arrays instead
  of expanding source-local substitution.
- Concrete enum constructors are checked on GPU today. The tests
  `type_checker_accepts_enum_constructors_with_concrete_types` and
  `type_checker_rejects_invalid_enum_constructor_payloads_on_gpu` cover payload
  arity and payload type checks for non-generic enums.
- Bounded generic enum constructor substitution now has GPU semantic coverage
  for annotated concrete local and return contexts. The module value enum-call
  passes consume resident type-instance refs, validate payload arity/type as a
  one-thread-per-payload-slot relation, and publish the constructor return type
  through `call_return_type` plus module value-path status rows for cases such
  as `Maybe<i32> = Some(1)` and `Result<i32, bool>` constructors. It also
  validates symbolic constructor returns such as
  `fn wrap<T>(value: T) -> Maybe<T> { return Some(value); }` against
  `fn_return_ref_*` and type-instance argument refs before finalization
  publishes the return row. Bounded GPU match typing now covers stdlib-shaped
  enum payload arms such as `Some(inner) -> inner` / `None -> fallback` and
  multi-slot variants such as `Left(left) -> left` through parser-owned
  match-payload rows, resolved variant declarations, and type-instance argument
  refs. Focused evidence covers both positive substitution and a mismatched
  payload arm that fails with `LNC0006` at the arm result instead of being
  accepted as an unresolved or source-local pattern. The old bounded WASM codegen slice for
  `core::ordering::compare_i32` unit enum returns plus a `match` over those unit
  variants is retired from the Rust generator: the pass is not loaded, its
  token/source bind group is not built, and it is not dispatched. It still
  contains token/HIR span walks and small input budgets in its quarantined shader
  file, so it is not active execution evidence and not production backend
  architecture evidence. Match exhaustiveness, payload enum layout,
  monomorphization, and broad backend lowering remain rejected.
- Bounded generic array and slice element declarations now have GPU semantic
  coverage through focused cases in `tests/type_checker_semantics.rs`, including
  const-generic array parameters and rejection of unbound generic array
  parameters. Direct calls with multiple declaration-backed actual arrays for
  the same `[T; N]` formal record now compare those concrete array instances,
  so equal-length calls are accepted and mismatched lengths fail closed with the
  existing type-mismatch diagnostic. The array-generic call inference pass also
  checks the raw HIR call argument count and function parameter count before
  consuming its four-slot cache; over-width calls now record a GPU call-mismatch
  status instead of letting a bounded prefix publish an inferred return type.
  The inference pass consumes parser-published expression-result roots and
  direct HIR call-argument rows for declaration-backed actual arguments, so it
  no longer carries a local expression-forward chase.
  Broader generic array calls remain rejected until their GPU consumers are
  present.
- Bounds and where predicates have bounded GPU semantic coverage. Parser
  coverage still includes type parameter bounds, multiple bounds, and where
  clauses such as `where T: core::cmp::Eq<T>`. The GPU type checker now records
  predicate rows for inline bounds, where clauses, qualified trait bounds, and
  trait impl headers, then validates simple call obligations against concrete
  impl predicate records. The acceptance and rejection tests cover multiple
  trait bounds, qualified bounds, missing bounds, subjects outside generic
  parameters, mixed concrete/generic bound arguments, and one/two-argument
  called trait predicates. The bounded inline `+` chain is checked independently
  for the currently published top-level predicate rows:
  `T: Bound<T> + Other<T>` accepts only when every required impl is present, and
  a missing later bound fails with the same stable obligation diagnostic as a
  missing first bound. Inline bound chains deeper than that parser-owned
  relation, such as `T: First<T> + Second<T> + Third<T>`, now fail closed with
  `LNC0008` instead of letting an unsupported later predicate disappear. Trait
  call-site substitutions normalize accepted type aliases before checking
  obligations, so a value annotated through `type Count = i32` satisfies
  `T: Eq<T>` through an `Eq<i32> for i32` impl, while an alias to `bool` still
  fails if no visible `Eq<bool>` impl exists. The same normalization applies
  when an alias-typed value fills a nonzero generic slot that appears as another
  slot's trait-bound argument, such as `U: Rel<T>`. Predicate type-argument
  aliases inside the bound or impl argument list now normalize through the same
  GPU alias-projected type refs when the alias resolves to an existing
  scalar/nominal type code, so `T: Rel<Count>`,
  `T: core::types::Rel<core::types::Count>`, and
  `impl Rel<Count> for i32` match `Rel<i32>` obligations. Nominal alias leaves
  are covered by the same contract: `type KeyAlias = Key` in `T: Rel<KeyAlias>`
  matches an `impl Rel<Key> for i32`, while an alias to a different nominal type
  still fails the call obligation. Alias leaves that cannot publish such a ref
  remain fail-closed.
  Trait bounds and trait impl headers wider than the
  current two-argument GPU predicate records now fail closed with a stable GPU
  predicate diagnostic instead of publishing partial predicate rows. Nested
  type-instance predicate arguments in both bounds and impl headers, such as
  `Rel<Boxed<i32>>`, now also fail closed until predicate rows carry argument
  type-instance refs. Unapplied generic type heads in predicate arguments, such
  as `Rel<Boxed>` where `Boxed<T>` is generic, fail closed for the same reason.
  Predicate type-argument leaves that resolve to traits still fail closed until
  compact predicate rows carry resolved argument refs instead of making
  obligation consumers rediscover declaration meaning from leaf tokens.
  Predicate type-argument leaves that resolve only across a private module
  boundary also fail closed from the predicate row's invalid-argument status,
  so visibility cannot be recovered later by obligation matching.
  Reference-shaped bound heads, such as `T: &Marker`, also fail closed with the
  GPU predicate-shape diagnostic instead of falling through as unknown types.
  Bounds that resolve to non-trait type declarations, such as
  `T: Bound<T>` where `Bound` is a struct, now report a stable GPU
  predicate diagnostic that identifies the bound target as non-trait instead of
  relying on raw rejection or later call use.
  Predicate and trait-impl headers now compare their
  recorded argument count against the resolved trait declaration's generic
  parameter count, so under-applied and over-applied trait names fail from GPU
  predicate status rows instead of becoming partial bounds. Trait impl
  validation also rejects method-level generic parameters and method-level
  where clauses until trait method contracts are
  represented as explicit GPU rows rather than partially compared signatures;
  these two unsupported method contract shapes now produce distinct
  source-spanned diagnostics instead of collapsing into generic signature
  mismatch.
  Trait impl targets with generic arguments, such as `impl Marker for Boxed<i32>`,
  and targets that name type aliases, such as `impl Marker for Count`, also fail
  closed because the current predicate row carries only the target leaf token;
  accepting them before target reference rows exist would erase or misrepresent
  the impl subject during obligation matching. Unresolved trait impl target
  names also fail closed through the same stable target-shape diagnostic instead
  of relying on downstream type-path validation to catch the missing subject.
  Generic type parameters in trait impl arguments, such as
  `impl<T> Rel<T> for i32`, now fail closed before concrete declaration lookup
  can reinterpret the generic leaf token. The predicate row preserves the
  offending trait-argument token for the stable `LNC0021` diagnostic; accepting
  that shape requires compact impl-argument rows that carry generic-parameter
  references, not just leaf tokens.
  Call-site obligation matching also treats symbolic generic type codes as
  unsupported exact impl keys, so forwarding a generic value into a bounded
  helper fails closed until recursive obligation/dictionary rows exist.
  Trait and inherent impl target discovery now consumes the parser-owned
  `hir_method_impl_receiver_type_node` row; if the parser cannot publish that
  owner-to-type relation, predicate collection reports the existing unsupported
  target-shape status rather than rediscovering the receiver from header
  siblings.
  Unqualified trait names in impl headers now resolve through the impl type
  path's GPU path-owner module, checking local declarations and import-visible
  type keys before falling back to unique leaf-name resolution. This keeps
  `impl Marker<i32> for i32` in a module that imports `core::marker` tied to the
  imported trait declaration instead of treating same-leaf traits elsewhere as
  ambiguous global names.
  Qualified predicate and trait-impl type paths now also use the declaration
  visibility records, so `core::secret::Hidden<T>` cannot be named from another
  module unless `Hidden` is public. Same-module private trait bounds remain
  valid because the GPU predicate pass compares the path-owner module with the
  declaration module before allowing private declarations.
  Trait impl methods are validated against their trait declarations but are not
  published into the inherent method lookup table. The predicate collection pass
  now also rejects extra or duplicate methods inside a trait impl instead of
  accepting an impl that merely contains every required method; extra impl
  methods publish a distinct GPU status keyed to the extra method name rather
  than collapsing into a generic signature mismatch. Reordered trait
  impl methods validate through sorted `(owner, method name)` contract ranges
  rather than declaration-order pairing. Method return-type facts now come from
  parser-owned `hir_fn_return_type_node` rows, and method-level generic/where
  rejection comes from parser-owned `hir_method_signature_flags` rows instead
  of bounded child-list scans in predicate consumers. A required impl method
  that adds method-level generics still fails from its own compact method-status
  row instead of satisfying the trait by owner/name and concrete signature
  shape, so unsupported generic method monomorphization cannot be hidden behind
  trait contract joining. A public
  trait method must also be implemented by a public impl method, so exported
  trait contracts cannot be satisfied by private method rows. Implementations of
  public traits must currently use a public impl header, because obligation
  matching does not yet carry module-scoped impl visibility rows. Public-trait
  contracts implemented by non-public impl headers now publish a distinct GPU
  predicate status and stable trait-implementation diagnostic instead of reusing
  the invalid-argument status. Focused coverage also locks the opposite header
  mismatch, so public impl headers for private trait contracts report the same
  stable trait-implementation diagnostic. The corresponding impl-method
  visibility mismatch diagnostic is also locked, so a private method row cannot
  satisfy a public trait contract by falling back to a raw rejection. Dot-call
  dispatch through a trait impl still fails closed with a stable call diagnostic
  until trait-method lookup has explicit predicate/selection rows. The method-contract pass
  now consumes parser-owned method name, owner, visibility, and parameter rows
  for trait declarations plus inherent and trait impl methods before building
  predicate records. Trait method contracts wider than the current 32-parameter GPU
  comparison window fail closed instead of validating only a prefix.
  Impl-method parameters consume parser-owned `hir_param_record` owner/ordinal
  rows and `hir_param_type_node` type rows from the pointer-jumped parser pass;
  if the method-parameter collector still cannot publish an ordinal or
  next-parameter relation, or if the local predecessor bridge disagrees with the
  parser-owned previous parameter owner/ordinal, it marks the method's parameter
  count beyond that window so signature validation rejects the whole method
  contract instead of silently dropping the parameter.
  Trait impl method owner rows now come from parser-owned method records instead
  of a predicate-pass fallback. This is still validation scaffolding rather than
  trait dispatch readiness because dispatch selection/dictionary rows are not
  implemented.
  Trait/impl method owner ranges wider than 32 rows still fail closed for full
  signature comparison, but method-contract validation now emits explicit
  per-method result rows for extra methods, duplicate impl methods,
  visibility/arity mismatches, and trait-side generic/where contract statuses.
  It also emits an impl-owner validation row when compact sorted owner-range
  counts prove that required trait methods are missing. Those row/reduce/apply
  passes let late methods report the specific contract failure instead of being
  hidden behind the legacy owner-window diagnostic while compact
  `(impl, trait_method)` and `(method, ordinal)` signature rows are built.
  Broader trait solving, associated types, recursive obligations,
  dictionaries/static dispatch, and trait-method lookup remain future work.
  Top-level predicate-owner discovery is still a capped transitional walk, but
  exhausting that cap now publishes `PREDICATE_STATUS_UNSUPPORTED_BOUND_ARG_RELATION`
  and the predicate obligation pass records the corresponding `LNC0008`
  diagnostic directly, so unsupported predicate shapes cannot disappear before
  the later condition validator sees them. The paper-aligned replacement is a
  parser-owned compact predicate/bound-argument relation, not a wider owner
  walk. Over-deep inline `+` bound chains also publish that status until
  parser-owned predicate-list rows can represent every bound as a compact record.
  The obligation pass also records fail-closed diagnostics for existing
  unsupported predicate-row statuses such as declaration-level bounds on
  non-callable generic items, unsupported bound argument shapes, and bound arity
  mismatches, so unsupported bounds are not accepted as comments while the full
  predicate-row relation is still incomplete.
  Predicate path extraction is likewise explicitly bounded. Bound and impl type
  paths currently scan at most 64 parser nodes inside the path subtree; wider
  predicate paths fail closed through existing predicate diagnostics instead of
  letting a shader invocation walk an arbitrary source-shaped subtree. This is a
  temporary guardrail until bound paths are materialized as parser-owned segment
  records and joined through sorted lookup tables.
  Bounded trait impl type-shape scans also fail closed when the impl header's
  trait/target type region exceeds the current GPU scan window, rather than
  treating an overwide region as if it had no nested unsupported type arguments.
- The LL(1) parser/HIR path in `shaders/parser/hir_nodes.slang` classifies
  coarse HIR nodes and now exposes parser-owned expression operator/operand
  records through the HIR readback contract, but most type-checking still relies
  on resident token buffers plus HIR spans rather than a fully lowered semantic
  AST.
- The resident call passes build GPU call metadata:
  `call_fn_index`, `call_return_type`, `call_return_type_token`,
  `call_param_count`, `call_param_type`, bounded `call_arg_node` rows, and
  function lookup hash tables. Direct scalar generic calls are accepted through
  `type_check_calls_03_resolve.slang` and
  `type_check_calls_04_erase_generic_params.slang`, while array/slice generic
  calls use the later `03b/03c` record consumers. `03_resolve` now consumes
  parser-owned expression-root rows for direct scalar call argument/return
  typing; the remaining direct-call gap is the bounded four-slot argument
  cache, not expression-forward chasing.
- The remaining scope and call passes can still represent generic parameter
  names as `TY_GENERIC_BASE + token_index`, but the active resident path should
  keep moving acceptance evidence to HIR/fact-table consumers instead of
  treating token-local equality checks as the generic-call architecture.

## Data Model Direction

The implementation should move from token-local generic recognition to explicit
GPU arrays. The arrays can initially be token-indexed to fit the current
resident compiler path, but they must represent semantic facts instead of CPU
rewritten source.

Required resident buffers:

- `generic_item_id[token]`: owning generic declaration for each type parameter,
  function, struct, enum, impl, trait, or predicate token; `INVALID` otherwise.
- `generic_param_count[item_token]`: number of type parameters on the item,
  excluding const parameters until const substitution is implemented.
- `generic_param_token[item_token, slot]`: token index of the parameter
  declaration at each slot.
- `generic_param_kind[item_token, slot]`: type parameter or const parameter.
- `generic_param_key_order[row]`: sorted generic-parameter rows keyed by
  `(owner declaration, name id)` for both type and const generic parameters.
  The validation pass should mark adjacent equal keys as duplicate-name errors
  before any use-slot inference consumes parameter names.
- `generic_arg_count[type_or_call_token]`: number of actual type substitutions
  known for this use site.
- `generic_arg_type[type_or_call_token, slot]`: concrete or generic type code
  bound to each slot.
- `generic_arg_const[type_or_call_token, slot]`: const generic value slot, used
  after the first function-call slice.
- `type_expr_ref_tag[token]` and `type_expr_ref_payload[token]`: a type
  expression head mapped to an existing scalar type code, a generic parameter
  token, or a type-instance id.
- `type_instance_*`: compact records for parameterized structs/enums, arrays,
  and slices. These are the next slice after simple generic function calls.
- `call_subst_type[call_token, slot]`: inferred type argument for each generic
  function call.
- `call_subst_state[call_token]`: unresolved, resolved, mismatch, unsupported.
- `subst_type_out[token]`: substituted type for a type-expression head,
  parameter, field, payload, return type, or expression head where a generic
  parameter appears.
- `predicate_owner[predicate_token]`, `predicate_subject[predicate_token]`, and
  `predicate_bound_type[predicate_token]`: compact where/bound records for the
  later trait stage.

All arrays are built and consumed by Slang compute passes. CPU orchestration may
allocate buffers, dispatch passes, and read final status words, but may not
interpret source, instantiate generics, rewrite HIR, or patch types.

## Stage 1: Simple Generic Function-Call Substitution

Goal: make direct calls to simple generic functions type-check when every type
parameter can be inferred from value arguments and the substituted return type is
needed by assignment or return checking.

Scope:

- Type parameters only.
- No explicit call syntax for type arguments.
- No generic structs/enums as substituted argument or return types.
- No generic array/slice elements.
- No bounds, where predicates, traits, methods, references, or backend
  specialization.
- A generic function body still type-checks once against symbolic generic type
  codes. Calls instantiate only call-site parameter and return types.

Active resident pass order for this slice:

1. `type_check_type_instances_00_clear`, `00a`, `00a1`, `00b`, `00c/00d`,
   and `00e` clear generic/type-instance state, publish generic declaration
   owners, scatter compact generic-parameter rows, sort them by owner/name, and
   publish parameter use slots.
2. The resident call metadata block runs `type_check_calls_01_resolve` as the
   current clear/init pass, then `02a_return_refs_from_hir`, `02b_entrypoints`,
   `02_functions`, `02f_params_from_hir`, `02c_intrinsics`,
   `02d_clear_hir_call_args`, and `02e_pack_hir_call_args` to prepare direct
   HIR call, parameter, return, and bounded argument-cache records. It stops
   before scalar call resolution until visibility/scope facts exist.
3. After scope/visible declaration facts exist, `type_check_calls_03_resolve`
   infers simple scalar generic call returns into `call_return_type` and checks
   repeated generic arguments for consistency. This pass consumes
   parser-owned expression-root rows like the newer module value-call and
   array-generic consumers, but still uses the bounded direct-call argument
   cache.
4. `type_check_calls_03b_infer_array_generics` and
   `type_check_calls_03c_validate_array_results` consume parser-published
   expression-root and direct call-argument rows for the bounded generic
   array/slice slice.
5. `type_check_calls_04_erase_generic_params.slang` clears unresolved generic
   parameter cache entries after the supported call substitutions have had a
   chance to publish concrete results. Later condition, control, backend, and
   later module consumers read the published `call_return_type` rows; earlier
   module value-call consumers run before this scalar direct-call slice and
   cannot be used as evidence for post-erasure call metadata.

Validation note: adding substitution directly inside `simple_expr_type` created
a recursive shader call shape and `slangc` rejected it. The working path keeps
inference bounded inside GPU call-resolution passes and the small
`type_check_calls_04_erase_generic_params.slang` pass, instead of letting later
token checks treat callee-local generic parameter ids as concrete types.

Failure behavior:

- If any formal generic parameter is not inferred from value arguments, record a
  GPU type-check error.
- If repeated inference for the same type parameter disagrees, record
  `AssignMismatch` or a new GPU error code such as `GenericSubstitutionMismatch`.
- If the substituted call type contains unsupported shapes such as symbolic
  `Range<T>`, `[T; N]`, or `[T]`, reject on GPU.
- Module-qualified generic aggregate returns must fail closed until the call
  site has a substituted type-ref result. Comparing only the outer struct/enum
  declaration code is not enough because `Wrapper<i32>` and `Wrapper<bool>`
  would otherwise look identical to scalar assignment checks.

## Next Slice: GPU Type-Instance Metadata

Objective: add the minimal resident metadata needed before generic
struct/enum/array semantics can be enabled. This slice builds reusable
type-instance records first, then enables narrow consumers only when they read
those records instead of reparsing declarations inside individual semantic
passes.

The key rule is that semantic passes must not rediscover generic arguments by
walking item headers, field declarations, or return type spans. They should read
precomputed type refs and emit errors. The earlier failed `Range<i32>.start` and
enum-constructor attempts both timed out because they put substitution work in
source-shaped consumers.

The first committed implementation slice starts with
`type_check_type_instances_01_collect.slang`, wired through the resident GPU
type-check path under `src/type_checker/`. It is intentionally metadata-only:
it creates token-indexed
`type_expr_ref_*`, `type_instance_*`, and `fn_return_ref_*` buffers for scalar
type heads, named generic candidates, arrays, slices, and function return type
heads, including named generic argument start/count records. The follow-up
metadata passes bind named generic instances to struct/enum declarations,
publish argument refs, publish `member_result_ref_*` plus
`struct_init_field_expected_ref_*` for generic struct fields, and publish a
bounded concrete array-return sentinel for matching `[i32; literal]` identifier
returns and HIR-backed i32 value array returns. A later bounded consumer now
validates concrete contextual generic enum constructors through module
value-call rows and publishes the constructor result into `call_return_type`.
A bounded array-index consumer now accepts generic array/slice declaration
shapes and precomputes `values[0]` element result types. The module resolver
also carries a parser-derived `decl_name_token` so type and enum projections use
declaration names instead of declaration span starts. Symbolic generic enum
constructor returns now compare precomputed return refs and expression refs in
the HIR/module consumers. Array literal returns are limited to concrete i32
value arrays with matching concrete lengths, including bounded `values[index]`
elements when the base has a concrete `[i32; literal]` type and the HIR index
expression has an i32 scalar index. Mismatched concrete lengths,
non-constructor symbolic generic enum returns, and broader match forms remain
rejected until HIR/module consumers compare the relevant records directly. The
current match slice is limited to HIR-spanned arms
  whose result expressions can be typed from visible declarations, literals, or
  tuple enum payload bindings.

Type refs are stored as two `u32` values at each use site:

- `TYPE_REF_INVALID`: no resolved type.
- `TYPE_REF_SCALAR`: payload is the existing scalar `TY_*` code.
- `TYPE_REF_GENERIC_PARAM`: payload is the generic parameter token.
- `TYPE_REF_INSTANCE`: payload is a `type_instance_id`.
- `TYPE_REF_ERROR`: payload is the GPU error code or source token that caused
  the unsupported type.

Core buffers:

- `type_instance_count[0]`: atomic instance count.
- `type_instance_kind[id]`: `struct`, `enum`, `array`, or `slice`.
- `type_instance_head_token[id]`: source type-expression head, such as `Range`,
  `Maybe`, `[` for arrays, or `[` for slices.
- `type_instance_decl_token[id]`: resolved struct/enum declaration token, or
  `INVALID` for arrays and slices.
- `type_instance_arg_start[id]` and `type_instance_arg_count[id]`: slice into
  the argument pool for generic struct/enum arguments.
- `type_instance_arg_ref_tag[arg]` and `type_instance_arg_ref_payload[arg]`:
  type refs for each actual type argument.
- `type_instance_elem_ref_tag[id]` and `type_instance_elem_ref_payload[id]`:
  array/slice element type ref, used only for array and slice records.
- `type_instance_len_kind[id]` and `type_instance_len_payload[id]`: array length
  as literal value, const generic parameter token, or unsupported.
- `type_instance_state[id]`: resolved, duplicate-but-equivalent, unresolved,
  mismatch, or unsupported.

Consumer-facing buffers:

- `member_result_ref_tag[member_token]` and
  `member_result_ref_payload[member_token]`: substituted result type for
  `base.field`.
- `struct_init_field_expected_ref_tag[field_name_token]` and
  `struct_init_field_expected_ref_payload[field_name_token]`: expected field
  value type in a struct literal.
- `fn_return_ref_tag[fn_token]` and `fn_return_ref_payload[fn_token]`: declared
  return type ref, including arrays, so return checking can compare precomputed
  element and length records instead of reparsing return type spans.

Minimal passes:

1. `type_instances_01_clear`
   clears instance, argument, and consumer-facing buffers.
2. `type_instances_02_collect_type_expr_refs`
   visits type-expression heads already surfaced by HIR spans and visible type
   metadata. It writes scalar refs for primitive types, generic-param refs for
   in-scope type parameters, and candidate instance refs for `Name<...>`,
   `[Elem; Len]`, and `[Elem]`. Nested type arguments that are not yet resolved
   mark the instance unsupported instead of forcing a token-local scan.
3. `type_instances_03_bind_generic_instance_args`
   resolves each `struct`/`enum` instance declaration, verifies that argument
   count matches `generic_param_count[decl_token]`, and binds slot `i` to
   `generic_param_token[decl_token, i]` by pointing at the instance argument
   pool. Argument publication is all-or-error for the current bounded stride,
   so later consumers never see a prefix of an unsupported generic argument
   list as if it were a complete instance. Const arguments may be recorded but
   remain unsupported for semantic acceptance until const substitution is
   implemented.
4. `type_instances_04_publish_struct_enum_uses`
   publishes substituted expected refs for struct literals and member
   projections. This pass walks declaration fields once, applies the instance
   slot map, and writes consumer-facing buffers. Downstream semantic consumers
   read those buffers directly.
5. `type_instances_05_publish_array_uses`
   publishes array/slice element and length refs for parameters, locals, fields,
   and returns. The current consumers accept matching concrete `[i32; literal]`
   identifier returns, HIR-backed i32 value array returns, and bounded generic
   identifier returns such as `[T; N]` by comparing generic element and const
   length slots from type-instance records. The call consumers also accept
   concrete declared array-return calls such as
   `let pair: [i32; 2] = make_pair(1, 2);` when the destination matches the
   callee's `fn_return_ref_*` instance, and concrete bounded return-calls such
   as `return copy(values);` when the enclosing function return has the same
   array instance. They reject mismatched concrete/generic lengths through the
   same records. Annotated-local array-valued call validation consumes the
   direct HIR initializer call record, and array-valued return-call validation
   consumes parser-produced expression-result roots, direct HIR call-argument
   rows, and `enclosing_fn`, instead of searching expression/function subtrees.
   Unsupported symbolic generic array-valued calls are likewise rejected from
   the direct HIR call record for this bounded slice.
   Broader generic array-valued calls stay rejected until the existing checks
   compare broader records directly.
   Indexed array literal elements are bounded to HIR index
   expressions whose base is a concrete i32 array and whose index is an i32
   scalar atom.
6. `modules_10l*_value_enum_calls`
   consume contextual concrete generic enum instances from annotated locals and
   returns, substitute payload generic refs through the instance argument pool,
   validate constructor arity/type in a separate one-thread-per-payload-slot
   pass, and publish the constructor return type only after finalization. The
   current call and variant payload records are still four-slot records and fail
   closed beyond that until compact payload rows replace the slot arrays.

The first implementation may allocate one instance record per type-expression
use. Canonical deduplication is not required for the initial metadata slice
because the first consumers derive expectations from a contextual instance
record. Cross-use equality can be added later with a GPU hash table keyed by
`kind`, `decl_token`, argument refs, element ref, and length ref.

## Stage 2: Generic Struct And Enum Type Substitution

Goal: support `Range<i32>` field and constructor semantics and generic enum
constructor payload checks for stdlib-shaped `Option<T>` and `Result<T, E>`.

Data structures:

- Consume the `type_expr_ref_*`, `type_instance_*`,
  `struct_init_field_expected_ref_*`, `member_result_ref_*`, and constructor
  sentinels from the metadata slice.
- Keep existing scalar `TY_*` codes for non-parameterized types. Do not pack
  generic struct/enum instances into scalar type-code ranges.
- Represent substituted structural types as `TYPE_REF_INSTANCE` plus instance
  id until a later canonical intern table exists.

Passes:

1. Dispatch the type-instance metadata passes before scope and semantic checks.
2. Keep struct literal checking in bounded HIR/fact-table consumers that read
   `struct_init_field_expected_ref_*`.
3. Keep member projection checking in bounded HIR/fact-table consumers that read
   `member_result_ref_*`.
4. Update enum constructor checking to consume the ordered module enum-call
   prepare, per-payload validation, and finalize passes after contextual
   concrete payload refs or symbolic constructor-return refs exist.
5. Update annotated let and constructor-return checks from contextual
   `TYPE_REF_INSTANCE` records. Concrete contextual instances validate scalar
   payloads, and symbolic generic enum constructor returns compare
   `fn_return_ref_*` against expression refs before publishing a return-token
   sentinel. Non-constructor symbolic generic returns and backend layout remain
   separate work.

Acceptance targets:

- Keep concrete `Range<i32>` construction, `range.start` projection, and the
  `core::range` source-pack seed accepting through GPU type-instance and module
  resolver arrays, including concrete call-result receivers such as
  `core::range::range_i32(1, 4).start()`.
- Keep `type_checker_accepts_contextual_generic_enum_constructors_on_gpu`
  accepting `let value: Maybe<i32> = Some(1)` and `Result<i32, bool>`
  constructors, and keep invalid payload tests rejecting.

Keep `fn wrap<T>(value: T) -> Maybe<T> { return Some(value); }` accepting at GPU
type-check time through the return-ref sentinel, and keep bounded
`Option<T>`-style matches accepting through HIR match spans and resolver arrays,
while keeping match exhaustiveness, payload enum layout, monomorphization, and
broad backend execution blocked. The separate codegen proof is limited to unit
enum tags and `Ordering`-style match dispatch.

## Stage 3: Generic Array And Slice Elements

Goal: support generic element types in `[T; N]` and `[T]` once substitution can
represent parameterized type instances.

Data structures:

- Use `type_instance_kind = array` and `type_instance_kind = slice`.
- Store element type in `type_instance_elem_ref_*`.
- Store const length in `type_instance_len_*`.
- Keep concrete scalar array behavior visible to existing tests while the new
  metadata path is introduced.

Passes:

1. Replace the blanket generic array/slice rejection in `type_check_scope.slang`
   with a bounded declaration validator: `[T; N]` and `[T]` are accepted in
   parameter, local annotation, and struct-field positions when `T` resolves to
   an owning type parameter and `N` resolves to an owning const parameter.
2. Substitute array/slice element types through a dedicated GPU index-result
   consumer, `type_check_type_instances_07_array_index_results.slang`, which
   publishes the precomputed result type for `values[0]`.
3. Preserve existing concrete `[i32; N]` behavior.
4. Keep broad generic array/slice calls rejected until type-instance
   unification can infer both element and length arguments at call sites. The
   current bounded call slice infers only an element return `T` from one
   declaration-backed actual array or slice argument.
5. Add return checking by comparing `fn_return_ref_*` and expression refs only
   after element and length records are precomputed. Do not reintroduce a
   return-node shader that reparses array spans.
6. Add broader length substitution only after type element substitution is
   stable.

Acceptance targets:

- `fn first<T, const N: usize>(values: [T; N]) -> T { return values[0]; }`
  type-checks as a generic declaration, including a local `let copy: [T; N]`
  annotation before returning `copy[0]`.
- Calls to `first_i32` continue to pass, and bounded direct calls to `first`
  / `first_slice` infer `T` from one declaration-backed actual array or slice
  argument. Broader generic array/slice calls remain rejected.
- `ArrayVec<T, const N: usize> { values: [T; N], len: usize }` type-checks as a
  declaration after generic struct fields and generic array elements are both
  represented.
- Constructing a concrete `ArrayVec<i32, 4>` with an inline `values: [..]`
  struct-literal field remains rejected until named generic instances carry
  substitutable const argument values. Accepting it before then would verify the
  element type at best while losing the `N = 4` length requirement.

## Stage 4: Bounds And Where Predicates

Goal: record predicates on GPU first, then use them for trait solving and method
lookup.

Data structures:

- Compact predicate records from inline bounds and `where` clauses:
  owner item, subject generic parameter, bound type path, bound type arguments,
  source token.
- Trait declaration records: trait name, type parameter slots, required method
  signatures.
- Impl records: implemented trait instance, target type instance, method tokens.
- Method candidate records keyed by receiver type/trait predicate.

Passes:

1. Predicate extraction for parseable inline bounds and `where` predicates is
   implemented for the bounded supported forms.
2. Predicate subjects are validated against in-scope generic parameters.
3. Bound names are validated as traits, including qualified trait paths through
   module records.
4. Simple call obligations are checked against concrete impl predicate records.
5. For method lookup, intersect receiver type with inherent impls and available
   trait predicates. Reject ambiguity on GPU.

Current predicate coverage includes substitutions where the obligation subject
is not the first generic parameter slot, such as `U: Supports<T>`,
two-argument obligations where both bound arguments come from generic call
slots, such as `U: Combines<T, V>`, and mixed concrete/generic bound arguments
such as `T: Rel<i32, U>`. Predicate rows must preserve the subject slot and
every supported bound argument slot. Predicate rows with more than two bound
arguments remain outside the current predicate record width and are rejected
from predicate status rows with explicit `LNC0008` fail-closed diagnostics.
Predicate rows and trait impl rows also reject argument-count mismatches against
the resolved trait declaration before any call-site obligation matching.
Call-site obligation substitution consumes the same sorted
`(owner declaration, name id)` generic-parameter records as predicate
collection, so subject and bound-argument slots are joined from compact GPU
facts instead of rediscovered by walking a declaration subtree for every call.
The obligation pass also fails closed before matching when the formal/actual
call argument cache exceeds its four-record window or when a called function has
more than 32 predicate rows in its sorted owner range, so a bounded invocation
never validates only a prefix of the required obligations.
A symbolic generic actual type is not a concrete impl key in this solver: calls
that would require carrying an obligation such as `U: Eq<U>` forward fail with
the normal trait-bound diagnostic until compact recursive obligation rows exist.
A focused regression fixture records the obligation-window contract with a
33-obligation generic call: the current solver must report the unsupported
obligation window rather than accept the call by checking only the first 32
predicate rows.
Sorted impl-predicate keys are also range-checked on GPU, so overlapping exact
supported impls fail as invalid trait implementations even if no call currently
uses the bound. The later condition pass no longer performs a per-impl scan
over every HIR node for overlap detection; exact impl uniqueness is owned by the
sorted predicate-key pass after predicate collection.
Sorted trait/impl method-contract owner ranges are endpoint-validated before
trait impl validation consumes them, so malformed non-empty owner ranges fail
closed instead of letting required or extra method rows be skipped.
Name-specific method-contract lookups also endpoint-validate the sorted
`(owner, name)` equal range before returning the first method row, so duplicate,
missing, and extra-method checks cannot consume a malformed key slice as a
valid trait method match. Method contract collection also marks every trait and
impl method production as unsupported when its owner/name relation cannot be
published, and impl-method malformed rows are surfaced directly as trait
contract errors instead of disappearing from the sorted owner/name join. Impl
method rows that carry their own compact unsupported-status record are checked
before the extra-method join classifies them by name, so a malformed extra
method fails for the malformed contract rather than being downgraded to an
ordinary extra method.
Required impl methods also check that the sorted
`(impl owner, method name)` range has only one row before signature comparison,
so a duplicate impl method cannot satisfy a trait contract by letting the first
row match and hiding the later row; duplicate impl methods now use a distinct
GPU predicate status and `LNC0021` diagnostic from duplicate trait declaration
methods. Reordered impl methods are accepted by joining the trait and impl rows
through those sorted owner/name facts instead of pairing methods by source
order. Extra, duplicate, and malformed impl-method rows are now reported by
explicit method-validation records reduced per impl owner, while the old
collector keeps only the remaining required-name/signature bridge. The next
pass-style readiness point is to move that bridge into compact parameter and
type-ref validation records rather than returning a status directly from each
impl header thread. That still would not
publish trait methods for dot-call dispatch or backend monomorphization.
Trait and impl owner ranges currently have a 32-method signature-comparison
window. Wider ranges fail closed from the sorted method-contract records instead
of letting a single shader invocation perform an unbounded walk over all
methods, and they now report a distinct `LNC0021` method-contract-window
diagnostic instead of being collapsed into ordinary method parameter arity
mismatch. The validation-row slice can now also classify the compact count case
where a trait's sorted owner range has more required methods than the impl's
range, so a missing required method beyond the old owner-window reports the
normal missing-method contract diagnostic instead of the generic window
diagnostic.
Method-contract collection should preserve the same pass order used by the
papers: materialize relation rows once, prefix-scan compact rows, sort keys, and
join/reduce ranges. For methods that means trait declarations, inherent impls,
and trait impl method bodies should all be represented as compact contract
facts before validation:

```text
(method, owner, method name, visibility, receiver, return type ref)
(method, signature status: method generics, method where, malformed return ref)
(method, parameter ordinal, parameter type ref)
```

The current implementation has only part of that shape. It consumes
parser-owned HIR method name rows, method owner rows, visibility rows, and
parameter rows for trait declarations plus inherent and trait impl methods.
Method-parameter publication has the same all-or-error contract: if an owned
parameter cannot be assigned an ordinal row,
the collector publishes an over-window parameter count and the validator rejects
the method signature instead of comparing a truncated parameter list. Method
return types now come from parser-owned `hir_fn_return_type_node` rows, and
method-level generic/where rejection comes from parser-owned
`hir_method_signature_flags` rows published before predicate validation, not
method-local child-list scans in predicate consumers.
Trait impl type-shape scans are intentionally bounded; exceeding that bound is
classified as an unsupported predicate shape on GPU, not as successful
validation of the scanned prefix.
Trait-method signature comparison also rejects over-width or nested generic
instance arguments instead of comparing the recorded prefix. The production fix
is the same type-ref leaf relation used by direct-call unification: compact
rows sorted by `(root_type_ref, leaf_path)` that preserve all generic argument
leaves before trait/impl signature joins run. The same relation must cover
method return refs before nested generic return signatures can participate in
trait impl validation or backend monomorphization.
Same-name inherent
methods on different concrete instances of the same generic type head now have a
bounded GPU method-key slice: the sorted lookup key includes the nominal
receiver plus up to four receiver type-argument refs from the type-instance
records, and method-key validation fails closed when those receiver argument
records are malformed or when the receiver instance never bound to its nominal
generic declaration. Inherent impl headers now also validate the receiver
target's nominal declaration arity and four-argument record window before method
lookup, so under-applied generic receiver impls fail from the GPU predicate
status path instead of waiting for a call to miss the sorted method table.
Over-width receiver instances fail through the same source-spanned `LNC0021`
predicate status before method lookup can publish or consume a truncated
receiver-key slice. Receiver targets whose top-level argument is itself a
generic instance also fail through that predicate status until method keys carry
flattened nested type-ref rows; accepting them with the current key would erase
the nested arguments.
Method-call lookup also rejects unresolved receiver instances before searching
the sorted method table, so unresolved generic receiver values cannot resolve by
matching only the recorded argument prefix.
Focused coverage now includes all four receiver argument slots, with
source-pack coverage for two-slot receivers. Method calls whose argument lists
exceed the current four-slot GPU argument cache fail closed before per-slot
validation, so a five-argument call cannot be accepted by comparing only the
first four argument records. Overlapping exact concrete and generic inherent
methods with the same receiver/name still need a sorted-record
specialization/ambiguity pass. Until that exists, method lookup fails closed
when both the exact receiver key and the generic receiver key produce a visible
candidate; it does not silently prefer the concrete method and call that
  specialization. Cross-module inherent method lookup also fails closed when a
  sorted receiver/name range has more than one candidate instead of scanning the
  range in-shader; public candidate compaction/reduction is still needed before
  multiple visible/hidden rows can be handled precisely. Broader method lookup
  still needs trait predicates, associated items, and backend specialization.

Bounds should not be treated as comments. Predicate forms outside the current
GPU predicate records and obligation checker must continue to fail with a GPU
type-check error.
Source-pack calls to imported generic functions preserve the same contract:
qualified trait bounds on the called function are checked against visible
public impls, imported bounded functions may forward through another generic
helper before returning the substituted value, and unsupported concrete callers
fail instead of bypassing the where clause. The imported contract also covers
nonzero bound subjects such as `require_right<T, U>(left: T, right: U) -> U
where U: Eq<U>`, so the predicate solver must infer and check the bound from
the second value argument before publishing the substituted return.

## Minimal First Implementation Slice

Objective: direct simple generic function calls substitute parameter and return
types on GPU. The current implementation covers literal/identifier arguments,
generic forwarding, nested direct helper calls, source-pack qualified forwarding
through helper calls, bounded nested generic-instance return argument inference,
nonzero-slot trait-bound obligations on imported qualified calls, and
repeated-parameter conflict detection for those direct-call shapes.

Files to change:

- The resident GPU type-check path under `src/type_checker/resident.rs`
  dispatches the call metadata block before visible/scope facts, then runs
  `type_check_calls_03_resolve`, `03b`, `03c`, and `04_erase_generic_params`
  after `type_check_scope_hir` publishes visibility. Use this resident ordering
  as the pass-order evidence for this slice.
- `shaders/type_checker/type_check_calls_02_functions.slang`
  keeps function parameter and return caches used by substitution.
- `shaders/type_checker/type_check_calls_03_resolve.slang`
  infers and applies direct call-site substitutions entirely on GPU.
- `shaders/type_checker/type_check_calls_04_erase_generic_params.slang`
  erases unresolved callee-local generic parameter ids in the parameter cache so
  later argument checks do not treat them as concrete mismatches after the
  resolved call return type has been substituted.
- `shaders/type_checker/type_check_scope.slang`
  preserve existing rejections for generic arrays, bounds, and where predicates;
  do not reject simple generic function declarations or calls once call
  substitution succeeds.
- Downstream condition, control, module, and backend consumers read substituted
  call return types and keep strict mismatch checks for unresolved generic
  codes.
- `tests/type_checker_semantics.rs` and `tests/type_checker_generics.rs`
  cover simple calls, nested direct calls, generic forwarding, source-pack
  qualified forwarding through generic helpers, and conflicting repeated
  inference.

Exact first tests:

```rust
#[test]
fn type_checker_accepts_simple_generic_function_call_substitution_on_gpu() {
    let src = r#"
fn keep<T>(value: T) -> T {
    return value;
}

fn main() {
    let value: i32 = keep(7);
    return value;
}
"#;

    assert_gpu_type_check_ok(src);
}

#[test]
fn type_checker_accepts_generic_function_call_from_generic_function_on_gpu() {
    let src = r#"
fn keep<T>(value: T) -> T {
    return value;
}

fn outer<T>(value: T) -> T {
    return keep(value);
}

fn main() {
    return 0;
}
"#;

    assert_gpu_type_check_ok(src);
}

#[test]
fn type_checker_rejects_conflicting_generic_function_inference_on_gpu() {
    assert_gpu_type_check_rejects(r#"
fn choose<T>(left: T, right: T) -> T {
    return left;
}

fn main() {
    let value: i32 = choose(1, true);
    return value;
}
"#);
}
```

Tests that must remain rejecting while their GPU consumers are missing:

- broader generic array return/call cases that cannot be represented by the
  current array/type-instance consumers
- broader trait solving cases that cannot be represented by the current
  predicate records or validated by the current obligation checker

## No-CPU-Fallback Guardrails

- `src/compiler.rs` must continue to pass source directly to GPU lexer/parser
  and type checker. `prepare_source_for_gpu*` must not expand imports, aliases,
  generics, or modules.
- Rust may allocate GPU buffers and schedule passes, but Rust must not inspect
  tokens to infer type arguments, instantiate generic functions, rewrite source,
  rewrite HIR, or patch return types.
- All generic substitution state must be represented in GPU buffers and produced
  by shader passes.
- Unsupported generic forms must fail with `CompileError::GpuTypeCheck`, not be
  accepted and ignored.
- Parser-only coverage must never be documented as semantic support. Each
  accepted generic feature needs a GPU type-check test, and codegen support must
  be documented separately.
- Rejections must be shape-specific, not feature-family blanket claims. Scoped
  GPU record coverage now exists for some modules/imports, qualified predicate
  paths, trait and impl headers, inherent methods, match expressions, for loops,
  generic arrays/slices, enum payload matches, and called predicate obligations.
  Any remaining unsupported shape inside those families should fail through
  explicit GPU status/error records until its record schema and passes exist.
- If a future backend needs specialized bodies, monomorphization must be a GPU
  body/type-instance expansion pass that emits GPU-resident codegen metadata. It
  must not resurrect CPU erasure or CPU specialization.
