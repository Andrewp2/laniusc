# Resident Type Checker

The resident type checker is the compiler phase that turns lexer tokens and
parser HIR records into semantic relations. It is a GPU-resident relation
builder, not a host AST walker. Rust records compute passes; Slang shaders build
and validate tables for names, modules, imports, types, calls, methods,
visibility, predicates, returns, conditions, control flow, and backend metadata.

Use this chapter to understand ownership, pass order, cache reuse, diagnostics,
and backend handoff. Use [generated/reference.md](generated/reference.md) for
the exact current inventories: type-check pass loader entries, type-check
record sites, status-code numbers, buffer carrier structs, large struct fields,
shader groups, and Rustdoc coverage.

## What This Chapter Owns

The type-checker docs cover the boundary where parser HIR becomes semantic
compiler state.

| Question | Owned here | Owned elsewhere |
| --- | --- | --- |
| Which syntax records exist? | Consumed from parser HIR. | [Parser and HIR](parser.md). |
| Which source file/module owns an item? | Module-path state and source-pack file ids. | [Module and source-root resolution](module-resolution.md). |
| Which names, types, calls, and methods resolve? | Resident type-check pass families. | Language design docs, when they exist. |
| How does a semantic rejection become a source diagnostic? | Status words and type-check diagnostic mapping. | [Diagnostics and status](diagnostics.md). |
| What metadata can codegen consume? | Retained codegen buffer wrappers. | [Codegen and backends](codegen.md). |
| What exact pass fields exist today? | Generated reference only. | `docs/compiler/generated/reference.md`. |

The most important local source roots are:

- `crates/laniusc-compiler/src/type_checker/mod.rs`: public structs, status
  codes, pass/state structs, retained backend metadata wrappers.
- `crates/laniusc-compiler/src/type_checker/resident.rs`: main recording
  sequence, cache-key construction, status readback, retained-buffer accessors.
- `crates/laniusc-compiler/src/type_checker/bind_groups.rs`: resident buffer
  allocation and bind-group construction.
- `crates/laniusc-compiler/src/type_checker/bind_models.rs`: typed bind model
  structs used by bind-group factories.
- `crates/laniusc-compiler/src/type_checker/params.rs`: uniform packets and
  constants shared with shaders.
- `crates/laniusc-compiler/src/type_checker/record/*.rs`: record helpers for
  pass families.
- `crates/laniusc-compiler/src/type_checker/module_path/*`: module, import,
  declaration, and path-resolution state.
- `shaders/type_checker/**`: GPU implementations for the pass families.

## Entry Points

The compiler normally reaches the type checker through `GpuCompiler`, after the
lexer and parser have already recorded and submitted their own frontend work.

| Entry point | Role |
| --- | --- |
| `GpuCompiler::type_check_source` | Type-checks one in-memory source string and labels diagnostics as `<source>`. |
| `GpuCompiler::type_check_source_from_path` | Reads one file and preserves the path for diagnostics. |
| `GpuCompiler::type_check_source_pack` | Type-checks an in-memory source pack after validating default unit limits. |
| `GpuCompiler::type_check_source_pack_manifest` | Type-checks a source pack while preserving manifest paths. |
| `GpuCompiler::type_check_expanded_source_with_diagnostic_path` | Single-source orchestration: lex, parse, retain parser buffers, record type check, finish readback. |
| `GpuCompiler::type_check_explicit_source_pack_with_paths` | Source-pack orchestration with per-file diagnostic metadata. |
| `GpuCompiler::record_typecheck_from_parse_buffers` | Internal boundary from retained lexer/parser buffers to `GpuTypeChecker`. |
| `GpuTypeChecker::record_resident_token_buffer_with_hir_items_on_gpu` | Main LL frontend path. Records type checking with parser-owned HIR item metadata. |
| `GpuTypeChecker::record_resident_token_buffer_with_hir_on_gpu` | Lower-level path that records type checking without parser item metadata. |
| `GpuTypeChecker::record_resident_token_buffer_with_hir_items_and_scratch_on_gpu` | Alternate path for callers that also prove earlier scratch buffers are dead and safe to reuse. |
| `GpuTypeChecker::finish_recorded_check` | Maps the status readback buffer and converts four GPU words into success or `GpuTypeCheckError`. |

