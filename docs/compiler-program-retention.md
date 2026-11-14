# Program retention

Program retention prototypes the first cross-unit boundary of the GPU
instantiation engine (`docs/compiler-gpu-instantiation-design.md` §1–3). One build store
lives for one build. Each frontend semantic job exports its declarations,
generic parameters, symbolic and closed terms, binder maps, signatures,
nominal schemas, call uses and generic body segments into the store. The
export runs at the end of the job, before the job's workspace can be reused.
The acceptance probe reads only the store. Discovery, projection and native
instance lowering are not connected yet. General compiler integration stays
off until each of them exists. The inputs projection still needs are listed
under "Not exported completely".

| Part | Location |
| --- | --- |
| Store records and interning | `shaders/type_checker/retention/retention_store.slang` |
| Job-side translation | `shaders/type_checker/retention/retention_job.slang` |
| Export kernels | `shaders/type_checker/retention/export/00_begin` … `18_rollback` |
| Store growth | `shaders/type_checker/retention/store_rehash.slang` |
| Substitution over retained terms (probe) | `shaders/type_checker/retention/retention_subst.slang` |
| Production substitution | `shaders/type_checker/retention/substitution/`, [guide](compiler-retained-substitution.md) |
| Host object | `crates/laniusc-compiler/src/type_checker/program_retention.rs` |
| Acceptance probe | `shaders/tests/retention_resolve.slang`, `tests/program_retention.rs` |

## Lifetime and integration

- `ProgramRetention::new(capacity)` allocates the store on the global GPU.
  `begin_build` starts a build in the same allocations. It clears the
  counters and the three hash tables and nothing else. Arena contents past
  a counter are dead and are never read, so nothing carries over from one
  build to the next.
- Each `begin_build` takes a new build generation, nonzero and unique over
  every build of every store in the process, and writes it to
  `rt_counts[RT_C_GENERATION]` (word 78; `ProgramRetention::generation`).
  Growth copies it with the counters. A derived GPU publication records the
  generation it was computed in, and its consumer compares the two
  ([retained substitution](compiler-retained-substitution.md)).
- `GpuCompiler::attach_program_retention(Some(store))` attaches the store.
  Recording captures that store once for the job, so later attachment changes
  affect only subsequent recordings. The captured store adds `program_retention` to its resident cache key,
  so an interface job's graph keeps every table the export reads
  (`RETAINED_PROGRAM_INPUTS`) alive until the graph's end. It uses the same
  consumer-contract mechanism as the generic-call readback
  (`retain_resources_imported_by`).
- When the job's type check has been recorded, and before the semantic
  interface and lowering are recorded, `ProgramRetention::record_job_snapshot`
  copies every job table an export kernel binds into store-owned buffers. The
  tables are the parser's compact HIR views, the retained type-check columns,
  the call-environment copy and the lexer's tokens, source bytes and file
  starts. Each table gets its own buffer, taken from a pool that finished jobs
  return to. The copies freeze the frontend's semantic inputs. Lowering may
  reuse type-check arenas, and two tables that share one arena cannot be
  bound read-write (`canonical_api` declares `ct_*` writable) and read-only in
  one dispatch.
- `finish_checked_source_pack_pipeline` calls `ProgramRetention::export_job`
  on that snapshot after the type-check status is accepted and all
  lowering-output retry points have passed. An attempt abandoned for an
  output retry drops its snapshot and exports nothing; the retried job takes
  its own. Only original interface jobs export. Explicit body-specialization
  and authorized-replay jobs never capture the store, even when they request
  interface storage. They keep their normal specialization policy and cannot
  publish duplicate or concrete definitions into the template store. An export
  checks that its workspace actually retained the input lifetimes.
  `physical_gpu_retention_exports_once_after_native_output_retry` covers a
  warm native export and a forced capacity retry, for an executable and for
  an object.
