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
- Generic function declarations type-check as source shape today. The acceptance
  test is `type_checker_accepts_generic_declarations_and_annotations` in
  `tests/type_checker_semantics.rs`, covering `fn keep<T>(value: T) -> T`.
- Simple generic function calls now have GPU type-check substitution for direct
  calls inferred from value arguments. The acceptance tests cover `keep(7)`,
  `keep(true)`, generic forwarding through `return keep(value)`, and nested
  direct calls such as `keep(keep(7))` and `return keep(keep(value))`.
  Conflicting repeated generic arguments are rejected, including
  `choose(keep(1), keep(true))`.
- Generic structs and enums parse and partly type-check as declarations and
  annotations. The same acceptance test covers `struct Boxed<T>`, `enum
  Maybe<T>`, `Boxed<i32>`, and `Maybe<i32>` annotations.
- Generic struct substitution has bounded GPU semantic coverage for concrete
  `Range<i32>`-style uses. The acceptance tests cover `Range<i32>`
  construction, `Range<i32>.start` projection, concrete `Range<i32>` inherent
  method calls, method receivers that are already resolved GPU call results,
  and the module-form `core::range` seed through resolver arrays.
  The bounded WASM aggregate-helper slice also executes
  `core::range::range_i32` construction plus `core::range::start_i32`
  projection from a full explicit source pack through GPU aggregate metadata,
  and the bounded aggregate body emitter can now lower an annotated-local
  `.start()` method projection by consuming the GPU method resolver result and
  method receiver refs. It can also lower the direct call-result receiver form
  `core::range::range_i32(1, 4).start()`/`.end()` by storing the
  resolver-selected aggregate constructor result into scalar slots before
  projecting the table-resolved method body.
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
  for annotated concrete local contexts. The pass
  `type_check_type_instances_06_enum_ctors.slang` consumes resident
  type-instance refs, validates payload arity/type for annotated concrete locals
  such as `Maybe<i32> = Some(1)` and `Result<i32, bool>` constructors, and writes a
  constructor-token sentinel consumed by `type_check_tokens_min.slang`. It also
  validates symbolic constructor returns such as
  `fn wrap<T>(value: T) -> Maybe<T> { return Some(value); }` against
  `fn_return_ref_*` and type-instance argument refs, then writes a return-token
  sentinel. Bounded GPU match typing now covers stdlib-shaped enum payload arms
  such as `Some(inner) -> inner` / `None -> fallback`, publishing the match
  result type from HIR match spans and resolver/type-instance metadata. A
  bounded WASM codegen slice now lowers `core::ordering::compare_i32` unit enum
  returns plus a `match` over those unit variants from a full explicit source
  pack by deriving variant tags from parser HIR item metadata. Match
  exhaustiveness, payload enum layout, monomorphization, and broad backend
  lowering remain rejected.
- Bounded generic array and slice element declarations now have GPU semantic
  coverage. `type_checker_accepts_generic_array_and_slice_elements_on_gpu`
  covers `[T; N]`, `[T]`, and `ArrayVec<T, const N: usize>` declarations, while
  `type_checker_rejects_invalid_generic_array_element_returns_on_gpu` keeps
  generic array calls, whole-array returns, invalid generic length/name
  ownership, and mismatched element returns rejected.
- Bounds and where predicates parse. `tests/parser_tree.rs` includes parser
  coverage for type parameter bounds, multiple bounds, and where clauses such as
  `where T: core::cmp::Eq<T>`.
- Bounds and where predicates are rejected semantically. The type checker
  rejection tests are
  `type_checker_rejects_generic_bounds_until_gpu_predicate_semantics_exist` and
  `type_checker_rejects_where_clauses_until_gpu_predicate_semantics_exist`.
- `shaders/parser/direct_hir.slang` and `shaders/parser/hir_nodes.slang`
  classify coarse HIR nodes, but most type-checking still relies on resident
  token buffers plus HIR spans rather than a fully lowered semantic AST.
- `shaders/type_checker/type_check_calls_01_resolve.slang`,
  `type_check_calls_02_functions.slang`, and
  `type_check_calls_03_resolve.slang` already build GPU call metadata:
  `call_fn_index`, `call_return_type`, `call_return_type_token`,
  `call_param_count`, `call_param_type`, and function lookup hash tables.
- `shaders/type_checker/type_check_scope.slang` and
  `type_check_tokens_min.slang` already recognize generic parameter names as
  `TY_GENERIC_BASE + token_index`, but assignment currently requires exact
  equality for generic type codes. That is why generic calls fail with
  `AssignMismatch` or `ReturnMismatch`.

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

Passes:

1. `generic_items_01_clear`
   clears the new generic buffers.
2. `generic_items_02_collect`
   scans item headers and records type parameter slots for `fn`, `struct`, and
   `enum`. For the first slice, only `fn` records are consumed.
3. `generic_calls_01_infer`
   runs one thread per call expression. It reads `call_fn_index`, formal
   parameter types from `call_param_type`, and actual argument types from
   `simple_expr_type`/`visible_type`. For each formal generic parameter
   `TY_GENERIC_BASE + param_token`, it records the corresponding actual type in
   `call_subst_type[call, slot]`. Repeated uses must agree.
4. `generic_calls_02_apply`
   writes substituted return types into `call_return_type[callee_use]` and, if
   needed, a `subst_type_out` entry for the call token. A return type of `T`
   becomes the inferred concrete type for `T`. Non-generic functions remain
   unchanged.
