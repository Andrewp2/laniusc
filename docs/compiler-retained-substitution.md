# Retained substitution

Retained substitution is the production engine that instantiates retained
terms ([program retention](compiler-program-retention.md)) under closed
environments on the GPU. It replaces the probe walk in
`retention_subst.slang` for production consumers. The probe stays for the
retention acceptance test until integration. No production code path calls
this engine yet: discovery and projection are the planned consumers.

| Part | Location |
| --- | --- |
| Kernels and shared module | `shaders/type_checker/retention/substitution/` |
| Host object | `crates/laniusc-compiler/src/type_checker/program_retention/substitution.rs` |
| Test fixture interpreter | `shaders/tests/retention_subst_fixture.slang` |
| Test request producer over retained uses | `shaders/tests/retention_subst_uses.slang` |
| Tests | `tests/retained_substitution.rs` (in the `compiler` binary) |

## Request and result contract

A GPU producer writes requests into `sb_requests` and their count into
`sb_request_count[0]` (`SubstitutionRequests`). A request is one uint4:

| Word | Contents |
| --- | --- |
| x | `DeclId` of the declaration whose binder chain the term uses |
| y | ENV `TermId`: the closed environment the declaration owns |
| z | the term reference to substitute |
| w | a producer tag, returned unchanged |

`sb_results` holds 2 × uint4 per request:

| Word | Contents |
| --- | --- |
| r0 | `(result TermId or RT_UNKNOWN, status, failed node, failed environment)` |
| r1 | `(failed child value, tag, run, 0)` |

`sb_counts[STATE]` is `PUBLISHED` (2) only after a committed run, and
`sb_counts[RUN]` names that run. Results stay on the GPU.
`RetainedSubstitution::publication` returns both buffers for a consumer to
bind. The host reads only status words.

Statuses:

| Code | Name | Meaning | Failed node |
| --- | --- | --- | --- |
| 0 | `OK` | r0.x is a closed, exactly interned term | — |
| 2 | `NOT_READY` | the store's `READY` bit is clear | request term |
| 3 | `DECL` | no committed, complete definition of the declaration | request term |
| 4 | `ENV` | not a closed ENV of the declaration (see validation) | request term |
| 5 | `UNRESOLVED` | a sentinel or out-of-range reference | the reference |
| 6 | `PRIOR_FIT` | an `RT_FIT_FAILED` reference in the input | the reference |
| 7 | `FOREIGN` | a parameter leaf outside the declaration's binder | the leaf |
| 8 | `UNBOUND` | a binder parameter that the ENV leaves unbound | the leaf |
| 9 | `SLOT_PENDING` | a dependency-signature slot leaf | the leaf |
| 10 | `FIT_FAILED` | a constant projection does not fit its target | the `CC_CAST` term |
| 11 | `COUNT` | an array length that is not a count | the array term |
| 12 | `UNSUPPORTED` | a kind or a constant shape the canonical rules reject | the term |
| 13 | `DEPTH` | the result would exceed the 64-level type graph | the term |
| 14 | `CAPACITY` | written only by an overflowed attempt; never published as a result | — |
| 15 | `INVARIANT` | an inconsistent store record | the term |

The failed environment is the task's environment: the request ENV, or 0
for a closed term or an environment binding. A `FIT_FAILED` result's
failed child value is the typed value that did not fit. These words are
store identities for later source mapping; the engine writes no
diagnostics.

A slot leaf is reported as `SLOT_PENDING`, never bound by slot position.
Binding it needs the dependency's defining binder, which the consumer
(discovery) knows and the term does not.

## Validation

Each request is validated before it creates any task:

- the store's `READY` bit;
- the declaration: a valid `DeclId` whose committed entry names it, with
  state `COMMITTED` and no `INCOMPLETE` flag;
- the ENV: a stored, closed `ENV` term whose owner word is the
  declaration; masks within the binder's type and constant counts (at most
  32 each); arity equal to the mask popcounts; type-slot count equal to the
  type popcount;
- each bound slot: the binder's `ParamId` has the slot's domain; a type slot
  is bound to a scalar, `NAMED`, `ARRAY`, `SLICE` or `REF`; a constant slot
  is bound to a `CC_VALUE` of the parameter's declared scalar or to a
  `CC_CAST` to it.

