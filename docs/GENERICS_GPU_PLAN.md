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
  direct calls such as `keep(keep(7))` and `return keep(keep(value))`.
  Conflicting repeated generic arguments are rejected, including
  `choose(keep(1), keep(true))`.
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
  Legacy aggregate and method WASM execution tests for `core::range` helpers
  remain ignored until backend lowering consumes those records directly.
  Current WASM/x86 executable coverage is narrower than this semantic slice.
  An earlier attempt to substitute `Range<i32>.start` directly inside
  `type_check_tokens_min.slang` by walking the base value's annotation, struct
  generic parameter list, and field type compiled, but made the focused GPU
  type-check test hit both the 2s and 60s watchdogs. That route was backed out;
  generic struct projection needs a precomputed GPU type-instance/substitution
  table instead of adding instance lookup to the hot token checker. A later
  attempt to feed the hot token checker a concrete scalar bridge from those
  metadata buffers still stalled in `type_check_tokens` compute-pipeline
  creation with both 15s and 30s focused-test watchdogs. The working path keeps
  reusable type-instance metadata in GPU arrays and feeds bounded consumers from
  those arrays instead of expanding token-local substitution.
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
  enum payload arms such as `Some(inner) -> inner` / `None -> fallback`,
  publishing the match result type from HIR match spans and
  resolver/type-instance metadata. The old bounded WASM codegen slice for
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
  called trait predicates. Trait bounds and trait impl headers wider than the
  current two-argument GPU predicate records now fail closed with a stable GPU
  predicate diagnostic instead of publishing partial predicate rows. Nested
  type-instance predicate arguments in both bounds and impl headers, such as
  `Rel<Boxed<i32>>`, now also fail closed until predicate rows carry argument
  type-instance refs. Unapplied generic type heads in predicate arguments, such
  as `Rel<Boxed>` where `Boxed<T>` is generic, fail closed for the same reason.
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
  also fail closed because the current predicate row carries only the target
  leaf token; accepting them before target type-argument rows exist would erase
  the impl subject during obligation matching.
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
  accepting an impl that merely contains every required method. Reordered trait
  impl methods validate through sorted `(owner, method name)` contract ranges
  rather than declaration-order pairing. Method return-type facts now come from
  parser-owned `hir_fn_return_type_node` rows, and method-level generic/where
  rejection comes from parser-owned `hir_method_signature_flags` rows instead
  of bounded child-list scans in predicate consumers. A public
  trait method must also be implemented by a public impl method, so exported
  trait contracts cannot be satisfied by private method rows. Implementations of
  public traits must currently use a public impl header, because obligation
  matching does not yet carry module-scoped impl visibility rows. Dot-call
  dispatch through a trait impl still fails closed with a stable call diagnostic
  until trait-method lookup has explicit predicate/selection rows. Public impl
  headers also fail closed when they name private traits, so exported impl rows
  do not leak
  contracts that cannot be named outside their module. The method-contract pass
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
  Trait/impl method owner ranges wider than 32 rows also fail closed before
  validation consumes them, so each impl-header thread has a bounded record
  window until method validation is emitted as its own sorted
  join/result-record pass. Broader trait solving, associated types, recursive
  obligations, dictionaries/static dispatch, and trait-method lookup remain
  future work.
  Top-level predicate-owner discovery is still a capped transitional walk, but
  exhausting that cap now publishes `PREDICATE_STATUS_UNSUPPORTED_BOUND_ARG_RELATION`
  and the predicate obligation pass records the corresponding `LNC0008`
  diagnostic directly, so unsupported predicate shapes cannot disappear before
  the later condition validator sees them. The paper-aligned replacement is a
  parser-owned compact predicate/bound-argument relation, not a wider owner
  walk.
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
- Legacy token checkers such as `type_check_scope.slang` and
  `type_check_tokens_min.slang` can still recognize generic parameter names as
  `TY_GENERIC_BASE + token_index`, but the active resident path should keep
  moving acceptance evidence to HIR/fact-table consumers instead of treating
  token-local equality checks as the generic-call architecture.

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
those records instead of reparsing declarations in the hot token checker.