5. Existing scope/token/control checks consume the substituted call return type.
   `assignable` should remain strict: generic type codes only compare equal
   after substitution has occurred or inside the generic declaration body.

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
`type_check_type_instances_01_collect.slang`, wired through
`src/type_checker/gpu.rs` in both the resident and one-shot GPU type-check
paths. It is intentionally metadata-only: it creates token-indexed
`type_expr_ref_*`, `type_instance_*`, and `fn_return_ref_*` buffers for scalar
type heads, named generic candidates, arrays, slices, and function return type
heads, including named generic argument start/count records. The follow-up
metadata passes bind named generic instances to struct/enum declarations,
publish argument refs, publish `member_result_ref_*` plus
`struct_init_field_expected_ref_*` for generic struct fields, and publish a
bounded concrete array-return sentinel for matching `[i32; literal]` identifier
returns and HIR-backed i32 value array returns. A later bounded consumer now
validates concrete contextual generic enum constructors and writes a
constructor-token sentinel. A bounded array-index consumer now accepts
generic array/slice declaration shapes and
  precomputes `values[0]` element result types. The module resolver also carries a
  parser-derived `decl_name_token` so type and enum projections use declaration
  names instead of declaration span starts. Symbolic generic enum constructor
returns now compare precomputed return refs and expression refs before the hot
token checker. Array literal returns are limited to concrete i32 value arrays
with matching concrete lengths, including bounded `values[index]` elements when
the base has a concrete `[i32; literal]` type and the HIR index expression has an
i32 scalar index. Mismatched concrete lengths, non-constructor symbolic generic
enum returns, and broader match forms remain rejected until consuming checks
compare the relevant records directly outside the hot token checker. The current
match slice is limited to HIR-spanned arms
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
   pool. Const arguments may be recorded but remain unsupported for semantic
   acceptance until const substitution is implemented.
4. `type_instances_04_publish_struct_enum_uses`
   publishes substituted expected refs for struct literals and member
   projections. This pass walks declaration fields once, applies the instance
   slot map, and writes consumer-facing buffers. The token checker only
   consumes those buffers.
5. `type_instances_05_publish_array_uses`
   publishes array/slice element and length refs for parameters, locals, fields,
   and returns. The first consumer accepts matching concrete `[i32; literal]`
   identifier returns and HIR-backed i32 value array returns while continuing
   to reject `[T; N]`, `[T]`, call returns, and mismatched concrete lengths until
   the existing checks compare broader records directly. Indexed array literal
   elements are bounded to HIR index expressions whose base is a concrete i32
   array and whose index is an i32 scalar atom.
6. `type_instances_06_enum_ctors`
   consumes contextual concrete generic enum instances from annotated locals,
   substitutes payload generic refs through the instance argument pool, validates
   constructor arity/type, and writes `GENERIC_ENUM_CTOR_OK` into
   `call_return_type[ctor_token]`. It intentionally does not allocate
   additional `enum_ctor_*` storage buffers, which keeps the pass under the
   adapter storage-buffer binding limit.

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
4. Update enum constructor checking to consume the `GENERIC_ENUM_CTOR_OK`
   sentinel after a dedicated pass validates contextual concrete payload refs
   or symbolic constructor-return refs.
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
   with a bounded declaration validator: `[T; N]` and `[T]` are accepted only
   in parameter and struct-field positions when `T` resolves to an owning type
   parameter and `N` resolves to an owning const parameter.
2. Substitute array/slice element types through a dedicated GPU index-result
   consumer, `type_check_type_instances_07_array_index_results.slang`, which
   publishes the precomputed result type for `values[0]`.
3. Preserve existing concrete `[i32; N]` behavior.
4. Keep generic array/slice calls rejected until type-instance unification can
   infer both element and length arguments at call sites.
5. Add return checking by comparing `fn_return_ref_*` and expression refs only
   after element and length records are precomputed. Do not reintroduce a
   return-node shader that reparses array spans.
6. Add broader length substitution only after type element substitution is
   stable.

Acceptance targets:

- `fn first<T, const N: usize>(values: [T; N]) -> T { return values[0]; }`
  type-checks as a generic declaration.
- Calls to `first_i32` continue to pass, while generic array/slice calls remain
  rejected.
- `ArrayVec<T, const N: usize> { values: [T; N], len: usize }` type-checks as a
  declaration after generic struct fields and generic array elements are both
  represented.

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

1. Replace the current `TK_WHERE` and bound-colon rejection guardrails with
   predicate extraction for parseable predicates.
2. Validate that predicate subjects name in-scope generic parameters.
3. Validate that bound names resolve to traits after trait declaration semantics
   exist.
4. For method lookup, intersect receiver type with inherent impls and available
   trait predicates. Reject ambiguity on GPU.

Bounds should not be treated as comments. Until a predicate is represented and
checked by these GPU records, the source must continue to fail with a GPU
type-check error.

## Minimal First Implementation Slice

Objective: direct simple generic function calls substitute parameter and return
types on GPU. The current implementation covers literal/identifier arguments,
generic forwarding, nested direct helper calls, and repeated-parameter conflict
detection for those direct-call shapes.

Files to change:

- `src/type_checker/gpu.rs`
  dispatches the call-resolution passes and the generic-parameter erasure pass
  before scope/token checks consume call metadata.
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

- `type_checker_rejects_invalid_generic_array_element_returns_on_gpu`
- `type_checker_rejects_generic_bounds_until_gpu_predicate_semantics_exist`
- `type_checker_rejects_where_clauses_until_gpu_predicate_semantics_exist`

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
- Existing syntax rejections for modules/imports, qualified value paths, general
  references, traits, methods, match, for loops, generic arrays/slices, and
  predicates should stay in place until their corresponding GPU data structures
  and passes exist.
- If a future backend needs specialized bodies, monomorphization must be a GPU
  body/type-instance expansion pass that emits GPU-resident codegen metadata. It
  must not resurrect CPU erasure or CPU specialization.
