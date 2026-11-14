# Program retention

Program retention prototypes the first cross-unit boundary of the GPU
instantiation engine (`docs/compiler-gpu-instantiation-design.md` §1–3). One build store
lives for one build. Each frontend semantic job exports its declarations,
generic parameters, symbolic and closed terms, binder maps, signatures,
nominal schemas, call uses and generic body segments into the store. The
export runs at the end of the job, before the job's workspace can be reused.
The acceptance probe reads only the store. Discovery, projection and native
instance lowering are not connected yet; the missing exports below prevent
this prototype from supplying those stages correctly.

| Part | Location |
| --- | --- |
| Store records and interning | `shaders/type_checker/retention/retention_store.slang` |
| Job-side translation | `shaders/type_checker/retention/retention_job.slang` |
| Export kernels | `shaders/type_checker/retention/export/00_begin` … `18_rollback` |
| Store growth | `shaders/type_checker/retention/store_rehash.slang` |
| Substitution over retained terms | `shaders/type_checker/retention/retention_subst.slang` |
| Host object | `crates/laniusc-compiler/src/type_checker/program_retention.rs` |
| Acceptance probe | `shaders/tests/retention_resolve.slang`, `tests/program_retention.rs` |

## Lifetime and integration

- `ProgramRetention::new(capacity)` allocates the store on the global GPU.
  `begin_build` starts a build in the same allocations. It clears the
  counters and the three hash tables and nothing else. Arena contents past
  a counter are dead and are never read, so nothing carries over from one
  build to the next.
- `GpuCompiler::attach_program_retention(Some(store))` attaches the store.
  Recording captures that store once for the job, so later attachment changes
  affect only subsequent recordings. The captured store adds `program_retention` to its resident cache key,
  so an interface job's graph keeps every table the export reads
  (`RETAINED_PROGRAM_INPUTS`) alive until the graph's end. It uses the same
  consumer-contract mechanism as the generic-call readback
  (`retain_resources_imported_by`).
- `finish_checked_source_pack_pipeline` calls `ProgramRetention::export_job`
  after the type-check status is accepted and all lowering-output retry points
  have passed. Only interface jobs export, and an export checks that its
  workspace actually retained the input lifetimes.
  The export's inputs are the parser's compact HIR views and the resident
  type-check graph's tables, bound by name.
- A job with a body-specialization split re-runs the substitution clear
  after its main inference, which resets `call_env_ct`. With a store
  attached, the type checker first copies `call_env_ct` into a
  retention-owned snapshot. The export reads that copy, which belongs to
  that job only. The canonical tables are not cleared, so the copied IDs
  stay valid.
- A checked local call names its callee by the function's first token
  (`target_token`). Step 02 builds a job-scratch map from function start
  token to row, so the callee resolves to its `DeclId`.
- Job-local interning (`ct_*`, `call_env_ct`) is unchanged. The export only
  reads it, and the store keeps its own typed adapter (`translate_ref`).

## Identities

Every handle is 1-based. Index 0 is never a valid handle.

| Handle | Record | Key (compared in full; the hash only picks the first probe) |
| --- | --- | --- |
| `DeclId` | `rt_decl_key` uint4 | `(library, unit, namespace, local)` |
| `ParamId` | `rt_param_key` uint4 | `(owner DeclId, domain, ordinal)`; `.w` is the declared scalar of a constant parameter, which is metadata and not part of the key |
| `TermId` | `rt_term_head` uint4 | `(kind \| arity << 8 \| type_slots << 16, w0, w1, w2)` plus its arguments |

Declaration namespaces and their local words:

- **`CALLABLE` (1).** The native callable identity
  (`callable_identity.slang`). It is the public index, or
  `0x80000000 | method row` for a public impl method or a required trait
  member, or `0x40000000 | token` otherwise. A dependency call names a
  callable with the same triple, so a caller and a definition in different
  jobs meet at one `DeclId`.
- **`NOMINAL` (2) and `TRAIT` (3).** The canonical store's nominal identity:
  the persisted interface index, or `CT_PRIVATE_LOCAL_BIT | decl id`.
- **`IMPL` (4).** The impl's HIR row, which the declaring job's
  `(library, unit)` qualifies.

A parameter's ordinal counts the declarations of its kind in its owner. A
trait's implicit `Self` is `(trait, TYPE, 0xffff)`. A parameter keeps its
declaring owner, so an inherited impl parameter and a shadowing method
parameter with the same spelling are different `ParamId`s.