The `GpuCompiler` entry points take the resident pipeline lock before lexing and
parsing. That lock protects the sequence of resident frontend buffers and the
type-check cache from overlapping compiler operations that would reuse or
release the wrong GPU resources.

## End-To-End Flow

The main single-source and source-pack check paths follow the same shape:

1. Prepare source bytes for the GPU frontend.
2. Record lexer work through the resident lexer helper.
3. Ask the parser for the projected tree capacity needed for HIR construction.
4. Record and submit the parser-boundary encoder.
5. Read parser LL(1) status. If parsing failed, map parser status to a source
   diagnostic before type checking starts.
6. Compute the active HIR capacity from parser output.
7. Clone parser HIR rows into `OwnedTypecheckParserBuffers`.
8. Release parser resident buffers and poll the device so the released cache is
   not accidentally used by the next phase.
9. Record type-check work into the caller's command encoder.
10. Submit the caller's encoder through the lexer helper.
11. Finish the recorded type-check readback and map any rejection to a
    compiler diagnostic.

That split matters. Parser work is submitted and checked before type-check
recording consumes retained parser rows. Type-check status readback is recorded
into the caller's encoder and finished only after that encoder has run.

## Inputs And Cardinalities

`TypeCheckParams` is the common uniform packet copied before recording:

| Field | Meaning |
| --- | --- |
| `n_tokens` | Token capacity for the current recording. The compiler passes `token_count.max(1)`. |
| `source_len` | Source byte length for source-buffer reads. |
| `n_hir_nodes` | Active semantic HIR capacity emitted by the parser. |
| `n_source_files` | Source-file table capacity for source-pack diagnostics and module state. |

The resident recorder also receives these input families:

| Input family | Examples | Notes |
| --- | --- | --- |
| Lexer buffers | token rows, token count, token file ids, source bytes | Borrowed from the lexer resident operation while type check records. |
| Parser base HIR | HIR kind, token start/end, token file id, LL status | Retained in `OwnedTypecheckParserBuffers` before parser cache release. |
| Parser item HIR | item kind/name/type rows, path rows, call rows, method rows, match rows, aggregate rows | Present in the normal compiler path and required by module/type/call/method families. |
| Optional scratch | external buffers supplied through `GpuTypeCheckExternalScratchBuffers` | Only valid after the caller has proven the previous phase no longer needs those buffers. |
| Timer state | optional `GpuTimer`, host timing env flag | Used for profiling; it must not be required for correctness. |

Treat capacities as allocation and dispatch contracts, not language limits. A
language limit should be documented separately, validated deliberately, and
reported at a user-visible source location.

## Resident State And Cache Key

`GpuTypeChecker` owns pass pipelines, a params buffer, a status buffer, a
readback buffer, and one mutex-protected `ResidentTypeCheckState`. The resident
state holds buffers and bind groups so GPU resources remain alive for all passes
and for later backend metadata access.

Before recording, `record_resident_token_buffer_with_hir_impl_on_gpu` builds a
`ResidentTypeCheckCacheKey`:

| Key field | Reuse rule | Why it matters |
| --- | --- | --- |
| `source_file_capacity` | Must match exactly. | Source-pack file tables and diagnostic/module metadata are keyed by file count. |
| `token_capacity` | Cached state may be larger. | Token-indexed buffers can safely cover a smaller current input. |
| `hir_node_capacity` | Cached state may be larger. | HIR-indexed buffers can safely cover a smaller active tree. |
| `parser_hir_node_capacity` | Cached state may be larger. | Parser-owned HIR rows may be larger than active semantic HIR rows. |
| `input_fingerprint` | Must match exactly. | Bind groups capture concrete `wgpu::Buffer` identities. |
| `uses_hir_control` | Must match exactly. | Selects HIR-aware control/scope passes versus token-only passes. |
| `uses_hir_items` | Must match exactly. | Distinguishes parser item metadata availability. |

The input fingerprint hashes every buffer identity that can affect resident
bind groups: token/source/HIR/status buffers, selected HIR item buffers, and any
external scratch buffers supplied by the caller. If a new pass binds a buffer
whose identity is not already in the fingerprint, add it when the bind group is
introduced. A stale bind group is a correctness bug, not just a missed cache
optimization.