A partially bound ENV is accepted. A leaf whose slot is unbound returns
`UNBOUND` only when the term reaches it.

A parameter leaf binds by exact `ParamId`: the engine finds the ParamId in
the declaration's composed binder (at most 64 entries) and checks its
domain. An inherited impl parameter and a shadowing method parameter with
the same spelling are different `ParamId`s and bind to different slots.
The binding is a term in the receiving scope and is never substituted
again. A compound binding is still evaluated as a closed term, because it
can contain a pending `CC_CAST`.

## Evaluation rules

- `NAMED`, `SLICE`, `REF` and `ENV` are rebuilt with their words unchanged.
  A nested `ENV` (an inner call's environment in the callee's scope) becomes
  a closed `ENV` of the inner callee. This is the discovery step.
- `ARRAY` takes its length's count class: a `CC_VALUE` length becomes
  `CC_COUNT(count)` (`constant_value_to_count`). Equal counts of different
  scalars give one array identity.
- `CC_CAST(target; child)` folds the child's typed value with the
  canonical rules (`ct_build_projection`). `constant_value_to_count`
  rejects a value that is not a count (`UNSUPPORTED`).
  `constant_value_from_count` either folds the value into
  `CC_VALUE(target, count, 0)` or fails the fit (`FIT_FAILED`). Closed
  terms are evaluated too, so a result never contains a `CC_CAST`.
- A task's arguments are checked in argument order, and the first failing
  argument decides the task's failure. Its status and provenance are copied
  from that argument's own result, so nested failures report the innermost
  failing projection. Provenance never comes from memo contents or lane
  order.
- A result whose height exceeds 64 returns `DEPTH`.

## Work distribution

A task is one unique key `(environment, term)`. The environment is the
request's ENV `TermId`, whose owner word names the owning definition, or 0
for the environment-independent evaluation of a closed term. Leaves never
become tasks: scalars, arity-0 records, parameter leaves and sentinels are
resolved in place on the edge that reaches them. Tasks are interned in an
open-addressing memo (`sb_memo`) with full-key comparison. A lane writes
its task record, fences, then publishes it with a CAS. A lane that loses
to an equal key kills its record (counted in `SPARE_TASKS`). The hash only
selects the first probe, and `set_hash_mask(0)` forces every key onto one
chain.

A task's level is `height(term) + height(env) - 1`, or `height(term)` for
environment 0. Every child task has a lower level: a child term is lower
than its parent, and a binding is lower than the ENV that holds it.

| Step | Lanes | Work |
| --- | --- | --- |
| 00 begin | 1 | open the attempt, save the store's term watermark, plan the roots |
| 01 roots | one per request | validate; resolve the term to an immediate or its root task |
| 02 expand plan | 1 | frontier = tasks created since the last plan; plan `frontier × max arity` lanes |
| 03 expand | one per (frontier task, argument) | resolve one edge, creating the child task if new; a repeated argument shares the first occurrence's edge |
| 04 scatter | one per task | bucket live tasks by level (counts are kept at creation) |
| 05 eval plan | 1 | the next nonempty level |
| 06 eval | one per task of the level | intern the task's result from its arguments' results, or fail |
| 07 publish | one per request | copy results; `CAPACITY` everywhere after an overflow |
| 08 finish | 1 | commit, or restore the store's term counters |
| 09 rollback | one per store term slot | clear slots of terms an overflowed attempt interned |

Work is O(tasks + edges) lane steps. An expansion lane also compares its
argument with the earlier arguments of the same task (at most 63), and a
binder search reads at most 64 words. An eval lane reads its task's
arguments. No lane walks a term DAG, a body or a table.

The dependency span is the number of expansion rounds plus the number of
nonempty levels. Both are bounded by the term height plus the
environment height. Indirect dispatch arguments make empty rounds
dispatch no workgroups. The host records one batch of `k` expansion rounds,
the scatter, `k` evaluation rounds and the end steps. It submits the batch
and reads the status words, then records batches of `2k`, `4k`, … until
the attempt is final (`k` = 8).

Measured on the focused tests (this desktop's GPU, release build, host wall
time per run including readbacks):