Term kinds follow the canonical store, with declaration words replaced:

| Kind | Words | Arguments |
| --- | --- | --- |
| `NAMED` 2 | `(DeclId, constant-operand mask, 0)` | the operands |
| `ARRAY` 3 | `0` | `(element, length)` |
| `SLICE` 4, `REF` 5 | `0` | `(element)` |
| `CC_VALUE` 8 | `(scalar, lo, hi)` | none |
| `CC_CAST` 9 | `(target scalar, 0, 0)` | `(child)` |
| `CC_COUNT` 10 | `(count, 0, 0)` | none |
| `ENV` 16 | `(owner DeclId or 0, type mask, constant mask)` | the bound type slots, then the bound constant slots |

`CC_CAST` is kept as a pending fit even when its count class equals the
child's. A term reference is one of:

- a `TermId` (scalars 1..31 are preseeded and have no record);
- a parameter leaf, `0x80000000 | [0x40000000 for a constant] | ParamId`;
- a dependency-signature slot leaf, which keeps the canonical encoding;
- a sentinel: `RT_UNKNOWN`, `RT_NONE` or `RT_FIT_FAILED` (0xfffffffc, the
  canonical `CT_FIT_FAILED`). A sentinel is never a resolved term.

A term record also stores its height, its flags and a structural hash. The
hash covers declaration keys, never IDs, so it is the same in every job.
Each record also keeps an owner summary: up to two distinct owner
`DeclId`s of its parameter leaves, or "many".

Interning is the canonical store's lock-free protocol. A lane writes the
complete record, fences, then publishes it with a CAS on an empty slot. A
lane that loses the race to an equal key leaves a tombstoned spare, counted
in `RT_C_SPARE`. Equality always compares the complete record.
`rt_config[0]` masks the hash, and mask 0 forces every key onto one probe
chain.

## Discovery records (resident)

Directory entry, `rt_dir`, 4 × uint4:

| Word | Contents |
| --- | --- |
| d0 | `(DeclId, kind, parent DeclId or 0, STAGED 1 / COMMITTED 2)` |
| d1 | `(binder start, type count \| const count << 16, signature start, parameter count)` |
| d2 | `(segment or INVALID, schema start, schema count, use start)` |
| d3 | `(use count, file id, committed-job ordinal, INCOMPLETE flag)` |

Declaration kinds are `FREE_FN 1`, `METHOD 2`, `REQUIRED_MEMBER 3`,
`EXTERN_FN 4`, `STRUCT 5`, `ENUM 6`, `IMPL 7` and `TRAIT 8`.
`rt_decl_def[DeclId]` holds the committed entry plus one. A second
committed definition of the same declaration is counted in
`RT_C_CONFLICTS`.

- **Binders, `rt_binders`.** `ParamId`s in composed slot order. The impl's
  type parameters come before the method's, then the impl's constant
  parameters before the method's. Unused parameters are included. A trait
  and its required members end the type domain with `Self`.
- **Signatures, `rt_sigs`.** The result term, then one term per parameter.
- **Schema, `rt_schema`.** One uint4 per struct field or enum variant
  payload: `(nominal DeclId, FIELD 1 / PAYLOAD 2 | ordinal << 8, variant
  ordinal, declared term)`.
- **Uses, `rt_uses`.** 3 × uint4, one per call row inside a function:
  - u0 `(owner DeclId, call row relative to the owner, form | adjustment <<
    8 | deref count << 16, callee DeclId or 0)`. Forms are `DIRECT 1`,
    `METHOD 2`, `CONSTRUCTOR 4`, `INTRINSIC 5`, `HOST 6` and
    `UNRESOLVED 7`. A local callee is its declaration key, a dependency
    callee its `(library, unit, CALLABLE, local)` triple, and an enum
    constructor its enum's `DeclId`.
  - u1 `(environment, result, matched receiver, receiver parameter)`. The
    environment is the call's value environment with owner 0 re-keyed to the
    callee. A nonzero owner must already match the callee; a mismatch raises
    an invariant and marks the containing entry incomplete. Its arguments are terms in the caller's scope: they must
    be owned by the caller's binder chain, and a consumer substitutes the
    caller's environment into them before binding the callee's slots.
  - u2 `(variant ordinal or intrinsic tag, a dependency callee's generic
    requirements, file id, callee token relative to the owner)`.