The cache key deliberately allows capacity reuse in one direction only. A
larger cached state can serve a smaller current program; a smaller cached state
must be rebuilt before larger dispatches can write into it.

## Buffer Ownership And Lifetime

This subsystem has both `LaniusBuffer<T>` and raw `wgpu::Buffer` references
because those names describe different ownership boundaries.

| Form | Use it for | Contract |
| --- | --- | --- |
| `LaniusBuffer<T>` | Type-check-owned or compiler-owned buffers with a known element type and byte size. | The owner keeps the buffer alive and can expose typed metadata such as size. |
| `&wgpu::Buffer` | Borrowed inputs and `wgpu` API boundaries. | The callee does not own the buffer and must not assume it survives past the recorded operation unless a retained wrapper says so. |
| `wgpu::BindGroup` | Reflected shader resources captured for later recording. | Every captured buffer identity must be covered by the resident cache key. |
| Owned retained wrappers | Metadata that must outlive the resident cache. | Taking the wrapper consumes the resident state so later phases own the needed buffers. |

The main lifetime categories are:

| Category | Examples | Lifetime |
| --- | --- | --- |
| Lexer-owned input | token rows, token count, token file ids, source bytes | Borrowed while the type-check operation records and finishes. |
| Parser-retained input | HIR rows, item rows, call/method/type rows, LL status | Cloned into `OwnedTypecheckParserBuffers` before parser resident buffers are released. |
| Type-check resident state | names, visible declarations, module paths, type instances, calls, methods, predicates, control facts | Reused while the resident cache key remains valid. |
| Optional external scratch | dead parser/lexer/codegen workspaces supplied by a caller | Borrowed only after the caller proves the old data is dead. |
| Retained backend metadata | resolved declarations, call/type rows, function context, member/aggregate metadata | Borrowed through accessors or moved through owned wrappers. |

Do not keep a raw `wgpu::Buffer` reference for a later phase just because the
Rust value still exists. Later phases may intentionally recycle scratch storage.
If backend code needs a semantic relation, expose it through
`GpuCodegenBuffers`, `OwnedGpuCodegenBuffers`, `GpuX86CodegenBuffers`, or
`OwnedGpuX86CodegenBuffers`.

## Bind Models And Parameter Packets

`type_checker/bind_models.rs` and `type_checker/params.rs` are a typed mirror of
shader resource layouts. They are not the place to encode language policy.

| Model kind | Examples | Meaning |
| --- | --- | --- |
| Parameter packets | `TypeCheckParams`, `ModuleKeyRadixParams`, `PredicateKeyParams` | Uniform data copied into shaders. |
| Row views | `ScanRows`, `RadixRows`, `PredicateRows`, `MethodDeclRows` | Borrowed buffers grouped by relation role. |
| Constructor inputs | `NameInput`, `MethodKeyInput`, `PredicateInput` | Complete typed input sets for bind-group factories. |
| Bind-group carriers | `CallBindGroups`, `TypeInstanceBindGroups`, `PredicateBindGroups` | Retained bind groups recorded by pass-family helpers. |

Keep this layer mechanical. If a model starts deciding whether a program is
valid, the decision probably belongs in a shader pass, recorder ordering, or
host diagnostic mapping.

Important constants in `params.rs` are usually row-layout or pass-layout facts:

| Constant | Meaning |
| --- | --- |
| `CALL_PARAM_CACHE_STRIDE` | Words reserved per cached call-parameter row. |
| `TYPE_INSTANCE_ARG_REF_STRIDE` | Words reserved per type-instance argument-reference row. This is a row stride, not a semantic cap on generic arguments. |
| `GENERIC_CLAIM_CAPACITY_MULTIPLIER` | Scratch sizing multiplier for generic claim validation relative to call rows. |
| `NAME_RADIX_BUCKETS` | Byte-wise radix bucket count plus end-of-name bucket. |
| `NAME_RADIX_MAX_BYTES` | Maximum source bytes inspected for one compacted name key. |
| `MODULE_KEY_RADIX_STEPS`, `DECL_KEY_RADIX_STEPS`, `METHOD_KEY_RADIX_STEPS`, predicate key radix steps | Fixed byte-pass counts for sorting packed keys. |