| Fixture | Requests | Tasks | Edges resolved | Rounds (expand + eval) | Max frontier | Dispatches | Time |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 40-level shared DAG (2^40 leaves as a tree), three equal requests | 3 | 40 | 40 | 40 + 40 | 3 | 498 | 6 ms |
| 4096 environments × 2 templates | 8192 | 45056 | 57344 | 8 + 9 | 12288 | 258 (5 attempts) | 6 ms |
| all contract cases (depth 64, 64-slot ENV, fits, invalid requests) | 46 | 209 | 314 | 63 + 64 | 31 | 1014 | 11–17 ms |
| two exported jobs, requests from retained uses | 93 | 10 | 10 | 2 + 2 | — | — | — |

The 4096-environment run grows its task table four times from the default
16384 tasks. Its span is the template height, independent of the number of
environments. A 64-level chain needs about 128 dependent rounds, which
costs four batches, five readbacks and about 1000 recorded dispatches,
most of them empty. The fixed cost of a run with no tasks is 38 dispatches
and one readback (0.8 ms).

## Capacity, transactions and reset

An attempt is one transaction over the substitution's tables and the
store's term arena.

- Step 00 saves the store's term and argument counters, spare counters,
  overflow word and term demands, then clears the store's overflow word.
- Any task, edge or memo overflow, and any store interning failure, sets an
  overflow bit. The planners then stop the attempt, step 07 writes
  `CAPACITY` for every request, and step 08 restores the store's counters
  and status words. Step 09 clears every term slot that points at or past
  the saved term watermark. Linear probing stays sound because every older
  key stopped at a slot that was occupied before the attempt.
- The host grows the overflowed tables. Its own tables grow to twice the
  recorded demand. The store grows through `ProgramRetention::grow` from the
  recorded store demand, which copies committed arenas and rehashes. The
  host then runs the attempt again over the same retained terms and
  requests. There is no frontend rerun and no replay. An attempt that
  overflows without a table to grow is an error.
- A committed attempt keeps the terms it interned in the store. They are
  complete records with exact identities, and they are dead after the next
  `begin_build`.

Allocations and pipelines persist across runs and builds. Every run clears
the memo and the status words and gets a new run number, and every
published result row carries that run number. Nothing from an earlier run
or build is read.

## Tests

`cargo test --release --test compiler retained_substitution_ -- --test-threads=1`

- `retained_substitution_is_memoized_parallel_and_exact`: the shared DAG
  (exactly 40 tasks, 40 rounds each way, one result for three equal
  requests), 4096 independent environments (span ≤ 10 + 11 rounds, frontier
  ≥ 8192), and every contract case. The cases cover depth 64 and 65, a
  64-slot ENV, a 32-operand application, count-class equality, `u8`/`i8`
  fit boundaries, nested projections, argument-order provenance, closed
  pending fits, a pending fit in an ENV binding, every ENV and declaration
  rejection, sentinels, foreign, unbound and slot leaves, and
  inherited/shadowing parameters.
- `retained_substitution_grows_retries_and_resets_per_build`: tiny
  substitution tables plus a store with no free term records (7 attempts,
  5 own growths, 1 store growth). The results match the reference
  structurally, and rolled-back attempts leave no store terms. It also
  covers a repeated run, forced memo and store collisions, a fresh build in
  the same allocations, and a store that is not `READY`.
- `retained_substitution_instantiates_exported_foreign_templates`: two
  frontend jobs export, the frontend is dropped and the exporter scratch is
  poisoned. A GPU kernel turns each foreign generic use into requests for
  the callee's result, parameters, body rows and inner call environments
  and results. Every request succeeds, each callee result equals the
  caller's checked type, and each inner environment closes to an `ENV`.

The synthetic programs are construction scripts run by a single GPU lane,
so every identity, including each expected result, comes from the store
interner. The host encodes only the script and the expected outcomes.

## Integration boundary

- Discovery must produce requests on the GPU and consume
  `sb_results`/`sb_counts`. Slot leaves need discovery's dependency binder
  mapping before they can be requested.
- The retention probe still calls `rt_subst`; production consumers must use
  this engine.
- A store flag that marks terms containing `CC_CAST` would let closed,
  cast-free subterms skip their environment-0 tasks. That is a store layout
  change and needs coordination with the exporter.
- The engine does not remove source replay. Replay deletion depends on
  discovery, projection and publication.