- On a retained original job, body specialization selects no generic body in
  place (`closure.record_inplace_select` is skipped). The late semantic
  artifact passes write `semantic_*_by_hir` after specialization, so a
  snapshot taken earlier would miss them, and a body specialized in place
  would leave concrete and symbolic facts mixed. Every retained generic body
  is therefore the template: `solo<V>`, called only at i32 in its own job,
  instantiates at bool from the store after the frontend is released.
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
- **`NOMINAL` (2).** Structs, enums and traits. The canonical store's nominal
  identity: the persisted interface index, or `CT_PRIVATE_LOCAL_BIT | decl
  id`. Namespace 3 is unused.
- **`IMPL` (4).** The impl's HIR row, which the declaring job's
  `(library, unit)` qualifies.
- **`VALUE` (5).** A constant: its public interface index, or
  `0x40000000 | first token`.

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
`EXTERN_FN 4`, `STRUCT 5`, `ENUM 6`, `IMPL 7`, `TRAIT 8` and `CONST 9`.
`d1.w` is the parameter count of a callable, the field count of a struct,
the variant count of an enum and 1 for an impl.
`rt_decl_def[DeclId]` holds the committed entry plus one. A second
committed definition of the same declaration is counted in
`RT_C_CONFLICTS`.

- **Binders, `rt_binders`.** `ParamId`s in composed slot order. The impl's
  type parameters come before the method's, then the impl's constant
  parameters before the method's. Unused parameters are included. A trait
  and its required members end the type domain with `Self`.
- **Signatures, `rt_sigs`.** For a callable, the result term, then one term
  per parameter. For an impl, the self type, then the trait term or
  `RT_NONE`. For a constant, its type term. The checker publishes no type
  for a trait reference row, so step 10 writes `RT_UNKNOWN` for a trait
  impl's trait term and step 14d replaces it with the term built from the
  accepted trait reference (see "Trait facts"). A required member's
  `self` or `&self` parameter has no checked type row; step 13 writes the
  trait's `Self` leaf, or `REF` of it, from the accepted receiver mode.
- **Schema, `rt_schema`.** One uint4 per record:
  - `FIELD 1`: `(struct, FIELD | ordinal << 8, 0, declared term)`.
  - `VARIANT 3`: `(enum, VARIANT | ordinal << 8, payload count, first
    payload record relative to the block)`. Every variant has one,
    including a payloadless variant. An enum's variants come first.
  - `PAYLOAD 2`: `(enum, PAYLOAD | ordinal << 8, variant ordinal, declared
    term)`, after the variants.
  - `CONST 4`: `(constant, CONST | concrete << 8, value lo, value hi)`.
    `concrete` is 0 or 1. The value comes from the folded initializer;
    a missing concrete value makes the declaration incomplete.
- **Uses, `rt_uses`.** 3 × uint4, one per call row inside a function:
  - u0 `(owner DeclId, use row relative to the owner, form | adjustment <<
    8 | deref count << 16, callee DeclId or 0)`. Forms are `DIRECT 1`,
    `METHOD 2`, `RECORD 3` (a struct literal; the callee is the struct),
    `CONSTRUCTOR 4` (a payload constructor call or a variant value, including
    an imported unit variant), `INTRINSIC 5`, `HOST 6`, `UNRESOLVED 7` and
    `FN_REF 8` (a function named as a value). A local callee is its
    declaration key, a dependency callee its `(library, unit, CALLABLE,
    local)` triple, and a constructor its enum's `DeclId`. Use rows are call
    rows, struct literals, and path or name rows outside callee position that
    name a variant or a function. A match pattern is never a use: `Ok(_)`
    matches a value and constructs none, so it is no discovery root. A use
    without a call has no environment and records its row's term as its
    result. A call whose artifact publishes no result (a unit method
    statement, `assert`) records its row's checked expression type: unit,
    never (`-> !`) or a value type. A result is never defaulted.
  - u1 `(environment, result, matched receiver, receiver parameter)`. The
    environment is the call's value environment with owner 0 re-keyed to the
    callee. A nonzero owner must already match the callee; a mismatch raises
    an invariant and marks the containing entry incomplete. Its arguments are terms in the caller's scope: they must
    be owned by the caller's binder chain, and a consumer substitutes the
    caller's environment into them before binding the callee's slots. All
    four terms are in the caller's scope and are owned by its binder chain.
    The receiver parameter is the receiver plan the method selector
    accepted (`methods/08_finalize_candidates.slang`), built from the
    caller's checked receiver for every callee kind (local, dependency,
    bound trait member). With adjustment 1 it is the matched receiver
    itself. With adjustment 2 it is `REF(matched)`: the last dereferenced
    reference or a fresh `&matched`. Any other shape raises
    `RT_INV_RECEIVER_SCOPE` and marks the caller incomplete. The callee's
    declared receiver is its own signature's `self` parameter.
  - u2 `(variant ordinal or intrinsic tag, a dependency callee's generic
    requirements, file id, callee token relative to the owner)`.