If a constant is really a user-visible language bound, document the source
construct that can hit it and ensure exhaustion produces a diagnostic at that
construct. Otherwise, describe it as a storage, row, dispatch, or sort contract.
The shared policy for making or removing such bounds lives in
[Capacity and limits](capacity-and-limits.md).

## Recording Pipeline

`record_resident_token_buffer_with_hir_impl_on_gpu` is the main pipeline. It
records all type-check passes into an existing `wgpu::CommandEncoder`; it does
not submit the encoder.

The current shape is:

1. Write `TypeCheckParams`.
2. Initialize status to accepted with `status_init_bytes`.
3. Build the input fingerprint.
4. Select HIR-aware or token-only control/scope passes.
5. Build or reuse `ResidentTypeCheckState`.
6. Clear per-recording name maxima and build active HIR dispatch arguments.
7. Build loop depth and enclosing control context.
8. Materialize language names, user names, and builtin declarations.
9. Clear predicate syntax-token rows when predicates are present.
10. Record module/path/import/declaration discovery and resolution when module
    path state is present.
11. Clear and collect type instances.
12. Record generic parameter discovery, owner propagation, scans, and key
    sorts.
13. Project type aliases and type paths, collect projected type instances, then
    project again.
14. Project type instances from resolved module paths.
15. Scan and hash type-instance argument rows.
16. Build function context, calls, and visible declarations.
17. Resolve type-instance declaration references.
18. Collect method declarations and aggregate/member metadata.
19. Bind match patterns and match payload types.
20. Record lexical scope state.
21. Resolve calls and repeatedly match argument rows to parameter rows.
22. Mark method call keys, consume module value calls, build method key tables,
    and revisit call rows after module/method resolution.
23. Infer and validate array generics and erase generic parameter cache rows.
24. Consume enum calls, const paths, enum units, and match expressions.
25. Resolve methods finally, validate generic claims, and apply final call row
    arguments.
26. Build late array/member/struct/aggregate facts.
27. Collect and validate predicate facts, method contracts, and obligations.
28. Clear, mark, propagate, and validate return facts.
29. Validate condition types and aggregate compare arguments.
30. Validate control flow.
31. Copy the four-word status buffer to the readback buffer.

Several revisits are intentional. Type paths are projected before and after
alias/type-instance projection. Calls are revisited after plain resolution,
module value-call consumption, method key construction, method resolution, and
late module/method interactions. Do not collapse those passes unless the
replacement proves the same dependency ordering.

## Pass Families

The generated reference reports the exact pass and record-site counts. The
maintainer-level grouping is:

| Family | Produced data | Main consumers |
| --- | --- | --- |
| Active HIR dispatch | indirect dispatch counts and active HIR rows | most HIR-indexed passes |
| Loop and function context | loop depth, enclosing function, control/scope facts | returns, loop control, codegen metadata |
| Names and language decls | compact name ids, builtin symbols, primitive/intrinsic declarations | modules, calls, methods, predicates |
| Module paths | module ids, imports, declaration lookup tables, path ids, resolved type/value refs | type instances, calls, match patterns, codegen |
| Type instances and generics | type refs, generic params, arg rows, member/array/struct refs | calls, methods, predicates, backend lowering |
| Calls | function rows, parameter types, argument rows, generic/const claims | module value paths, methods, backend call metadata |
| Visible declarations | lexical/module visibility rows and scope tree | name lookup and backend metadata |
| Methods | method declarations, receiver metadata, method keys, method call resolution | calls, type instances, predicates |
| Predicates | trait/impl rows, method contracts, obligation pairs | method validation and semantic status |
| Returns | function/block return facts | return diagnostics and codegen assumptions |
| Conditions | condition expression facts and aggregate compare arguments | semantic status |
| Control | break/continue/function control validation | final type-check status |

Pass-family helpers in `record/*.rs` should stay at the family boundary. They
can own local repeated recording patterns, but cross-family ordering belongs in
`resident.rs` so a maintainer can audit the whole semantic pipeline in one
place.

## Module Path State