The key rule is that `type_check_tokens_min.slang` must not rediscover generic
arguments by walking item headers, field declarations, or return type spans.
Token checks should read precomputed type refs and emit errors. The earlier
failed `Range<i32>.start` and enum-constructor attempts both timed out because
they put substitution work in hot token-local paths.

The first committed implementation slice starts with
`type_check_type_instances_01_collect.slang`, wired through the resident and
standalone GPU type-check paths under `src/type_checker/`. It is intentionally
metadata-only: it creates token-indexed
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
   slot map, and writes consumer-facing buffers. The token checker only
   consumes those buffers.
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

1. Dispatch the type-instance metadata passes before scope/token checks.
2. Split struct literal checking out of `type_check_tokens_min.slang` and have the
   new checker read `struct_init_field_expected_ref_*`.
3. Split member projection checking out of `type_check_tokens_min.slang` and have
   the new checker read `member_result_ref_*`.
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
valid trait method match. Method contract collection also marks a method row as
unsupported when its owner/name relation cannot be published, so later
validation cannot accept a trait method whose relation evidence is missing.
Required impl methods also check that the sorted
`(impl owner, method name)` range has only one row before signature comparison,
so a duplicate impl method cannot satisfy a trait contract by letting the first
row match and hiding the later row. Reordered impl methods are accepted by
joining the trait and impl rows through those sorted owner/name facts instead
of pairing methods by source order. Extra impl methods are detected from owner
range counts after those required-name joins, rather than by scanning every impl
method row a second time. The next pass-style readiness point is to emit
explicit trait-method validation result records from those joins, rather than
returning a status directly from each impl header thread. That still would not
publish trait methods for dot-call dispatch or backend monomorphization.
Trait and impl owner ranges currently have a 32-method validation window. Wider
ranges fail closed from the sorted method-contract records instead of letting a
single shader invocation perform an unbounded walk over all methods.
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
Same-name inherent
methods on different concrete instances of the same generic type head now have a
bounded GPU method-key slice: the sorted lookup key includes the nominal
receiver plus up to four receiver type-argument refs from the type-instance
records, and method-key validation fails closed when those receiver argument
records are malformed or when the receiver instance never bound to its nominal
generic declaration. Method-call lookup also rejects unresolved receiver
instances before searching the sorted method table, so under-applied generic
receiver types cannot resolve by matching only the recorded argument prefix.
Focused coverage now includes all four receiver argument slots, with
source-pack coverage for two-slot receivers. Overlapping exact concrete and
generic inherent methods with the same receiver/name still need a sorted-record
specialization/ambiguity pass. Until that exists, method lookup fails closed
when both the exact receiver key and the generic receiver key produce a visible
candidate; it does not silently prefer the concrete method and call that
specialization. Cross-module inherent method lookup also fails closed when a
sorted receiver/name range exceeds the current 32-candidate visibility window
instead of scanning the whole range. Broader method lookup still needs trait
predicates, associated items, and backend specialization.

Bounds should not be treated as comments. Predicate forms outside the current
GPU predicate records and obligation checker must continue to fail with a GPU
type-check error.

## Minimal First Implementation Slice

Objective: direct simple generic function calls substitute parameter and return
types on GPU. The current implementation covers literal/identifier arguments,
generic forwarding, nested direct helper calls, and repeated-parameter conflict
detection for those direct-call shapes.

Files to change:

- The resident GPU type-check path under `src/type_checker/resident.rs`
  dispatches the call metadata block before visible/scope facts, then runs
  `type_check_calls_03_resolve`, `03b`, `03c`, and `04_erase_generic_params`
  after `type_check_scope_hir` publishes visibility. The older standalone
  token-buffer path still records resolve and erasure inside its single
  `record_call_bind_groups` block before legacy scope checks, so do not cite
  standalone ordering as resident pass-order evidence.
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
- `shaders/type_checker/type_check_tokens_min.slang`
  consume substituted call return types and keep strict mismatch checks for
  unresolved generic codes.
- `tests/type_checker_semantics.rs` and `tests/type_checker_generics.rs`
  cover simple calls, nested direct calls, generic forwarding, and conflicting
  repeated inference.

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