## Trait facts (resident)

Each job exports the predicates and trait-impl method bindings its
predicate and method validators accepted (`shaders/type_checker/predicates`,
steps 14b–14d). These are the inputs `FrozenCatalog::freeze` rebuilds on the
host from `CheckedUnitContracts`. They are a producer boundary for the GPU
trait solver: nothing here selects an implementation, proves an
obligation or certifies a route.

`rt_dir_trait` is a column of the directory, one uint4 per entry:
`(first predicate record, predicate count, first binding record, binding
count)`. Every entry has one; an entry without facts has counts 0.

`rt_traits` (arena `RT_A_TRAITS` 14) holds 2 × uint4 per record:

| Kind | t0 | t1 |
| --- | --- | --- |
| `PREDICATE 1` | `(owner DeclId, PREDICATE \| ordinal << 8, subject term, trait term)` | `(trait DeclId, file id, file-relative byte start of the trait name/path, byte length)` |
| `BINDING 2` | `(impl DeclId, BINDING \| receiver mode << 8 \| ordinal << 16, required member DeclId, method DeclId)` | `(trait DeclId, required member symbol, file id, file-relative byte start of the method name)` |

- **Owners.** A predicate's owner is the function or impl that declares
  it; inherited predicates stay on their declaring owner, and the
  directory's parent chain reaches them. An impl's prerequisites are its
  own predicate block. The block is in source order of the bounds;
  `ordinal` is the rank inside it.
- **Subjects.** A type parameter leaf, resolved by the parameter's
  declaration token, so a method parameter that shadows its impl's has its
  own `ParamId`; or a scalar `TermId` (`where bool: Pair<T>`).
- **Trait terms.** `NAMED (trait DeclId, constant-operand mask)` over the
  bound's checked argument roots, with the type-slot count and mask the
  canonical store gives a NAMED term. Equal applications intern to the
  impl header's trait term. Constants nested inside type arguments, such
  as `Pair<[i32; N]>`, keep their terms and declared scalars. This does not
  establish support for constant parameters on traits themselves: imported
  constant-generic traits are rejected, and the local predicate validator
  counts only type parameters. Program catalog admission must check the
  complete defining binder before accepting an application.