The module-path submodule owns the transition from parser item/path HIR to
module-aware semantic lookup. It is used only when parser item metadata is
available.

The state is built in these conceptual stages:

1. `RecordDiscovery` marks HIR records by family, extracts one family at a
   time, scans family flags, and scatters compact path/module/import/declaration
   rows.
2. Path segment passes count path segments, scan them, and scatter compact
   segment rows with name ids.
3. Module-index passes build module keys, sort them, validate duplicates,
   resolve imports, sort import edges, validate cycles, and build the file to
   module map.
4. Declaration passes sort declaration keys, validate declarations, mark
   namespace keys, and build public/import-visible lookup tables.
5. Path-resolution passes resolve local, imported, and qualified type/value
   paths.
6. Projection passes turn resolved paths into type refs, value-call facts,
   const facts, enum payload facts, and match payload bindings.

Put a new relation in module-path state only when it depends on modules,
imports, declarations, path ids, or source-file ownership. Name compaction, call
matching, predicates, and backend-specific facts have separate owners.

See [Module and source-root resolution](module-resolution.md) for the
cross-boundary model that connects CLI/package loading, source-pack metadata,
parser HIR, module-path state, and source-labeled diagnostics.

## Names And Language Declarations

The name family compactly identifies source lexemes and builtin symbols.

The usual order is:

1. Clear and materialize builtin language names.
2. Mark source lexemes that participate in type checking.
3. Count and scatter compact name rows.
4. Radix sort names by source bytes and kind.
5. Deduplicate adjacent equal names.
6. Assign stable name ids.
7. Materialize language declarations from builtin symbol slots.

`LANGUAGE_SYMBOL_BYTES`, `LANGUAGE_SYMBOL_STARTS`, and parallel declaration
tables define the current builtin names and declaration tags. `NAME_RADIX_MAX_BYTES`
is a fixed implementation bound on inspected name bytes. If normal code can hit
that in a way that changes semantics, the right fix is to remove or extend the
algorithmic bound, not to hide the behavior in diagnostics prose.

## Type Instances, Generics, And Type Aliases

The type-instance family converts parser type HIR into compact type-reference
and type-instance rows. It also records generic parameter metadata used by call
resolution and backend lowering.

Major responsibilities:

- Clear type-instance state for the current recording.
- Mark generic parameter records.
- Propagate generic declaration owners.
- Scan compact generic parameter rows.
- Sort generic parameter keys and slots.
- Resolve generic parameter uses.
- Collect scalar, named, aggregate reference, and aggregate detail type
  instances.
- Collect named type-argument references and hash argument rows.
- Resolve declaration refs for type instances.
- Build member, struct field, array index, array return, and aggregate access
  facts.

`TYPE_INSTANCE_ARG_REF_STRIDE` is a storage row width. It reserves four words
per compacted type-instance argument reference. It does not mean "four generic
arguments maximum."

Type aliases currently use a fixed host-side recording loop:
`TYPE_ALIAS_PROJECTION_PASSES` repeats `modules_project_type_aliases` eight
times. Each dispatch projects one alias hop across all alias records. This keeps
per-lane shader work bounded, but it is still a real convergence bound. If
valid library code can reasonably need deeper alias chains, this should become
a scan/range-query/worklist-style GPU relation or an error that points at the
alias/type syntax that exceeded the supported depth.

## Calls, Methods, And Argument Matching

The call family records function rows, parameter rows, call argument rows,
intrinsics, return refs, generic claims, const claims, and array-generic
validation.

Argument-to-parameter resolution is not a linear scan over all parameters in a
shader lane. The recorder uses `record_call_arg_param_matching_with_passes`,
which initializes row matches and then records logarithmic matching steps over
jump buffers. `record_call_arg_matching_and_collect_with_passes` runs that
matcher and then collects row-argument metadata. The main pipeline invokes this
helper multiple times as module and method information becomes available.

The method family is separate because methods need receiver facts and method
key tables:

- collect method declarations from HIR;
- attach receiver/name/module/visibility metadata;
- bind `self` receiver rows;
- sort and validate method keys;
- mark method call keys;
- resolve method table rows;
- resolve final method call results.

Module value-call projection and method resolution interact. When changing call
or method resolution, audit the revisits around:

- `modules_consume_value_calls`;
- `modules_mirror_value_call_leaf`;
- `methods_mark_call_keys`;
- method key table recording;
- method call resolution;
- final call row matching and generic claim validation.

## Predicates And Obligations

Predicate passes own trait/impl rows, method contracts, bound-argument facts,
and obligation validation.

The current family shape is:

1. Clear syntax-token and bound-argument scratch rows.
2. Collect bound-argument facts.
3. Collect method contracts.
4. Sort method-contract and method-parameter keys.
5. Collect predicate rows.
6. Emit, reduce, and apply method validation errors.
7. Sort owner and impl keys.
8. Count obligation pairs.
9. Scan obligation pairs and build indirect dispatch args.
10. Validate obligation pairs.

Predicate status must preserve a token or HIR-derived source location that
points to the user construct that created the missing, ambiguous, or invalid
obligation. Do not report a synthetic key row when the source-level trait,
impl, method, or call site is available.

## Returns, Conditions, And Control

These late families validate facts that depend on earlier type/call/function
relations.

Returns are recorded as clear, mark, `mark_if`, one ordered `mark_if`
propagation step, and validate. The extra propagation step exists so a direct
nested `if`/`else` can mark its enclosing block before an outer direct
`if`/`else` consumes it.

Conditions validate HIR condition facts and aggregate compare arguments. The
aggregate path counts rows, scans them, builds dispatch args, then validates the
argument rows indirectly.

Control validation consumes HIR/fact tables instead of rescanning whole-token
syntax. The recorder chooses between HIR-aware and token-only control/scope
passes through `uses_hir_control`.

## Status And Diagnostics

The main type-check status buffer has four `u32` words:

| Word | Meaning |
| --- | --- |
| `0` | accepted flag. Nonzero means success. |
| `1` | token or source-related index, carried on the host as `token`. |
| `2` | `GpuTypeCheckCode` numeric value. |
| `3` | status-specific detail payload. |

`status_init_bytes` initializes status to accepted. A rejecting shader writes a
zero accepted flag, a source-related index, a code, and optional detail.
`finish_recorded_check` maps the readback buffer, reads the four words, and
returns either `Ok(())` or `GpuTypeCheckError::Rejected`.

Host diagnostic mapping lives in
`crates/laniusc-compiler/src/compiler/gpu_compiler/typecheck.rs`. Single-source
and source-pack paths use different token-buffer wrappers so the same GPU
status can be labeled with the correct file path and span.

When adding or changing a rejection:

1. Pick the source token or HIR row closest to the user-visible cause.
2. Use an existing `GpuTypeCheckCode` only if the diagnostic class is genuinely
   the same.
3. Add a new code when the compiler should distinguish the error in diagnostics
   or tests.
4. Use `detail` only for data that improves the message or disambiguates a
   shared code.
5. Add or update host diagnostic mapping.
6. Add a smallest-source diagnostic test when the rejection is reachable from
   user code.
7. Regenerate or check `docs/compiler/generated/reference.md`.

Loop exhaustion or fixed-bound exhaustion must report the syntax that made the
bound visible to the user. A diagnostic at an internal row, dispatch arg, or
temporary sort key is not good enough.

## Retained Backend Metadata

The retained metadata wrappers are the ownership boundary between type checking
and backend recording:

| Wrapper | Purpose |
| --- | --- |
| `GpuCodegenBuffers<'a>` | Borrowed full semantic metadata view for GPU backend recording while resident state remains owned by the type checker. |
| `OwnedGpuCodegenBuffers` | Owned full semantic metadata after the resident cache is consumed. |
| `GpuX86CodegenBuffers<'a>` | Borrowed x86-specific subset. |
| `OwnedGpuX86CodegenBuffers` | Owned x86-specific subset after the resident cache is consumed. |

Use `with_codegen_buffers` or narrow `with_*_buffer` accessors when the backend
only needs a temporary borrow and the type-check cache should remain available.
Use `take_codegen_buffers` or `take_x86_codegen_buffers` when the backend must
own metadata after the resident cache is released. A successful take empties the
resident state.

If a backend needs a new semantic table, add it to the appropriate retained
wrapper and the `take_*` destructuring path. Do not reach through
`ResidentTypeCheckState` from backend code.