## Body payloads (streamable)

Discovery records reach body payloads only through a segment index and the
ranges a segment names. Bodies can therefore be paged out and in without
touching discovery records.

A segment, `rt_segments`, is 4 × uint4:

| Word | Contents |
| --- | --- |
| s0 | `(DeclId, first row, row count, first side record)` |
| s1 | lengths of side tables 0–3 |
| s2 | lengths of side tables 4–6, the token span |
| s3 | statistics `(untyped, foreign, ownership, untranslated)` |

A row, `rt_seg_rows`, is 5 × uint4:

| Word | Contents |
| --- | --- |
| r0 | `(kind, parent, token start, token end)` |
| r1 | `(first child, next sibling, subtree end, file id)` |
| r2 | the payload, with the same column classes as `closure/09_exec_rows.slang` |
| r3 | `(type term, use index within the body or RT_NONE, 0, TYPED 1 \| FOREIGN 2)` |
| r4 | `(return-type row, constant-value row, array-element start, array-element count)` |

Side records, `rt_seg_side`, are 2 × uint4 per side row. The seven tables
come in order: call arguments, fields, match arms, match payloads, array
elements, strings and parameters. The first uint4 is the table record. The
second holds the extras: a field's struct-init ordinal, a match arm's
payload start and count, or a parameter's declared term. A string's
decoded bytes are copied into `rt_seg_bytes`, and its record holds that
word base.

Reference domains inside a body:

- **Row references** are relative to the function row. A subtree end may
  equal the row count.
- **Token references** are relative to the function's first token.
- **Side-table indices** are relative to the body's block of that table.
- **Statement and expression context words** keep their STMT bit, with the
  id relative to the body.
- **A reference outside the body** becomes `0xc0000000`. It is counted in
  the segment's `foreign` statistic and marks its directory entry
  `INCOMPLETE`.
- **Terms** are store references. A term whose leaf is outside its record's
  binder chain is counted in `ownership` and raises `RT_INV_OWNERSHIP`.
  The binder chain is the function and its container for a body, a
  signature or a schema, and the caller for a use.

## Transactions and growth

1. Step 00 records every arena counter as the job's watermark.
2. Steps 01–15 intern and write records. An allocation past a capacity
   records the overflow bit and the demand.
3. Step 16 commits when nothing overflowed. Otherwise it restores every
   counter and spare counter to the watermark.
4. Step 17 publishes the job's staged directory entries.
5. Step 18 clears every hash slot that points at a record allocated by a
   rolled-back job. Linear probing stays sound, because no older probe chain
   crosses a slot that a later key filled.

No partial or duplicated record of a failed job stays reachable. Then:

1. The host reads `rt_counts`.
2. It grows each overflowed arena to twice its demand, and keeps each slot
   table at least twice its arena.
3. It copies the old arena buffers into the larger buffers. The restored
   counters delimit the committed prefixes; bytes beyond them stay unreachable.
4. `store_rehash` republishes every live record. Tombstones are skipped.
5. The host runs the export again over the same job tables.

Invariant failures do not roll a job back. The current job reports
`RT_C_INVARIANTS`, `RT_C_FIRST_INVARIANT` and `RT_C_INCOMPLETE`.
Commit accumulates the invariant and incomplete-entry totals across the
build; conflicts found during publication update those totals too. Any such
failure clears `RT_C_READY` until `begin_build`. A duplicate definition may
leave a scheduling-dependent pointer, but the conflicting build cannot be
consumed by the probe or an admitted consumer.

`export_job` returns a `JobReport` with that readiness bit and retains it in
`job_reports()`. A successful transaction alone does not certify completeness.
This bit checks the current exported schema; it is not code-generation
admission and does not certify the missing fields listed below. Tests check
every job's report, resolved expected types and each callee's incomplete flag.

## Work distribution

All semantic work runs on the GPU. The host allocates buffers, clears job
scratch, submits one command buffer per attempt and reads the 96 status
words and 256 scratch words.

The export records 177 dispatches per attempt: 21 kernels, including 79
translation/advance pairs and the three scan kernels. Empty translation
heights dispatch no translation workgroups, but their advance dispatches
still run. This boundary has not yet been timed on settings.