- **Trait identity.** A local trait is its declaration's `DeclId`; an
  imported one is the defining unit's nominal key, `(library, unit,
  NOMINAL, interface index)`, the key that unit's export gives it. Private
  traits are qualified by their unit.
- **Bindings.** One per method of a trait impl. The required member is
  `(trait library, trait unit, CALLABLE, interface member symbol)`, the
  defining unit's `REQUIRED_MEMBER` entry; the method is its own `DeclId`,
  whose local word must equal the native symbol the semantic artifact
  published for it. A local trait's member must be that trait's row.
  Receiver modes are `NONE 0`, `SELF 1`, `REF_SELF 2` and `EXPLICIT 3`.
  An impl's head (self type, trait term) is its signature block.

Step 14d checks every fact against its producers: predicate status and
owner, the ordered argument rows, the subject token, the trait
reference, the impl header's status and canonical trait-node shape, the trait term's
`DeclId` against the trait reference, method validation status, the
required symbol and the native symbol, and that an impl binds as many
members as its trait requires. A failure raises `RT_INV_TRAIT_FACT` (10),
`RT_INV_TRAIT_ORDER` (11, an owner's facts are not one source-ordered
block) or `RT_INV_TRAIT_IDENTITY` (12) and marks the owner's entry
incomplete, so the build is not ready. A predicate whose owner has no
directory entry raises 10 without a record.

The checker resolves a trait impl from the canonical `payload.b` row; the
export uses that same row. Its copied predicate column is not independent
evidence of identity. Argument counts must agree with the canonical range,
including zero. Predicate diagnostics span the trait name/path through the
accepted name token, excluding type arguments and following delimiters.

Before solver admission, the program consumer must also resolve imported
trait and required-member keys to committed entries, check their kinds and
parent identities, verify the complete defining binder's arity, and check
distinct method bindings. Export currently checks local member identity and
producer counts; the cross-unit checks below run only in the test probe.

`shaders/tests/retention_traits.slang` validates the facts from the store
alone, per entry: exact owners and ordinals, subjects in the entry's binder
map, trait terms over a committed `TRAIT` with matching arity, argument
leaves inside the owner's chain, required members committed as
`REQUIRED_MEMBER`s of the impl's trait, methods committed as `METHOD`s of
the impl whose binder maps start with the impl's, distinct members and one
binding per required member. `tests/program_retention_traits.rs` runs it
after releasing the frontend and poisoning the exporter's scratch.

## Body payloads (streamable)

Discovery records reach body payloads only through a segment index and the
ranges a segment names. Bodies can therefore be paged out and in without
touching discovery records.

A segment, `rt_segments`, is 6 × uint4:

| Word | Contents |
| --- | --- |
| s0 | `(DeclId, first row, row count, first side record)` |
| s1 | lengths of side tables 0–3 |
| s2 | lengths of side tables 4–6, token count |
| s3 | statistics `(untyped, foreign, ownership, untranslated)` |
| s4 | `(file id, file-relative byte start, text length, first token record)` |
| s5 | `(first text word in rt_seg_bytes, 0, 0, 0)` |

The body text is the source from the body's first token to its last
token's end, copied into `rt_seg_bytes` by one lane per token (steps 12b,
12c). Each lane walks its token and the gap before the next token; long
comments can therefore leave one lane with substantial serial work.
Its token records, `rt_seg_tokens`, are one uint4 per token: `(kind, byte
start relative to the text, length, FNV-1a hash of the spelling)`.

A row, `rt_seg_rows`, is 7 × uint4:

| Word | Contents |
| --- | --- |
| r0 | `(kind, parent, token start, token end)` |
| r1 | `(first child, next sibling, subtree end, file id)` |
| r2 | the payload, each word encoded by its class (`row_classes.slang`, which mirrors `closure/09_exec_rows.slang`) |
| r3 | `(term, use index within the body or RT_NONE, role, TYPED 1 \| FOREIGN 2 \| MISSING 4)` |
| r4 | `(return-type row, constant-value row, array-element start, array-element count)` |
| r5 | `(binding kind, binding value, binding aux, member field ordinal)` |
| r6 | `(argument mode \| iterable kind << 8, constant flags, value lo, value hi)` |

Row terms and roles:

- A TYPE row's term is its checked type (`type_row_term`). An array length
  row in type position (`N` in `[i32; N]`) takes its array term's length
  operand.
- Expression rows and let/const statements take their checked expression
  reference. Other rows (function, parameter, block and the remaining
  statements) carry the per-row scalar cache in that column, which is not a
  type, so their term is `RT_NONE`.
- Roles are `STRUCTURAL 0`, `VALUE 1`, `TYPE 2`, `CALLEE 3`, `BOUND 4`
  and `PATTERN 5`. A callee row is marked by its call (step 01b), because
  its HIR parent need not be the call. A VALUE or TYPE row without a
  resolved term is `MISSING`, is counted `untyped` and marks its entry
  `INCOMPLETE`. BOUND, PATTERN and CALLEE rows denote no value.
- A BOUND row is a TYPE row whose semantic kind is a bound path or bound
  reference. It has no checked type; its facts are its predicate record.
  Its r3.y is that predicate's ordinal in the function's predicate block
  (step 14e), so the record is `rt_traits[rt_dir_trait[entry].x + r3.y]`
  and the record's ordinal equals r3.y. A bound reference and the path
  inside it name the same predicate. (The frontend currently rejects a
  `&Trait` bound head.)
- A PATTERN row is a match arm's or payload's pattern that names an enum
  variant (`Ok(_)`, `None`, `Error::Busy`), or the wildcard `_` (one token
  spelled `_`). A variant's identity is its binding (r5). The row keeps
  its checked term when the checker publishes one and needs none. The
  matched type is the scrutinee's term. Named payload binders (`inner`)
  and literal patterns stay VALUE rows with their types.
- A variant constructor's callee (`Wrap::Value` in `Wrap::Value(e)`) keeps
  no term. The checker types that row with the enum's declared self
  application over the enum's own parameters, which is a schema fact. The
  caller-scoped instance is the call row's term and its use's result. The
  export still checks that the producer's term is owned by the enum or by
  the caller.
- A match or `value?` whose type is a parameter of the body (`Ok(inner) ->
  inner, Err(_) -> panic()` at `T`) has that parameter's leaf as its term
  (`semantic/artifact/01_expression_refs.slang` publishes the joined arm
  type of `modules/10n_type_match_exprs.slang`).
- Binding kinds are `NONE 0`, `LOCAL 1` (value: the binder's relative
  token), `DECL 2` (value: `DeclId`), `VARIANT 3` (value: the enum's
  `DeclId`, aux: the ordinal), `PARAM 4` (value: the parameter leaf) and
  `FOREIGN 5`. A receiver `&self` is bound to its parameter row's name
  token, which is the `&`.
- Constant flags are `CONCRETE 0x80000000`, `VARIANT 0x40000000` and
  `SYMBOLIC 0x20000000`. A symbolic value's lo word is the constant
  parameter's leaf.

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
leave a scheduling-dependent pointer, but `rt_binding` itself rejects a build
whose readiness bit is clear. An export error on the host also clears that
bit, including a readback failure after the GPU committed the job.

`export_job` returns a `JobReport` with that readiness bit and retains it in
`job_reports()`. A successful transaction alone does not certify completeness.
This bit checks the current exported schema; it is not code-generation
admission and does not certify the missing fields listed below. Tests check
every job's report, resolved expected types and each callee's incomplete flag.

## Work distribution

All semantic work runs on the GPU. The host allocates buffers, clears job
scratch, submits one command buffer per attempt and reads the 96 status
words and 256 scratch words.

The export records 187 dispatches per attempt: 28 kernels, including 79
translation/advance pairs and the three scan kernels, which run twice. Empty translation
heights dispatch no translation workgroups, but their advance dispatches
still run. This boundary has not yet been timed on settings.

| Step | Lanes | Work |
| --- | --- | --- |
| 00, 04, 07, 09, 16 | 1 lane | transaction, plans and reservations |
| 01 | one per generic parameter | `ParamId` interning and the job's parameter map |
| 01b | one per HIR row, token and variant | declaration-token map, callee and pattern marks |
| 02 | one per HIR row | `DeclId` interning, trait `Self`, scan flags, token spans |
| 03, 05 | one per canonical record | height buckets |
| 06 | one per record of the current height, 79 indirect rounds | children are always translated first |
| 08 | uint4 prefix scan over rows | row counts, use counts, directory counts and segment counts together |
| 10 | one per declaration | directory, binders, signature, schema, segment |
| 11 | one per body row | segment rows |
| 12 | one per side index × 7 tables | side records |
| 12b, 12c | one per job token | clear, then copy, body text; token records |
| 13 | one per parameter, field and variant payload | signatures and schema |
| 14 | one per call | use records |
| 14b | one per HIR row, predicate and method | trait-fact flags and per-owner counts |
| 08 again | uint4 prefix scan over rows | trait-fact ranks and owner blocks |
| 14c | 1 lane | trait-fact reservation |
| 14d | one per declaration, predicate and method | trait column, predicate and binding records |
| 14e | one per HIR row | BOUND row predicate ordinals |
| 15 | one per declaration | statistics |
| 17 | one per staged entry | publish |
| 18 | one per hash slot | rollback |

Substitution (`retention_subst.slang`) resolves a parameter leaf by its
`ParamId` through the callee's committed binder map. It walks terms in
post-order on a global-memory stack, so it uses no per-thread arrays.
It rejects an unready build, incomplete/uncommitted entries, a foreign environment owner,
inconsistent mask/arity counts and domains exceeding the 32-slot masks.
Unresolved references return `RT_SUBST_UNRESOLVED`; failed projections retain
`RT_SUBST_FIT_FAILED`. Neither can compare as a successfully substituted type.
This is a probe implementation: it visits shared terms as a tree without a
memo. The production engine is
[retained substitution](compiler-retained-substitution.md), with its own
kernels. It memoizes `(environment, term)` tasks and evaluates fits. It
consumes the term identities and kinds above, which this export keeps
stable; a change to them has to be coordinated with it.

The acceptance probe calls `rt_subst` from three sites: the signature with
the rejection terms, the per-row checks (term, parameter binding, symbolic
constant, member receiver, member field) and the uses. Its fully inlined
size is 21957 instructions.

## Not exported completely

This boundary does not yet carry:

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
- **Bound-member calls.** Their trait-solver evidence is not exported.
  The use records the trait member's `DeclId` and the caller-scoped
  environment. The catalog inputs the solver needs (predicates, impl
  heads, prerequisites, bindings) are under "Trait facts".
- **Trait-level predicates** (bounds owned by a trait item) have no
  accepted producer (`predicate_generic_owner_supported`). A required
  member's own bounds are function-owned and export like any other.
- **Constant fits.** `CC_CAST` terms are retained. The probe does not
  evaluate fits. The production engine does, and returns the failing
  projection with each result
  ([retained substitution](compiler-retained-substitution.md)).
- **`for` statement rows** have no term. The producer publishes no checked
  reference for them; the iterable kind and the binder's let-like rows are
  retained.
- **File ids** are job-local. Token kinds, byte offsets and spellings are
  retained per body, so diagnostics and identifiers need no job tables.

Readiness covers the retained schema, not all inputs required by lowering.
Member field ordinals, iterable kinds and argument modes are retained but
not yet exhaustively validated for every supported form. Projection must
validate those facts before publishing executable code. Function-reference
uses have no instance environment: supported function values are nongeneric;
generic function values are rejected by the frontend.

The semantic projection and export use the parser's statement forms:
const is 4 and return is 2. Local const statements are not currently accepted
by the grammar; the retained schema covers top-level constant declarations.
Return statement payloads are never interpreted as declaration-name tokens.

## Dependencies for discovery and projection

- A row's type term is whatever the checker publishes for that row. A
  contextual literal inside a generic body (the `1` in `a + 1` with
  `a: T`) needs its symbolic expected type. The literal/operator producer
  boundary has to publish that type as a term over the body's parameters.
  Retention then exports it like any other term, and instantiation resolves
  the literal's type, range and payload per instance before operand
  validation. The literal's kind, magnitude words and float words are
  already retained, unchanged, in the row payload. The producer (8546fe2d1,
  2d9330575) publishes a symbolic literal context only over a parameter of
  the literal's own enclosing binder chain. Projection must keep its
  realization rule: in a pointer context, integer literals and
  literal-derived operator results stay i32 (`table_rows`, with
  `inherited_expression_type`), as bound-body `00_init` does, so the
  ordinary null and offset rules validate `p == 0`, `p + 8`, `p += 8` and
  `p + (4 * 2)` with their integer widths.

- Discovery needs the trait solver's implementation evidence to select
  bound-member callees. The solver's catalog inputs are retained
  ("Trait facts"); its admission, coherence check and evidence are not.
- A dependency-signature slot leaf has to map to the dependency's committed
  binder entry. The dependency interface's slot order has to match the
  composed binder order above (impl before method per domain, then `Self`).
- Physical projection into the existing lowering columns needs the layout
  caches, expression-parent/root and loop columns and lowering facts listed
  above, recomputed on the GPU from the segment. Token text and spellings
  are retained.