## Performance And Bounded Work

The type checker should prefer GPU-wide relation algorithms over per-item
source-shape loops:

- counted scans for compact row construction;
- radix sorts for packed keys;
- range or scope trees for visibility and lookup;
- indirect dispatch for counted work;
- jump-buffer or doubling steps for matching linked relations;
- fixed-size row layouts only when the stride is not a semantic limit.

Host-side loops that record a bounded number of GPU passes are acceptable when
the bound is tied to key width or a deliberate convergence contract. Examples
include radix byte passes, logarithmic matching steps, and the current eight
type-alias projection passes. Shader loops proportional to "number of children,"
"number of parameters," "number of generic arguments," or "number of path
segments" are usually the wrong shape unless they have a proven normal-case
bound and a source-located exhaustion diagnostic.

Known bounded mechanisms that deserve scrutiny when changing semantics:

- `TYPE_ALIAS_PROJECTION_PASSES = 8`;
- `NAME_RADIX_MAX_BYTES = 64`;
- module, declaration, import, visible, method, and predicate radix step counts;
- `GENERIC_CLAIM_CAPACITY_MULTIPLIER`;
- row strides such as `CALL_PARAM_CACHE_STRIDE` and
  `TYPE_INSTANCE_ARG_REF_STRIDE`;
- source-pack and work-queue page/inline-record caps outside this subsystem.

If normal library code can plausibly hit a bound, remove the bound with a
segmented scan, sort/range query, indirect dispatch, or logarithmic linked-list
matching approach. If the bound must remain, make the failure path explicit and
source-labeled. Use [Capacity and limits](capacity-and-limits.md) when deciding
whether the bound is storage shape, dispatch shape, or a real language limit.

## Changing The Type Checker

Use this checklist for a new relation, validation, or retained semantic table:

1. Decide which existing family owns the relation.
2. Define the row layout in Rust and Slang.
3. Allocate storage in `ResidentTypeCheckState` or prove supplied external
   scratch is dead and safe to reuse.
4. Add typed bind models or parameter packets only as mechanical layout mirrors.
5. Include every bind-group-affecting buffer identity in the resident
   fingerprint.
6. Load the shader in `type_checker/pass_loaders.rs`.
7. Create bind groups in the owner bind-group factory.
8. Record the pass in dependency order.
9. Expose data to codegen only through retained metadata wrappers.
10. Add status codes and diagnostic mapping if user code can be rejected.
11. Add the smallest focused test or generated-reference check that proves the
    contract.
12. Update hand-written docs when ownership, pass order, diagnostics, or
    retained metadata changes.

The owner is the first phase that has enough stable data to define the
relation. Do not move semantic policy into the parser merely because parser HIR
construction already sees the syntax.

## Common Mistakes

Avoid these changes:

- Adding a raw `wgpu::Buffer` to a bind group without adding it to the resident
  fingerprint.
- Treating a row stride as a language limit.
- Reusing parser or lexer scratch without proving the previous phase has
  finished and released ownership.
- Adding backend access to `ResidentTypeCheckState` instead of a retained
  wrapper.
- Collapsing repeated call/module/method revisits because the pass names look
  redundant.
- Reporting a diagnostic at a compact row or generated key when a source token
  is available.
- Hiding a normal-program bound behind an internal `BadHir` or `Unknown` error.
- Adding host-side special cases for one input file instead of fixing the
  relation that failed.

## Evidence To Update

After changing this subsystem, choose the narrowest evidence that covers the
change:

- `tools/compiler_inventory.py --check docs/compiler/generated/reference.md`
  when pass loaders, record sites, status codes, public operation signatures,
  large structs, or buffer carriers changed.
- A diagnostic test with the smallest source that reaches a new or changed
  rejection.
- A focused compiler/type-check test when semantic behavior changed without a
  new diagnostic class.
- A shader-loop or generated-reference audit when changing bounds, row strides,
  radix passes, projection passes, or matching algorithms.
- A backend test when retained metadata or `take_*`/`with_*` wrappers changed.

Docs-only edits do not require compiler tests, but they should still pass the
generated-reference freshness check and a Markdown link check.