| Step | Lanes | Work |
| --- | --- | --- |
| 00, 04, 07, 09, 16 | 1 lane | transaction, plans and reservations |
| 01 | one per generic parameter | `ParamId` interning and the job's parameter map |
| 02 | one per HIR row | `DeclId` interning, trait `Self`, scan flags, token spans |
| 03, 05 | one per canonical record | height buckets |
| 06 | one per record of the current height, 79 indirect rounds | children are always translated first |
| 08 | uint4 prefix scan over rows | row counts, use counts, directory counts and segment counts together |
| 10 | one per declaration | directory, binders, signature, schema, segment |
| 11 | one per body row | segment rows |
| 12 | one per side index × 7 tables | side records |
| 13 | one per parameter, field and variant payload | signatures and schema |
| 14 | one per call | use records |
| 15 | one per declaration | statistics |
| 17 | one per staged entry | publish |
| 18 | one per hash slot | rollback |

Substitution (`retention_subst.slang`) resolves a parameter leaf by its
`ParamId` through the callee's committed binder map. It walks terms in
post-order on a global-memory stack, so it uses no per-thread arrays.
It rejects incomplete/uncommitted entries, a foreign environment owner,
inconsistent mask/arity counts and domains exceeding the 32-slot masks.
Unresolved references return `RT_SUBST_UNRESOLVED`; failed projections retain
`RT_SUBST_FIT_FAILED`. Neither can compare as a successfully substituted type.
This is a probe implementation: it visits shared terms as a tree without a
memo. Production instance substitution still needs bounded work over the DAG.

## Not exported completely

This boundary does not yet carry:

- **Resolved bindings and checked body facts.** Local/parameter declarations,
  member field ordinals, constant values/presence, argument modes and iterable
  kinds must be retained from the semantic columns. Token text is insufficient
  to reconstruct these checks. Type-annotation rows also need their checked
  type terms, and missing required terms must mark the entry incomplete.
- **Complete declaration and use records.** Enum variants without payloads,
  const/static declarations, impl self types and trait headers, and use
  environments on struct-literal and path rows are not completely represented.

- **Token text and source locations.** Body tokens are relative indices
  only, and no token byte table or original body token base is retained.
  File IDs are job-local. Export must retain the source mapping before the
  frontend is released; projection cannot recover it from these segments.
  Identifiers and diagnostics need these inputs.
- **Expression-parent, expression-root and nearest-loop columns.** The
  receiver must rebuild them from the relative tree.
- **Aggregate, native-width and ABI caches** (`type_native_word_count`,
  layout words). These belong to projection.
- **Function-entry and call-target lowering facts.** Uses carry semantic
  callee identity only.
- **Dependency callee bodies.** A body that a job consumed through a
  dependency interface is exported by its defining job, not by its caller.
  A dependency-signature slot leaf in a caller's term stays a slot leaf
  until discovery maps the dependency's binder.
- **Nongeneric bodies.** They lower in their own job and keep no segment.
  Their uses are exported, as discovery roots.
- **Bound-member calls.** Their trait-solver evidence is not exported yet.
  The use records the trait member's `DeclId` and the caller-scoped
  environment.
- **Constant fits.** `CC_CAST` terms are retained. Retained substitution
  does not yet evaluate fits. When it does, it must return the failing
  projection from the substitution itself.

## Dependencies for discovery and projection

- The frontend export must preserve symbolic columns before in-place body
  specialization. Copying only `call_env_ct` leaves the other columns with
  potentially concrete types. This producer fix remains outstanding.

- A row's type term is whatever the checker publishes for that row. A
  contextual literal inside a generic body (the `1` in `a + 1` with
  `a: T`) needs its symbolic expected type. The literal/operator producer
  boundary has to publish that type as a term over the body's parameters.
  Retention then exports it like any other term, and instantiation resolves
  the literal's type, range and payload per instance before operand
  validation. The literal's kind, magnitude words and float words are
  already retained, unchanged, in the row payload.

- Discovery needs the trait solver's implementation evidence as store
  records (`IMPL` declarations, their trait arguments and the receiver
  plan) to select bound-member callees.
- A dependency-signature slot leaf has to map to the dependency's committed
  binder entry. The dependency interface's slot order has to match the
  composed binder order above (impl before method per domain, then `Self`).
- Projection needs the token-text and layout tables listed above, or an
  equivalent GPU-side recomputation from the segment.
